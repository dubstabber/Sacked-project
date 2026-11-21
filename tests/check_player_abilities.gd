extends SceneTree

# The console lamps' abilities on the real level-13 map, which has a waiting room (3), a
# server room (4) and the boss's office (8): smoking's four records by the room at the
# player, its states 10 to 14 and their timing, the clip, the smoke's spawn and removal, the
# console's feed, the requests that are dropped, the catch, and the 31-slot inventory; then
# urinating's two records, its states 20 to 24, the facing, S0174, the puddle's life on the
# shared clock, its catch, the float32 timers at 60 fps, the depth test both effects are
# handed, and the level taking both with it; then the pill's states 40 to 43, the forty-second
# slow-down it starts on every agent, a second pill restarting it, and the overlay.
# See docs/player-ability-reference.md.

const LEVEL_SCENE := preload("res://scenes/level_13.tscn")
const AbilityController := preload("res://scenes/player/ability_controller.gd")
const PrankController := preload("res://scenes/player/prank_controller.gd")
const CollisionLayerScript := preload("res://scenes/shared/collision_map_layer.gd")
const POINT_SCRIPT := preload("res://scenes/npc/npc_activity_point.gd")
const LevelAudioScript := preload("res://scenes/level/level_audio.gd")
const PROFILES := {
	"jobless": preload("res://scenes/player/profiles/jobless.tres"),
	"anne": preload("res://scenes/player/profiles/anne.tres"),
}
const ITEM_BLADDER := 26
const ITEM_PILL := 14
const SlowdownOverlay := preload("res://scenes/player/slowdown_overlay.gd")
const Slowdown := preload("res://scenes/npc/slowdown.gd")
const PROGRESS_PATH := "user://check_player_abilities_progress.cfg"
const SETTINGS_PATH := "user://check_player_abilities_settings.cfg"

# A step every clock in the port can hold exactly, so 12.0 s is 192 of them.
const STEP := 0.0625
# Cells of level 13 and the room each lies in.
const WAITING_ROOM := Vector2(20, 19)
const SERVER_ROOM := Vector2(24, 3)
const BOSS_OFFICE := Vector2(5, 4)
const CORRIDOR := Vector2(9, 7)

var _failures := 0
var _level: Node
var _world: Node
var _player: Node2D
var _prank: Node
var _abilities: Node
var _layer: Node
var _session: Node
var _console: Node
var _watch: Node
var _cursor: Node
var _restore_progress := ""
var _restore_settings := ""


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_redirect_stores()
	_level = LEVEL_SCENE.instantiate()
	_world = _level.get_node("World")
	for child in _world.get_children():
		if child is CharacterBody2D and child.has_node("Brain"):
			child.get_node("Brain").enabled = false
	root.add_child(_level)
	await process_frame
	await process_frame
	_world.get_node("WorldDepthCompositor").set_process(false)
	_world.get_node("CharacterDepthCompositor").set_process(false)

	_player = _world.get_node("Player")
	_player.set_physics_process(false)
	_player.get_node("FootstepPlayer").stop_footsteps()
	_player.get_node("FootstepPlayer").stream = null
	_prank = _player.get_node("PrankController")
	_prank.set_process(false)
	_abilities = _player.get_node("AbilityController")
	_abilities.set_process(false)
	# The two frames above ran its clock on the wall clock; from zero, every step below is exact.
	_abilities.now = 0.0
	_abilities.random_source = func() -> float: return 0.5
	_cursor = _player.get_node("MovementArrow")
	_layer = _world.get_node("CollisionTileMapLayer")
	_session = _level.get_node("LevelRuntime")
	_session.set_physics_process(false)
	_console = _level.get_node("LevelRuntime/Console")
	_watch = _level.get_node("LevelRuntime/CatchWatch")
	_watch.set_process(false)

	_check_the_inventory_has_thirty_one_slots()
	_check_the_room_is_rounded_and_truncated()
	_check_each_room_pays_its_record()
	_check_state_13_asks_the_room_again()
	_check_the_timeline()
	_check_the_clip_plays_once_then_idles()
	_check_the_console_reads_the_ability()
	_check_a_lamp_click_reaches_the_controller()
	_check_requests_are_dropped_not_queued()
	_check_the_request_order()
	_check_the_player_is_held()
	_check_the_catch()
	_check_a_smoke_caught_after_its_clip_frees_at_once()

	_check_urinating_pays_by_room()
	_check_state_23_asks_the_room_again()
	for id: String in PROFILES:
		_player.apply_profile(PROFILES[id])
		_check_the_urination_facing(id)
		_check_the_puddle_lands_ahead(id)
	_player.apply_profile(PROFILES["jobless"])
	_check_s0174_plays_once()
	_check_one_puddle_that_spreads_fades_and_goes()
	_check_urinating_is_caught_in_21_and_22()
	_check_smoking_restarts_the_puddle_window()
	_check_the_timers_sum_as_float32()
	_check_smoking_and_urinating_stop_the_footstep()
	_check_the_pill()
	_check_the_slowdown_lasts_forty_seconds()
	_check_the_overlay()
	_check_the_overlay_covers_a_clustered_looping_item()
	_check_a_second_pill_restarts_the_slowdown()
	await _check_the_effects_are_depth_tested()
	var leftovers := _urinate_until_the_sound_plays()

	_level.free()
	_check_the_level_takes_both_with_it(leftovers)
	_restore_stores()
	if _failures == 0:
		print("Player abilities: 31 inventory slots, the room lookup, smoking's four records, its timeline, the clip, the console feed, dropped requests, the request order, the held player and the catch; urinating's records, facing, S0174, puddle, catch, shared clock, float32 timers, the effects' depth test and teardown; the pill's states, its forty seconds, a second pill and the overlay passed")
	quit(1 if _failures else 0)


func _expect(condition: bool, label: String) -> void:
	if not condition:
		_failures += 1
		push_error(label)


# A score can end the level through ScreenManager, which records progress; neither file may
# be the developer's.
func _redirect_stores() -> void:
	var progress := root.get_node("ProgressStore")
	_restore_progress = progress.path
	progress.path = PROGRESS_PATH
	DirAccess.remove_absolute(PROGRESS_PATH)
	progress.reload()
	var settings := root.get_node("SettingsStore")
	_restore_settings = settings.path
	settings.path = SETTINGS_PATH
	DirAccess.remove_absolute(SETTINGS_PATH)
	settings.reload()


func _restore_stores() -> void:
	var progress := root.get_node("ProgressStore")
	progress.path = _restore_progress
	progress.reload()
	DirAccess.remove_absolute(PROGRESS_PATH)
	var settings := root.get_node("SettingsStore")
	settings.path = _restore_settings
	settings.reload()
	DirAccess.remove_absolute(SETTINGS_PATH)


func _place(cell: Vector2) -> void:
	_player.global_position = _layer.from_grid_position(cell)


func _give_smokes(count := 1) -> void:
	_prank.inventory[5] = 0
	_prank.inventory[6] = 0
	for _i in range(count):
		_prank.grant_item(5)
	_prank.grant_item(6)


func _clear_effects() -> void:
	for effect in _abilities.effects:
		if is_instance_valid(effect):
			effect.get_parent().remove_child(effect)
			effect.free()
	_abilities.effects.clear()
	_abilities.smoke = null
	_abilities.puddle = null
	_abilities._stop_piss_sound()


func _advance_until_free(limit := 400) -> int:
	var ticks := 0
	while _abilities.mode != AbilityController.Mode.FREE and ticks < limit:
		_abilities.advance(STEP)
		ticks += 1
	return ticks


func _start_smoking(cell := CORRIDOR) -> void:
	_clear_effects()
	_place(cell)
	_give_smokes()
	_abilities.request(AbilityController.REQUEST_SMOKE)
	_abilities.advance(STEP)


func _absolute_z(item: CanvasItem) -> int:
	var z := 0
	var node: Node = item
	while node is CanvasItem:
		z += (node as CanvasItem).z_index
		if not (node as CanvasItem).z_as_relative:
			break
		node = node.get_parent()
	return z


func _hover_text() -> String:
	return String((_console.get_node("Band/HoverText") as Label).text)


# sub_41AF60 clears 31 bytes, +1008 to +1038, so items 28 and 29 have slots, and the
# requirement rules that name them now apply.
func _check_the_inventory_has_thirty_one_slots() -> void:
	_expect(_prank.inventory.size() == 31, "the inventory has 31 slots, got %d" % _prank.inventory.size())
	for case in [[115, 28], [135, 29]]:
		var action_id: int = case[0]
		var item: int = case[1]
		var point = POINT_SCRIPT.new()
		point.action_ids = PackedInt32Array([action_id])
		point.reset_actions()
		_prank.inventory[item] = 0
		_expect(_prank.available_slots(point).is_empty(), "action %d is hidden without item %d" % [action_id, item])
		_prank.grant_item(item)
		_expect(_prank.inventory[item] == 1, "granting item %d lands in its slot" % item)
		_expect(_prank.available_slots(point) == PackedInt32Array([0]), "action %d is offered once item %d is held" % [action_id, item])
		_prank.inventory[item] = 0
		point.free()


# sub_412AE0(int(x + 0.5), int(z + 0.5), 4): ftol truncates toward zero, and off the grid is 0.
func _check_the_room_is_rounded_and_truncated() -> void:
	var cases := {WAITING_ROOM: 3, SERVER_ROOM: 4, BOSS_OFFICE: 8, CORRIDOR: 0}
	for cell: Vector2 in cases:
		_expect(_layer.room_category(cell) == int(cases[cell]), "level 13's cell %s is room %d" % [cell, cases[cell]])
	_expect(_layer.room_category(Vector2(20.49, 19.0)) == 3 and _layer.room_category(Vector2(20.5, 19.0)) == 0, "x + 0.5 is truncated to the cell")
	_expect(_layer.room_category(Vector2(19.5, 19.0)) == 3, "and x.5 rounds up")

	var small = CollisionLayerScript.new()
	small.room_ids = PackedByteArray([7, 1, 2, 3])
	small.room_grid_size = Vector2i(2, 2)
	_expect(small.room_category(Vector2(-0.9, 0.2)) == 7, "int(-0.4) is 0, so just off the left edge still reads column 0")
	_expect(small.room_category(Vector2(-1.6, 0.0)) == 0, "a cell off the grid answers 0")
	_expect(small.room_category(Vector2(0.6, 0.6)) == 3, "and the rest of the grid is x + width * z")
	_expect(small.room_category(Vector2(2.0, 0.0)) == 0, "past the right edge answers 0 too")
	small.free()


# sub_41BC50's four records, each 120 tenths (a total of 1200 hundredths), paid in state 13
# once elapsed * 100 >= 1200, with one pack of cigarettes spent and the lighter kept. State 12
# zeroes the timers on its way to 13, so the stopwatch is empty on that tick.
func _check_each_room_pays_its_record() -> void:
	var cases := [[WAITING_ROOM, 22], [SERVER_ROOM, 76], [BOSS_OFFICE, 24], [CORRIDOR, 23]]
	var lamp := _console.get_node("Band/LampSmoke") as Sprite2D
	for case in cases:
		var cell: Vector2 = case[0]
		var expected: int = case[1]
		var record := ActionTable.get_action(expected)
		var score_before := int(_session.score)
		_start_smoking(cell)
		var started: float = _abilities.now
		_expect(_abilities.mode == AbilityController.Mode.SMOKING and _abilities.state == 11, "the lamp starts mode 2 and state 10 runs in the same tick")
		_expect(_abilities.record == expected, "cell %s pays record %d, got %d" % [cell, expected, _abilities.record])
		_expect(is_equal_approx(_abilities.total, 1200.0), "the total is 120 tenths as 1200 hundredths")
		_expect(_hover_text() == ActionTable.action_name(expected), "the hover bar names record %d, got %s" % [expected, _hover_text()])
		_expect(lamp.visible, "the lamp is lit while the pack is held")
		var state_13_at := -1.0
		var guard := 0
		var clock := _console.get_node("Band/ClockBar") as Sprite2D
		while _abilities.mode != AbilityController.Mode.FREE and guard < 400:
			_abilities.advance(STEP)
			guard += 1
			if _abilities.state == 13 and state_13_at < 0.0:
				state_13_at = _abilities.now - started
				_expect(is_zero_approx(_abilities.elapsed) and is_zero_approx(_abilities.total), "state 12 zeroes the timers on its way to 13")
				_expect(not clock.visible, "so the stopwatch is empty on that tick, not full")
		_expect(is_equal_approx(state_13_at, 12.0), "state 13 comes at 12.0 s, got %f" % state_13_at)
		_expect(int(_session.score) == score_before + int(record["score"]), "record %d pays %d" % [expected, record["score"]])
		_expect(_prank.inventory[5] == 0, "the pack of cigarettes is spent")
		_expect(_prank.inventory[6] == 99, "the lighter is never spent")
		_expect(not lamp.visible, "the lamp goes dark with the last pack")
		_expect(is_equal_approx(_abilities.elapsed, 0.0) and is_equal_approx(_abilities.total, 0.0), "the timers stay zeroed")
	_clear_effects()


# State 13 asks sub_412AE0 for the room at the player again to choose the score it pays
# (0x41C023-0x41C07E), while the hover bar keeps the name state 10 chose.
func _check_state_13_asks_the_room_again() -> void:
	_start_smoking(SERVER_ROOM)
	while _abilities.state != 13 and _abilities.mode != AbilityController.Mode.FREE:
		_abilities.advance(STEP)
	_expect(_abilities.state == 13 and _abilities.record == 76, "the server room chose record 76")
	var score_before := int(_session.score)
	_place(BOSS_OFFICE)
	_abilities.advance(STEP)
	_expect(int(_session.score) == score_before + int(ActionTable.get_action(24)["score"]), "state 13 pays the boss's office, record 24's %d, got %d" % [ActionTable.get_action(24)["score"], int(_session.score) - score_before])
	_expect(_hover_text() == ActionTable.action_name(76), "while the hover bar keeps record 76's name")
	_clear_effects()


# From the state-10 tick S: the smoke strictly after 0.4 s, its emission stopped past S + 4.9 on
# the shared clock, and the smoke gone once its last particle has died, about S + 9.4.
func _check_the_timeline() -> void:
	_clear_effects()
	_place(CORRIDOR)
	_give_smokes()
	_player.set("last_direction", IsoDirection.get_screen_directions()[2])
	_abilities.request(AbilityController.REQUEST_SMOKE)
	_abilities.advance(0.2)
	var start: float = _abilities.now
	_expect(is_equal_approx(_abilities.effect_clock, start), "state 10 sets the effect clock")
	_abilities.advance(0.2)
	_abilities.advance(0.2)
	_expect(_abilities.smoke == null and _abilities.state == 11, "nothing is spawned at exactly 0.4 s")
	_abilities.advance(0.2)
	var smoke: Node2D = _abilities.smoke
	_expect(smoke != null and _abilities.state == 12, "the smoke is spawned once 0.4 s is passed")
	if smoke == null:
		return
	var spawned: float = _abilities.now
	_expect(is_equal_approx(_abilities.effect_clock, spawned), "the spawn resets the effect clock")
	_expect(smoke.get_parent() == _world and smoke.z_index == 3, "the smoke lives in the world, drawn after the characters")
	# Main_RenderUpdate draws the walk arrow (sub_415500, 0x402D01) after the effects pass.
	_expect(_absolute_z(_cursor) > _absolute_z(smoke), "the walk arrow draws over the smoke, z %d over %d" % [_absolute_z(_cursor), _absolute_z(smoke)])
	var ground: Vector2 = _layer.to_grid_position(_player.global_position)
	var a := (2.0 * 45.0 + 180.0) * 0.017453
	_expect(
		is_equal_approx(smoke.emitter.x, ground.x - 0.21 * sin(a)) and is_equal_approx(smoke.emitter.z, ground.y + 0.21 * cos(a)),
		"the emitter is 0.21 tiles along view 2's facing, got %s" % smoke.emitter
	)
	_expect(is_equal_approx(smoke.emitter.y, 1.85), "at the mouth, 1.85 units up")
	while _abilities.now - spawned <= 4.5:
		_expect(not smoke.stopped, "the smoke emits until 4.5 s have passed on the shared clock")
		_abilities.advance(STEP)
	_expect(smoke.stopped, "past 4.5 s the player's tick stops it for good")
	var removed_at := -1.0
	while _abilities.mode != AbilityController.Mode.FREE:
		_abilities.advance(STEP)
		if removed_at < 0.0 and _abilities.smoke == null:
			removed_at = _abilities.now - start
	_expect(removed_at > 8.4 and removed_at < 9.8, "the smoke is deleted once its last particle is dead, %f s after state 10" % removed_at)
	_expect(not is_instance_valid(smoke) or smoke.is_queued_for_deletion(), "and freed")
	_expect(_abilities.effects.is_empty(), "the effects list is empty again")


# SMOKE plays once in the facing the player has, holds its last frame one extra tick, and gives
# way to the clock-driven idle; the player stays in mode 2 for the rest of the 12 s.
func _check_the_clip_plays_once_then_idles() -> void:
	var facing: Vector2 = IsoDirection.get_screen_directions()[5]
	_player.set("last_direction", facing)
	_start_smoking()
	var controller = _player.animation_controller
	var id := String(_player.profile.get("id"))
	var expected: String = "%s-actions/%s-smoke-%s" % [id, id, "left"]
	_expect(controller.current_animation == expected, "state 10 plays %s, got %s" % [expected, controller.current_animation])
	_expect(_player.action_animation_name("smoke", facing) == expected, "the clip keeps the facing")
	var length: float = _player.animation_player.get_animation(expected).length
	var frames: Array = controller._animation_frames(expected)["frames"]
	var ticks := int(round(length / STEP))
	for _i in range(ticks):
		_abilities.advance(STEP)
	var sprite := _player.get_node("Sprite2D") as Sprite2D
	_expect(controller.current_animation == expected, "the clip is still up the tick it runs out")
	_expect(sprite.texture == frames[frames.size() - 1]["texture"], "showing its last frame")
	_abilities.advance(STEP)
	_expect(String(controller.current_animation).begins_with(controller.idle_animation_prefix), "the next tick plays the idle, got %s" % controller.current_animation)
	_expect(_player.get("last_direction") == facing, "in the same view")
	_expect(_abilities.mode == AbilityController.Mode.SMOKING and _player.input_locked, "and the player idles, held, for the rest of the 12 s")
	_advance_until_free()
	_clear_effects()


# The console reads the ability through the prank controller's own signals: the record's
# name, the stopwatch sweeping 12 s, the centre icon hidden, and "..." back on the first free
# tick.
func _check_the_console_reads_the_ability() -> void:
	_start_smoking(SERVER_ROOM)
	var clock := _console.get_node("Band/ClockBar") as Sprite2D
	var icon := _console.get_node("Band/ActionIcon") as Sprite2D
	for _i in range(96):
		_abilities.advance(STEP)
	var progress := float(_console.action_progress)
	_expect(clock.visible and is_equal_approx(progress, _abilities.elapsed * 100.0 / 1200.0), "the stopwatch sweeps elapsed / 12 s, got %f" % progress)
	_expect(not icon.visible, "the centre icon stays hidden")
	_expect(_hover_text() == ActionTable.action_name(76), "the hover bar holds the record's name")
	_advance_until_free()
	_expect(not clock.visible, "the stopwatch clears when the timers are zeroed")
	_expect(_hover_text() == ActionTable.action_name(76), "the name stays until the first free tick")
	_prank._process(0.0)
	_expect(_hover_text() == "...", "which writes ... back, got %s" % _hover_text())
	_clear_effects()


# sub_41CF20 only looks while +900 == 0, and the next frame's mask loses the bit otherwise.
# The whole route on the real level: a left press and release inside the lit smoking lamp go
# to the console, which found this controller through the player_abilities group in its
# _ready, and the controller's next tick starts smoking. See "The lamps are buttons" in
# docs/player-ability-reference.md.
func _check_a_lamp_click_reaches_the_controller() -> void:
	_clear_effects()
	_place(CORRIDOR)
	_give_smokes()
	var lamp := _console.get_node("Band/LampSmoke") as Sprite2D
	_expect(lamp.visible, "cigarettes and a lighter light the smoking lamp")
	var band := _console.get_node("Band") as Control
	var inside := Vector2.INF
	for y in range(int(lamp.texture.get_height())):
		for x in range(int(lamp.texture.get_width())):
			var at: Vector2 = band.get_global_transform_with_canvas() * (lamp.position + Vector2(x, y) + Vector2(0.5, 0.5))
			if _console.lamp_at(at) == "LampSmoke":
				inside = at
				break
		if inside.is_finite():
			break
	_expect(inside.is_finite(), "some pixel of the smoking lamp is its own")
	if not inside.is_finite():
		return
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		event.pressed = pressed
		event.position = inside
		event.global_position = inside
		root.push_input(event, true)
	_expect(_abilities.mode == AbilityController.Mode.FREE, "the press waits for the controller's next tick")
	_abilities.advance(STEP)
	_expect(
		_abilities.mode == AbilityController.Mode.SMOKING and _abilities.state == 11,
		"the lamp's click starts smoking on that tick, got mode %d state %d" % [_abilities.mode, _abilities.state]
	)
	_advance_until_free()
	_clear_effects()


func _check_requests_are_dropped_not_queued() -> void:
	_clear_effects()
	_place(CORRIDOR)
	_give_smokes()
	for busy in [PrankController.State.ACTING, PrankController.State.MENU]:
		_prank.state = busy
		_abilities.request(AbilityController.REQUEST_SMOKE)
		_abilities.advance(STEP)
		_prank.state = PrankController.State.FREE
		_abilities.advance(STEP)
		_expect(_abilities.mode == AbilityController.Mode.FREE, "a press while the prank controller is in state %d is lost" % busy)

	_abilities.request(AbilityController.REQUEST_SMOKE)
	paused = true
	paused = false
	_abilities.advance(STEP)
	_expect(_abilities.mode == AbilityController.Mode.FREE, "a press the pause swallowed is gone once it lifts")

	_start_smoking()
	_abilities.advance(STEP)
	var state: int = _abilities.state
	_abilities.request(AbilityController.REQUEST_SMOKE)
	_abilities.advance(STEP)
	_expect(_abilities.state == state or _abilities.state == state + 1, "a second press does not restart the ability")
	_advance_until_free()
	_abilities.advance(STEP)
	_expect(_abilities.mode == AbilityController.Mode.FREE, "and is not kept for later")

	# The act input with a focus item comes first: the ring opens and the lamp is lost.
	var point := _first_point_with_actions()
	if point == null:
		_expect(false, "level 13 has an item with actions")
	else:
		_give_smokes()
		_prank.focus_point = point
		_prank.entries = _prank.build_entries(point)
		var act := InputEventKey.new()
		act.physical_keycode = KEY_SPACE
		act.pressed = true
		_prank._unhandled_input(act)
		_abilities.request(AbilityController.REQUEST_SMOKE)
		_abilities.advance(STEP)
		_expect(_prank.menu_open and _abilities.mode == AbilityController.Mode.FREE, "act with a focus beats the lamp")
		_prank.close_menu()
		_prank.focus_point = null
	_clear_effects()


func _first_point_with_actions() -> Node:
	for point in get_nodes_in_group("npc_activity_points"):
		if not _prank.build_entries(point).is_empty():
			return point
	return null


# Smoking 0x800, then urination 0x1000, foam 0x2000 and the pill 0x4000. Foam has no states and
# nothing raises its bit, so a request for it goes nowhere.
func _check_the_request_order() -> void:
	var smoke := AbilityController.REQUEST_SMOKE
	var piss := AbilityController.REQUEST_PISS
	var pill := AbilityController.REQUEST_PILL
	_expect(AbilityController.pick_request(smoke | piss | pill) == smoke, "smoking wins")
	_expect(AbilityController.pick_request(piss | pill) == piss, "then urination")
	_expect(AbilityController.pick_request(pill) == pill, "then the pill")
	_give_smokes()
	_abilities.request(AbilityController.REQUEST_FOAM)
	_abilities.advance(STEP)
	_expect(_abilities.mode == AbilityController.Mode.FREE, "mode 4 never starts")


# An ability stops the player at once, even mid-walk; Escape, the down arrow and the right
# button do not cancel it, and the keyboard walk, which lives in the player's own physics
# tick, goes nowhere; a right release puts the pointer back on the player (0x40447E-0x4044A3)
# without starting a walk; a right button still held at the end walks again.
func _check_the_player_is_held() -> void:
	_player.set("is_mouse_movement_active", true)
	_start_smoking()
	_expect(_player.input_locked and not _player.is_mouse_movement_active, "the walk stops the tick the ability starts")
	_expect(_cursor.shows_busy_cursor, "the clock is the pointer")
	var state: int = _abilities.state
	var held_at := _player.global_position
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	var down := InputEventKey.new()
	down.physical_keycode = KEY_DOWN
	down.pressed = true
	var right := InputEventMouseButton.new()
	right.button_index = MOUSE_BUTTON_RIGHT
	right.pressed = true
	right.position = Vector2(400, 300)
	for event in [escape, down, right]:
		root.push_input(event, true)
	Input.action_press("move_down")
	for _i in range(4):
		_player._physics_process(STEP)
		_abilities.advance(STEP)
	Input.action_release("move_down")
	_expect(_abilities.mode == AbilityController.Mode.SMOKING and _abilities.state >= state, "Escape, down and the right button cancel nothing")
	_expect(_player.global_position == held_at and _player.input_locked, "the down arrow walks nowhere while it runs")
	_expect(not _player.is_mouse_movement_active, "and the right button starts no walk")

	_cursor.last_recentre = Vector2.INF
	var release := right.duplicate() as InputEventMouseButton
	release.pressed = false
	root.push_input(release, true)
	_expect(_cursor.last_recentre == _player.get_player_viewport_position(), "a right release puts the pointer back on the player, got %s" % _cursor.last_recentre)
	_expect(_cursor.shows_busy_cursor and not _player.is_mouse_movement_active, "keeping the clock and starting no walk")

	Input.action_press("mouse-movement")
	_advance_until_free()
	_expect(not _player.input_locked and _player.is_mouse_movement_active, "a right button held at the end walks again")
	Input.action_release("mouse-movement")
	_player.stop_mouse_movement()

	var controller = _player.animation_controller
	Input.action_press("move_down")
	_player._physics_process(STEP)
	Input.action_release("move_down")
	_expect(String(controller.current_animation).begins_with(controller.walk_animation_prefix), "once free, the down arrow walks again")
	_player._physics_process(STEP)
	_place(CORRIDOR)

	_start_smoking()
	_advance_until_free()
	_expect(not _cursor.shows_busy_cursor and not _player.is_mouse_movement_active, "otherwise the pointer comes back and the player stands")
	_clear_effects()


# sub_402470 catches smoking in 11 and 12 and writes 14, which waits for SMOKE, then idles and
# frees the player without paying or spending. The smoke stays.
func _check_the_catch() -> void:
	var agent: Node2D = null
	for node in get_nodes_in_group("npc_agents"):
		agent = node
		break
	_watch.hands_off_to_minigame = false
	_watch.reset()
	_expect(not _watch._is_mid_prank(), "standing about is safe")
	_start_smoking()
	_expect(_watch._is_mid_prank(), "state 11 can be caught from its first tick")
	while _abilities.state == 11:
		_abilities.advance(STEP)
	_expect(_watch._is_mid_prank(), "so can state 12")
	var smoke: Node2D = _abilities.smoke
	var score_before := int(_session.score)
	var elapsed_before: float = _abilities.elapsed
	_watch._catch(agent)
	_expect(_abilities.state == 14, "the catch writes state 14, got %d" % _abilities.state)
	_expect(not _cursor.shows_busy_cursor, "14 shows the pointer")
	_expect(not _watch._is_mid_prank(), "and is not caught again")
	var clock := _console.get_node("Band/ClockBar") as Sprite2D
	_abilities.advance(STEP)
	_expect(_abilities.state == 14 and is_equal_approx(_abilities.elapsed, elapsed_before), "14 waits for SMOKE with the stopwatch held")
	_expect(clock.visible, "which still shows the partial sweep")
	_advance_until_free()
	_expect(int(_session.score) == score_before, "a catch pays nothing")
	_expect(_prank.inventory[5] == 1, "and spends nothing")
	_expect((_console.get_node("Band/LampSmoke") as Sprite2D).visible, "so the lamp stays lit")
	_expect(is_instance_valid(smoke) and smoke == _abilities.smoke, "the smoke already spawned stays")
	_expect(not clock.visible and is_equal_approx(_abilities.total, 0.0), "14 zeroes the timers")
	_expect(String(_player.animation_controller.current_animation).begins_with(_player.animation_controller.idle_animation_prefix), "and idles")

	# Neither the first and last states nor the pill are in the catch set.
	for probe in [[AbilityController.Mode.SMOKING, 10], [AbilityController.Mode.SMOKING, 13], [AbilityController.Mode.PILL, 42]]:
		_abilities.mode = probe[0]
		_abilities.state = probe[1]
		_expect(not _abilities.is_catchable(), "mode %d state %d is never caught" % probe)
	_abilities.mode = AbilityController.Mode.FREE
	_abilities.state = 0
	_watch.reset()
	_console.hide_catch_warning()
	_clear_effects()


# A smoke caught once SMOKE has run out gets its abort at the banner's zero step: 14 finds the
# clip finished, idles and frees the player at once.
func _check_a_smoke_caught_after_its_clip_frees_at_once() -> void:
	_watch.hands_off_to_minigame = false
	_watch.reset()
	_start_smoking()
	var controller = _player.animation_controller
	var length: float = _player.animation_player.get_animation(controller.current_animation).length
	while _abilities.now - _abilities.effect_clock < length + 0.5:
		_abilities.advance(STEP)
	_expect(_abilities.state == 12, "the smoke is still in state 12")
	_abilities.catch()
	_expect(_abilities.mode == AbilityController.Mode.FREE, "14 runs in the catch's zero step and frees the player, got mode %d state %d" % [_abilities.mode, _abilities.state])
	_watch.reset()
	_clear_effects()


func _give_bladder(count := 1) -> void:
	_prank.inventory[ITEM_BLADDER] = 0
	for _i in range(count):
		_prank.grant_item(ITEM_BLADDER)


# rand() for state 20's facing tests, in turn, then 0.
func _roll(values: Array) -> void:
	var queue := values.duplicate()
	_abilities.facing_roll = func() -> int: return int(queue.pop_front()) if not queue.is_empty() else 0


# The request's tick runs state 20, which leaves 21 for the next.
func _start_urinating(cell := CORRIDOR, rolls := [8]) -> void:
	_clear_effects()
	_place(cell)
	_give_bladder()
	_roll(rolls)
	_abilities.request(AbilityController.REQUEST_PISS)
	_abilities.advance(STEP)


func _profile_id() -> String:
	return String(_player.profile.get("id"))


func _puddles_listed() -> int:
	return _abilities.effects.filter(func(effect) -> bool: return is_instance_valid(effect) and effect.name.begins_with("Puddle")).size()


# sub_41C120's two records, 70 tenths each: 75 in the boss's office (800) and 74 anywhere else
# (500), paid in state 23 with one bladder spent, the stopwatch sweeping the 7 s.
func _check_urinating_pays_by_room() -> void:
	var lamp := _console.get_node("Band/LampPiss") as Sprite2D
	var clock := _console.get_node("Band/ClockBar") as Sprite2D
	for case in [[CORRIDOR, 74, 500], [BOSS_OFFICE, 75, 800]]:
		var cell: Vector2 = case[0]
		var expected: int = case[1]
		var score_before := int(_session.score)
		_start_urinating(cell)
		var started: float = _abilities.now
		_expect(_abilities.mode == AbilityController.Mode.URINATING and _abilities.state == 21, "the lamp starts mode 3 and state 20 runs in the same tick")
		_expect(_abilities.record == expected, "cell %s picks record %d, got %d" % [cell, expected, _abilities.record])
		_expect(is_equal_approx(_abilities.total, 700.0), "the total is 70 tenths as 700 hundredths, got %f" % _abilities.total)
		_expect(_hover_text() == ActionTable.action_name(expected), "the hover bar names record %d, got %s" % [expected, _hover_text()])
		_expect(_abilities.puddle == null, "state 20 spawns nothing")
		_expect(_player.input_locked and _cursor.shows_busy_cursor, "the player is held under the clock")
		_expect(lamp.visible, "the lamp is lit while the bladder is full")
		var state_23_at := -1.0
		var guard := 0
		while _abilities.mode != AbilityController.Mode.FREE and guard < 400:
			_abilities.advance(STEP)
			guard += 1
			if guard == 56:
				var progress := float(_console.action_progress)
				_expect(clock.visible and is_equal_approx(progress, _abilities.elapsed * 100.0 / 700.0), "the stopwatch sweeps elapsed / 7 s, got %f" % progress)
			if _abilities.state == 23 and state_23_at < 0.0:
				state_23_at = _abilities.now - started
				_expect(is_zero_approx(_abilities.elapsed) and is_zero_approx(_abilities.total), "state 22 zeroes the timers on its way to 23")
		_expect(is_equal_approx(state_23_at, 7.0), "state 23 comes at 7.0 s, got %f" % state_23_at)
		_expect(int(_session.score) == score_before + int(case[2]), "record %d pays %d, got %d" % [expected, case[2], int(_session.score) - score_before])
		_expect(_prank.inventory[ITEM_BLADDER] == 0, "the bladder is spent")
		_expect(not lamp.visible, "the lamp goes dark with it")
		_expect(not _player.input_locked and not _cursor.shows_busy_cursor, "and the player is free")
	_clear_effects()


# State 23 asks sub_412AE0 for the room at the player again to choose the score it pays
# (0x41C52A-0x41C55F), while the hover bar keeps the name state 20 chose.
func _check_state_23_asks_the_room_again() -> void:
	_start_urinating(CORRIDOR)
	while _abilities.state != 23 and _abilities.mode != AbilityController.Mode.FREE:
		_abilities.advance(STEP)
	_expect(_abilities.state == 23 and _abilities.record == 74, "the corridor chose record 74")
	var score_before := int(_session.score)
	_place(BOSS_OFFICE)
	_abilities.advance(STEP)
	_expect(int(_session.score) == score_before + 800, "state 23 pays the boss's office, record 75's 800, got %d" % (int(_session.score) - score_before))
	_expect(_hover_text() == ActionTable.action_name(74), "while the hover bar keeps record 74's name")
	_clear_effects()


# Two rand() & 8 tests pick the first view half the time and the others a quarter each: Anne
# 2, 3, 4 and Jo 0, 6, 7, played as PISS#1 on the clock, and kept after the end. Selector 12
# picks the same way, and every view it picks ships both PISS clips.
func _check_the_urination_facing(id: String) -> void:
	var views: Array = PrankController.PISS_VIEWS[id]
	var directions := IsoDirection.get_screen_directions()
	for case in [[[8], 0], [[0, 8], 1], [[0, 0], 2], [[8, 0], 0], [[24, 0], 0], [[7, 15], 1]]:
		var queue: Array = (case[0] as Array).duplicate()
		var picked := PrankController.piss_facing(id, func() -> int: return int(queue.pop_front()) if not queue.is_empty() else 0)
		_expect(picked == directions[int(views[int(case[1])])], "%s: rolls %s pick view %d" % [id, case[0], views[int(case[1])]])
	for view in views:
		for clip in ["piss-1", "piss-2"]:
			_expect(_player.action_animation_name(clip, directions[int(view)]) != "", "%s ships %s in view %d" % [id, clip, view])

	var controller = _player.animation_controller
	for choice in range(3):
		var rolls: Array = [[8], [0, 8], [0, 0]][choice]
		_player.set("last_direction", directions[1])
		_start_urinating(CORRIDOR, rolls)
		var facing: Vector2 = directions[int(views[choice])]
		var expected: String = _player.action_animation_name("piss-1", facing)
		_expect(_player.get("last_direction") == facing and _abilities.view_index() == int(views[choice]), "%s faces view %d" % [id, views[choice]])
		_expect(expected != "" and controller.current_animation == expected, "%s plays %s, got %s" % [id, expected, controller.current_animation])
		_expect(controller.is_clock_driven_animation(expected) and controller.clock_driven_animation_frames.has(expected), "PISS#1 is locked to the clock")
		var data: Dictionary = controller.clock_driven_animation_frames.get(expected, {})
		_expect(is_equal_approx(float(data.get("length", 0.0)), 0.375) and (data.get("frames", []) as Array).size() == 6, "six frames at 16 fps, 0.375 s")
		_expect(not _player.animation_player.is_playing(), "the frame comes from the clock, not the AnimationPlayer")
		_advance_until_free()
		_expect(_player.get("last_direction") == facing, "the facing is kept afterwards")
		_expect(controller.current_animation == controller.get_directional_animation_name(controller.idle_animation_prefix, facing), "in the idle, got %s" % controller.current_animation)
	_clear_effects()


# State 21 builds the puddle a = (view * 45 + 180) degrees and d tiles along it, 0.2 for Anne
# and 0.6 for Jo, and sets the shared clock.
func _check_the_puddle_lands_ahead(id: String) -> void:
	var views: Array = PrankController.PISS_VIEWS[id]
	for choice in range(3):
		var rolls: Array = [[8], [0, 8], [0, 0]][choice]
		_start_urinating(CORRIDOR, rolls)
		_abilities.advance(STEP)
		var puddle: Sprite2D = _abilities.puddle
		_expect(puddle != null and _abilities.state == 22, "state 21 builds the puddle")
		if puddle == null:
			continue
		_expect(puddle.get_parent() == _world and puddle.z_index == 3, "in the world, drawn after the characters")
		_expect(puddle.get_index() > _player.get_index(), "after the player, so its own _process follows the controller's tick")
		_expect(is_equal_approx(_abilities.effect_clock, _abilities.now) and is_equal_approx(puddle.start, _abilities.now), "state 21 sets the shared clock and the clip's start")
		var ground: Vector2 = _layer.to_grid_position(_player.global_position)
		var a := (float(views[choice]) * 45.0 + 180.0) * 0.017453
		var reach := 0.2 if id == "anne" else 0.6
		var expected := Vector2(ground.x - reach * sin(a), ground.y + reach * cos(a))
		_expect(puddle.ground.distance_to(expected) < 1.0e-4, "%s view %d: the puddle lies %.1f tiles ahead at %s, got %s" % [id, views[choice], reach, expected, puddle.ground])
		_expect(is_equal_approx(puddle.height, 0.1), "0.1 units up")
		_expect(puddle.clip_frame == 0 and puddle.texture != null, "showing the clip's first frame")
		_advance_until_free()
	_clear_effects()


# sub_42A6A0(handler, "S0174", 0, 0): once, at the full effects volume, not positional, through
# the game's own handler, held in +1116 until state 23 stops it. It plays on through a pause
# while the ability's clock stands still.
func _check_s0174_plays_once() -> void:
	_start_urinating()
	_expect(_abilities.piss_sound == null, "state 20 starts no sound")
	_abilities.advance(STEP)
	var sound: AudioStreamPlayer = _abilities.piss_sound
	_expect(sound != null and _abilities.state == 22, "state 21 starts S0174")
	if sound == null:
		_clear_effects()
		return
	var stream := LevelAudioScript.effect_stream("S0174")
	_expect(stream != null and sound.stream == stream, "the sound is S0174")
	_expect(stream is AudioStreamWAV and (stream as AudioStreamWAV).loop_mode == AudioStreamWAV.LOOP_DISABLED, "played once, not looped")
	_expect(is_zero_approx(sound.volume_db) and sound.bus == &"SFX", "at the full effects volume")
	_expect(sound.get_parent() == root.get_node("ScreenManager"), "through the game's handler, with no position")
	_expect(sound.playing, "it plays through state 22")
	for _i in range(40):
		_abilities.advance(STEP)
	_expect(_abilities.piss_sound == sound and _abilities.state == 22, "and state 22 starts no second one")
	paused = true
	_expect(sound.can_process() and sound.playing, "the pause leaves it playing")
	_expect(not _abilities.can_process(), "while the ability's clock stands still")
	paused = false
	_advance_until_free()
	_expect(_abilities.piss_sound == null, "state 23 lets go of +1116")
	_expect(not is_instance_valid(sound) or (not sound.playing and sound.is_queued_for_deletion()), "and stops S0174")

	# The sound lasts 6.762 s, so in play it ends 0.24 s before state 23 and the handler frees
	# its player; state 23 and 24 then stop nothing, and must not trip over the freed handle.
	for abort in [false, true]:
		_start_urinating()
		_abilities.advance(STEP)
		_abilities.piss_sound.free()
		if abort:
			_abilities.catch()
		else:
			_advance_until_free()
		_expect(_abilities.mode == AbilityController.Mode.FREE and _abilities.piss_sound == null, "state %d lets go of a handle whose sound has ended" % (24 if abort else 23))
	_clear_effects()


# One puddle at a time, drawn with the clip's frame; past ten seconds on the shared clock it
# spreads and fades, and past seventeen it is gone.
func _check_one_puddle_that_spreads_fades_and_goes() -> void:
	_start_urinating()
	_abilities.advance(STEP)
	var first: Sprite2D = _abilities.puddle
	_advance_until_free()
	_give_bladder()
	_abilities.request(AbilityController.REQUEST_PISS)
	_abilities.advance(STEP)
	_expect(_abilities.puddle == first, "the old puddle stays until the new one's state 21")
	_abilities.advance(STEP)
	var puddle: Sprite2D = _abilities.puddle
	_expect(puddle != null and puddle != first, "state 21 builds a new puddle")
	_expect(not is_instance_valid(first) or first.is_queued_for_deletion(), "and deletes the old one at once")
	_expect(_puddles_listed() == 1, "only one puddle is on the effects list, got %d" % _puddles_listed())
	if puddle == null:
		_clear_effects()
		return
	var clock: float = _abilities.effect_clock
	_advance_until_free()
	_expect(_abilities.puddle == puddle, "the puddle outlives the ability")
	_abilities.advance(clock + 10.0 - _abilities.now)
	_expect(puddle.scale_units() == 256 and puddle.alpha_byte() == 179, "up to 10 s it keeps scale 1 and alpha 179")
	_expect(puddle.clip_frame == 10, "holding the grown frame")
	_abilities.advance(clock + 12.0 - _abilities.now)
	_expect(puddle.scale_units() == 296 and puddle.alpha_byte() == 135, "at 12 s: scale 296/256 and alpha 135, got %d and %d" % [puddle.scale_units(), puddle.alpha_byte()])
	_expect(puddle.drawn_rect.size == Vector2(78, 55), "the 68 x 48 frame covers 78 x 55, got %s" % puddle.drawn_rect.size)
	_abilities.advance(clock + 16.9 - _abilities.now)
	_expect(puddle.scale_units() == 397 and puddle.alpha_byte() == 29, "at 16.9 s: scale 397/256 and alpha 29, got %d and %d" % [puddle.scale_units(), puddle.alpha_byte()])
	_abilities.advance(clock + 17.0 - _abilities.now)
	_expect(_abilities.puddle == puddle and is_instance_valid(puddle), "at exactly 17 s it is still there")
	_abilities.advance(clock + 17.1 - _abilities.now)
	_expect(_abilities.puddle == null, "past 17 s the tick deletes it")
	_expect(not is_instance_valid(puddle) or puddle.is_queued_for_deletion(), "and frees it")
	_expect(_puddles_listed() == 0, "the effects list lets it go")
	_clear_effects()


# sub_402470 catches urinating in 21 and 22 and writes 24, which the banner's zero step runs at
# once: idle, free, S0174 stopped, nothing paid or spent. 21 is caught only on the tick that
# set it, before any puddle exists.
func _check_urinating_is_caught_in_21_and_22() -> void:
	var agent: Node2D = null
	for node in get_nodes_in_group("npc_agents"):
		agent = node
		break
	var lamp := _console.get_node("Band/LampPiss") as Sprite2D
	var clock := _console.get_node("Band/ClockBar") as Sprite2D
	var controller = _player.animation_controller
	_watch.hands_off_to_minigame = false
	_watch.reset()

	_start_urinating()
	var facing: Vector2 = _player.get("last_direction")
	var score_before := int(_session.score)
	_expect(_abilities.state == 21 and _watch._is_mid_prank(), "state 21 can be caught on the tick that set it")
	_watch._catch(agent)
	_expect(_abilities.mode == AbilityController.Mode.FREE, "24 runs at once and frees the player, got mode %d state %d" % [_abilities.mode, _abilities.state])
	_expect(_abilities.puddle == null and _abilities.piss_sound == null, "no puddle was built and no sound started")
	_expect(int(_session.score) == score_before and _prank.inventory[ITEM_BLADDER] == 1 and lamp.visible, "nothing is paid or spent, and the lamp stays lit")
	_expect(not _cursor.shows_busy_cursor, "the pointer is back")
	_expect(controller.current_animation == controller.get_directional_animation_name(controller.idle_animation_prefix, facing), "the player idles in the same view")
	_watch.reset()
	_console.hide_catch_warning()

	_start_urinating()
	_abilities.advance(STEP)
	for _i in range(20):
		_abilities.advance(STEP)
	var puddle: Sprite2D = _abilities.puddle
	var sound: AudioStreamPlayer = _abilities.piss_sound
	score_before = int(_session.score)
	_expect(_abilities.state == 22 and _watch._is_mid_prank(), "so can state 22")
	_watch._catch(agent)
	_expect(_abilities.mode == AbilityController.Mode.FREE, "22 is caught into 24, which frees the player")
	_expect(_abilities.piss_sound == null and (not is_instance_valid(sound) or (not sound.playing and sound.is_queued_for_deletion())), "and stops S0174")
	_expect(is_instance_valid(puddle) and _abilities.puddle == puddle, "the puddle already built stays")
	_expect(int(_session.score) == score_before and _prank.inventory[ITEM_BLADDER] == 1 and lamp.visible, "a catch pays nothing and spends nothing")
	_expect(not clock.visible and is_zero_approx(_abilities.total), "24 zeroes the timers")

	for probe in [[AbilityController.Mode.URINATING, 20], [AbilityController.Mode.URINATING, 23]]:
		_abilities.mode = probe[0]
		_abilities.state = probe[1]
		_expect(not _abilities.is_catchable(), "mode %d state %d is never caught" % probe)
	_abilities.mode = AbilityController.Mode.FREE
	_abilities.state = 0
	_watch.reset()
	_console.hide_catch_warning()
	_clear_effects()


# player+1048 is the one clock every effect reads, and smoking writes it too: lighting up
# restarts the puddle's age, so a spreading puddle freezes, snaps back to scale 1 and alpha
# 0.7 once the new age passes ten, and lives seventeen seconds from the smoke.
func _check_smoking_restarts_the_puddle_window() -> void:
	_start_urinating()
	_abilities.advance(STEP)
	var puddle: Sprite2D = _abilities.puddle
	var clock: float = _abilities.effect_clock
	_advance_until_free()
	_abilities.advance(clock + 11.0 - _abilities.now)
	var frozen_units: int = puddle.scale_units()
	var frozen_alpha: int = puddle.alpha_byte()
	_expect(frozen_units == 276 and frozen_alpha == 157, "at 11 s it has spread to 276/256 and faded to 157, got %d and %d" % [frozen_units, frozen_alpha])
	_give_smokes()
	_abilities.request(AbilityController.REQUEST_SMOKE)
	_abilities.advance(STEP)
	_expect(_abilities.mode == AbilityController.Mode.SMOKING, "the smoke starts")
	while _abilities.smoke == null:
		_abilities.advance(STEP)
	var restarted: float = _abilities.effect_clock
	_expect(restarted > clock + 11.0, "and its spawn moves the shared clock")
	_abilities.advance(clock + 17.5 - _abilities.now)
	_expect(is_instance_valid(puddle) and _abilities.puddle == puddle, "so the puddle outlives its own 17 s")
	_expect(puddle.scale_units() == frozen_units and puddle.alpha_byte() == frozen_alpha, "frozen where it was")
	_abilities.advance(restarted + 10.5 - _abilities.now)
	_expect(puddle.scale_units() == 266 and puddle.alpha_byte() == 168, "past the new 10 s it snaps back near 1.0 and 0.7, got %d and %d" % [puddle.scale_units(), puddle.alpha_byte()])
	var removed_at := -1.0
	while _abilities.puddle != null and _abilities.now - restarted < 20.0:
		_abilities.advance(STEP)
		if _abilities.puddle == null:
			removed_at = _abilities.now - restarted
	_expect(removed_at > 17.0 and removed_at <= 17.0 + STEP, "and is deleted 17 s after the smoke's spawn, got %f" % removed_at)
	_advance_until_free()
	_clear_effects()


# +992 is a float32 that the x87 adds a float step to and tests before it is rounded (see "The
# controller" in docs/player-ability-reference.md). At 60 fps urinating's 7.0 s ends on the
# 420th step, and smoking spawns its smoke on the 24th and ends 12.0 s on the 721st, where a
# double sum lands on 421, 25 and 720. At 30 fps the smoke comes on the 12th, where the double
# sum, or a test of the stored float, gives the 13th.
func _check_the_timers_sum_as_float32() -> void:
	var frame := 1.0 / 60.0
	var stored := PackedFloat32Array([frame])[0]
	_start_urinating()
	_abilities.advance(frame)
	_expect(_abilities.state == 22 and _abilities.elapsed == stored and stored != frame, "state 21 stores the float32 step, got %.17f" % _abilities.elapsed)
	var steps := 1
	while _abilities.state != 23 and steps < 500:
		_abilities.advance(frame)
		steps += 1
	_expect(steps == 420, "at 60 fps urinating's 7.0 s ends on the 420th step, got %d" % steps)
	_advance_until_free()

	_start_smoking()
	steps = 0
	var spawned_on := -1
	while _abilities.state != 13 and steps < 800:
		_abilities.advance(frame)
		steps += 1
		if spawned_on < 0 and _abilities.smoke != null:
			spawned_on = steps
	_expect(spawned_on == 24, "at 60 fps the smoke is spawned on the 24th step, past the float 0.4, got %d" % spawned_on)
	_expect(steps == 721, "and smoking's 12.0 s ends on the 721st, got %d" % steps)
	_advance_until_free()

	_start_smoking()
	steps = 0
	while _abilities.smoke == null and steps < 100:
		_abilities.advance(1.0 / 30.0)
		steps += 1
	_expect(steps == 12, "at 30 fps the smoke is spawned on the 12th step, got %d" % steps)
	_advance_until_free()
	_clear_effects()


# EffectDepth hands each effect's shader the world composite and the depth-composited actors
# its quad overlaps. The puddle gets it from tick(), so the tick state 21 builds it on, whose
# frame runs no _process of the puddle's, is tested too, and its _process follows an actor that
# moves after the tick; the smoke gets it once it has particles.
func _check_the_effects_are_depth_tested() -> void:
	_start_urinating()
	_abilities.advance(STEP)
	var puddle: Sprite2D = _abilities.puddle
	_expect(puddle != null, "state 21 built a puddle for the depth test")
	if puddle != null:
		_expect_depth_test(puddle.material as ShaderMaterial, puddle.drawn_rect, "the puddle on the tick that builds it")
		_player.global_position += Vector2(2, 1)
		await process_frame
		_expect_depth_test(puddle.material as ShaderMaterial, puddle.drawn_rect, "the puddle a frame after the player moved")
	_advance_until_free()

	_start_smoking()
	var guard := 0
	while (_abilities.smoke == null or int(_abilities.smoke.alive) == 0) and guard < 100:
		_abilities.advance(STEP)
		guard += 1
	var smoke: Node2D = _abilities.smoke
	_expect(smoke != null and int(smoke.alive) > 0, "the smoke has puffed for the depth test")
	if smoke != null:
		await process_frame
		_expect_depth_test(smoke.material as ShaderMaterial, smoke.drawn_bounds, "the smoke with particles")
	_advance_until_free()
	_clear_effects()


func _expect_depth_test(material: ShaderMaterial, bounds: Rect2, label: String) -> void:
	var mask := _world.get_node("WorldDepthCompositor")
	var characters := _world.get_node("CharacterDepthCompositor")
	var depth_bounds: Rect2 = mask.depth_bounds
	_expect(material != null and material.get_shader_parameter("world_depth_enabled") == true, "%s: is tested against the world composite" % label)
	if material == null:
		return
	_expect(mask.depth_texture != null and material.get_shader_parameter("world_depth") == mask.depth_texture, "%s: the composite's own buffer" % label)
	_expect(material.get_shader_parameter("world_depth_origin") == depth_bounds.position and material.get_shader_parameter("world_depth_size") == depth_bounds.size, "%s: placed where the composite lies" % label)
	var sprite := _player.get_node("Sprite2D") as Sprite2D
	var frame := Rect2((sprite.global_position + sprite.offset).round(), sprite.texture.get_size())
	_expect(frame.intersects(bounds), "%s: overlaps the player's frame %s, drawn at %s" % [label, frame, bounds])
	var count_value = material.get_shader_parameter("actor_count")
	var count := int(count_value) if count_value != null else 0
	var rects = material.get_shader_parameter("actor_rect")
	var bases = material.get_shader_parameter("actor_base")
	var found := -1
	for index in range(count):
		var rect: Vector4 = rects[index]
		if Rect2(rect.x, rect.y, rect.z, rect.w) == frame:
			found = index
	_expect(found >= 0, "%s: the player is among its %d actors" % [label, count])
	if found < 0:
		return
	var base := ceilf(float(int(sprite.global_position.y)) * 0.5)
	_expect(is_equal_approx(float(bases[found]), base), "%s: at the player's base %.0f, got %s" % [label, base, bases[found]])
	var plane = material.get_shader_parameter("actor_depth_%d" % found)
	_expect(plane != null and plane == characters.depth_texture_for(sprite), "%s: through the player's own depth plane" % label)


# Left mid-urination for the teardown below.
func _urinate_until_the_sound_plays() -> Array:
	_start_urinating()
	_abilities.advance(STEP)
	return [_abilities.piss_sound, _abilities.puddle]


# Every way out of a level frees it: the puddle goes with World, and ~CObj_Player stops +1116.
func _check_the_level_takes_both_with_it(leftovers: Array) -> void:
	var sound = leftovers[0]
	_expect(sound != null, "the teardown check had S0174 playing")
	_expect(not is_instance_valid(sound) or (not sound.playing and sound.is_queued_for_deletion()), "the level's teardown stops S0174")
	_expect(not is_instance_valid(leftovers[1]), "and frees the puddle")


func _give_pill() -> void:
	_prank.inventory[ITEM_PILL] = 0
	_prank.grant_item(ITEM_PILL)


func _level_agents() -> Array:
	var agents := []
	for node in get_nodes_in_group("npc_agents"):
		if _world.is_ancestor_of(node):
			agents.append(node)
	return agents


func _all_slowed(value: bool) -> bool:
	var agents := _level_agents()
	for agent in agents:
		if bool(agent.get("slowed")) != value:
			return false
	return not agents.is_empty()


# Builds the overlay through a pill when no check before has, and lets the slow-down run out,
# so a check of the overlay owns its setup.
func _ensure_overlay() -> void:
	if _abilities.overlay != null:
		return
	_take_pill()
	var guard := 0
	while _abilities.slowdown_shown and guard < 1000:
		_abilities.advance(STEP)
		guard += 1


# Takes a pill and runs the controller up to the tick state 43 runs on.
func _take_pill() -> void:
	_give_pill()
	_abilities.request(AbilityController.REQUEST_PILL)
	var guard := 0
	while (guard == 0 or _abilities.mode != AbilityController.Mode.FREE) and guard < 100:
		_abilities.advance(STEP)
		guard += 1


# State 10 stops S0601 (sub_41BC50) and state 20 the footsteps (sub_41C120), and the locked tick
# does not start them again; only the pill leaves a sounding footstep alone.
func _check_smoking_and_urinating_stop_the_footstep() -> void:
	var footsteps := _player.get_node("FootstepPlayer")
	footsteps.footstep_loop_active = true
	_start_smoking()
	_expect(_abilities.state == 11 and not footsteps.footstep_loop_active, "state 10 stops a sounding footstep")
	_expect(not _player.footsteps_held, "and does not hold it")
	_player._physics_process(STEP)
	_expect(not footsteps.footstep_loop_active, "the locked tick keeps it stopped while smoking")
	_advance_until_free()
	_clear_effects()

	footsteps.footstep_loop_active = true
	_start_urinating()
	_expect(_abilities.state == 21 and not footsteps.footstep_loop_active, "state 20 stops a sounding footstep")
	_expect(not _player.footsteps_held, "and does not hold it")
	_player._physics_process(STEP)
	_expect(not footsteps.footstep_loop_active, "the locked tick keeps it stopped while urinating")
	_advance_until_free()
	_clear_effects()


# sub_41CD90: state 40 writes record 73's "..." and a total of 200, 41 adds no time, 42 runs
# 2.0 s and zeroes the timers on the way to 43, which pays 10, idles, frees the player, spends
# item 14 and slows every agent. Nothing changes the clip or the sound until then, the player
# does not move, and no state is caught.
func _check_the_pill() -> void:
	_clear_effects()
	_place(CORRIDOR)
	_give_pill()
	var lamp := _console.get_node("Band/LampMatrix") as Sprite2D
	_expect(lamp.visible, "item 14 lights the Matrix lamp")
	var fractions: Array[float] = []
	var record := func(elapsed: float, total: float) -> void: fractions.append(elapsed / total if total > 0.0 else 0.0)
	_prank.progress_changed.connect(record)
	var controller = _player.animation_controller
	var footsteps := _player.get_node("FootstepPlayer")
	var facing: Vector2 = IsoDirection.get_screen_directions()[1]
	_player.set("last_direction", facing)
	controller.play_walk(facing)
	var walk: String = controller.current_animation
	footsteps.footstep_loop_active = true
	var held_at := _player.global_position
	var score_before := int(_session.score)

	_abilities.request(AbilityController.REQUEST_PILL)
	_abilities.advance(STEP)
	_expect(_abilities.mode == AbilityController.Mode.PILL and _abilities.state == 41, "state 40 runs in the press's tick and hands over to 41, got mode %d state %d" % [_abilities.mode, _abilities.state])
	_expect(_abilities.record == 73 and is_equal_approx(_abilities.total, 200.0) and _abilities.elapsed == 0.0, "record 73's 20 tenths as a total of 200")
	_expect(_hover_text() == "...", "the hover bar reads record 73's ..., got %s" % _hover_text())
	_expect(_player.input_locked and _cursor.shows_busy_cursor, "the player is held under the clock")
	_abilities.advance(STEP)
	_expect(_abilities.state == 42 and _abilities.elapsed == 0.0, "41 hands over to 42 and adds no time")
	_expect(fractions.size() >= 2 and fractions[0] == 0.0 and fractions[1] == 0.0, "the stopwatch reads 0 on the first two ticks, got %s" % [fractions])
	var ticks := 0
	while _abilities.state == 42 and ticks < 100:
		_expect(not _abilities.is_catchable(), "state 42 is never caught")
		_player._physics_process(STEP)
		_abilities.advance(STEP)
		ticks += 1
	_expect(ticks == 32, "42 runs 2.0 s, 32 steps of 1/16 s, got %d" % ticks)
	_expect(_abilities.state == 43 and _abilities.elapsed == 0.0 and _abilities.total == 0.0, "and zeroes the timers on the way to 43")
	_expect(fractions.size() >= 2 and fractions[fractions.size() - 2] > 0.9 and fractions[fractions.size() - 1] == 0.0, "the stopwatch swept 2 s and drops to 0 at 43")
	_expect(controller.current_animation == walk, "no clip changes before 43: WALK loops in place, got %s" % controller.current_animation)
	_expect(footsteps.footstep_loop_active, "and the footstep goes on")
	_expect(_player.global_position == held_at, "while the player stands")
	_expect(not _abilities.is_catchable(), "43 is never caught")
	_expect(_all_slowed(false), "nobody is slowed before 43")

	_abilities.advance(STEP)
	_expect(_abilities.mode == AbilityController.Mode.FREE and not _player.input_locked, "43 frees the player")
	_expect(int(_session.score) == score_before + 10, "and pays record 73's 10, got %d" % (int(_session.score) - score_before))
	_expect(_prank.inventory[ITEM_PILL] == 0 and not lamp.visible, "one pill is spent and the lamp goes dark")
	_expect(String(controller.current_animation).begins_with(controller.idle_animation_prefix), "slot 0 idles, got %s" % controller.current_animation)
	_expect(_abilities.slow_total == 4000.0, "+1004 is record 73's 400 tenths times 10, got %f" % _abilities.slow_total)
	_expect(_abilities.slow_elapsed == STEP, "and counts from 43's own tick, got %f" % _abilities.slow_elapsed)
	_expect(_abilities.slowdown_shown, "+1044 is up from that tick")
	_expect(_all_slowed(true), "every agent is slowed: %d of them" % _level_agents().size())
	var roles := {}
	for agent in _level_agents():
		roles[String(agent.profile.get("id"))] = true
	_expect(roles.has("boss") and roles.has("janitor"), "the boss and the janitor among them, got %s" % [roles.keys()])
	_expect(_player.get("slowed") == null and is_equal_approx(controller.speed_scale, 1.0), "the player never is")
	_player._physics_process(STEP)
	_expect(not footsteps.footstep_loop_active, "the first free tick with no direction stops the footstep")
	_prank._process(0.0)
	_expect(_hover_text() == "...", "and the hover bar keeps ...")
	_prank.progress_changed.disconnect(record)
	_expect(not _abilities.is_catchable(), "a free player is not caught for the pill")


# sub_41CFC0 0x41D401-0x41D458: +996 counts from 43's tick; at exactly 40.0 s the agents are
# still slowed, and the tick past it releases them. +1044 is still up on that tick and down on
# the next. The timer stands still while the tree is paused.
func _check_the_slowdown_lasts_forty_seconds() -> void:
	_take_pill()
	var ticks := 1
	while _abilities.slow_elapsed < 40.0 and ticks < 1000:
		_abilities.advance(STEP)
		ticks += 1
	_expect(ticks == 640 and _abilities.slow_elapsed == 40.0, "40.0 s after 43 is 640 ticks, got %d at %f" % [ticks, _abilities.slow_elapsed])
	_expect(_all_slowed(true) and _abilities.slow_total == 4000.0, "at exactly 40.0 s the agents are still slowed")
	paused = true
	_expect(not _abilities.can_process(), "the pause stops the slow-down with the level clock")
	paused = false
	_abilities.advance(STEP)
	_expect(_all_slowed(false), "the tick past 40.0 s releases every agent")
	_expect(_abilities.slow_total == 0.0 and _abilities.slow_elapsed == 0.0, "and zeroes both timers")
	_expect(_abilities.slowdown_shown and _abilities.overlay != null and _abilities.overlay.visible, "the overlay stays up for that tick")
	_abilities.advance(STEP)
	_expect(not _abilities.slowdown_shown and not _abilities.overlay.visible, "and is gone on the next")


# sub_41D500 paints its gradient before the player, the character list's first entry: over the
# floor, the field of view, the walls, the glass, the world composite and every item, looping
# ones included, and under every character.
func _check_the_overlay() -> void:
	_ensure_overlay()
	var overlay: Node2D = _abilities.overlay
	_expect(overlay != null, "the slow-down built the overlay")
	if overlay == null:
		return
	_expect(overlay.get_parent() == _player and _player.get_child(0, true) == overlay and not _player.get_children().has(overlay), "it is the player's first, internal child")
	_expect(overlay.z_index == 1 and not overlay.z_as_relative, "at z 1, the characters' z")
	var sprite := _player.get_node("Sprite2D") as Sprite2D
	_expect(_absolute_z(sprite) == 1, "which CharacterDepthCompositor gives the player's sprite, got %d" % _absolute_z(sprite))
	_expect(sprite.is_greater_than(overlay), "drawn before the player's sprite")
	var agents := _level_agents()
	_expect(not agents.is_empty() and agents.all(func(agent: Node) -> bool: return agent.is_greater_than(overlay)), "and before every agent")
	_expect(overlay.is_greater_than(_world.get_node("Objects")), "after every item, a looping one at z 1 too")
	_expect(_absolute_z(_world.get_node("WorldDepthCompositor")) < 1, "above the world composite")
	var fov := _level.get_node_or_null("LevelRuntime/FieldOfView") as CanvasItem
	_expect(fov == null or fov.z_index < 1, "and the field of view")
	_expect(SlowdownOverlay.world_clip(Vector2(800, 600)) == Rect2i(1, 1, 799, 509), "the clip is (1, 1)-(799, 509) at 800 x 600")
	_expect(SlowdownOverlay.world_clip(Vector2(1067, 600)) == Rect2i(1, 1, 1066, 509), "and follows a wider canvas")
	_expect(SlowdownOverlay.world_clip(Vector2(800, 640)) == Rect2i(1, 1, 799, 549), "and a taller one")
	var material := overlay.material as ShaderMaterial
	var corners: Array = Slowdown.params()["overlay_corners"]
	var names := ["top_left", "top_right", "bottom_left", "bottom_right"]
	for index in range(4):
		var corner: Array = corners[index]
		_expect(material.get_shader_parameter(names[index]) == Vector3(corner[0], corner[1], corner[2]), "the %s corner is %s" % [names[index], corner])
	_expect(material.get_shader_parameter("top_left") == Vector3(0, 160, 0) and material.get_shader_parameter("bottom_right") == Vector3(0, 160, 160), "green top left, cyan bottom right")
	_expect(material.get_shader_parameter("original_clip") == Vector2(799, 509), "the steps come from the original's 799 x 509 clip, got %s" % material.get_shader_parameter("original_clip"))


# The first item on level 13 whose damaged state loops, put into that state, which draws it as a
# depth actor at the characters' z.
func _loop_an_item() -> MapObject:
	for node in _world.get_node("Objects").get_children():
		var item := node as MapObject
		if item == null:
			continue
		for state in range(MapObject.FIRST_TRANSITION_STATE + MapObject.DESTROYED_OFFSET, MapObject.STATE_NAMES.size()):
			if not item.has_state(state):
				continue
			item.set_state(state)
			if item.is_in_group(MapObject.ACTOR_GROUP):
				return item
			item.set_state(0)
	return null


# A looping item that a character overlaps is composed with it on the CPU and its own sprite is
# hidden. The item was still drawn in the item pass before the gradient in the original, so its
# pixels go on a surface at the back of World/Objects, before the overlay; only the character's
# are drawn after it. The two never share a pixel.
func _check_the_overlay_covers_a_clustered_looping_item() -> void:
	_ensure_overlay()
	var overlay: Node2D = _abilities.overlay
	var compositor := _world.get_node("CharacterDepthCompositor")
	var item := _loop_an_item()
	_expect(item != null, "level 13 has an item whose damaged state loops")
	if item == null or overlay == null:
		return
	var item_sprite := item.get_node("Sprite2D") as Sprite2D
	var player_sprite := _player.get_node("Sprite2D") as Sprite2D
	var saved := _player.global_position
	var frame := Rect2((item_sprite.global_position + item_sprite.offset).round(), item_sprite.texture.get_size())
	var item_surface: Sprite2D = null
	var player_surface: Sprite2D = null
	for stand in [Vector2(frame.end.x + 10, frame.end.y - 10), Vector2(frame.get_center().x, frame.end.y + 10), Vector2(frame.position.x - 10, frame.end.y - 10)]:
		_player.global_position = stand
		compositor.update_composition()
		item_surface = compositor.surface_for(item_sprite)
		player_surface = compositor.surface_for(player_sprite)
		if item_surface != null and player_surface != null:
			break
	_expect(not item_sprite.visible and not player_sprite.visible, "the player and the looping %s are drawn as one cluster" % item.name)
	_expect(item_surface != null and player_surface != null and item_surface != player_surface, "on two surfaces, the item's and the characters'")
	if item_surface != null and player_surface != null:
		_expect(item_surface.visible and player_surface.visible and item_surface.global_position == player_surface.global_position, "both shown over the same window")
		_expect(item_surface.get_parent() == item.get_parent() and not item.get_parent().get_children().has(item_surface), "the item's is an internal child of World/Objects")
		_expect(_absolute_z(item_surface) == _absolute_z(item_sprite) and _absolute_z(item_surface) == overlay.z_index, "at the items' z, the overlay's, got %d" % _absolute_z(item_surface))
		_expect(overlay.is_greater_than(item_surface), "so the overlay is drawn over the item")
		_expect(_absolute_z(player_surface) == overlay.z_index and player_surface.is_greater_than(overlay), "and the characters' surface after it")
		var items := item_surface.texture.get_image()
		var characters := player_surface.texture.get_image()
		var item_pixels := 0
		var character_pixels := 0
		var shared := 0
		for y in range(items.get_height()):
			for x in range(items.get_width()):
				var on_item := items.get_pixel(x, y).a > 0.0
				var on_character := characters.get_pixel(x, y).a > 0.0
				item_pixels += int(on_item)
				character_pixels += int(on_character)
				shared += int(on_item and on_character)
		_expect(item_pixels > 0 and character_pixels > 0, "each surface holds its own pixels, got %d and %d" % [item_pixels, character_pixels])
		_expect(shared == 0, "and none of them twice, got %d" % shared)
	item.set_state(0)
	_player.global_position = saved
	compositor.update_composition()
	_expect(item_sprite.visible and player_sprite.visible, "a still item and a lone player draw their own sprites again")
	_expect(item_surface == null or not item_surface.visible, "and the item's surface is put away")


# State 43 writes the slow-down unconditionally: a second pill pays again, spends again and
# restarts the full forty seconds from its own 43.
func _check_a_second_pill_restarts_the_slowdown() -> void:
	_take_pill()
	for _i in range(320):
		_abilities.advance(STEP)
	_expect(_all_slowed(true) and _abilities.slow_elapsed == 20.0 + STEP, "20 s into the first pill, got %f" % _abilities.slow_elapsed)
	var score_before := int(_session.score)
	_take_pill()
	_expect(int(_session.score) == score_before + 10 and _prank.inventory[ITEM_PILL] == 0, "the second pill pays and spends again")
	_expect(_abilities.slow_elapsed == STEP and _abilities.slow_total == 4000.0, "and restarts the count, got %f" % _abilities.slow_elapsed)
	var ticks := 1
	while _all_slowed(true) and ticks < 1000:
		_abilities.advance(STEP)
		ticks += 1
	_expect(ticks == 641, "which runs a full 40.0 s from the second 43, released on tick %d" % ticks)
	_abilities.advance(STEP)
	_expect(not _abilities.overlay.visible, "and takes the overlay with it")
