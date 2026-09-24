extends SceneTree


const BRAIN := preload("res://scenes/npc/npc_brain.gd")
const POINT := preload("res://scenes/npc/npc_activity_point.gd")
const COLLISION_SCRIPT := preload("res://scenes/shared/collision_map_layer.gd")
const COLLISION_TILESET := preload("res://resources/tilemaps/sacked-collision.tres")

class TestProfile extends Resource:
	var id: StringName = &"male-employee-1"
	var gender: int = 0

class AgentStub extends Node2D:
	var profile: Resource
	var last_direction := Vector2.RIGHT

class SessionStub extends Node:
	var score := 0
	var scored_at := Vector2.INF

	func _enter_tree() -> void:
		add_to_group("level_session")

	func add_score(points: int, world_position := Vector2.INF) -> void:
		score += points
		scored_at = world_position

class Actor extends Node2D:
	signal destination_reached
	signal navigation_failed
	signal activity_finished
	var profile: Resource = TestProfile.new()
	var route_path := NodePath()
	var last_direction := Vector2.RIGHT
	var destination := Vector2.INF
	var activity: Dictionary = {}
	var cancel_count := 0
	var activity_available := true
	var navigation_available := true
	var _return_position := Vector2.INF

	func navigate_to(target_global: Vector2) -> bool:
		if not navigation_available:
			return false
		destination = target_global
		return true

	func start_activity(animation: StringName, duration: float, facing: Vector2, anchor := Vector2.INF, return_position := Vector2.INF) -> bool:
		if not activity_available:
			return false
		activity = {"animation": animation, "duration": duration, "facing": facing, "anchor": anchor, "return_position": return_position}
		_return_position = return_position
		if anchor.is_finite():
			global_position = anchor
		return true

	func finish_activity() -> void:
		_restore_position()
		activity_finished.emit()

	func cancel_commands() -> void:
		cancel_count += 1
		destination = Vector2.INF
		activity.clear()
		_restore_position()

	func _restore_position() -> void:
		if _return_position.is_finite():
			global_position = _return_position
		_return_position = Vector2.INF

var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_check_work_cycle()
	_check_filters()
	_check_room_masks()
	_check_cleanup()
	_check_arrival_actions()
	_check_arriving_at_a_taken_target()
	_check_reacting_to_a_tampered_item()
	_check_repairing_a_broken_item()
	_check_rescuing_a_locked_in_colleague()
	_check_social_target()
	_check_routes_end_on_cell_centres()
	_check_interrupted_activity()
	_check_routes_and_retry_limit()
	if _failures == 0:
		print("NPC brain: source needs, target filters, arrival actions, retry limits and claim cleanup passed")
	quit(1 if _failures else 0)


func _fixture(profile_id := &"male-employee-1") -> Dictionary:
	var world := Node2D.new()
	root.add_child(world)
	var chair := _point(world, "Chair", Vector2(3, 2), Vector2(1, 0), 6, 68, 0, false)
	var monitor := _point(world, "Monitor", Vector2(3, 3), Vector2(1, 0), 6, 152, 0, true)
	var actor := Actor.new()
	actor.name = "NPC"
	actor.position = chair.global_position
	actor.profile.id = profile_id
	var brain := BRAIN.new()
	brain.name = "Brain"
	brain.random_seed = 1037
	brain.assigned_workstation = NodePath("../../Monitor/ActivityPoint")
	brain.assigned_chair = NodePath("../../Chair/ActivityPoint")
	actor.add_child(brain)
	world.add_child(actor)
	brain._initialize()
	brain.set_physics_process(false)
	return {"world": world, "actor": actor, "brain": brain, "chair": chair, "monitor": monitor}


func _point(world: Node2D, label: String, ground: Vector2, offset: Vector2, category: int, item_type: int, room: int, active: bool) -> Node2D:
	var object := Node2D.new()
	object.name = label
	object.position = IsoDirection.ground_to_screen(ground)
	world.add_child(object)
	var point := POINT.new()
	point.name = "ActivityPoint"
	point.position = IsoDirection.ground_to_screen(offset)
	point.category = category
	point.item_type = item_type
	point.room_id = room
	point.active = active
	object.add_child(point)
	return point


func _begin_work(fixture: Dictionary) -> void:
	var brain: Node = fixture["brain"]
	brain._random.seed = 1
	brain._attempt_goal(3)
	var actor: Actor = fixture["actor"]
	_expect(actor.destination.is_finite(), "an assigned workstation produces a navigation command")
	actor.destination_reached.emit()


func _check_work_cycle() -> void:
	var fixture := _fixture()
	var brain: Node = fixture["brain"]
	var actor: Actor = fixture["actor"]
	var chair: Node2D = fixture["chair"]
	_expect(brain._needs[3] == 10.0, "the original work need starts at ten")
	for goal in [0, 1, 2, 4, 5, 6, 7]:
		_expect(brain._needs[goal] >= 20.0 and brain._needs[goal] <= 100.0, "other original needs start between twenty and one hundred")
	for goal in [5, 6]:
		_expect(not brain._goal_disabled[goal], "sub_4187F0 never disables the social or smoking goal %d" % goal)
	_expect(not brain._goal_disabled[3], "the assigned work goal stays enabled")
	_expect(brain._rates[3] > 0.0, "an enabled goal keeps its original decay rate")
	for goal in [0, 1, 2]:
		_expect(brain._goal_disabled[goal], "goal %d without any candidate item is disabled like sub_4187F0" % goal)
	for goal in range(8):
		if brain._goal_disabled[goal]:
			_expect(brain._rates[goal] == 0.0, "disabled goal %d stops decaying" % goal)
	brain._random.seed = 1
	brain._physics_process(0.02)
	brain._physics_process(0.02)
	_expect(actor.destination == chair.global_position, "the initial work need walks to the assigned chair interaction point")
	actor.destination_reached.emit()
	_expect(actor.activity.get("animation") == &"sit-use", "ordinary coworker work uses the supplied sitting animation")
	_expect(float(actor.activity.get("duration", 0.0)) >= 50.0 and float(actor.activity.get("duration", 0.0)) <= 60.0, "monitor work uses the original fifty-to-sixty-second duration")
	_expect(chair.get("occupant") == actor, "the working actor claims its chair")
	_expect(actor.global_position.is_equal_approx((chair.get_parent() as Node2D).global_position + Vector2(0, -2.4)), "the seated anchor preserves original logical height")
	_expect(actor.activity.get("facing") == -IsoDirection.ground_to_screen(Vector2.RIGHT).normalized(), "work sitting faces opposite the interaction offset")
	actor.finish_activity()
	_expect(chair.get("occupant") == null, "completing work releases the chair")
	_expect(actor.global_position == chair.global_position, "completing work returns to the interaction point")
	_expect(brain._needs[3] >= 60.0 and brain._needs[3] <= 100.0, "a completed need resets to the original sixty-to-one-hundred range")
	fixture["world"].free()


func _check_filters() -> void:
	var fixture := _fixture()
	var world: Node2D = fixture["world"]
	var brain: Node = fixture["brain"]
	var valid := _point(world, "Plant", Vector2(6, 5), Vector2.ZERO, 9, 30, 2, false)
	_point(world, "WrongRoom", Vector2(7, 5), Vector2.ZERO, 9, 30, 7, false)
	var fridge := _point(world, "Fridge", Vector2(8, 5), Vector2.ZERO, 4, 150, 0, true)
	var other_world := Node2D.new()
	root.add_child(other_world)
	_point(other_world, "ForeignPlant", Vector2(6, 5), Vector2.ZERO, 9, 30, 2, false)
	brain._build_candidates()
	_expect(brain._candidates(2) == [valid], "targets obey goal category, room mask and current world")
	_expect(brain._candidates(0) == [fridge], "a special-action item is an ordinary candidate for its goal")
	valid.set("occupant", other_world)
	_expect(brain._candidates(2) == [valid], "sub_417120 keeps a claimed point on the list; only the arrival tests it")
	var chair: Node2D = fixture["chair"]
	chair.set("occupant", other_world)
	_begin_work(fixture)
	_expect(fixture["actor"].activity.get("animation") == &"idle", "a monitor visitor does not take an occupied chair")
	_expect(chair.get("occupant") == other_world, "another actor's chair claim is preserved")
	fixture["world"].free()
	other_world.free()


# Each archetype's initialiser writes its own eight room masks, exported from the binary by
# tools/export_npc_profiles.py. Goal 3's mask is where they part: rooms 0 and 2 for
# coworkers (5), room 2 for the secretary (4, sub_41E2C0), rooms 1, 2 and 4 for the janitor
# (22, sub_41A830). On level 8 the coworkers' row put a room-0 flipchart on her list.
func _check_room_masks() -> void:
	for profile_id in BRAIN.profiles():
		_expect(BRAIN.profiles()[profile_id]["rooms"].size() == 8, "%s has eight exported room masks" % profile_id)
	var expected := {
		&"male-employee-1": ["Room0", "Room2"],
		&"secretary": ["Room2"],
		&"janitor": ["Room1", "Room2", "Room4"],
	}
	for profile_id: StringName in expected:
		var fixture := _fixture(profile_id)
		var world: Node2D = fixture["world"]
		for room in range(5):
			_point(world, "Room%d" % room, Vector2(6 + room, 5), Vector2.ZERO, 2, 128, room, true)
		fixture["brain"]._build_candidates()
		var names: Array[String] = []
		for point in fixture["brain"]._alternate_candidates:
			names.append(String(point.get_parent().name))
		_expect(names == expected[profile_id], "%s picks alternate work in %s, got %s" % [profile_id, expected[profile_id], names])
		world.free()


func _check_cleanup() -> void:
	var fixture := _fixture()
	_begin_work(fixture)
	var brain: Node = fixture["brain"]
	var actor: Actor = fixture["actor"]
	var chair: Node2D = fixture["chair"]
	brain.enabled = false
	_expect(chair.get("occupant") == null, "disabling the brain releases its chair immediately")
	_expect(actor.cancel_count == 1 and actor.global_position == chair.global_position, "disabling cancels commands and restores the standing position")
	brain.enabled = true
	_begin_work(fixture)
	brain.free()
	_expect(chair.get("occupant") == null, "removing the brain releases its chair")
	_expect(actor.global_position == chair.global_position, "removing the brain restores the standing position")
	fixture["world"].free()


func _check_routes_and_retry_limit() -> void:
	var fixture := _fixture()
	var brain: Node = fixture["brain"]
	var actor: Actor = fixture["actor"]
	actor.route_path = NodePath("AuthoredRoute")
	brain._physics_process(30.0)
	brain._physics_process(30.0)
	_expect(not actor.destination.is_finite(), "an explicit authored route overrides autonomous goals")
	actor.route_path = NodePath()
	brain.assigned_workstation = NodePath()
	brain.assigned_chair = NodePath()
	_expect(brain._select_target(3).is_empty(), "work does not invent an assignment when none exists")
	for attempt in range(5):
		brain._attempt_goal(3)
		_expect(brain._retry_delay >= 0.5 and brain._retry_delay <= 1.5, "unreachable work retries after the original delay")
	_expect(brain._pending_goal == -1, "five failed attempts abandon the queued goal")
	fixture["world"].free()


func _check_social_target() -> void:
	var fixture := _fixture()
	var world: Node2D = fixture["world"]
	var brain: Node = fixture["brain"]
	var actor: Actor = fixture["actor"]
	_expect(brain._select_target(5).is_empty(), "social needs another agent to walk to")
	_agent(world, "SameGender", 0, Vector2(4, 2))
	_expect(brain._select_target(5).is_empty(), "social ignores an agent of its own gender")
	_agent(world, "FarAway", 1, Vector2(40, 40))
	_expect(brain._select_target(5).is_empty(), "social ignores an agent beyond the original eight tiles")
	_agent(world, "First", 1, Vector2(5, 2))
	var partner := _agent(world, "Partner", 1, Vector2(4, 3))
	_expect(brain._select_target(5).get("agent") == partner, "sub_417320 keeps the last matching agent, not the nearest")

	brain._attempt_goal(5)
	_expect(brain._state == BRAIN.State.NAVIGATING and brain._goal == 5, "social starts a route of its own")
	var ahead := IsoDirection.screen_to_ground(partner.last_direction).normalized() * 1.2
	_expect(actor.destination.is_equal_approx(partner.global_position + IsoDirection.ground_to_screen(ahead)), "social aims 1.2 tiles in front of the other agent")
	actor.destination = Vector2.INF
	brain._physics_process(1.0)
	_expect(not actor.destination.is_finite(), "a social route holds for the original three seconds")
	brain._physics_process(2.1)
	_expect(actor.destination.is_finite(), "a social route is rebuilt once its refresh elapses")

	actor.destination_reached.emit()
	_expect(actor.activity.get("animation") == &"idle", "a social visit stands and talks")
	_expect(float(actor.activity.get("duration", 0.0)) >= 10.0 and float(actor.activity.get("duration", 0.0)) <= 16.0, "a social visit keeps the default action timer")
	_expect(actor.activity.get("facing") == (partner.global_position - actor.global_position).normalized(), "a social visit faces the other agent, not its parent")
	world.free()


# sub_416D50 rounds the interaction point to its cell (0x416E2B) and sub_416960 the social
# point (0x416A60); both routes end on that cell's centre. The level-1 sofa's point is 0.79
# tiles from a blocked cell, inside the footprint, while its own cell is free.
func _check_routes_end_on_cell_centres() -> void:
	var fixture := _fixture()
	var world: Node2D = fixture["world"]
	var brain: Node = fixture["brain"]
	var actor: Actor = fixture["actor"]
	var layer := COLLISION_SCRIPT.new() as TileMapLayer
	layer.tile_set = COLLISION_TILESET
	# Put the grid's cell (0, 0) on the fixture's ground origin.
	layer.position = -IsoDirection.ground_to_screen(Vector2(1, 0))
	layer.set_cell(Vector2i(7, 3), 0, Vector2i.ZERO)
	world.add_child(layer)
	var sofa := _point(world, "Sofa", Vector2(7.208, 3.125), Vector2(-1, 0), 7, 182, 3, false)
	_expect(layer.to_grid_position(sofa.global_position).is_equal_approx(Vector2(6.208, 3.125)), "the fixture grid is the fixture's ground plane")
	brain._build_candidates()
	brain._attempt_goal(7)
	_expect(brain._state == BRAIN.State.NAVIGATING and brain._target == sofa, "the sofa is picked for goal 7")
	_expect(actor.destination.is_equal_approx(IsoDirection.ground_to_screen(Vector2(6, 3))), "the route ends on the centre of the sofa's cell, got %s" % layer.to_grid_position(actor.destination))

	var partner := _agent(world, "Partner", 1, Vector2(4, 3))
	var ahead := Vector2(4, 3) + IsoDirection.screen_to_ground(partner.last_direction).normalized() * 1.2
	var cell := Vector2(floorf(ahead.x + 0.5), floorf(ahead.y + 0.5))
	_expect(brain._social_destination(partner).is_equal_approx(IsoDirection.ground_to_screen(cell)), "the social route ends on the centre of the cell 1.2 tiles in front")
	world.free()


func _agent(world: Node2D, label: String, gender: int, ground: Vector2) -> AgentStub:
	var agent := AgentStub.new()
	agent.name = label
	agent.position = IsoDirection.ground_to_screen(ground)
	var profile := TestProfile.new()
	profile.gender = gender
	agent.profile = profile
	agent.last_direction = IsoDirection.get_screen_directions()[0]
	agent.add_to_group("npc_agents")
	world.add_child(agent)
	return agent


func _check_arrival_actions() -> void:
	# sub_417B00 dispatch: the arrived item's type picks animation, duration and claim.
	var cubicle := _arrive(_point_fixture(8, 173, 7, true))
	_expect(cubicle["animation"] == &"idle", "a toilet cubicle is entered standing")
	_expect(cubicle["duration"] >= 10.0 and cubicle["duration"] <= 15.0, "a cubicle uses the original ten-to-fifteen-second stay")
	_expect(cubicle["claimed"], "entering a cubicle claims it")
	_expect(cubicle["anchor"].is_equal_approx(cubicle["item"]), "a cubicle occupant stands on the item anchor")
	_expect(cubicle["facing"] == (cubicle["interaction"] - cubicle["item"]).normalized(), "a cubicle occupant faces back out of the stall")

	var sofa := _arrive(_point_fixture(7, 182, 3, false))
	_expect(sofa["animation"] == &"sit-easy", "a coworker's sofa uses the relaxed sitting clip")
	_expect(sofa["duration"] >= 15.0 and sofa["duration"] <= 25.0, "relaxed sitting uses the original fifteen-to-twenty-five-second duration")
	_expect(sofa["claimed"], "relaxed sitting claims its seat")
	_expect(sofa["anchor"].is_equal_approx(sofa["item"].lerp(sofa["interaction"], 0.3) + Vector2(0, -2.4)), "relaxed sitting shifts thirty percent toward the interaction point")
	_expect(sofa["facing"] == (sofa["interaction"] - sofa["item"]).normalized(), "relaxed sitting faces along the interaction offset")

	# Each tick picks its own seated slot: sub_419740 plays the boss's SIT#IDLE on any seat,
	# sub_41A8D0 the janitor's SIT#EASY on any seat, and the secretary sits like a coworker.
	var seated_clips := {
		&"boss": [&"sit-idle", &"sit-idle"],
		&"janitor": [&"sit-easy", &"sit-easy"],
		&"secretary": [&"sit-easy", &"sit-use"],
		&"male-employee-1": [&"sit-easy", &"sit-use"],
	}
	for profile_id: StringName in seated_clips:
		var relaxed := _arrive(_point_fixture(7, 182, 3, false, profile_id))
		var working := _arrive(_point_fixture(6, 68, 0, false, profile_id))
		_expect(relaxed["animation"] == seated_clips[profile_id][0], "%s sits on a sofa with %s, got %s" % [profile_id, seated_clips[profile_id][0], relaxed["animation"]])
		_expect(working["animation"] == seated_clips[profile_id][1], "%s sits on a work chair with %s, got %s" % [profile_id, seated_clips[profile_id][1], working["animation"]])
		_expect(relaxed["anchor"].is_equal_approx(relaxed["item"].lerp(relaxed["interaction"], 0.3) + Vector2(0, -2.4)), "%s keeps the relaxed seat's thirty percent shift" % profile_id)
		_expect(relaxed["facing"] == (relaxed["interaction"] - relaxed["item"]).normalized(), "%s faces out of a relaxed seat" % profile_id)

	var machine := _arrive(_point_fixture(5, 140, 0, true))
	_expect(machine["animation"] == &"special-1", "a drinks machine plays the special action")
	_expect(is_equal_approx(machine["duration"], 15.0), "a special action lasts the original fifteen seconds")
	_expect(not machine["claimed"], "a special action does not claim its item")

	var copier := _arrive(_point_fixture(2, 129, 0, true))
	_expect(is_equal_approx(copier["duration"], 20.0), "the copier runs for the original twenty seconds")
	_expect(copier["claimed"], "using the copier claims it")

	var ashtray := _arrive(_point_fixture(1, 234, 3, false), 6)
	_expect(ashtray["animation"] == &"special-2", "smoking asks for slot 6 and falls back to idle without it")
	_expect(ashtray["duration"] >= 10.0 and ashtray["duration"] <= 16.0, "smoking keeps the default action timer")

	# sub_417B00 raises the special-action flag for every archetype, but only the coworkers'
	# tick reads it (sub_419CE0, 0x419DC3), or goal 6. The others stand idle for the same time.
	for profile_id: StringName in [&"boss", &"secretary", &"janitor", &"male-employee-2"]:
		var coworker := profile_id == &"male-employee-2"
		var expected := &"special-1" if coworker else &"idle"
		var active_special := _arrive(_point_fixture(5, 140, 0, true, profile_id))
		var passive_special := _arrive(_point_fixture(4, 5, 0, false, profile_id))
		_expect(active_special["animation"] == expected, "%s at a drinks machine plays %s, got %s" % [profile_id, expected, active_special["animation"]])
		_expect(passive_special["animation"] == expected, "%s at a passive special item plays %s, got %s" % [profile_id, expected, passive_special["animation"]])
		_expect(is_equal_approx(active_special["duration"], 15.0) and is_equal_approx(passive_special["duration"], 15.0), "%s keeps the special action's fifteen seconds" % profile_id)
		var smoking := _arrive(_point_fixture(1, 234, 3, false, profile_id), 6)
		_expect(smoking["animation"] == (&"special-2" if coworker else &"idle"), "%s smokes with %s" % [profile_id, &"special-2" if coworker else &"idle"])

	var plant := _arrive(_point_fixture(9, 30, 0, false))
	_expect(plant["animation"] == &"idle", "an ordinary target keeps the standing idle")
	_expect(plant["duration"] >= 10.0 and plant["duration"] <= 16.0, "an ordinary target keeps the default action timer")


func _point_fixture(category: int, item_type: int, room: int, active: bool, profile_id := &"male-employee-1") -> Dictionary:
	var fixture := _fixture(profile_id)
	var point := _point(fixture["world"], "Target", Vector2(6, 5), Vector2(1, 0), category, item_type, room, active)
	fixture["brain"]._build_candidates()
	fixture["point"] = point
	return fixture


func _arrive(fixture: Dictionary, goal := 2) -> Dictionary:
	var brain: Node = fixture["brain"]
	var actor: Actor = fixture["actor"]
	var point: Node2D = fixture["point"]
	brain._target = point
	if point.active:
		brain._active = point
	else:
		brain._passive = point
	brain._state = BRAIN.State.NAVIGATING
	brain._goal = goal
	actor.destination_reached.emit()
	var result := {
		"animation": actor.activity.get("animation"),
		"duration": float(actor.activity.get("duration", 0.0)),
		"facing": actor.activity.get("facing", Vector2.ZERO),
		"anchor": actor.activity.get("anchor", Vector2.INF),
		"claimed": point.get("occupant") == actor,
		"item": (point.get_parent() as Node2D).global_position,
		"interaction": point.global_position,
	}
	fixture["world"].free()
	return result


# sub_417120 picks without reading item+216, so an agent walks to a seat or cubicle somebody
# else holds. sub_417B00 finds it taken only on arrival (0x417D64 cubicles, 0x417F16 relaxed
# seats), and the agent stands there for sub_416660's 10-16 s before the goal completes.
func _check_arriving_at_a_taken_target() -> void:
	for spec in [[8, 173, 7, true, 4], [7, 182, 3, false, 7]]:
		var fixture := _point_fixture(spec[0], spec[1], spec[2], spec[3])
		var brain: Node = fixture["brain"]
		var actor: Actor = fixture["actor"]
		var point: Node2D = fixture["point"]
		var goal: int = spec[4]
		var holder := Node2D.new()
		fixture["world"].add_child(holder)
		point.set("occupant", holder)
		_expect(brain._select_target(goal).values().has(point), "goal %d still picks the taken type %d" % [goal, spec[1]])
		brain._attempt_goal(goal)
		_expect(brain._state == BRAIN.State.NAVIGATING and brain._target == point, "goal %d walks to the taken type %d" % [goal, spec[1]])
		actor.destination_reached.emit()
		var duration := float(actor.activity.get("duration", 0.0))
		_expect(actor.activity.get("animation") == &"idle", "type %d, taken: the agent stands idle" % spec[1])
		_expect(duration >= 10.0 and duration <= 16.0, "type %d, taken: the default 10-16 s timer runs, got %f" % [spec[1], duration])
		_expect(actor.activity.get("anchor", Vector2.INF) == Vector2.INF, "type %d, taken: the agent stays where it arrived" % spec[1])
		_expect(point.get("occupant") == holder, "type %d, taken: the holder keeps its claim" % spec[1])
		brain._needs[goal] = 1.0
		actor.finish_activity()
		_expect(brain._state == BRAIN.State.IDLE and brain._needs[goal] >= 60.0, "type %d, taken: the wait still completes goal %d" % [spec[1], goal])
		fixture["world"].free()

	# Goal 3's pair comes back whole even when the assigned chair is taken; the monitor's own
	# seat search (sub_418230, tested in _check_filters) is what skips it.
	var work := _fixture()
	var chair: Node2D = work["chair"]
	chair.set("occupant", work["world"])
	var pairs := 0
	for attempt in range(16):
		var selection: Dictionary = work["brain"]._select_target(3)
		if selection.get("active") == work["monitor"]:
			pairs += 1
			_expect(selection.get("passive") == chair, "the assigned pair keeps its taken chair")
	_expect(pairs > 0, "the assigned pair is drawn 7 times in 8")
	work["world"].free()


# sub_417B00 checks the item it arrived at for tampering before it looks at the type, and
# sub_416450 runs the reaction from there. See docs/npc-reference.md.
func _check_reacting_to_a_tampered_item() -> void:
	var session := SessionStub.new()
	root.add_child(session)

	var fixture := _point_fixture(9, 30, 0, true)
	var brain: Node = fixture["brain"]
	var actor: Actor = fixture["actor"]
	var point: Node2D = fixture["point"]
	_expect(not bool(point.get("tampered")), "an untouched object is not tampered with")
	point.set("tampered", true)
	brain._target = point
	brain._active = point
	brain._state = BRAIN.State.NAVIGATING
	brain._goal = 2
	actor.destination_reached.emit()

	_expect(actor.activity.get("animation") == &"pissed", "a coworker reacts with its PISSED clip")
	var duration := float(actor.activity.get("duration", 0.0))
	_expect(duration >= 10.0 and duration <= 12.0, "the reaction lasts the original ten to twelve seconds, got %f" % duration)
	_expect(brain._goal == BRAIN.REACTION_GOAL, "the reaction holds goal 8, which is what raises the ANGRY bubble")
	_expect(brain._state == BRAIN.State.ACTING, "the reaction is an action, not a failed arrival")
	_expect(point.get("occupant") != actor, "reacting to an object does not claim it")
	_expect(session.score == BRAIN.REACTION_SCORE, "catching an agent out pays the player 25, got %d" % session.score)
	# sub_41DEA0 floats that 25 at the agent, not at the player.
	_expect(session.scored_at == actor.global_position, "the 25 is scored where the agent is standing")
	_expect(actor.activity.get("anchor", Vector2.INF) == Vector2.INF, "the agent reacts where it arrived")

	# sub_416450 resets every need on the way out, not just the one it was pursuing.
	for goal in range(brain._needs.size()):
		brain._needs[goal] = 1.0
	actor.finish_activity()
	var reset := true
	for goal in range(brain._needs.size()):
		if brain._needs[goal] < 60.0 or brain._needs[goal] > 100.0:
			reset = false
	_expect(reset, "ending the reaction resets all eight needs to 60..100")
	_expect(brain._goal == -1 and brain._state == BRAIN.State.IDLE, "the agent is free again once it has calmed down")
	fixture["world"].free()

	# The boss has no PISSED clip; its reaction slot is STAND#EXPLODE.
	var boss_fixture := _fixture(&"boss")
	var boss_point := _point(boss_fixture["world"], "Target", Vector2(6, 5), Vector2(1, 0), 9, 30, 0, true)
	boss_fixture["brain"]._build_candidates()
	boss_point.set("tampered", true)
	boss_fixture["brain"]._target = boss_point
	boss_fixture["brain"]._active = boss_point
	boss_fixture["brain"]._state = BRAIN.State.NAVIGATING
	boss_fixture["brain"]._goal = 2
	(boss_fixture["actor"] as Actor).destination_reached.emit()
	_expect((boss_fixture["actor"] as Actor).activity.get("animation") == &"explode", "the boss reacts with STAND#EXPLODE")
	boss_fixture["world"].free()

	# An untampered item of the same type still dispatches on its type.
	var paid := session.score
	var clean := _arrive(_point_fixture(9, 30, 0, true))
	_expect(clean["animation"] == &"idle", "an untampered object is used, not reacted to")
	_expect(session.score == paid, "an untampered object pays nothing")

	# sub_40FEF0 clears item+228 with the rest of the item state.
	var reset_point := _point(Node2D.new(), "Reset", Vector2.ZERO, Vector2.ZERO, 9, 30, 0, true)
	reset_point.set("tampered", true)
	reset_point.call("reset_actions")
	_expect(not bool(reset_point.get("tampered")), "resetting an item clears the tampering flag")
	reset_point.get_parent().free()

	session.free()


func _check_interrupted_activity() -> void:
	var fixture := _fixture()
	var brain: Node = fixture["brain"]
	var actor: Actor = fixture["actor"]
	var chair: Node2D = fixture["chair"]
	actor.activity_available = false
	_begin_work(fixture)
	_expect(brain._state == BRAIN.State.IDLE and brain._pending_goal == 3, "an unavailable action clip retries instead of entering an activity")
	_expect(chair.get("occupant") == null, "an unavailable action clip cannot retain its seat claim")
	actor.activity_finished.emit()
	_expect(brain._needs[3] == 10.0, "a deferred rejected-action signal cannot satisfy a need")
	actor.activity_available = true
	_begin_work(fixture)
	var standing_position := chair.global_position
	chair.get_parent().free()
	brain._physics_process(0.02)
	_expect(brain._state == BRAIN.State.IDLE, "removing an active seat cancels its action")
	_expect(actor.cancel_count == 1 and actor.global_position == standing_position, "removing an active seat restores the standing position")
	fixture["world"].free()


func _expect(condition: bool, label: String) -> void:
	if not condition:
		_failures += 1
		push_error(label)


# sub_417B00 files the job for a janitor whose broken item is one of the thirty types
# sub_4180F0 lists. The reaction runs as any other, goal 8 and the ANGRY bubble: sub_416770
# asks sub_416450 first and stops there while it is busy, so sub_4164E0's goal 9 is never
# shown. sub_4164E0 only sees the timer's end, and puts the item back through sub_4100B0.
# See docs/npc-reference.md.
func _check_repairing_a_broken_item() -> void:
	var session := SessionStub.new()
	root.add_child(session)

	# Type 152 is a workstation, and one of the thirty the jump table answers yes for.
	var repairable := BRAIN.repairable_types()
	_expect(repairable.size() == 30, "the exported table holds thirty repairable types, got %d" % repairable.size())
	_expect(repairable.has(152), "the workstation type 152 is repairable")
	_expect(not repairable.has(68), "the chair type 68 is not")

	var fixture := _point_fixture(9, 152, 0, true, &"janitor")
	var brain: Node = fixture["brain"]
	var actor: Actor = fixture["actor"]
	var point: Node2D = fixture["point"]
	point.action_ids = PackedInt32Array([1, 0, 0, 0, 0, 0, 0, 0])
	point.reset_actions()
	point.set("tampered", true)
	point.disable_slot(0)

	brain._target = point
	brain._active = point
	brain._state = BRAIN.State.NAVIGATING
	brain._goal = 2
	actor.destination_reached.emit()

	_expect(brain._goal == BRAIN.REACTION_GOAL, "a janitor filing a repair holds goal 8, the ANGRY bubble, got %d" % brain._goal)
	# No tick has a repair branch, so the janitor is angry rather than busy.
	_expect(actor.activity.get("animation") == &"pissed", "the janitor still plays the reaction clip")
	_expect(brain._repair_job == point, "the job names the item it will put back")
	_expect(bool(point.get("tampered")), "the item is still broken while the repair runs")
	_expect(not point.is_action_enabled(0), "its used-up action is still disabled mid-repair")

	actor.finish_activity()
	_expect(brain._goal == -1 and brain._state == BRAIN.State.IDLE, "the janitor is free once the repair is done")
	_expect(not bool(point.get("tampered")), "a finished repair clears the tampering")
	_expect(point.is_action_enabled(0), "a finished repair re-enables the action the player used")
	_expect(brain._repair_job == null, "the job is cleared with the item")

	# Anyone else meets the same broken item and only sulks at it.
	var other := _point_fixture(9, 152, 0, true)
	other["point"].set("tampered", true)
	other["brain"]._target = other["point"]
	other["brain"]._active = other["point"]
	other["brain"]._state = BRAIN.State.NAVIGATING
	other["brain"]._goal = 2
	(other["actor"] as Actor).destination_reached.emit()
	_expect(other["brain"]._goal == BRAIN.REACTION_GOAL, "a coworker holds goal 8 at the same item")
	_expect(other["brain"]._repair_job == null, "a coworker files no repair job")
	(other["actor"] as Actor).finish_activity()
	_expect(bool(other["point"].get("tampered")), "a coworker leaves the item broken")

	# A janitor at a type outside the thirty does the same.
	var unlisted := _point_fixture(9, 68, 0, true, &"janitor")
	unlisted["point"].set("tampered", true)
	unlisted["brain"]._target = unlisted["point"]
	unlisted["brain"]._active = unlisted["point"]
	unlisted["brain"]._state = BRAIN.State.NAVIGATING
	unlisted["brain"]._goal = 2
	(unlisted["actor"] as Actor).destination_reached.emit()
	_expect(unlisted["brain"]._goal == BRAIN.REACTION_GOAL, "a janitor holds goal 8 at an unrepairable item")
	_expect(unlisted["brain"]._repair_job == null, "an unrepairable item files no job")

	# The cubicles. sub_4181F0 takes only a locked type 173 (0x418203) from anyone but the
	# janitor; sub_4180F0 takes both types from the janitor, locked or merely tampered with.
	var cases := [
		[&"male-employee-1", 173, true, true],
		[&"male-employee-1", 173, false, false],
		[&"male-employee-1", 262, true, false],
		[&"janitor", 173, false, true],
		[&"janitor", 262, true, true],
		[&"janitor", 262, false, true],
	]
	var cubicles: Array = []
	for case in cases:
		var cubicle := _point_fixture(8, case[1], 7, true, case[0])
		cubicles.append(cubicle)
		cubicle["point"].set("tampered", true)
		cubicle["point"].set("locked_in", case[2])
		cubicle["brain"]._target = cubicle["point"]
		cubicle["brain"]._active = cubicle["point"]
		cubicle["brain"]._state = BRAIN.State.NAVIGATING
		cubicle["brain"]._goal = 4
		(cubicle["actor"] as Actor).destination_reached.emit()
		var label := "%s at a %s type-%d cubicle" % [case[0], "locked" if case[2] else "tampered", case[1]]
		_expect((cubicle["brain"]._repair_job != null) == case[3], "%s %s" % [label, "files a repair" if case[3] else "files no repair"])
		_expect(cubicle["brain"]._goal == BRAIN.REACTION_GOAL, "%s holds goal 8" % label)

	for key in ["world"]:
		for owned in [fixture, other, unlisted] + cubicles:
			var node: Node = owned[key]
			root.remove_child(node)
			node.queue_free()
	root.remove_child(session)
	session.free()


# Actions 110 and 112 lock a cubicle's occupant in. sub_417120 still hands that cubicle to the
# next colleague who needs it; the colleague finds it tampered with, reacts, and files the
# repair through sub_4181F0 (type 173 with item+224 set). The repair's expiry resets the item
# (sub_4100B0), and on its next tick sub_416090 lets the inmate out.
func _check_rescuing_a_locked_in_colleague() -> void:
	var fixture := _point_fixture(8, 173, 7, true)
	var world: Node2D = fixture["world"]
	var brain: Node = fixture["brain"]
	var actor: Actor = fixture["actor"]
	var cubicle: Node2D = fixture["point"]
	var item := (cubicle.get_parent() as Node2D).global_position

	var inmate := Actor.new()
	inmate.name = "Inmate"
	var inmate_brain := BRAIN.new()
	inmate_brain.name = "Brain"
	inmate_brain.random_seed = 7
	inmate.add_child(inmate_brain)
	world.add_child(inmate)
	inmate_brain._initialize()
	inmate_brain.set_physics_process(false)
	inmate_brain._target = cubicle
	inmate_brain._active = cubicle
	inmate_brain._state = BRAIN.State.NAVIGATING
	inmate_brain._goal = 4
	inmate.destination_reached.emit()
	_expect(cubicle.get("occupant") == inmate and inmate.global_position.is_equal_approx(item), "the inmate goes into the cubicle")
	# The prank's lock, and the tampered mark sub_41B240 leaves after any action.
	cubicle.set("locked_in", true)
	cubicle.set("tampered", true)
	var toilet_need: float = inmate_brain._needs[4]
	inmate.finish_activity()
	_expect(inmate_brain._goal == BRAIN.REACTION_GOAL and inmate_brain.is_locked_in(), "a locked-in occupant turns angry when its timer runs out")
	_expect(inmate.global_position.is_equal_approx(item), "the locked-in occupant stays inside the cubicle")
	_expect(inmate_brain.is_blind(), "and sees nothing from in there")
	inmate.finish_activity()
	_expect(cubicle.get("occupant") == inmate and inmate.global_position.is_equal_approx(item), "sulking longer does not let it out")

	_expect(brain._candidates(4) == [cubicle], "the locked, tampered, occupied cubicle is still a goal-4 candidate")
	brain._attempt_goal(4)
	_expect(brain._state == BRAIN.State.NAVIGATING and brain._target == cubicle, "a colleague who needs the toilet walks to it")
	actor.destination_reached.emit()
	_expect(actor.activity.get("animation") == &"pissed", "the colleague finds it tampered with and reacts")
	_expect(brain._repair_job == cubicle, "sub_4181F0 files the locked cubicle as the colleague's repair job")
	_expect(brain._goal == BRAIN.REACTION_GOAL, "the rescuer shows the ANGRY bubble, not REPAIR")
	_expect(cubicle.get("occupant") == inmate, "the colleague does not take the cubicle")
	inmate_brain._physics_process(0.1)
	_expect(cubicle.get("occupant") == inmate, "the inmate stays locked in while the repair runs")
	actor.finish_activity()
	_expect(not bool(cubicle.get("locked_in")) and not bool(cubicle.get("tampered")), "the finished repair resets the cubicle")
	_expect(brain._repair_job == null, "the repair job is done")
	inmate_brain._physics_process(0.1)
	_expect(cubicle.get("occupant") == null, "the inmate leaves on its next tick")
	_expect(inmate.global_position.is_equal_approx(cubicle.global_position), "the inmate steps out onto the interaction point")
	_expect(inmate_brain._state == BRAIN.State.IDLE and not inmate_brain.is_blind(), "the inmate is free and can see again")
	_expect(inmate_brain._needs[4] == toilet_need, "being let out completes goal 8, not the toilet goal")
	world.free()
