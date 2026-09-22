extends SceneTree

# sub_41DC80's four global consequences and sub_41D820's cubicle-occupancy rule. Both reach
# past the object the action was performed on, which is what made them the last prank
# machinery the port was missing. See docs/prank-reference.md.

const CONTROLLER := preload("res://scenes/player/prank_controller.gd")
const POINT := preload("res://scenes/npc/npc_activity_point.gd")

class ProfileStub extends Resource:
	var id: StringName = &"male-employee-1"

class OccupantStub extends Node2D:
	var profile: Resource = ProfileStub.new()

var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_check_the_blackout_and_its_countdown()
	_check_the_projector_takes_the_first_in_its_box()
	_check_the_heating_reaches_a_whole_category()
	_check_the_cubicle_rule()
	_check_locking_someone_in()
	_check_the_reposition_picks_its_side()
	_check_the_start_state_actions_level_2_places()
	if _failures == 0:
		print("Prank consequences: the blackout and its countdown, the projector box, the heating sweep, the cubicle rule, the reposition and the start-state actions passed")
	quit(1 if _failures else 0)


func _expect(condition: bool, label: String) -> void:
	if not condition:
		_failures += 1
		push_error(label)


class ObjectStub extends Node2D:
	var state := 0
	func set_state(value: int) -> void:
		state = value


func _point(world: Node2D, label: String, ground: Vector2, item_type: int, category := 0) -> Node2D:
	var object := ObjectStub.new()
	object.name = label
	object.position = IsoDirection.ground_to_screen(ground)
	world.add_child(object)
	var point := POINT.new()
	point.name = "ActivityPoint"
	point.item_type = item_type
	point.category = category
	object.add_child(point)
	return point


func _fixture() -> Dictionary:
	var world := Node2D.new()
	root.add_child(world)
	var controller := CONTROLLER.new()
	world.add_child(controller)
	return {"world": world, "controller": controller}


func _drop(fixture: Dictionary) -> void:
	root.remove_child(fixture["world"])
	fixture["world"].free()


# 79 blacks out every type-253 item and arms player+1068 at 400, ticked at dt * 10.
func _check_the_blackout_and_its_countdown() -> void:
	var fixture := _fixture()
	var world: Node2D = fixture["world"]
	var controller: Node = fixture["controller"]
	var lamps := [
		_point(world, "Lamp1", Vector2(1, 1), CONTROLLER.BLACKOUT_ITEM_TYPE),
		_point(world, "Lamp2", Vector2(40, 40), CONTROLLER.BLACKOUT_ITEM_TYPE),
	]
	var other := _point(world, "Other", Vector2(2, 2), 99)

	controller._apply_global_consequence(CONTROLLER.CONSEQUENCE_BLACKOUT, lamps[0])
	for lamp in lamps:
		_expect(int(lamp.get_parent().state) == 9, "the blackout reaches every type-253 item, however far away")
	_expect(int(other.get_parent().state) == 0, "it leaves everything else alone")
	_expect(
		is_equal_approx(controller.blackout_remaining, CONTROLLER.BLACKOUT_TIMER),
		"the countdown starts at the recovered 400"
	)

	# 400 at ten a second is forty seconds; just short of it nothing has come back.
	controller._advance_blackout(39.0)
	_expect(int(lamps[0].get_parent().state) == 9, "the items stay out for the full forty seconds")
	controller._advance_blackout(1.5)
	_expect(is_equal_approx(controller.blackout_remaining, 0.0), "the countdown stops at zero")
	for lamp in lamps:
		_expect(int(lamp.get_parent().state) == 0, "the items come back when it runs out")
	_drop(fixture)


# 116 stops at the first type-265 item inside a box on each axis. It never measures a
# distance, so a nearer one later in the world's order loses to a farther one earlier in it.
func _check_the_projector_takes_the_first_in_its_box() -> void:
	var fixture := _fixture()
	var world: Node2D = fixture["world"]
	var controller: Node = fixture["controller"]
	var focus := _point(world, "Beamer", Vector2(10, 10), 1)
	var far_but_inside := _point(world, "ScreenA", Vector2(14, 14), CONTROLLER.PROJECTOR_ITEM_TYPE)
	var near := _point(world, "ScreenB", Vector2(11, 10), CONTROLLER.PROJECTOR_ITEM_TYPE)
	var outside := _point(world, "ScreenC", Vector2(10, 16), CONTROLLER.PROJECTOR_ITEM_TYPE)

	controller._apply_global_consequence(CONTROLLER.CONSEQUENCE_PROJECTOR, focus)
	_expect(int(far_but_inside.get_parent().state) == 9, "the first candidate inside the box is the one that flips")
	_expect(int(near.get_parent().state) == 0, "a nearer one later in world order is not preferred")
	_expect(int(outside.get_parent().state) == 0, "a candidate outside the box is skipped")

	# The bounds are strict, so exactly five tiles out is already too far.
	var edge_fixture := _fixture()
	var edge_world: Node2D = edge_fixture["world"]
	var edge_focus := _point(edge_world, "Beamer", Vector2(10, 10), 1)
	var on_edge := _point(edge_world, "Screen", Vector2(15, 10), CONTROLLER.PROJECTOR_ITEM_TYPE)
	edge_fixture["controller"]._apply_global_consequence(CONTROLLER.CONSEQUENCE_PROJECTOR, edge_focus)
	_expect(int(on_edge.get_parent().state) == 0, "the box excludes a candidate exactly five tiles away")
	_drop(edge_fixture)
	_drop(fixture)


func _check_the_heating_reaches_a_whole_category() -> void:
	var fixture := _fixture()
	var world: Node2D = fixture["world"]
	var radiators := [
		_point(world, "Rad1", Vector2(1, 1), 10, CONTROLLER.HEATING_CATEGORY),
		_point(world, "Rad2", Vector2(30, 30), 11, CONTROLLER.HEATING_CATEGORY),
	]
	var desk := _point(world, "Desk", Vector2(2, 2), 12, 6)
	fixture["controller"]._apply_global_consequence(CONTROLLER.CONSEQUENCE_HEATING, radiators[0])
	for radiator in radiators:
		_expect(int(radiator.get_parent().state) == 9, "the heating reaches every category-9 item")
	_expect(int(desk.get_parent().state) == 0, "and nothing outside that category")
	_drop(fixture)


# sub_41D820's fourth rule: 43, 44 and 138 need the cubicle empty, 110 needs somebody in it
# who is not the boss, 112 needs the boss.
func _check_the_cubicle_rule() -> void:
	var fixture := _fixture()
	var controller: Node = fixture["controller"]
	var cubicle := _point(fixture["world"], "Cubicle", Vector2(4, 4), 173)

	for action_id in [43, 44, 138]:
		_expect(controller._occupancy_allows(action_id, cubicle), "%d is offered on an empty cubicle" % action_id)
	for action_id in [110, 112]:
		_expect(not controller._occupancy_allows(action_id, cubicle), "%d needs somebody in the cubicle" % action_id)

	var worker := OccupantStub.new()
	fixture["world"].add_child(worker)
	cubicle.occupant = worker
	for action_id in [43, 44, 138]:
		_expect(not controller._occupancy_allows(action_id, cubicle), "%d is withdrawn once it is occupied" % action_id)
	_expect(controller._occupancy_allows(110, cubicle), "110 shuts in a colleague")
	_expect(not controller._occupancy_allows(112, cubicle), "112 is only for the boss")

	worker.profile.id = &"boss"
	_expect(controller._occupancy_allows(112, cubicle), "112 is offered when the boss is inside")
	_expect(not controller._occupancy_allows(110, cubicle), "110 is not, because the boss is not a colleague")

	# Anything without a cubicle rule is unaffected either way.
	_expect(controller._occupancy_allows(1, cubicle), "an ordinary action ignores the occupant")
	_drop(fixture)


func _check_locking_someone_in() -> void:
	var fixture := _fixture()
	var controller: Node = fixture["controller"]
	var cubicle := _point(fixture["world"], "Cubicle", Vector2(4, 4), 173)

	controller._apply_global_consequence(110, cubicle)
	_expect(not cubicle.locked_in, "an empty cubicle cannot be locked")

	var worker := OccupantStub.new()
	fixture["world"].add_child(worker)
	cubicle.occupant = worker
	controller._apply_global_consequence(110, cubicle)
	_expect(cubicle.locked_in, "an occupied cubicle locks its occupant in")

	# Only the item reset lets them out, which is what a finished repair performs.
	cubicle.reset_actions()
	_expect(not cubicle.locked_in, "a repair releases the lock")
	_drop(fixture)


# sub_41B240 selector 5: the object's quarter-turn index picks which side the player steps
# onto, and the two sides are the only two views the clip ships.
func _check_the_reposition_picks_its_side() -> void:
	var offsets: Dictionary = CONTROLLER.REPOSITION_OFFSETS
	_expect(offsets.size() == 2, "the reposition offers the two recovered sides")
	_expect(offsets[0].is_equal_approx(Vector2(0.80, 0.85)), "orientation 0 steps to (0.80, 0.85)")
	_expect(offsets[1].is_equal_approx(Vector2(0.85, 0.80)), "any other orientation steps to (0.85, 0.80)")
	# The side index lines up with the two clip views, so one cannot be reordered alone.
	var facings: Array = CONTROLLER.ASSCOPY_FACINGS
	_expect(facings.size() == offsets.size(), "each side has a view to face")
	_expect(facings[0] == Vector2(1, 1), "side 0 faces down-right, the 090 view")
	_expect(facings[1] == Vector2(-1, 1), "side 1 faces down-left, the 180 view")

	var fixture := _fixture()
	var controller: Node = fixture["controller"]
	_expect(not controller._return_position.is_finite(), "nothing is saved until an action moves the player")
	controller._step_back()
	_expect(not controller._return_position.is_finite(), "stepping back with nothing saved is harmless")
	_drop(fixture)


# Most actions set the object's state when they finish. A few set it the moment they begin,
# and an abort has to put that back. Level 2 is the first map to place any of them, so this
# pins which two it places and that both use a clip the port now has.
func _check_the_start_state_actions_level_2_places() -> void:
	var manifest = JSON.parse_string(FileAccess.get_file_as_string("res://resources/levels/level_2.json"))
	_expect(manifest is Dictionary, "level 2's manifest is readable")
	if not (manifest is Dictionary):
		return
	var placed := {}
	for item in manifest["objects"]:
		for action_id in item["action_ids"]:
			var action := ActionTable.get_action(int(action_id))
			if not action.is_empty() and bool(action.get("state_at_start", false)):
				placed[int(action_id)] = String(item["node_name"])

	_expect(placed.has(2), "level 2 places action 2, which empties a case on the spot")
	_expect(placed.has(126), "level 2 places action 126, the copier's own start-state action")
	_expect(placed.size() == 2, "those are the only two it places, got %s" % str(placed.keys()))
	for action_id in placed:
		var action := ActionTable.get_action(int(action_id))
		var selector := int(action.get("player_animation", -1))
		_expect(
			CONTROLLER.SELECTOR_CLIPS.has(selector),
			"action %d's clip is imported, selector %d" % [action_id, selector]
		)
		_expect(
			int(action.get("result_state", -1)) > 0,
			"action %d names the state it applies at the start" % action_id
		)
