extends SceneTree

# sub_41DC80's four global consequences and sub_41D820's cubicle-occupancy rule. Both reach
# past the object the action was performed on, which is what made them the last prank
# machinery the port was missing. See docs/prank-reference.md.

const CONTROLLER := preload("res://scenes/player/prank_controller.gd")
const POINT := preload("res://scenes/npc/npc_activity_point.gd")
const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const JOBLESS := preload("res://scenes/player/profiles/jobless.tres")

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
	_check_the_reposition_lands_on_the_copier()
	_check_the_turn_toward_the_item()
	_check_the_start_state_actions_level_2_places()
	_check_marker_18_hides_its_object()
	if _failures == 0:
		print("Prank consequences: the blackout and its countdown, the projector box, the heating sweep, the cubicle rule, the reposition and its lift, the turn toward the item, the start-state actions and marker 18's hide passed")
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
	# 0x41B4AF adds [0x4658F0] = 0.8 to z and 0x41B4BD adds [0x4658EC] = 0.85 to x.
	_expect(offsets[0].is_equal_approx(Vector2(0.85, 0.80)), "orientation 0 steps to (x + 0.85, z + 0.80)")
	_expect(offsets[1].is_equal_approx(Vector2(0.80, 0.85)), "any other orientation steps to (x + 0.80, z + 0.85)")
	_expect(is_equal_approx(CONTROLLER.REPOSITION_HEIGHT, 1.8), "sub_42B330 lifts the player to a height of 1.8")
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


# A real player rather than a stand-in: the lift lives in player.gd's height setter, and a
# stub without it would take the controller's set("height", ...) silently.
func _player_fixture() -> Dictionary:
	var world := Node2D.new()
	root.add_child(world)
	var player := PLAYER_SCENE.instantiate()
	player.profile = JOBLESS
	world.add_child(player)
	player.set_physics_process(false)
	player.get_node("FootstepPlayer").stop_footsteps()
	player.get_node("FootstepPlayer").stream = null
	var controller := player.get_node("PrankController")
	# Nothing here should depend on what the pointer happens to be over.
	controller.set_process(false)
	return {"world": world, "player": player, "controller": controller}


func _item(world: Node2D, ground: Vector2, interaction: Vector2, orientation: int, action_ids: Array) -> Node2D:
	var object := ObjectStub.new()
	object.name = "Item"
	object.position = IsoDirection.ground_to_screen(ground)
	world.add_child(object)
	var point := POINT.new()
	point.name = "InteractionPoint"
	point.position = IsoDirection.ground_to_screen(interaction)
	point.orientation = orientation
	point.action_ids = PackedInt32Array(action_ids)
	point.reset_actions()
	object.add_child(point)
	return point


func _open_and_commit(controller: Node, point: Node, action_id: int) -> void:
	controller.focus_point = point
	controller.entries = controller.build_entries(point)
	controller.open_menu()
	for index in range(controller.entries.size()):
		if int(controller.entries[index]["action_id"]) == action_id:
			controller.set_highlighted(index)
	controller.confirm()


func _playing(player: Node) -> String:
	return String(player.get_node("AnimationController").current_animation)


# sub_41B240 0x41B460: the base is the copier's own position, not its interaction point one
# tile out, and sub_42B330(x, 1.8, z) lifts the player 43.2 pixels onto the glass. States 4
# and 5 both put him back on the floor where he stood.
func _check_the_reposition_lands_on_the_copier() -> void:
	# Level 3's copier 122. Every placed copier's interaction offset is one whole tile, along
	# x for orientation 0 and along z for the odd orientations.
	var copier := Vector2(21.9375, 10.8125)
	for orientation in [0, 1]:
		var fixture := _player_fixture()
		var player: Node2D = fixture["player"]
		var controller: Node = fixture["controller"]
		var side := 0 if orientation == 0 else 1
		var interaction := Vector2(1, 0) if side == 0 else Vector2(0, 1)
		var point := _item(fixture["world"], copier, interaction, orientation, [126])
		var start: Vector2 = point.global_position
		player.global_position = start

		_open_and_commit(controller, point, 126)
		_expect(controller.state == CONTROLLER.State.ACTING, "orientation %d: the copier's action starts" % orientation)
		var offset: Vector2 = CONTROLLER.REPOSITION_OFFSETS[side]
		var landed := IsoDirection.screen_to_ground(player.global_position)
		_expect(
			landed.is_equal_approx(copier + offset),
			"orientation %d: the player lands at the copier + %s, got %s" % [orientation, offset, landed - copier]
		)
		_expect(is_equal_approx(player.height, CONTROLLER.REPOSITION_HEIGHT), "orientation %d: the player is lifted to 1.8" % orientation)
		for part in ["Sprite2D", "Shadow"]:
			var lift: Vector2 = (player.get_node(part) as Node2D).position
			_expect(
				lift.is_equal_approx(Vector2(0.0, -43.2)),
				"orientation %d: the %s is drawn 24 px a unit higher, got %s" % [orientation, part, lift]
			)
		_expect(
			player.last_direction == CONTROLLER.ASSCOPY_FACINGS[side],
			"orientation %d: the player faces %s, got %s" % [orientation, CONTROLLER.ASSCOPY_FACINGS[side], player.last_direction]
		)
		var view := "down-right" if side == 0 else "down-left"
		_expect(_playing(player).ends_with("asscopy-" + view), "orientation %d: ASSCOPY plays its %s view, got %s" % [orientation, view, _playing(player)])

		# State 5 on one side, state 4 on the other: both restore the saved position.
		if side == 0:
			controller.abort_action()
		else:
			controller._advance_action(controller._duration)
		_expect(controller.state == CONTROLLER.State.FREE, "orientation %d: the action is over" % orientation)
		_expect(player.global_position.is_equal_approx(start), "orientation %d: the player is put back where he stood" % orientation)
		_expect(is_zero_approx(player.height), "orientation %d: and back on the floor" % orientation)
		for part in ["Sprite2D", "Shadow"]:
			_expect((player.get_node(part) as Node2D).position == Vector2.ZERO, "orientation %d: the %s drops back with him" % [orientation, part])
		_drop(fixture)


# sub_41B240 state 0 (0x41B290) turns toward the item's own position as the ring opens, in
# 45-degree sectors of the ground plane (sub_41A400), and the clip then plays from that view.
func _check_the_turn_toward_the_item() -> void:
	var item := Vector2(10.0, 10.0)
	# The player's ground offset from the item, and the view he must end up in.
	var cases := [
		[Vector2(1.0, 0.0), "up-left", "standing on an interaction point one tile along x faces the 270 view"],
		[Vector2(-1.0, -0.45), "down", "a ground delta of (1, 0.45) falls in the 135 sector"],
		[Vector2(0.0, 1.0), "up-right", "one tile along z faces the 000 view"],
		[Vector2(-0.4, 0.3), "right", "a short diagonal takes the 045 sector"],
	]
	# The screen-space snap the port used to take lands the second case on 090 instead.
	var snapped := IsoDirection.snap_to_8_directions(IsoDirection.ground_to_screen(Vector2(1.0, 0.45)))
	_expect(snapped.is_equal_approx(Vector2(48.0, 24.0).normalized()), "the second case is one a screen-space snap gets wrong")
	for case in cases:
		var fixture := _player_fixture()
		var player: Node2D = fixture["player"]
		var controller: Node = fixture["controller"]
		# Action 13 is selector 0, STAND#USE, which ships all eight views.
		var point := _item(fixture["world"], item, Vector2(1.0, 0.0), 0, [13])
		player.global_position = IsoDirection.ground_to_screen(item + case[0])
		player.last_direction = Vector2.LEFT

		controller.focus_point = point
		controller.entries = controller.build_entries(point)
		controller.open_menu()
		player._physics_process(0.016)
		_expect(_playing(player).ends_with("idle1-atmen-" + case[1]), "%s: the idle turns as the ring opens, got %s" % [case[2], _playing(player)])
		controller.confirm()
		_expect(_playing(player).ends_with("stand-use-" + case[1]), "%s, got %s" % [case[2], _playing(player)])
		controller.abort_action()
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


# Marker 18 (records 67, 68 and 154) raises item+232 for as long as the action runs, which
# hides the item and its click box; applying the action or aborting it brings it back.
func _check_marker_18_hides_its_object() -> void:
	var fixture := _player_fixture()
	var world: Node2D = fixture["world"]
	var controller: Node = fixture["controller"]
	var point := _item(world, Vector2(1, 1), Vector2(1, 2), 0, [67])
	var object := point.get_parent() as Node2D
	_expect(int(ActionTable.get_action(67).get("result_state", 0)) == CONTROLLER.STATE_IN_USE, "record 67 carries marker 18")

	_open_and_commit(controller, point, 67)
	_expect(controller.state == CONTROLLER.State.ACTING, "action 67 runs")
	_expect(point.in_use and not object.visible, "the object is hidden while its marker-18 action runs")
	controller._advance_action(float(controller._duration))
	_expect(not point.in_use and object.visible, "it comes back when the action applies")
	_expect(int(object.state) == 0, "marker 18 is not a state, so the object keeps its own")

	point.reset_actions()
	_open_and_commit(controller, point, 67)
	_expect(not object.visible, "a second run hides it again")
	point.reset_actions()
	_expect(point.in_use and not object.visible, "an item reset leaves the hide flag alone, as sub_4100B0 does")
	controller.abort_action()
	_expect(not point.in_use and object.visible, "an aborted action brings it back")
	_drop(fixture)

