extends CharacterBody2D


signal destination_reached
signal navigation_failed
signal activity_finished
signal waypoint_reached(index: int)
signal route_finished

const MAP_COLLISION := preload("res://scenes/shared/collision_map_layer.gd")
const NAVIGATION := preload("res://scenes/shared/grid_navigation.gd")

enum Command { NONE, TRAVEL, ACTIVITY }

@export var profile: Resource
@export_range(0.0, 20.0, 0.1, "suffix:tiles/s") var move_speed_tiles: float = 0.0
@export_node_path("Node2D") var route_path: NodePath
@export var patrol_offsets: Array[Vector2] = []
@export var arrival_distance: float = 6.0
@export var pause_seconds: float = 0.4
@export var initial_direction: Vector2 = Vector2.RIGHT

var last_direction: Vector2 = Vector2.RIGHT
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

@onready var sprite: Sprite2D = $Sprite2D
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var animation_controller = $AnimationController


func _ready() -> void:
	add_to_group("depth_composited_characters")
	add_to_group("npc_agents")
	last_direction = IsoDirection.snap_to_8_directions(initial_direction)
	_patrol_origin = global_position
	_build_patrol_targets()
	apply_profile(profile)
	animation_controller.play_idle(last_direction)
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
	if _command == Command.TRAVEL:
		_follow_navigation(delta)
		return
	if _command == Command.ACTIVITY:
		_activity_remaining = maxf(_activity_remaining - delta, 0.0)
		if _activity_remaining == 0.0:
			cancel_commands()
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
	if move_speed_tiles > 0.0:
		return move_speed_tiles
	return profile.walk_speed_tiles if profile != null else 1.5


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
	cancel_commands()
	_navigation_target = target_global
	_navigation_path = _find_navigation_path(target_global)
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
		var bounds: Rect2i = layer.get_used_rect().grow(1)
		bounds = bounds.expand(Vector2i(floori(start.x + 0.5), floori(start.y + 0.5)))
		bounds = bounds.expand(Vector2i(floori(goal.x + 0.5), floori(goal.y + 0.5)))
		var path: PackedVector2Array = NAVIGATION.find_path(start, goal, layer.is_blocked, bounds)
		for index in range(path.size()):
			path[index] = layer.to_global(origin + IsoDirection.ground_to_screen(path[index]))
		return path
	return PackedVector2Array([target])


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
	if animation == &"idle" or animation == &"":
		animation_controller.play_idle(last_direction)
	else:
		var clip := _action_clip(animation)
		if clip.is_empty():
			# sub_41A510 drops to the idle slot when an action has no clip at all.
			_warn_missing_action(animation)
			animation_controller.play_idle(last_direction)
		else:
			animation_controller.play_animation(clip)
	if anchor != Vector2.INF:
		global_position = anchor
	_activity_return = return_position
	_activity_remaining = maxf(duration, 0.0)
	_command = Command.ACTIVITY
	current_activity = animation
	return true


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
	_command = Command.NONE
	_navigation_path.clear()
	velocity = Vector2.ZERO
	if _activity_return != Vector2.INF:
		global_position = _activity_return
	_activity_return = Vector2.INF
	current_activity = &"idle"
	if is_node_ready():
		animation_controller.play_idle(last_direction)


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
