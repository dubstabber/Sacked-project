extends SceneTree

# The player's side of a prank, as recovered in docs/player-action-reference.md: the focus
# item is whatever the cursor is over, and it is only actionable within 2 tiles and with a
# clear sight ray. Nothing here may depend on walking to an object.

const LEVEL := preload("res://scenes/level_1.tscn")
const GRID := preload("res://scenes/shared/grid_collision.gd")
const POINT_SCRIPT := preload("res://scenes/npc/npc_activity_point.gd")

var _failures := 0
var _level: Node
var _player: Node2D
var _controller: Node
var _layer: Node


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_check_sight_ray()
	_check_availability_filter()
	await _check_level_focus_rules()
	if _failures == 0:
		print("Player interaction: sight ray, availability filter, reach rule and menu cancel passed")
	quit(1 if _failures else 0)


func _expect(condition: bool, label: String) -> void:
	if not condition:
		_failures += 1
		push_error(label)


# sub_412E30 walks quarter cells and tests every sample from the start to the destination.
func _check_sight_ray() -> void:
	var wall := func(cell: Vector2i) -> bool: return cell.x == 2
	var clear := func(_cell: Vector2i) -> bool: return false
	_expect(GRID.has_line_of_sight(Vector2i(2, 8), Vector2i(18, 8), clear), "an unobstructed ray reaches its target")
	_expect(not GRID.has_line_of_sight(Vector2i(2, 8), Vector2i(18, 8), wall), "a wall between the ends blocks the ray")
	_expect(not GRID.has_line_of_sight(Vector2i(6, 8), Vector2i(10, 8), wall), "the destination cell is tested too")
	_expect(GRID.has_line_of_sight(Vector2i(6, 6), Vector2i(6, 6), wall), "a zero-length ray inside a clear cell passes")
	var only_start := func(cell: Vector2i) -> bool: return cell == Vector2i(1, 1)
	_expect(not GRID.has_line_of_sight(Vector2i(6, 6), Vector2i(20, 6), only_start), "the ray tests the cell it starts in")
	# A diagonal ray takes the y-major branch when it falls more than it runs.
	_expect(not GRID.has_line_of_sight(Vector2i(4, 4), Vector2i(12, 40), wall), "a steep ray still finds the wall it crosses")


# sub_41D820: a slot needs an action id, its enabled flag, and every required item.
func _check_availability_filter() -> void:
	var controller = preload("res://scenes/player/prank_controller.gd").new()
	controller.inventory.resize(32)
	var point = POINT_SCRIPT.new()
	# 43 takes the toilet roll and needs nothing; 44 needs item 20, which 43 grants.
	point.action_ids = PackedInt32Array([43, 44, 0, 0])
	point.reset_actions()

	_expect(controller.available_slots(point) == PackedInt32Array([0]), "a slot whose item is missing is left out")
	controller.inventory[20] = 1
	_expect(controller.available_slots(point) == PackedInt32Array([0, 1]), "holding the item offers the slot")
	point.disable_slot(0)
	_expect(controller.available_slots(point) == PackedInt32Array([1]), "a used slot is not offered again")

	var entries: Array = controller.build_entries(point)
	_expect(entries.size() == 1 and int(entries[0]["action_id"]) == 44, "the menu carries the surviving action")
	_expect(String(entries[0]["name"]) != "", "the menu entry carries the original action name")
	_expect(entries[0]["icon"] != null, "the menu entry carries its ACTICON")

	# sub_4100B0 disables whatever the enabled slots unlock.
	var gated = POINT_SCRIPT.new()
	gated.action_ids = PackedInt32Array([110, 151, 0, 0])
	gated.reset_actions()
	_expect(gated.is_action_enabled(0) and not gated.is_action_enabled(1), "an unlocked action starts disabled")
	gated.apply_action_lists(110)
	_expect(gated.is_action_enabled(1), "performing the unlocking action opens the slot")

	point.free()
	gated.free()
	controller.free()


func _check_level_focus_rules() -> void:
	_level = LEVEL.instantiate()
	var runtime := _level.get_node_or_null("LevelRuntime")
	if runtime != null:
		runtime.enabled = false
	root.add_child(_level)
	await process_frame

	_player = _level.get_node_or_null("World/Player") as Node2D
	_controller = _level.get_node_or_null("World/Player/PrankController")
	_layer = _level.get_node_or_null("World/CollisionTileMapLayer")
	_expect(_controller != null, "the player carries a prank controller")
	_expect(_layer != null and not (_layer.sight_blocked_cells as PackedVector2Array).is_empty(), "the level carries its sight blockers")
	if _controller == null or _layer == null or _player == null:
		_level.free()
		return

	# Every prankable object must be actionable from somewhere, without walking to it.
	var reachable := 0
	var prankable := 0
	for node in _level.get_node("World/Objects").get_children():
		var point := node.get_node_or_null("InteractionPoint")
		if point == null or (point.get("action_ids") as PackedInt32Array).is_empty():
			continue
		prankable += 1
		_player.global_position = (point as Node2D).global_position
		if _controller._is_within_reach(point):
			reachable += 1
	_expect(prankable == 38, "level 1 places its 38 prankable objects, saw %d" % prankable)
	_expect(reachable == prankable, "every prankable object is actionable from its own interaction point (%d of %d)" % [reachable, prankable])

	# The rule is a range, so standing far away must drop the focus.
	var far := _level.get_node("World/Objects").get_children()[0] as Node2D
	var far_point := far.get_node_or_null("InteractionPoint")
	if far_point != null:
		_player.global_position = (far_point as Node2D).global_position + Vector2(2000.0, 0.0)
		_expect(not _controller._is_within_reach(far_point), "an object far away is out of reach")

	# The ring only opens on a focus, and cancelling closes it.
	_controller.focus_point = null
	_controller.entries = []
	_controller.open_menu()
	_expect(not _controller.menu_open, "the ring does not open without a focus")
	_controller.focus_point = far_point
	_controller.entries = [{"slot": 0, "action_id": 43, "name": "x", "icon": null}]
	_controller.open_menu()
	_expect(_controller.menu_open and _controller.highlighted == 0, "the ring opens with its first entry highlighted")
	_controller.close_menu()
	_expect(_controller.highlighted == -1, "cancelling the ring drops the selection")
	_expect(not _controller.menu_open and _controller.highlighted == -1, "cancelling closes the ring")

	_check_action_applies()
	_check_pickup_opens_a_gated_action()
	_level.free()


# A pickup is the only way level 1 opens its item-gated rows: sub_41AF60 clears the whole
# inventory, so the player starts every level holding nothing.
func _check_pickup_opens_a_gated_action() -> void:
	var lighter := _level.get_node_or_null("World/Objects/Object039Feuerzeug")
	var bin := _level.get_node_or_null("World/Objects/Object033Papierkorb01")
	if lighter == null or bin == null:
		_expect(false, "level 1 places the lighter and the wastebasket")
		return
	var lighter_point := lighter.get_node("InteractionPoint")
	var bin_point := bin.get_node("InteractionPoint")

	_expect(_controller.inventory.count(0) == _controller.inventory.size(), "the player starts with an empty inventory")
	_expect(_controller.build_entries(bin_point).is_empty(), "the wastebasket offers nothing without the lighter")

	_player.global_position = (lighter_point as Node2D).global_position
	_controller.focus_point = lighter_point
	_controller.entries = _controller.build_entries(lighter_point)
	_expect(_controller.entries.size() == 1, "the lighter offers exactly its pickup")
	_controller.open_menu()
	_controller.confirm()
	_controller._advance_action(_controller._duration)

	# Ids 6 and 9 are inexhaustible, so the pickup fills the slot rather than adding one.
	_expect(_controller.inventory[6] == 99, "taking the lighter fills its inventory slot")
	_expect(lighter.is_queued_for_deletion(), "a pickup that grants an item takes the object out of the world")

	var opened: Array = _controller.build_entries(bin_point)
	_expect(opened.size() == 1 and int(opened[0]["action_id"]) == 34, "holding the lighter opens the wastebasket")


# sub_41B240 states 2 to 4: commit, run out the record's own duration, then apply.
func _check_action_applies() -> void:
	var session := _level.get_node_or_null("LevelRuntime")
	var object := _level.get_node_or_null("World/Objects/Object010MonitorTastaturFrontal")
	if session == null or object == null:
		_expect(false, "the level carries its session and a keyboard to prank")
		return
	var point := object.get_node("InteractionPoint")
	_player.global_position = (point as Node2D).global_position
	_controller.focus_point = point
	_controller.entries = _controller.build_entries(point)
	_expect(_controller.entries.size() == 3, "the keyboard offers its three free actions")

	var entry: Dictionary = _controller.entries[0]
	var action := ActionTable.get_action(int(entry["action_id"]))
	var score_before: int = session.score
	var console := session.get_node_or_null("Console")
	_expect(console != null, "the level carries its console")
	_controller.open_menu()
	_expect(console == null or console.get_node("ActionIcon").visible, "opening the ring shows the highlighted action's icon")
	_controller.confirm()
	_expect(_controller.state == 2, "confirming an entry starts the action")
	_expect(not _controller.menu_open, "committing closes the ring")
	# sub_41B240 only clears player+920 once the action applies, so the console keeps the
	# chosen action's icon and name up for as long as it runs.
	_expect(_controller.highlighted == 0, "committing keeps the chosen entry selected")
	_expect(console == null or console.get_node("ActionIcon").visible, "the icon stays up while the action runs")
	_expect(
		console == null or console.get_node("HoverText").text == String(entry["name"]),
		"the hover bar keeps the running action's name"
	)
	_expect(_player.input_locked, "the player is held still while the action runs")
	_expect(is_equal_approx(_controller._duration, float(action["duration_tenths"]) / 10.0), "the action runs for its own duration")

	_controller._advance_action(_controller._duration * 0.5)
	_expect(_controller.state == 2, "the action is still running halfway through")
	_expect(session.score == score_before, "no score is paid out before the action finishes")
	_expect(not point.tampered, "an object is not tampered with until the action applies")

	_controller._advance_action(_controller._duration)
	_expect(_controller.state == 0, "the action ends when its duration is up")
	_expect(not _player.input_locked, "the player is free again once the action applies")
	_expect(session.score == score_before + int(action["score"]), "the score rises by the table's value")
	# sub_41DE60 adds the score and floats the number off the player in the same breath.
	var popups := session.get_node_or_null("ScorePopups")
	_expect(popups != null and popups.live_count() == 1, "finishing an action floats its score")
	_expect(object.state == int(action["result_state"]), "the object reaches the action's result state")
	_expect(not point.is_action_enabled(int(entry["slot"])), "a used slot is not offered again")
	# ... and sub_41B0C0, the tick that is not an action session, puts it back to "...".
	_expect(_controller.highlighted == -1, "the selection is dropped once the action applies")
	_expect(console == null or not console.get_node("ActionIcon").visible, "the icon goes once the action applies")
	_expect(console == null or console.get_node("HoverText").text == "...", "the hover bar goes back to its placeholder")
	# sub_41B240 writes the slot flag and item+228 together, whatever the action did.
	_expect(point.tampered, "finishing an action leaves the object tampered with")
	var remaining: Array = _controller.build_entries(point).map(func(e): return int(e["action_id"]))
	_expect(not remaining.has(int(entry["action_id"])), "the ring loses the action that was used")
	# sub_410450: an action also shuts down whatever its own disable list names.
	for disabled in action.get("disables", []):
		_expect(not remaining.has(int(disabled)), "action %d also closes %d" % [int(entry["action_id"]), int(disabled)])
