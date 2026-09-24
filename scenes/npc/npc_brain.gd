class_name NPCBrain
extends Node


signal goal_changed(goal: int)

const GOAL_CATEGORIES := [4, 5, 9, 6, 8, 7, 1, 7]
# sub_418BE0 maps goal 3 to its alternate work-equipment category.
const ALTERNATE_WORK_CATEGORY := 2
# sub_4187F0 only clears the item goals; the social and smoking goals stay enabled.
const ITEM_GOALS := [0, 1, 2, 3, 4, 7]
const SUPPORTED_GOALS := [0, 1, 2, 3, 4, 5, 6, 7]
const SOCIAL_GOAL := 5
const SMOKING_GOAL := 6
# sub_417B00 sets agent+1820 when the item it walked to is tampered with, and sub_416450
# holds goal 8 -- the ANGRY bubble -- for as long as the busy timer it starts. A filed repair
# job shows it too: sub_416770 asks sub_416450 before sub_4164E0 and stops at the first that
# is busy, so sub_4164E0's goal 9, the REPAIR bubble (0x416535), is never reached. It only
# ever sees the timer run out, and resets the item. See docs/npc-reference.md.
const REACTION_GOAL := 8
const REPAIRABLE_TYPES_PATH := "res://resources/original/repairable_types.json"
const JANITOR_PROFILE: StringName = &"janitor"
# sub_41DEA0(25, agent x, agent y): the player scores for every agent it catches out.
const REACTION_SCORE := 25
# Each archetype's tick reads the reaction flag from its own animation table, and the names
# are not shared: sub_419CE0 picks PISSED, sub_419740 picks STAND#EXPLODE, and sub_41E360
# has no reaction branch at all -- the secretary is angry without changing what she is
# playing. See docs/catch-reference.md.
const REACTION_CLIPS := {
	&"boss": &"explode",
	&"secretary": &"idle",
}
# The seated slot is each tick's own choice too. sub_419740 plays the boss's SIT#IDLE on any
# seat and never reads the relaxed flag +1804 (0x4197F1), and sub_41A8D0 plays the janitor's
# SIT#EASY on any seat (0x41A969); sub_419CE0 and sub_41E360 take SIT#EASY when relaxed and
# SIT#USE otherwise.
const SEATED_CLIPS := {
	&"boss": &"sit-idle",
	&"janitor": &"sit-easy",
}
# Only the coworkers' tick, sub_419CE0, has a branch for the special-action flag +1812 (slot 5
# SPECIAL#1, 0x419DC3) or for goal 6 (slot 6 SPECIAL#2, 0x419DF1). sub_419740, sub_41E360 and
# sub_41A8D0 stay in their idle slot for the same timer, so the SPECIAL#1 the secretary's and
# janitor's tables name is never shown.
const COWORKER_PROFILES := [&"male-employee-1", &"male-employee-2", &"female-employee-1", &"female-employee-2"]
const SECRETARY_PROFILE: StringName = &"secretary"
# Every agent's tick runs once per rendered frame, and the original has no frame limiter: its
# fullscreen present is Flip(NULL, DDFLIP_WAIT) (0x42DD11 in sub_42DCD0), so it ran at the
# monitor's refresh. The per-frame rolls below use a nominal 60 Hz, the rate chosen for the
# port. See docs/npc-reference.md.
const ORIGINAL_FRAME_SECONDS := 1.0 / 60.0
# sub_4187A0 turns the view when (rand() & 0xFFF) > 4000, one step back when (u8)rand() <= 0x80
# and one step on otherwise: on 95/4096 of the frames, and 129/256 of the turns go back.
const LOOK_AROUND_ROLL := 4000
const LOOK_BACK_ROLL := 0x80
# sub_419CE0 and sub_41E360 read the slot they are showing before they roll anything in their
# idle branch (0x419DFE, 0x41E43D), and only they play IDLE#2, on (rand() & 0xFFF) > 0xFF8:
# 7/4096 of the idle frames. The boss's table has no IDLE#2, and the janitor's tick never
# picks the one his names.
const SLOT_READING_PROFILES := [&"male-employee-1", &"male-employee-2", &"female-employee-1", &"female-employee-2", &"secretary"]
const FIDGET_ROLL := 0xFF8
# sub_4187F0 splits a full meter across the goals the map can actually offer, and
# sub_417B00 hands an agent one share the first time each of its goals is spoiled -- so an
# agent is at its angriest once that many different goals have been.
const AGGRESSION_LIMIT := 100.0
const AGGRESSION_SHARED_GOALS := [0, 1, 2, 3, 4]
# An agent that finds its own workstation tampered with gives up on working altogether.
const WORK_GOAL := 3
# sub_416960 aims 1.2 tiles in front of the other agent and sub_417320 only
# considers agents of the other gender within eight tiles.
const SOCIAL_APPROACH_TILES := 1.2
const SOCIAL_RANGE_TILES := 8.0
# sub_416770 rebuilds a social route every three seconds while it is walking.
const SOCIAL_REFRESH_SECONDS := 3.0
# The decay rates, speeds and notice constants come out of sub_4184B0's table at 0x46E7D8,
# and the room masks out of each archetype's initialiser, through
# tools/export_npc_profiles.py. See docs/npc-reference.md.
const PROFILE_TABLE_PATH := "res://resources/original/npc_profiles.json"

static var _profile_table: Dictionary = {}
static var _repairable_types: Dictionary = {}


# The thirty item types sub_4180F0 answers yes for, exported from the binary's own jump
# table by tools/export_repairable_types.py.
static func repairable_types() -> Dictionary:
	if not _repairable_types.is_empty():
		return _repairable_types
	var file := FileAccess.open(REPAIRABLE_TYPES_PATH, FileAccess.READ)
	if file == null:
		push_warning("Missing repairable type table: %s" % REPAIRABLE_TYPES_PATH)
		return _repairable_types
	var parsed = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary):
		push_warning("Repairable type table is not readable: %s" % REPAIRABLE_TYPES_PATH)
		return _repairable_types
	for entry in parsed.get("types", []):
		_repairable_types[int((entry as Dictionary).get("type", -1))] = true
	return _repairable_types


# One parse for every agent on the map, kept on the class rather than the instance.
static func profiles() -> Dictionary:
	if not _profile_table.is_empty():
		return _profile_table
	var file := FileAccess.open(PROFILE_TABLE_PATH, FileAccess.READ)
	if file == null:
		push_warning("Missing NPC profile table: %s" % PROFILE_TABLE_PATH)
		return _profile_table
	var parsed = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary):
		push_warning("NPC profile table is not readable: %s" % PROFILE_TABLE_PATH)
		return _profile_table
	for id in parsed.get("profiles", {}):
		var entry: Dictionary = parsed["profiles"][id]
		var rates: Array = []
		for rate in entry.get("rates", []):
			rates.append(float(rate))
		var rooms: Array = []
		for mask in entry.get("rooms", []):
			rooms.append(int(mask))
		if rates.size() != 8 or rooms.size() != 8:
			push_warning("NPC profile %s lacks its eight rates and room masks: %s" % [id, PROFILE_TABLE_PATH])
			continue
		_profile_table[StringName(id)] = {
			"rates": rates,
			"rooms": rooms,
			"speed_tiles": float(entry.get("speed_tiles", 0.0)),
			"notice_radius_tiles": float(entry.get("notice_radius_tiles", 0.0)),
			"notice_cone_degrees": float(entry.get("notice_cone_degrees", 0.0)),
		}
	return _profile_table


# agent+1732, the world's entity list that sub_418D20 and sub_418EA0 walk: every agent, and
# the player, whom sub_4049F0 appends to the same list (0x404B42).
static func world_entities(world: Node) -> Array[Node2D]:
	var result: Array[Node2D] = []
	var tree := world.get_tree()
	for node in tree.get_nodes_in_group("npc_agents"):
		if node is Node2D and world.is_ancestor_of(node):
			result.append(node)
	for actions in tree.get_nodes_in_group("player_actions"):
		var player := actions.get_parent() as Node2D
		if player != null and world.is_ancestor_of(player):
			result.append(player)
	return result
# Item types sub_417B00 dispatches on; see docs/npc-reference.md.
const WORK_SEATS := [68, 69, 70, 71, 72, 73, 74, 86, 93, 94, 121, 122]
const MONITOR_TYPES := [152, 153, 154, 155]
const CUBICLE_TYPES := [173, 262]
const LOCKED_CUBICLE_REPAIR_TYPE := 173
const COPIER_TYPES := [129]
# The state sub_416340 holds the copier in while its first user photocopies at it.
const COPIER_IN_USE_STATE := 9
# sub_417B00 writes 20.0 to +1124 at the copier on every arrival (0x417E8A).
const COPIER_SECONDS := 20.0
const SPECIAL_ACTIVE_TYPES := [139, 140, 146, 147, 150, 151]
const SPECIAL_PASSIVE_TYPES := [5, 6, 7, 8, 9, 88, 97, 98, 115]
const WORK_CHAIR_TYPES := [68, 69, 70, 71]
const RELAXED_SEAT_TYPES := [121, 122, 179, 180, 181, 182, 183, 184]
# Height 0.1 in sub_4161E0 lifts the seated image by 2.4 screen pixels.
const SEAT_LIFT := Vector2(0.0, -2.4)
const RELAXED_SEAT_SHIFT := 0.3

enum State { IDLE, NAVIGATING, ACTING }

@export var enabled := true:
	set(value):
		enabled = value
		if is_inside_tree() and not value:
			_stop()
@export var assigned_workstation: NodePath
@export var assigned_chair: NodePath
@export var random_seed := 0

var _actor: Node2D
var _profile_id: StringName
var _configuration: Dictionary = {}
var _needs: Array[float] = []
var _rates: Array[float] = []
var _goal_disabled: Array[bool] = []
var _random := RandomNumberGenerator.new()
var _state := State.IDLE
var _goal := -1:
	set(value):
		if _goal != value:
			_goal = value
			goal_changed.emit(value)
var _pending_goal := -1
var _retries := 0
var _retry_delay := 0.0
var _target: Node2D
var _active: Node2D
# agent+1832: the item a filed repair job will reset when the reaction's timer runs out.
var _repair_job: Node2D
# The object whose state this agent raised while using it, put back when it stops.
var _using_object: Node
var _passive: Node2D
var _claimed_seat: Node2D
var _social_refresh := 0.0
# agent+1076, agent+1060 and the once-per-goal flags at agent+980 + 4 * goal.
var aggression := 0.0
var _aggression_share := 0.0
var _aggravated: Array[bool] = []
var _goal_candidates: Array = []
var _alternate_candidates: Array[Node2D] = []
var _has_claim := false
# agent+1824, raised by sub_416090 while the agent is inside a toilet cubicle.
var _inside_cubicle := false
# Set once the cubicle timer has run out on a locked door and sub_416090 turned the goal to 8.
var _shut_in := false
# agent+1812, which sub_417B00 raises at a special-action item for the length of its timer.
var _special_action := false
# agent+1808, raised for the copier's first user while sub_416340 holds the copier in state 9.
var _copying := false
# The per-frame rolls draw from a stream of their own, so the time an agent spends idle does
# not shift the choices a seeded brain makes.
var _frame_random := RandomNumberGenerator.new()
var _frame_debt := 0.0
# Whether slot 0 is already showing, as the idle branch of sub_419CE0 and sub_41E360 reads +126.
var _showing_idle := false
var _initialized := false


func _ready() -> void:
	set_physics_process(false)
	call_deferred("_initialize")


func _initialize() -> void:
	if _initialized:
		return
	_actor = get_parent() as Node2D
	if _actor == null or not _actor.has_method("navigate_to"):
		return
	var actor_profile := _actor.get("profile") as Resource
	if actor_profile == null:
		return
	_profile_id = StringName(actor_profile.get("id"))
	_configuration = profiles().get(_profile_id, {})
	if _configuration.is_empty():
		return
	if random_seed == 0:
		_random.randomize()
		_frame_random.randomize()
	else:
		_random.seed = random_seed
		_frame_random.seed = hash(random_seed)
	for goal in range(8):
		_needs.append(_random.randf_range(20.0, 100.0))
		_rates.append(float(_configuration["rates"][goal]))
		_goal_disabled.append(not SUPPORTED_GOALS.has(goal))
	_needs[3] = 10.0
	_build_candidates()
	# sub_4187F0 disables an item goal whose candidate list came out empty and
	# stops its need from decaying, so it never becomes the lowest again.
	for goal in ITEM_GOALS:
		if not _goal_disabled[goal] and _goal_candidates[goal].is_empty():
			_goal_disabled[goal] = true
	for goal in range(8):
		if _goal_disabled[goal]:
			_rates[goal] = 0.0
	# sub_4187F0's last line: a full meter divided by the goals that survived that scan.
	var shared := 0
	for goal in AGGRESSION_SHARED_GOALS:
		if not _goal_disabled[goal]:
			shared += 1
	_aggression_share = AGGRESSION_LIMIT / float(shared) if shared > 0 else 0.0
	_aggravated.resize(8)
	_actor.connect("destination_reached", _on_destination_reached)
	_actor.connect("navigation_failed", _on_navigation_failed)
	_actor.connect("activity_finished", _on_activity_finished)
	_initialized = true
	set_physics_process(true)


func _physics_process(delta: float) -> void:
	if not enabled or not _initialized:
		return
	var route_path: NodePath = _actor.get("route_path")
	if not route_path.is_empty():
		if _state != State.IDLE:
			_stop()
		return
	_think(delta)
	for frame in range(_elapsed_frames(delta)):
		_run_frame()


# sub_416770's needs and goals, which run on the elapsed time rather than once per frame.
func _think(delta: float) -> void:
	if _state != State.IDLE:
		if _state == State.NAVIGATING and _goal == SOCIAL_GOAL and is_instance_valid(_target):
			_social_refresh -= delta
			if _social_refresh <= 0.0:
				_refresh_social_route()
			return
		if _state == State.NAVIGATING and not is_instance_valid(_target):
			_actor.call("cancel_commands")
			_on_navigation_failed()
		elif _state == State.ACTING and (not is_instance_valid(_target) or (_has_claim and not is_instance_valid(_claimed_seat))):
			_stop()
		return
	# sub_416540 gates a queued start on the same timer that holds the retry delay.
	if _retry_delay > 0.0:
		_retry_delay = maxf(0.0, _retry_delay - delta)
		return
	if _pending_goal >= 0:
		_attempt_goal(_pending_goal)
		if _state != State.IDLE:
			return
	# sub_416770 decays every need on any tick without a route or action, including
	# the ticks where a queued goal has just failed. Skipping those would freeze an
	# agent whose lowest need belongs to a goal it can never satisfy.
	for goal in range(8):
		if _goal_disabled[goal]:
			continue
		_needs[goal] = clampf(_needs[goal] - delta * _rates[goal] * 0.5, 0.0, 100.0)
	_select_goal()


# Whole original frames in this much simulated time, carrying the remainder, so the rolls run
# once per 1/60 s whatever the physics rate or the --fixed-fps step.
func _elapsed_frames(delta: float) -> int:
	_frame_debt += delta
	var frames := 0
	while _frame_debt >= ORIGINAL_FRAME_SECONDS:
		_frame_debt -= ORIGINAL_FRAME_SECONDS
		frames += 1
	return frames


# The end of one frame of the archetype's own tick, once sub_416770 and sub_417730 have run.
func _run_frame() -> void:
	if not _in_idle_branch():
		_showing_idle = false
		return
	if _profile_id in SLOT_READING_PROFILES:
		if not _showing_idle:
			# IDLE#2 plays out, and the first idle frame after it or any other slot only puts
			# slot 0 back (0x419E12, 0x41E451).
			_showing_idle = not bool(_actor.call("is_fidgeting"))
			return
		if (_frame_random.randi() & 0xFFF) > FIDGET_ROLL and bool(_actor.call("fidget")):
			_showing_idle = false
	_look_around()


# The branch of each tick that calls sub_4187A0: the boss's at 0x41983B, the coworkers' at
# 0x419EBF, the janitor's at 0x41A99C and the secretary's at 0x41E4FE. Walking and sitting
# come first in all four. After that only the coworkers' sub_419CE0 branches on the
# special-action flag +1812 and on goal 6, whatever clip those resolve to; the boss's
# sub_419740 and the janitor's sub_41A8D0 branch only on the reaction flag +1820, and the
# secretary's sub_41E360 on neither, so she looks around while she is angry. A cubicle's
# occupant and the copier's first user are faced back the way they were on every frame
# (sub_416090, sub_416340), so a look-around there would barely show; the port leaves them
# still. See docs/npc-reference.md.
func _in_idle_branch() -> bool:
	if _state == State.NAVIGATING:
		return false
	if _state == State.IDLE:
		return true
	if _has_claim or _copying:
		return false
	if _profile_id in COWORKER_PROFILES:
		return not _special_action and _goal != REACTION_GOAL and _goal != SMOKING_GOAL
	return _profile_id == SECRETARY_PROFILE or _goal != REACTION_GOAL


func _look_around() -> void:
	if (_frame_random.randi() & 0xFFF) <= LOOK_AROUND_ROLL:
		return
	_actor.call("turn_view", -1 if (_frame_random.randi() & 0xFF) <= LOOK_BACK_ROLL else 1)


func _select_goal() -> void:
	# sub_415FF0 takes the lowest need among enabled goals; sub_4165D0 queues it below 15.
	var lowest := -1
	for goal in range(8):
		if _goal_disabled[goal]:
			continue
		if lowest < 0 or _needs[goal] < _needs[lowest]:
			lowest = goal
	if lowest < 0:
		lowest = 2
	if _needs[lowest] < 15.0:
		_pending_goal = lowest
		_retry_delay = 0.0


func _attempt_goal(goal: int) -> void:
	# sub_416660: a started goal clears the queue and its failure count; a failed one
	# keeps the queue until the fifth try and only then abandons it.
	var selection := _select_target(goal)
	if selection.is_empty():
		_fail_goal()
		return
	if goal == SOCIAL_GOAL:
		var agent := selection.get("agent") as Node2D
		if not _actor.call("navigate_to", _social_destination(agent)):
			_fail_goal()
			return
		_goal = goal
		_pending_goal = -1
		_retries = 0
		_state = State.NAVIGATING
		_target = agent
		_active = null
		_passive = null
		_social_refresh = SOCIAL_REFRESH_SECONDS
		return
	var active := selection.get("active") as Node2D
	var passive := selection.get("passive") as Node2D
	# sub_416D50 walks to the passive item when the pick produced one, else the active.
	var target := passive if is_instance_valid(passive) else active
	if not is_instance_valid(target) or not _actor.call("navigate_to", _route_end(target.global_position)):
		_fail_goal()
		return
	_goal = goal
	_pending_goal = -1
	_retries = 0
	_state = State.NAVIGATING
	_target = target
	_active = active
	_passive = passive


func _fail_goal() -> void:
	_goal = -1
	_state = State.IDLE
	_target = null
	_active = null
	_passive = null
	_retries += 1
	_retry_delay = _random.randf_range(0.5, 1.5)
	if _retries >= 5:
		_retries = 0
		_pending_goal = -1


func _select_target(goal: int) -> Dictionary:
	if goal == SOCIAL_GOAL:
		var agent := _social_agent()
		return {} if agent == null else {"agent": agent}
	if goal == 3:
		var workstation := get_node_or_null(assigned_workstation) as Node2D if not assigned_workstation.is_empty() else null
		var chair := get_node_or_null(assigned_chair) as Node2D if not assigned_chair.is_empty() else null
		if workstation != null and (not bool(workstation.get("active")) or int(workstation.get("item_type")) not in MONITOR_TYPES):
			workstation = null
		if chair != null and (bool(chair.get("active")) or int(chair.get("item_type")) not in WORK_SEATS):
			chair = null
		if workstation == null and chair != null and int(chair.get("item_type")) not in WORK_CHAIR_TYPES:
			chair = null
		if workstation == null and chair == null:
			# sub_417120 gives up on goal 3 without an assignment; only the unused
			# variant 3 falls back to picking an arbitrary desk.
			return {}
		if _random.randf() < 0.875:
			return {"active": workstation, "passive": chair}
	var candidates := _candidates(goal, goal == 3)
	if candidates.is_empty():
		return {}
	var point := candidates[_random.randi_range(0, candidates.size() - 1)]
	# sub_417120 files the pick into the active or passive slot by its own flag.
	if bool(point.get("active")):
		return {"active": point, "passive": null}
	return {"active": null, "passive": point}


# sub_4187F0 scans the item list once at startup and keeps at most 64 matches per
# goal; sub_417120 then picks at random from that list rather than rescanning.
func _build_candidates() -> void:
	_goal_candidates.clear()
	for goal in range(8):
		_goal_candidates.append(_scan_candidates(int(GOAL_CATEGORIES[goal]), goal))
	_alternate_candidates = _scan_candidates(ALTERNATE_WORK_CATEGORY, 3)


func _scan_candidates(category: int, goal: int) -> Array[Node2D]:
	var result: Array[Node2D] = []
	var room_mask := int(_configuration["rooms"][goal])
	for point in _activity_points():
		var room := int(point.get("room_id"))
		if room < 0 or room >= 32 or room_mask & (1 << room) == 0:
			continue
		if int(point.get("category")) != category:
			continue
		result.append(point)
		if result.size() == 64:
			break
	return result


# Neither sub_417120 nor sub_410EA0 reads item+216: a seat, cubicle or copier someone is
# using stays a candidate, and sub_417B00 only finds out on arrival (0x417D64, 0x417EDB,
# 0x417F16), leaving the agent standing for sub_416660's 10-16 s. That is also what lets a
# colleague reach a cubicle whose occupant has been locked in, and file its repair.
func _candidates(goal: int, alternate_work := false) -> Array[Node2D]:
	var pool: Array = _alternate_candidates if alternate_work else _goal_candidates[goal]
	var result: Array[Node2D] = []
	for point in pool:
		if is_instance_valid(point):
			result.append(point)
	return result


func _social_agent() -> Node2D:
	# sub_417320 scans every agent and keeps the last match rather than the nearest.
	var own_gender := int((_actor.get("profile") as Resource).get("gender"))
	var world := _actor.get_parent()
	var found: Node2D = null
	for node in get_tree().get_nodes_in_group("npc_agents"):
		if node == _actor or not node is Node2D or not world.is_ancestor_of(node):
			continue
		var profile := node.get("profile") as Resource
		if profile == null or int(profile.get("gender")) == own_gender:
			continue
		var offset: Vector2 = node.global_position - _actor.global_position
		if IsoDirection.screen_to_ground(offset).length() < SOCIAL_RANGE_TILES:
			found = node
	return found


func _social_destination(agent: Node2D) -> Vector2:
	var facing: Vector2 = agent.get("last_direction")
	var ahead := IsoDirection.screen_to_ground(facing).normalized() * SOCIAL_APPROACH_TILES
	# sub_416960 rounds this point to its cell too (0x416A60/0x416A72).
	return _route_end(agent.global_position + IsoDirection.ground_to_screen(ahead))


# sub_416D50 rounds the interaction point to a cell with (__int64)(v + 0.5) at 0x416E2B, and
# sub_417730 ends the route on that cell rather than on the point. A* never tests anything but
# the cell itself, so a point flush against a wall is reachable whenever its cell is free,
# which the port's footprint test would refuse at the exact point. See docs/npc-reference.md.
func _route_end(point: Vector2) -> Vector2:
	for layer in get_tree().get_nodes_in_group("collision_maps"):
		if not layer.enabled or not layer.get_parent().is_ancestor_of(_actor):
			continue
		var grid: Vector2 = layer.to_grid_position(point)
		return layer.to_global(layer.map_to_local(Vector2i(floori(grid.x + 0.5), floori(grid.y + 0.5))))
	return point


func _refresh_social_route() -> void:
	_social_refresh = SOCIAL_REFRESH_SECONDS
	if _actor.call("navigate_to", _social_destination(_target)):
		return
	# sub_416960 fails (0x416D3F) with the old route already freed, but goal 5 stays and so
	# does sub_416660's 10-16 s busy timer, which does not run while a route is walked.
	# Without a route it does, and sub_4165D0 then completes the goal: the agent stands
	# where it stopped, still facing the way it walked.
	var facing: Vector2 = _actor.get("last_direction")
	if _actor.call("start_activity", &"idle", _random.randf_range(10.0, 16.0), facing):
		_state = State.ACTING
	else:
		_on_navigation_failed()


func _activity_points() -> Array[Node2D]:
	var result: Array[Node2D] = []
	var world := _actor.get_parent()
	for node in get_tree().get_nodes_in_group("npc_activity_points"):
		if node is Node2D and world.is_ancestor_of(node):
			result.append(node)
	return result


func _focus_position(node: Node2D) -> Vector2:
	# An activity point marks an offset on its object; a social target is its own anchor.
	if node.is_in_group("npc_activity_points"):
		return (node.get_parent() as Node2D).global_position
	return node.global_position


func _available(point: Node2D) -> bool:
	return is_instance_valid(point) and bool(point.call("is_available", _actor))


func _on_destination_reached() -> void:
	if not enabled or _state != State.NAVIGATING:
		return
	if not is_instance_valid(_target):
		_on_navigation_failed()
		return

	# sub_417B00 tests the active item for tampering before it looks at any type, so a
	# sabotaged object is reacted to rather than used.
	if is_instance_valid(_active) and bool(_active.get("tampered")):
		_start_reaction()
		return

	# sub_417B00 picks the action from the arrived item's type. The active slot is
	# checked first; a monitor or cubicle consumes the arrival, anything else also
	# lets the passive slot apply its own rule.
	var duration := _random.randf_range(10.0, 16.0)
	var animation := &"idle"
	var special := &"special-1" if _profile_id in COWORKER_PROFILES else &"idle"
	var special_action := false
	var copying := false
	var claim: Node2D = null
	var seated := false
	var relaxed := false
	# sub_417730 turns an arriving agent toward +1112 or +1116 (0x417809-0x4178F8), which
	# sub_416660 cleared for the social goal, so it keeps the heading it walked in on.
	var focus: Node2D = null if _goal == SOCIAL_GOAL else _target
	var active_handled := false
	if is_instance_valid(_active):
		var active_type := int(_active.get("item_type"))
		focus = _active
		if active_type in MONITOR_TYPES:
			duration = _random.randf_range(50.0, 60.0)
			claim = _find_work_seat()
			seated = claim != null
			active_handled = true
		elif active_type in CUBICLE_TYPES:
			active_handled = true
			if _available(_active):
				duration = _random.randf_range(10.0, 15.0)
				claim = _active
		elif active_type in COPIER_TYPES:
			duration = COPIER_SECONDS
			# Only the copier's first NPC user claims it (0x417E6E) and raises +1808, which has
			# sub_416340 hold it in state 9, so its DESTROYED_1 loop runs in ordinary play with
			# no prank involved. The claim is never let go, and every later visitor, the first
			# one included, stands idle at it for the same 20 s.
			if not bool(_active.get("copier_claimed")):
				_active.set("copier_claimed", true)
				copying = true
				_using_object = _set_object_state(_active, COPIER_IN_USE_STATE)
		elif active_type in SPECIAL_ACTIVE_TYPES:
			duration = 15.0
			animation = special
			special_action = true
	if not active_handled and is_instance_valid(_passive):
		var passive_type := int(_passive.get("item_type"))
		focus = _passive
		if passive_type in SPECIAL_PASSIVE_TYPES:
			duration = 15.0
			animation = special
			special_action = true
		elif passive_type in WORK_CHAIR_TYPES:
			if _available(_passive):
				duration = _random.randf_range(40.0, 50.0)
				claim = _passive
				seated = true
		elif passive_type in RELAXED_SEAT_TYPES:
			if _available(_passive):
				duration = _random.randf_range(15.0, 25.0)
				claim = _passive
				seated = true
				relaxed = true

	if claim != null:
		_claimed_seat = claim
		_has_claim = true
		claim.set("occupant", _actor)
		# sub_416090 keeps agent+1824 raised while the agent is shut in a cubicle, so a
		# colleague in there notices nothing. See docs/catch-reference.md.
		_inside_cubicle = int(claim.get("item_type")) in CUBICLE_TYPES
	if _goal == SMOKING_GOAL and _profile_id in COWORKER_PROFILES:
		# sub_419CE0 plays slot 6 for goal 6; sub_41A510 drops to idle without it.
		animation = &"special-2"
	var placement := _placement(claim, seated, relaxed, focus)
	if seated:
		animation = SEATED_CLIPS.get(_profile_id, &"sit-easy" if relaxed else &"sit-use") as StringName
	var started := bool(_actor.call(
		"start_activity", animation, duration, placement["facing"], placement["anchor"], placement["return"]
	))
	_special_action = started and special_action
	_copying = started and copying
	if started:
		_state = State.ACTING
	else:
		_release_seat()
		_on_navigation_failed()


# sub_417B00's tampered branch, then sub_416450. The agent stands where it arrived and is
# angry for a fixed stretch; the player is paid once, on the spot. See docs/npc-reference.md.
func _start_reaction() -> void:
	_take_offence(_goal)
	var animation := REACTION_CLIPS.get(_profile_id, &"pissed") as StringName
	var facing := _focus_position(_active) - _actor.global_position
	var started := bool(_actor.call(
		"start_activity", animation, _random.randf_range(10.0, 12.0), facing
	))
	if not started:
		_on_navigation_failed()
		return
	# sub_417B00 files the job before the reaction, which then runs as any other: goal 8 and
	# the reaction's own clip, as no tick has a repair branch. Only the timer's end differs.
	_repair_job = _active if _can_repair(_active) else null
	_goal = REACTION_GOAL
	_state = State.ACTING
	var session := get_tree().get_first_node_in_group("level_session")
	if session != null:
		session.call("add_score", REACTION_SCORE, _actor.global_position)


# sub_417B00's bookkeeping, which runs before it raises the reaction and only for a goal
# that is still enabled. The original also adds 25 to the work goal's decay rate, which can
# never be felt because the same branch disables that goal. See docs/npc-reference.md.
func _take_offence(goal: int) -> void:
	if goal < 0 or goal >= _goal_disabled.size() or _goal_disabled[goal]:
		return
	if goal == WORK_GOAL:
		_goal_disabled[WORK_GOAL] = true
		_rates[WORK_GOAL] = 0.0
	if _aggravated[goal]:
		return
	_aggravated[goal] = true
	aggression = minf(aggression + _aggression_share, AGGRESSION_LIMIT)


func _placement(claim: Node2D, seated: bool, relaxed: bool, focus: Node2D) -> Dictionary:
	# sub_4161E0 seats the agent on the item anchor and sub_416090 puts it inside the
	# cubicle; both step back onto the interaction point when the timer runs out.
	var anchor := Vector2.INF
	var return_position := Vector2.INF
	var facing := Vector2.ZERO
	if claim != null:
		var interaction := claim.global_position
		var item := (claim.get_parent() as Node2D).global_position
		var occupies := seated or int(claim.get("item_type")) in CUBICLE_TYPES
		if occupies:
			return_position = interaction
			if relaxed or not seated:
				# Relaxed sitting and cubicle use face out along the interaction offset.
				anchor = item.lerp(interaction, RELAXED_SEAT_SHIFT) if relaxed else item
				facing = interaction - item
			else:
				anchor = item
				facing = item - interaction
			if seated:
				anchor += SEAT_LIFT
	if facing == Vector2.ZERO and is_instance_valid(focus):
		facing = _focus_position(focus) - _actor.global_position
	if facing == Vector2.ZERO:
		facing = _actor.get("last_direction")
	return {"anchor": anchor, "facing": facing.normalized(), "return": return_position}


func _find_work_seat() -> Node2D:
	for point in _activity_points():
		if bool(point.get("active")) or int(point.get("item_type")) not in WORK_SEATS or not _available(point):
			continue
		var anchor := (point.get_parent() as Node2D).global_position
		var distance := IsoDirection.screen_to_ground(anchor - _actor.global_position).length()
		if distance < 1.8:
			return point
	return null


func _on_navigation_failed() -> void:
	if not enabled or _state != State.NAVIGATING:
		return
	# The original builds its whole route up front, so a route can only fail before it
	# starts. Losing one mid-walk is a port safeguard; requeue the goal and retry it.
	_pending_goal = _goal
	_fail_goal()


func _on_activity_finished() -> void:
	if not enabled or _state != State.ACTING:
		return
	# sub_416410 drops +1812 with the timer that ran out, and sub_416340 drops +1808.
	_special_action = false
	_copying = false
	_clear_object_state()
	# sub_416090 once the cubicle timer is spent: a locked door keeps the agent in with goal 8
	# (0x416143), and an open one lets it out only when sub_418EA0 finds nobody else within
	# half a tile of the interaction point (0x4160FE). Either way it asks again next tick.
	if is_locked_in():
		_shut_in = true
		_goal = REACTION_GOAL
		_hold_inside()
		return
	if _inside_cubicle and _exit_is_blocked():
		_hold_inside()
		return
	_release_seat()
	_finish_repair()
	_clear_object_state()
	if _shut_in:
		# sub_4165D0 completes goal 8, whose need slot lies past the eight sub_416770
		# decays, so a freed inmate still wants the toilet it never got to use.
		_shut_in = false
	elif _goal == REACTION_GOAL:
		# sub_416450 ends the reaction by resetting every need, not just the one it was
		# after, so a provoked agent walks away with nothing left to want.
		for goal in range(_needs.size()):
			_needs[goal] = _random.randf_range(60.0, 100.0)
	else:
		_needs[_goal] = _random.randf_range(60.0, 100.0)
	_goal = -1
	_state = State.IDLE
	_target = null
	_active = null
	_passive = null
	_retries = 0


# Actions 110 and 112 shut an occupant in, and sub_416090 never reaches the branch that
# would let them out, so a locked agent keeps its claim until the item is reset -- which is
# what a finished repair does. See docs/prank-reference.md.
func is_locked_in() -> bool:
	return is_instance_valid(_claimed_seat) and bool(_claimed_seat.get("locked_in"))


func _release_seat() -> void:
	if is_locked_in():
		return
	if is_instance_valid(_claimed_seat) and _claimed_seat.get("occupant") == _actor:
		_claimed_seat.set("occupant", null)
	_claimed_seat = null
	_has_claim = false
	_inside_cubicle = false


func _stop() -> void:
	if is_instance_valid(_actor) and _actor.has_method("cancel_commands") and _state != State.IDLE:
		_actor.call("cancel_commands")
	_release_seat()
	_clear_object_state()
	_repair_job = null
	_shut_in = false
	_special_action = false
	_copying = false
	_state = State.IDLE
	_goal = -1
	_pending_goal = -1
	_target = null
	_active = null
	_passive = null
	_retry_delay = 0.0
	_retries = 0


func _exit_tree() -> void:
	_stop()


# sub_418310, the whole of how an agent notices the player. The cheap eight-tile box comes
# first, then the radius, then the cone -- which is bypassed entirely within two tiles, so a
# prank right beside a colleague is seen whatever they are facing -- and finally the same
# sight ray the player's own reach test uses. See docs/catch-reference.md.
const NOTICE_BOX_TILES := 8.0
const NOTICE_ALWAYS_TILES := 2.0
const NOTICE_RADIUS_STEP := 0.2
# sub_419740 alone applies none of the band widenings.
const UNHURRIED_PROFILE := &"boss"
const NOTICE_CONE_STEP := 5.0


func notices(target: Node2D, layer: Node) -> bool:
	if _actor == null or target == null or layer == null or not _initialized:
		return false
	var from: Vector2 = layer.to_grid_position(_actor.global_position)
	var to: Vector2 = layer.to_grid_position(target.global_position)
	var delta := to - from
	if absf(delta.x) > NOTICE_BOX_TILES or absf(delta.y) > NOTICE_BOX_TILES:
		return false
	var distance := delta.length()
	if distance > notice_radius_tiles():
		return false
	if distance > NOTICE_ALWAYS_TILES and absf(_bearing_error(layer, delta)) > notice_cone_degrees() * 0.5:
		return false
	return layer.has_line_of_sight(_actor.global_position, target.global_position)


# The original's heading convention, shared with the player turning to face an item:
# 180 - atan2(dx, dz) * 57.29579, in logical tiles rather than screen pixels.
func _bearing_error(layer: Node, delta: Vector2) -> float:
	var facing: Vector2 = _facing_tiles(layer)
	if facing == Vector2.ZERO or delta == Vector2.ZERO:
		return 0.0
	var error := _heading_degrees(facing) - _heading_degrees(delta)
	error = fposmod(error, 360.0)
	return 360.0 - error if error > 180.0 else error


func _heading_degrees(direction: Vector2) -> float:
	return 180.0 - rad_to_deg(atan2(direction.x, direction.y))


# The actor keeps its heading in screen space; the map is a linear projection, so two
# converted points give the same direction in logical tiles.
func _facing_tiles(layer: Node) -> Vector2:
	var screen: Vector2 = _actor.get("facing_screen")
	if screen == null or screen == Vector2.ZERO:
		return Vector2.ZERO
	var origin: Vector2 = layer.to_grid_position(_actor.global_position)
	return layer.to_grid_position(_actor.global_position + screen * 32.0) - origin


func notice_radius_tiles() -> float:
	return _noticed_value("notice_radius_tiles", NOTICE_RADIUS_STEP)


func notice_cone_degrees() -> float:
	return _noticed_value("notice_cone_degrees", NOTICE_CONE_STEP)


# The three coworker-shaped ticks widen both with the aggression band exactly as they widen
# speed; sub_419740, the boss, applies none of the three.
func _noticed_value(field: String, step: float) -> float:
	var base := float(_configuration.get(field, 0.0))
	if _profile_id == UNHURRIED_PROFILE:
		return base
	return base + step * float(_actor.get("aggression_band"))


# sub_416090 raises agent+1824 while the agent is inside a toilet cubicle, and only clears
# it when it steps back out -- which an agent locked in by action 110 or 112 does only once a
# repair has let it out.
func is_blind() -> bool:
	return _inside_cubicle or is_locked_in()


# sub_417B00 asks sub_4180F0 for a janitor (+1740 == 3, 0x417BCF): one of the thirty types its
# jump table answers yes for, both cubicles among them, locked or not. Everyone else goes to
# sub_4181F0, which only takes a type-173 cubicle whose occupant has been shut in (0x418203),
# so the lockable type 262 waits for the janitor. See docs/npc-reference.md.
func _can_repair(item: Node2D) -> bool:
	if not is_instance_valid(item):
		return false
	var item_type := int(item.get("item_type"))
	if _profile_id == JANITOR_PROFILE:
		return repairable_types().has(item_type)
	return item_type == LOCKED_CUBICLE_REPAIR_TYPE and bool(item.get("locked_in"))


# sub_4164E0's expiry branch: the job is cleared and the item put back the way sub_4100B0
# leaves it, which re-enables every action slot the player had used up.
func _finish_repair() -> void:
	if not is_instance_valid(_repair_job):
		_repair_job = null
		return
	if _repair_job.has_method("reset_actions"):
		_repair_job.call("reset_actions")
	var object := _repair_job.get_parent()
	if object != null and object.has_method("set_state"):
		object.call("set_state", 0)
	_repair_job = null


# An agent that may not leave its cubicle stays on the item's anchor for one more tick, and
# sub_416090 asks again. Only sub_416090 reads +1796, and no tick picks a clip for it, so the
# agent stands in its idle slot whether it is shut in or waiting for the way out; a locked-in
# one is angry through goal 8 alone. It does not re-score the player -- sub_41DEA0 pays once,
# when the agent is first caught out -- and it does not file a repair on its own cubicle:
# sub_4181F0's route belongs to whoever walks up to it next.
func _hold_inside() -> void:
	var placement := _placement(_claimed_seat, false, false, null)
	if not bool(_actor.call(
		"start_activity", &"idle", 0.0, placement["facing"], placement["anchor"], placement["return"]
	)):
		_state = State.IDLE


# sub_418EA0 walks the world's entity list and refuses the way out when any other agent, or
# the player, stands strictly within half a tile of the interaction point on both axes.
func _exit_is_blocked() -> bool:
	var exit := _claimed_seat.global_position
	for entity in world_entities(_actor.get_parent()):
		if entity == _actor:
			continue
		var offset := IsoDirection.screen_to_ground(entity.global_position - exit)
		if absf(offset.x) < 0.5 and absf(offset.y) < 0.5:
			return true
	return false


func _set_object_state(point: Node, state: int) -> Node:
	var object := point.get_parent() if point != null else null
	if object == null or not object.has_method("set_state"):
		return null
	object.call("set_state", state)
	return object


func _clear_object_state() -> void:
	if is_instance_valid(_using_object):
		_using_object.call("set_state", 0)
	_using_object = null
