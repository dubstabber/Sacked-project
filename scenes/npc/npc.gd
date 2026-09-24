extends CharacterBody2D


signal destination_reached
signal navigation_failed
signal activity_finished
signal waypoint_reached(index: int)
signal route_finished

# sub_419CE0, sub_41E360 and sub_41A8D0 all walk at base_speed + 0.15 * agent+1064, the
# office's aggression band. sub_419740, the boss, reads the same band but not this formula.
const AGGRESSION_SPEED_STEP := 0.15
const UNHURRIED_PROFILE := &"boss"

const MAP_COLLISION := preload("res://scenes/shared/collision_map_layer.gd")
const NAVIGATION := preload("res://scenes/shared/grid_navigation.gd")
const NPC_BRAIN := preload("res://scenes/npc/npc_brain.gd")
# Slot 1 of the coworkers' and the secretary's tables, IDLE#2.
const FIDGET_ACTION := &"idle-2"
# sub_4179B0's sway and easing (0x4179D7, 0x417A4C).
const SWAY_DEGREES := 10.0
const HEADING_EASING := 0.125

enum Command { NONE, TRAVEL, ACTIVITY }

@export var profile: Resource
@export_range(0.0, 20.0, 0.1, "suffix:tiles/s") var move_speed_tiles: float = 0.0
@export_node_path("Node2D") var route_path: NodePath
@export var patrol_offsets: Array[Vector2] = []
@export var arrival_distance: float = 6.0
@export var pause_seconds: float = 0.4
@export var initial_direction: Vector2 = Vector2.RIGHT

# agent+1064, which sub_402350 writes from the office-wide mean every frame.
var aggression_band := 0
var last_direction: Vector2 = Vector2.RIGHT
# agent+1848, the heading sub_418310 tests the player against, in the original's degrees:
# 180 - atan2(dx, dz), so 0 is view _000 and 45 is _045. It follows the view, never the other
# way round. sub_402260 calls sub_4179B0 for every agent each frame, which aims at the view,
# 45 * agent+124, plus a sway of 10 * sin(agent+1844 + agent+72), and moves 1/8 of the short
# way there (sub_45E270, 0x417A4C). It starts at 0 (0x415EC4), so a new agent's cone swings
# in from _000. See docs/npc-reference.md.
var notice_heading := 0.0
# agent+1844: rand() / 32767 (0x415EB8), a phase of 0 to 1 radian rather than a full turn. A
# seeded brain draws it again from its own stream.
var sway_phase := randf()
# notice_heading as a screen direction, which the brain turns back into logical tiles for the
# notice test. See docs/catch-reference.md.
var facing_screen: Vector2 = Vector2.RIGHT
# agent+72, the game clock the tick last ran at, the same for every agent; the port counts it
# from the level's start, in whole original frames.
var _sway_clock := 0.0
var _heading_debt := 0.0
var _patrol_origin := Vector2.ZERO
var _patrol_targets: Array[Vector2] = []
var _target_index := 0
var _pause_remaining := 0.0
var current_activity: StringName = &"idle"
var _command := Command.NONE
var _navigation_path := PackedVector2Array()
var _navigation_index := 0
var _navigation_target := Vector2.ZERO
var _stuck_seconds := 0.0
var _activity_remaining := 0.0
var _activity_return := Vector2.INF
var _route: Node2D
var _waypoint_index := 0
var _route_done := false
var _route_retry := 0.0
var _warned_actions: Dictionary = {}
var _fidgeting := false
# Targets whose search failed from _refusals_start on the layer _refusals_layer, each with the
# cells of other entities that refused it and who stood there; see _still_refused.
var _refusals: Dictionary = {}
var _refusals_layer := 0
var _refusals_start := Vector2i.ZERO

@onready var sprite: Sprite2D = $Sprite2D
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var animation_controller = $AnimationController


func _ready() -> void:
	add_to_group("depth_composited_characters")
	add_to_group("npc_agents")
	last_direction = IsoDirection.snap_to_8_directions(initial_direction)
	facing_screen = _heading_screen(notice_heading)
	_patrol_origin = global_position
	_build_patrol_targets()
	apply_profile(profile)
	animation_controller.play_idle(last_direction)
	animation_player.animation_finished.connect(_on_animation_finished)
	if not route_path.is_empty():
		_route = get_node_or_null(route_path) as Node2D
		if _route == null or not _route.has_method("get_waypoints") or is_ancestor_of(_route):
			push_warning("NPC routes must be stationary NPCRoute nodes outside the moving NPC")
			_route = null
		else:
			destination_reached.connect(_on_route_arrival)
			activity_finished.connect(_on_route_activity_finished)
			navigation_failed.connect(_on_route_blocked)
			call_deferred("_start_route_waypoint")


func _physics_process(delta: float) -> void:
	_ease_notice_heading(delta)
	if _command == Command.TRAVEL:
		_follow_navigation(delta)
		return
	if _command == Command.ACTIVITY:
		_activity_remaining = maxf(_activity_remaining - delta, 0.0)
		if _activity_remaining == 0.0:
			# The busy timer running out changes no slot, so an IDLE#2 under way plays on.
			_drop_command()
			if not _fidgeting:
				animation_controller.play_idle(last_direction)
			activity_finished.emit()
		return
	if _route != null:
		if _route_retry > 0.0:
			_route_retry = maxf(0.0, _route_retry - delta)
			if _route_retry == 0.0:
				_start_route_waypoint()
		return
	if _patrol_targets.is_empty():
		velocity = Vector2.ZERO
		if not _fidgeting:
			animation_controller.play_idle(last_direction)
		return

	if _pause_remaining > 0.0:
		_pause_remaining = maxf(_pause_remaining - delta, 0.0)
		velocity = Vector2.ZERO
		animation_controller.play_idle(last_direction)
		return

	var target := _patrol_targets[_target_index]
	var to_target := target - global_position
	if to_target.length_squared() <= arrival_distance * arrival_distance:
		var allowed := MAP_COLLISION.constrain_body_motion(self, to_target)
		if allowed.is_equal_approx(to_target) and not test_move(global_transform, to_target):
			global_position = target
			_advance_target()
			return

	var snapped_direction := IsoDirection.snap_to_8_directions(to_target.normalized())
	last_direction = snapped_direction
	velocity = IsoDirection.screen_velocity(to_target, get_move_speed_tiles())
	animation_controller.play_walk(snapped_direction)
	velocity = MAP_COLLISION.constrain_body_motion(self, velocity * delta) / delta
	move_and_slide()


func get_move_speed_tiles() -> float:
	var base := move_speed_tiles
	if base <= 0.0:
		base = profile.walk_speed_tiles if profile != null else 1.5
	if profile != null and StringName(profile.get("id")) == UNHURRIED_PROFILE:
		return base
	return base + AGGRESSION_SPEED_STEP * float(aggression_band)


func apply_profile(selected_profile: Resource) -> void:
	if selected_profile == null:
		push_warning("NPC has no CharacterProfile")
		return

	profile = selected_profile
	var initial_texture := profile.get("initial_texture") as Texture2D
	if initial_texture != null:
		sprite.texture = initial_texture

	var animation_library := profile.get("animation_library") as AnimationLibrary
	var profile_id := StringName(profile.get("id"))
	if animation_library != null:
		var library_name: StringName = profile_id
		if animation_player.has_animation_library(library_name):
			animation_player.remove_animation_library(library_name)
		animation_player.add_animation_library(library_name, animation_library)
	var actions := profile.get("action_animation_library") as AnimationLibrary
	if actions != null:
		var action_library_name := StringName("%s-actions" % profile_id)
		if animation_player.has_animation_library(action_library_name):
			animation_player.remove_animation_library(action_library_name)
		animation_player.add_animation_library(action_library_name, actions)

	var library_prefix := ""
	if String(profile_id) != "":
		library_prefix = "%s/" % String(profile_id)

	animation_controller.configure(
		library_prefix + String(profile.get("idle_animation_prefix")),
		library_prefix + String(profile.get("walk_animation_prefix"))
	)


func _build_patrol_targets() -> void:
	_patrol_targets.clear()
	for offset in patrol_offsets:
		_patrol_targets.append(_patrol_origin + offset)


func _advance_target() -> void:
	velocity = Vector2.ZERO
	animation_controller.play_idle(last_direction)
	_target_index = (_target_index + 1) % _patrol_targets.size()
	_pause_remaining = pause_seconds


func navigate_to(target_global: Vector2) -> bool:
	var path := PackedVector2Array()
	var standing := _command == Command.NONE and _activity_return == Vector2.INF
	if standing:
		# sub_416660's failed start (0x416712-0x41675E) and sub_416D50's failure exits never
		# reach sub_41A510, so a start that finds no route leaves the clip alone, IDLE#2 too.
		# Dropping an activity can stand the agent back on its return point, so that search
		# waits for the drop.
		path = _find_navigation_path(target_global)
		if path.is_empty():
			navigation_failed.emit.call_deferred()
			return false
	cancel_commands()
	if not standing:
		path = _find_navigation_path(target_global)
	_navigation_target = target_global
	_navigation_path = path
	_navigation_index = 0
	_stuck_seconds = 0.0
	if _navigation_path.is_empty():
		navigation_failed.emit.call_deferred()
		return false
	_command = Command.TRAVEL
	current_activity = &"walking"
	# cancel_commands() above dropped to idle; a rebuilt route (social refresh) must
	# not show that frame, so resume walking straight away.
	animation_controller.play_walk(last_direction)
	return true


func _find_navigation_path(target: Vector2) -> PackedVector2Array:
	for layer in get_tree().get_nodes_in_group("collision_maps"):
		if not layer.enabled or not layer.get_parent().is_ancestor_of(self):
			continue
		var origin: Vector2 = layer.map_to_local(Vector2i.ZERO)
		var start := IsoDirection.screen_to_ground(layer.to_local(global_position) - origin)
		var goal := IsoDirection.screen_to_ground(layer.to_local(target) - origin)
		var start_cell := Vector2i(floori(start.x + 0.5), floori(start.y + 0.5))
		var goal_cell := Vector2i(floori(goal.x + 0.5), floori(goal.y + 0.5))
		if _still_refused(layer, origin, start_cell, target):
			return PackedVector2Array()
		var bounds: Rect2i = layer.get_used_rect().grow(1)
		bounds = bounds.expand(start_cell)
		bounds = bounds.expand(goal_cell)
		var occupied := _occupied_cells(layer, origin, start_cell)
		var refused := {}
		var is_blocked := func(cell: Vector2i) -> bool:
			if occupied.has(cell):
				refused[cell] = occupied[cell]
				return true
			return layer.is_blocked(cell)
		var path := PackedVector2Array()
		if occupied.has(goal_cell):
			refused[goal_cell] = occupied[goal_cell]
		else:
			path = NAVIGATION.find_path(start, goal, is_blocked, bounds)
			# The step back is for a start the search refuses outright, footprint or first leg
			# onto its own cell's centre. From any other start the search above has already
			# flooded from that cell with the same cells blocked.
			if path.is_empty() and NAVIGATION.find_path(start, Vector2(start_cell), is_blocked, bounds).is_empty():
				path = _step_back_path(start_cell, goal, is_blocked, bounds)
		if path.is_empty():
			_refusals[target] = refused
			return path
		for index in range(path.size()):
			path[index] = layer.to_global(origin + IsoDirection.ground_to_screen(path[index]))
		return path
	return PackedVector2Array([target])


# sub_4165D0 queues a failed goal again with +1124 cleared on the very next tick (0x416644), so
# an agent whose way is shut retries its search every tick. The search depends only on the
# start cell, the target and which cells are blocked, the map never changes in play, and
# blocking more cells can only shrink what it reaches. So a failed search stays failed for as
# long as everyone whose cell refused it still stands in that cell, and is not run again.
func _still_refused(layer: Node, origin: Vector2, start_cell: Vector2i, target: Vector2) -> bool:
	if layer.get_instance_id() != _refusals_layer or start_cell != _refusals_start:
		_refusals.clear()
		_refusals_layer = layer.get_instance_id()
		_refusals_start = start_cell
		return false
	if not _refusals.has(target):
		return false
	var world: Node = layer.get_parent()
	var refused: Dictionary = _refusals[target]
	for cell: Vector2i in refused:
		var entity = refused[cell]
		if not is_instance_valid(entity) or not world.is_ancestor_of(entity) or _cell_of(layer, origin, entity) != cell:
			_refusals.erase(target)
			return false
	return true


# sub_4161E0 and sub_416090 stand an agent back on the exact interaction point, which can be
# flush against a wall or even inside a blocked cell, and the footprint test then refuses
# every route from there. sub_416D50 plans from the agent's rounded cell (0x416D8A) and
# sub_41EE70 never tests that cell, so this does the same and steps back onto its centre
# first. Only the search exempts the cell; walking keeps its collision.
func _step_back_path(start_cell: Vector2i, goal: Vector2, blocked: Callable, bounds: Rect2i) -> PackedVector2Array:
	var is_blocked := func(cell: Vector2i) -> bool: return cell != start_cell and blocked.call(cell)
	var path: PackedVector2Array = NAVIGATION.find_path(Vector2(start_cell), goal, is_blocked, bounds)
	if not path.is_empty():
		path.insert(0, Vector2(start_cell))
	return path


# sub_418D20 runs before every search (0x416D6E, 0x4169A0): it marks the rounded cell of every
# other entity on the world's list -- the agents and the player -- as blocked and restores it
# afterwards. sub_41EE70 never tests the start, and the goal is reached by popping it, so a
# cell someone stands on stops the route when it is the goal or on the way, never when it is
# the agent's own. Nor does the port's start footprint refuse a route over one: a start it
# refuses falls back to the step back, whose search from the cell's centre tests only that
# unmarked cell. Each cell maps to an entity standing in it.
func _occupied_cells(layer: Node, origin: Vector2, start_cell: Vector2i) -> Dictionary:
	var cells := {}
	for entity in NPC_BRAIN.world_entities(layer.get_parent()):
		if entity == self:
			continue
		cells[_cell_of(layer, origin, entity)] = entity
	cells.erase(start_cell)
	return cells


static func _cell_of(layer: Node, origin: Vector2, entity: Node2D) -> Vector2i:
	var ground := IsoDirection.screen_to_ground(layer.to_local(entity.global_position) - origin)
	return Vector2i(floori(ground.x + 0.5), floori(ground.y + 0.5))


func _follow_navigation(delta: float) -> void:
	var target := _navigation_path[_navigation_index]
	var to_target := target - global_position
	if to_target.length_squared() < 0.0001:
		_navigation_index += 1
		if _navigation_index == _navigation_path.size():
			_command = Command.NONE
			velocity = Vector2.ZERO
			current_activity = &"idle"
			animation_controller.play_idle(last_direction)
			destination_reached.emit()
		return
	last_direction = IsoDirection.snap_to_8_directions(to_target.normalized())
	animation_controller.play_walk(last_direction)
	var motion := IsoDirection.screen_velocity(to_target, get_move_speed_tiles()) * delta
	if motion.length_squared() > to_target.length_squared():
		motion = to_target
	var start := global_position
	velocity = MAP_COLLISION.constrain_body_motion(self, motion) / delta
	move_and_slide()
	_stuck_seconds = _stuck_seconds + delta if global_position.distance_squared_to(start) < 0.00001 else 0.0
	if _stuck_seconds >= 0.5:
		navigate_to(_navigation_target)


func start_activity(animation: StringName, duration: float, facing: Vector2, anchor: Vector2 = Vector2.INF, return_position: Vector2 = Vector2.INF) -> bool:
	cancel_commands()
	if facing != Vector2.ZERO:
		last_direction = IsoDirection.snap_to_8_directions(facing.normalized())
	_show_clip(animation)
	if anchor != Vector2.INF:
		global_position = anchor
	_activity_return = return_position
	_activity_remaining = maxf(duration, 0.0)
	_command = Command.ACTIVITY
	current_activity = animation
	return true


func _show_clip(animation: StringName) -> void:
	if animation == &"idle" or animation == &"":
		animation_controller.play_idle(last_direction)
		return
	var clip := _action_clip(animation)
	if clip.is_empty():
		# sub_41A510 drops to the idle slot when an action has no clip at all.
		_warn_missing_action(animation)
		animation_controller.play_idle(last_direction)
	else:
		animation_controller.play_animation(clip)


# sub_4187A0's turn: one step round the eight views (sub_41A3F0 masks the index with 7),
# after which sub_41A510 resolves the slot the agent was showing again, in the new view. The
# brain decides when; see docs/npc-reference.md.
func turn_view(step: int) -> void:
	var directions := IsoDirection.get_screen_directions()
	last_direction = directions[posmod(view_index() + step, directions.size())]
	if _fidgeting:
		animation_controller.play_animation(_action_clip(FIDGET_ACTION))
	elif _command != Command.TRAVEL:
		_show_clip(current_activity)


# sub_419CE0 and sub_41E360 switch to slot 1, IDLE#2, and play it once: they clear its loop
# flag +548 as they start it (0x419EA8, 0x41E4E7) and put slot 0 back once it has finished
# (+556). The library imports it one-shot; the brain decides when.
func fidget() -> bool:
	var clip := _action_clip(FIDGET_ACTION)
	if clip.is_empty():
		return false
	_fidgeting = true
	animation_controller.play_animation(clip)
	return true


func is_fidgeting() -> bool:
	return _fidgeting


func _on_animation_finished(animation_name: StringName) -> void:
	if _fidgeting and String(animation_name) == animation_controller.current_animation:
		_fidgeting = false
		animation_controller.play_idle(last_direction)


# sub_4179B0, once per original frame at the port's nominal 60 Hz (see npc_brain.gd).
func _ease_notice_heading(delta: float) -> void:
	_heading_debt += delta
	while _heading_debt >= NPC_BRAIN.ORIGINAL_FRAME_SECONDS:
		_heading_debt -= NPC_BRAIN.ORIGINAL_FRAME_SECONDS
		_sway_clock += NPC_BRAIN.ORIGINAL_FRAME_SECONDS
		var target := fposmod(45.0 * view_index() + SWAY_DEGREES * sin(sway_phase + _sway_clock), 360.0)
		notice_heading = fposmod(notice_heading - HEADING_EASING * heading_difference(notice_heading, target), 360.0)
		facing_screen = _heading_screen(notice_heading)


# sub_45E270: heading minus target the short way round, within (-180, 180].
static func heading_difference(heading: float, target: float) -> float:
	if heading == target:
		return 0.0
	if target <= heading:
		var behind := heading - target
		return behind - 360.0 if behind > 180.0 else behind
	var ahead := target - heading
	return 360.0 - ahead if ahead > 180.0 else -ahead


static func _heading_screen(heading: float) -> Vector2:
	var radians := deg_to_rad(heading)
	return IsoDirection.ground_to_screen(Vector2(sin(radians), -cos(radians))).normalized()


# agent+124: the eight-way view, numbered as the sprite suffixes are, _000 through _315.
func view_index() -> int:
	var directions := IsoDirection.get_screen_directions()
	var best := 0
	for index in range(1, directions.size()):
		if last_direction.dot(directions[index]) > last_direction.dot(directions[best]):
			best = index
	return best


func _action_clip(action: StringName) -> String:
	if profile == null:
		return ""
	var prefix := "%s-actions/%s-%s-" % [profile.id, profile.id, action]
	var clip: String = animation_controller.get_directional_animation_name(prefix, last_direction)
	if animation_player.has_animation(clip):
		return clip
	# sub_41A510 falls back to view 000 when a seated action lacks the requested view.
	clip = prefix + "up-right"
	return clip if animation_player.has_animation(clip) else ""


func _warn_missing_action(action: StringName) -> void:
	if _warned_actions.has(action):
		return
	_warned_actions[action] = true
	push_warning("NPC action animation is not available, using idle: %s" % action)


func cancel_commands() -> void:
	_fidgeting = false
	_drop_command()
	if is_node_ready():
		animation_controller.play_idle(last_direction)


func _drop_command() -> void:
	_command = Command.NONE
	_navigation_path.clear()
	velocity = Vector2.ZERO
	if _activity_return != Vector2.INF:
		global_position = _activity_return
	_activity_return = Vector2.INF
	current_activity = &"idle"


func _start_route_waypoint() -> void:
	if not is_instance_valid(_route) or _route_done:
		return
	var waypoints: Array = _route.get_waypoints()
	if waypoints.is_empty():
		_route_done = true
		route_finished.emit()
		return
	if _waypoint_index >= waypoints.size():
		if not _route.loop:
			_route_done = true
			route_finished.emit()
			return
		_waypoint_index = 0
	navigate_to(waypoints[_waypoint_index].global_position)


func _on_route_arrival() -> void:
	if not is_instance_valid(_route):
		return
	var waypoints: Array = _route.get_waypoints()
	if _waypoint_index >= waypoints.size():
		return
	var waypoint: Marker2D = waypoints[_waypoint_index]
	waypoint_reached.emit(_waypoint_index)
	start_activity(StringName(waypoint.animation), waypoint.wait_seconds, waypoint.facing)


func _on_route_activity_finished() -> void:
	_waypoint_index += 1
	call_deferred("_start_route_waypoint")


func _on_route_blocked() -> void:
	_route_retry = 1.0
