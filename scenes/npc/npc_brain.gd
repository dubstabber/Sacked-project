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
# holds goal 8 -- the ANGRY bubble -- for as long as the busy timer it starts.
const REACTION_GOAL := 8
# sub_41DEA0(25, agent x, agent y): the player scores for every agent it catches out.
const REACTION_SCORE := 25
# sub_416960 aims 1.2 tiles in front of the other agent and sub_417320 only
# considers agents of the other gender within eight tiles.
const SOCIAL_APPROACH_TILES := 1.2
const SOCIAL_RANGE_TILES := 8.0
# sub_416770 rebuilds a social route every three seconds while it is walking.
const SOCIAL_REFRESH_SECONDS := 3.0
# Verified ordinary goals and profile tables: docs/npc-reference.md.
const PROFILES := {
	&"boss": {
		"rates": [5.0, 5.0, 65.0, 0.0, 10.0, 7.0, 10.0, 20.0],
		"rooms": [10, 266, 328, 256, 128, 76, 264, 72],
	},
	&"male-employee-1": {
		"rates": [12.0, 15.0, 19.0, 87.0, 15.0, 15.0, 13.0, 9.0],
		"rooms": [11, 11, 76, 5, 128, 76, 12, 72],
	},
	&"female-employee-1": {
		"rates": [17.0, 8.0, 16.0, 86.0, 21.0, 17.0, 19.0, 7.0],
		"rooms": [11, 11, 76, 5, 128, 76, 12, 72],
	},
}
# Item types sub_417B00 dispatches on; see docs/npc-reference.md.
const WORK_SEATS := [68, 69, 70, 71, 72, 73, 74, 86, 93, 94, 121, 122]
const MONITOR_TYPES := [152, 153, 154, 155]
const CUBICLE_TYPES := [173, 262]
const COPIER_TYPES := [129]
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
var _passive: Node2D
var _claimed_seat: Node2D
var _social_refresh := 0.0
var _goal_candidates: Array = []
var _alternate_candidates: Array[Node2D] = []
var _has_claim := false
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
	_configuration = PROFILES.get(_profile_id, {})
	if _configuration.is_empty():
		return
	if random_seed == 0:
		_random.randomize()
	else:
		_random.seed = random_seed
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
	if not is_instance_valid(target) or not _actor.call("navigate_to", target.global_position):
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
			if is_instance_valid(workstation) and not _available(workstation):
				return {}
			if is_instance_valid(chair) and not _available(chair):
				chair = null
			if workstation == null and chair == null:
				return {}
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


func _candidates(goal: int, alternate_work := false) -> Array[Node2D]:
	var pool: Array = _alternate_candidates if alternate_work else _goal_candidates[goal]
	var result: Array[Node2D] = []
	for point in pool:
		if _available(point):
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
	return agent.global_position + IsoDirection.ground_to_screen(ahead)


func _refresh_social_route() -> void:
	_social_refresh = SOCIAL_REFRESH_SECONDS
	if not _actor.call("navigate_to", _social_destination(_target)):
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
	var claim: Node2D = null
	var seated := false
	var relaxed := false
	var focus := _target
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
			if _available(_active):
				duration = 20.0
				claim = _active
		elif active_type in SPECIAL_ACTIVE_TYPES:
			duration = 15.0
			animation = &"special-1"
	if not active_handled and is_instance_valid(_passive):
		var passive_type := int(_passive.get("item_type"))
		focus = _passive
		if passive_type in SPECIAL_PASSIVE_TYPES:
			duration = 15.0
			animation = &"special-1"
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
	if _goal == SMOKING_GOAL:
		# sub_419CE0 plays slot 6 for goal 6; sub_41A510 drops to idle without it.
		animation = &"special-2"
	var placement := _placement(claim, seated, relaxed, focus)
	if seated:
		animation = &"sit-easy" if relaxed else (&"sit-idle" if _profile_id == &"boss" else &"sit-use")
	var started := bool(_actor.call(
		"start_activity", animation, duration, placement["facing"], placement["anchor"], placement["return"]
	))
	if started:
		_state = State.ACTING
	else:
		_release_seat()
		_on_navigation_failed()


# sub_417B00's tampered branch, then sub_416450. The agent stands where it arrived and is
# angry for a fixed stretch; the player is paid once, on the spot. The original also nudges
# its aggression at agent+952 and hands a janitor the repair job at agent+1816 -- neither
# system exists here yet, so neither is reproduced. See docs/npc-reference.md.
func _start_reaction() -> void:
	var animation := &"explode" if _profile_id == &"boss" else &"pissed"
	var facing := _focus_position(_active) - _actor.global_position
	var started := bool(_actor.call(
		"start_activity", animation, _random.randf_range(10.0, 12.0), facing
	))
	if not started:
		_on_navigation_failed()
		return
	_goal = REACTION_GOAL
	_state = State.ACTING
	var session := get_tree().get_first_node_in_group("level_session")
	if session != null:
		session.call("add_score", REACTION_SCORE, _actor.global_position)


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
	_release_seat()
	if _goal == REACTION_GOAL:
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


func _release_seat() -> void:
	if is_instance_valid(_claimed_seat) and _claimed_seat.get("occupant") == _actor:
		_claimed_seat.set("occupant", null)
	_claimed_seat = null
	_has_claim = false


func _stop() -> void:
	if is_instance_valid(_actor) and _actor.has_method("cancel_commands") and _state != State.IDLE:
		_actor.call("cancel_commands")
	_release_seat()
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
