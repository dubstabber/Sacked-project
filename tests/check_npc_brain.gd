extends SceneTree


const BRAIN := preload("res://scenes/npc/npc_brain.gd")
const POINT := preload("res://scenes/npc/npc_activity_point.gd")

class TestProfile extends Resource:
	var id: StringName = &"male-employee-1"

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
	_check_cleanup()
	_check_arrival_actions()
	_check_interrupted_activity()
	_check_routes_and_retry_limit()
	if _failures == 0:
		print("NPC brain: source needs, target filters, arrival actions, retry limits and claim cleanup passed")
	quit(1 if _failures else 0)


func _fixture() -> Dictionary:
	var world := Node2D.new()
	root.add_child(world)
	var chair := _point(world, "Chair", Vector2(3, 2), Vector2(1, 0), 6, 68, 0, false)
	var monitor := _point(world, "Monitor", Vector2(3, 3), Vector2(1, 0), 6, 152, 0, true)
	var actor := Actor.new()
	actor.name = "NPC"
	actor.position = chair.global_position
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
		_expect(brain._goal_disabled[goal], "goal %d has no port implementation and stays disabled" % goal)
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
	_expect(brain._candidates(2) == [valid], "targets obey goal category, room mask and current world")
	_expect(brain._candidates(0) == [fridge], "a special-action item is an ordinary candidate for its goal")
	valid.set("occupant", other_world)
	_expect(brain._candidates(2).is_empty(), "claimed activity points are unavailable to another NPC")
	var chair: Node2D = fixture["chair"]
	chair.set("occupant", other_world)
	_begin_work(fixture)
	_expect(fixture["actor"].activity.get("animation") == &"idle", "a monitor visitor does not take an occupied chair")
	_expect(chair.get("occupant") == other_world, "another actor's chair claim is preserved")
	fixture["world"].free()
	other_world.free()


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


func _check_arrival_actions() -> void:
	# sub_417B00 dispatch: the arrived item's type picks animation, duration and claim.
	var cubicle := _arrive(_point_fixture(8, 173, 7, true))
	_expect(cubicle["animation"] == &"idle", "a toilet cubicle is entered standing")
	_expect(cubicle["duration"] >= 10.0 and cubicle["duration"] <= 15.0, "a cubicle uses the original ten-to-fifteen-second stay")
	_expect(cubicle["claimed"], "entering a cubicle claims it")
	_expect(cubicle["anchor"].is_equal_approx(cubicle["item"]), "a cubicle occupant stands on the item anchor")
	_expect(cubicle["facing"] == (cubicle["interaction"] - cubicle["item"]).normalized(), "a cubicle occupant faces back out of the stall")

	var sofa := _arrive(_point_fixture(7, 182, 3, false))
	_expect(sofa["animation"] == &"sit-easy", "a sofa uses the relaxed sitting clip")
	_expect(sofa["duration"] >= 15.0 and sofa["duration"] <= 25.0, "relaxed sitting uses the original fifteen-to-twenty-five-second duration")
	_expect(sofa["claimed"], "relaxed sitting claims its seat")
	_expect(sofa["anchor"].is_equal_approx(sofa["item"].lerp(sofa["interaction"], 0.3) + Vector2(0, -2.4)), "relaxed sitting shifts thirty percent toward the interaction point")
	_expect(sofa["facing"] == (sofa["interaction"] - sofa["item"]).normalized(), "relaxed sitting faces along the interaction offset")

	var machine := _arrive(_point_fixture(5, 140, 0, true))
	_expect(machine["animation"] == &"special-1", "a drinks machine plays the special action")
	_expect(is_equal_approx(machine["duration"], 15.0), "a special action lasts the original fifteen seconds")
	_expect(not machine["claimed"], "a special action does not claim its item")

	var copier := _arrive(_point_fixture(2, 129, 0, true))
	_expect(is_equal_approx(copier["duration"], 20.0), "the copier runs for the original twenty seconds")
	_expect(copier["claimed"], "using the copier claims it")

	var plant := _arrive(_point_fixture(9, 30, 0, false))
	_expect(plant["animation"] == &"idle", "an ordinary target keeps the standing idle")
	_expect(plant["duration"] >= 10.0 and plant["duration"] <= 16.0, "an ordinary target keeps the default action timer")


func _point_fixture(category: int, item_type: int, room: int, active: bool) -> Dictionary:
	var fixture := _fixture()
	var point := _point(fixture["world"], "Target", Vector2(6, 5), Vector2(1, 0), category, item_type, room, active)
	fixture["point"] = point
	return fixture


func _arrive(fixture: Dictionary) -> Dictionary:
	var brain: Node = fixture["brain"]
	var actor: Actor = fixture["actor"]
	var point: Node2D = fixture["point"]
	brain._target = point
	if point.active:
		brain._active = point
	else:
		brain._passive = point
	brain._state = BRAIN.State.NAVIGATING
	brain._goal = 2
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
