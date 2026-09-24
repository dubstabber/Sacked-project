extends SceneTree

# Pause and the quit confirmation, as Main_RenderUpdate draws them and sub_403780 and
# sub_404990 react to them; see docs/game-rules-reference.md.

const PROMPTS := preload("res://scenes/hud/level_prompts.gd")

const I18N_SCRIPT := preload("res://autoloads/i18n.gd")


# A GDScript runtime error leaves a --script run's exit code alone, so the check listens for
# one itself.
class ErrorLog extends Logger:
	var errors: Array[String] = []
	var _mutex := Mutex.new()

	func _log_error(
		function: String, file: String, line: int, code: String, rationale: String,
		_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]
	) -> void:
		_mutex.lock()
		errors.append("%s:%d %s: %s (type %d)" % [file, line, function, rationale if rationale != "" else code, error_type])
		_mutex.unlock()

	func count() -> int:
		_mutex.lock()
		var size := errors.size()
		_mutex.unlock()
		return size

	func since(mark: int) -> Array[String]:
		_mutex.lock()
		var found := errors.slice(mark)
		_mutex.unlock()
		return found


var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	# Pinned so the assertions read one language whatever the machine's locale is.
	_i18n().set_language(&"pl")
	await _check_pause_stops_the_level()
	await _check_quit_prompt()
	await _check_what_carries_on_behind_the_prompt()
	await _check_the_ring_cancel_waits_behind_the_pause_key()
	await _check_a_button_held_behind_the_pause_walks()
	await _check_the_answer_keys_follow_the_language()
	await _check_yes_drops_a_cancel_owed_to_the_ring()
	await _check_yes_leaves_the_running_level()
	paused = false
	if _failures == 0:
		print("Level prompts: pause stops the clock, the panel restates the level, the quit prompt pauses it and answers T/N, and the ring's cancel and the walk carry across the pause key")
	quit(1 if _failures else 0)


func _expect(condition: bool, label: String) -> void:
	if not condition:
		_failures += 1
		push_error(label)


# Whether the key was consumed; the flag holds after push_input returns.
func _key(code: Key) -> bool:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	root.push_input(event)
	return root.is_input_handled()


func _level() -> Node:
	var level := (load("res://scenes/level_1.tscn") as PackedScene).instantiate()
	root.add_child(level)
	return level


func _check_pause_stops_the_level() -> void:
	var level := _level()
	await process_frame
	var session: Node = level.get_node("LevelRuntime")
	var prompts: Node = level.get_node("LevelRuntime/LevelPrompts/Panels")

	_key(KEY_P)
	await process_frame
	_expect(prompts.is_paused and paused, "P pauses the level")

	# The recovered rects are absolute in an 800-wide viewport, so recentring is the identity
	# there and only moves them on a wider canvas. See docs/widescreen.md.
	if is_equal_approx(prompts.size.x, PROMPTS.ORIGINAL_WIDTH):
		_expect(prompts.panel_rect(PROMPTS.PAUSE_PANEL) == PROMPTS.PAUSE_PANEL, "the pause panel keeps its recovered rect at 800 wide")
		_expect(prompts.panel_rect(PROMPTS.QUIT_PANEL) == PROMPTS.QUIT_PANEL, "the quit panel keeps its recovered rect at 800 wide")
	_expect(
		is_equal_approx(prompts.panel_rect(PROMPTS.PAUSE_PANEL).size.x, PROMPTS.PAUSE_PANEL.size.x),
		"recentring never changes a panel's width"
	)
	var elapsed: float = session.elapsed
	for i in range(5):
		await process_frame
	_expect(is_equal_approx(session.elapsed, elapsed), "the clock does not run while paused")

	# The panel restates the level's own CONDITION, in its mode's wording.
	session.mode = &"time"
	var lines: Array = prompts._goal_lines()
	_expect(lines[0] == tr(GoalText.TIME_GOAL), "the time game states its goal")
	_expect(lines[1] == tr(GoalText.TIME_GOAL_FORMAT) % [4000, 6], "the time game states level 1's 4000 points in 6 minutes")
	_expect(lines[0] == "Aby ukończyć ten poziom, musisz zdobyć", "the Polish wording is the original's own")
	session.mode = &"points"
	lines = prompts._goal_lines()
	_expect(lines[0] == tr(GoalText.POINTS_GOAL_FORMAT) % 5, "the points game states its own 5 minutes")
	_expect(lines[1] == tr(GoalText.POINTS_TARGET_FORMAT) % 3000, "the points game states its own 3000 points")

	_key(KEY_P)
	await process_frame
	_expect(not prompts.is_paused and not paused, "P resumes the level")
	for i in range(3):
		await process_frame
	_expect(session.elapsed > elapsed, "the clock runs again once resumed")

	root.remove_child(level)
	level.free()


func _check_quit_prompt() -> void:
	var level := _level()
	await process_frame
	var session: Node = level.get_node("LevelRuntime")
	var prompts: Node = level.get_node("LevelRuntime/LevelPrompts/Panels")

	_expect(_key(KEY_Q), "Q is consumed")
	_expect(prompts.is_quit_prompt_open, "Q asks whether to leave")
	# sub_407370's case 10 sets the pause bit, so the level stops and Main_RenderUpdate draws
	# the pause panel under the prompt.
	_expect(paused and prompts.is_paused, "the level pauses behind the quit prompt")
	var elapsed: float = session.elapsed
	for i in range(3):
		await process_frame
	_expect(is_equal_approx(session.elapsed, elapsed), "the clock does not run behind the quit prompt")

	# Screen 10 reads nothing but its answers; the numpad's Enter is a code of its own.
	for code: Key in [KEY_P, KEY_Q, KEY_A, KEY_UP, KEY_ESCAPE, KEY_KP_ENTER]:
		var name := OS.get_keycode_string(code)
		_expect(_key(code), "the prompt swallows %s" % name)
		_expect(prompts.is_quit_prompt_open, "%s leaves the prompt up" % name)
		_expect(paused and prompts.is_paused, "%s leaves the level paused" % name)

	for code: Key in [KEY_N, KEY_ENTER, KEY_SPACE]:
		var name := OS.get_keycode_string(code)
		if not prompts.is_quit_prompt_open:
			_key(KEY_Q)
		_expect(_key(code), "%s is consumed" % name)
		_expect(not prompts.is_quit_prompt_open, "%s dismisses the prompt" % name)
		_expect(not paused and not prompts.is_paused, "%s lets the level run again" % name)
	for i in range(3):
		await process_frame
	_expect(session.elapsed > elapsed, "the clock runs again once the prompt is dismissed")

	# sub_407370's case 1 clears the bit however it was set, so refusing to leave also ends
	# a pause that was already on before Q.
	_key(KEY_P)
	_expect(prompts.is_paused and paused, "P pauses the level")
	_expect(_key(KEY_Q), "Q is taken while paused")
	_expect(prompts.is_quit_prompt_open, "Q asks whether to leave while paused")
	_key(KEY_N)
	_expect(not prompts.is_quit_prompt_open, "N dismisses the prompt opened while paused")
	_expect(not paused and not prompts.is_paused, "N also ends the pause that was on before Q")

	# sub_403FB0 refuses both keys while the player is caught, and the duel after it never
	# reaches that handler at all.
	var watch: Node = level.get_node("LevelRuntime/CatchWatch")
	var catcher := Node2D.new()
	watch.set("caught_by", catcher)
	_expect(not _key(KEY_Q), "Q is passed on while the player is caught")
	_expect(not prompts.is_quit_prompt_open, "Q does not ask while the player is caught")
	_expect(not _key(KEY_P), "P is passed on while the player is caught")
	_expect(not prompts.is_paused, "P does not pause while the player is caught")
	watch.call("reset")
	catcher.free()

	paused = false
	root.remove_child(level)
	level.free()


# The pause bit stops the level and nothing else: the music and effects play on, the port's
# F1 still reaches the window, and a walk ends with its button even when the release lands
# behind the prompt, because sub_403FB0 rebuilds the walk bit from the polled button.
func _check_what_carries_on_behind_the_prompt() -> void:
	var level := _level()
	await process_frame
	var prompts: Node = level.get_node("LevelRuntime/LevelPrompts/Panels")
	var player: Node = level.get_node("World/Player")

	Input.action_press("mouse-movement")
	player.start_mouse_movement()
	_key(KEY_Q)
	Input.action_release("mouse-movement")
	_key(KEY_N)
	await process_frame
	_expect(not player.is_mouse_movement_active, "a right button let go behind the prompt ends the walk")
	Input.action_press("mouse-movement")
	player.start_mouse_movement()
	_key(KEY_Q)
	_key(KEY_N)
	await process_frame
	_expect(player.is_mouse_movement_active, "a right button held through the prompt keeps walking")
	Input.action_release("mouse-movement")
	player.stop_mouse_movement()

	var audio: Node = level.get_node("LevelRuntime/LevelAudio")
	var music: Array = audio.get_children().filter(func(child): return child is AudioStreamPlayer and child.bus == &"Music")
	_expect(music.size() == 1, "the level has one theme player")
	_key(KEY_Q)
	if music.size() == 1:
		var theme: AudioStreamPlayer = music[0]
		_expect(theme.can_process() and not theme.stream_paused, "the theme plays on behind the quit prompt")
		var watch: Node = level.get_node("LevelRuntime/CatchWatch")
		watch.call("_hold_level_music", true)
		_expect(theme.stream_paused, "the duel stops the theme")
		watch.call("_hold_level_music", false)
		_expect(not theme.stream_paused, "and the end of the duel brings it back")

	var settings: Node = root.get_node("SettingsStore")
	var settings_path: String = settings.path
	settings.path = "user://check_level_prompts_settings.cfg"
	settings.reload()
	var fullscreen: bool = settings.is_fullscreen()
	_expect(_key(KEY_F1), "F1 is taken behind the quit prompt")
	_expect(settings.is_fullscreen() != fullscreen, "F1 still toggles the window behind the quit prompt")
	_expect(prompts.is_quit_prompt_open, "and leaves the prompt up")
	_key(KEY_F1)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(settings.path))
	settings.path = settings_path
	settings.reload()

	_key(KEY_N)
	paused = false
	root.remove_child(level)
	level.free()


# Through the Input singleton, the way the game's own input arrives: it updates the action
# state the prank controller polls, then reaches the GUI and the unhandled handlers.
func _send(event: InputEvent) -> void:
	Input.parse_input_event(event)
	await process_frame
	await process_frame


func _tap(code: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		await _send(event)


func _right_button(pressed: bool, at: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_RIGHT
	event.button_mask = MOUSE_BUTTON_MASK_RIGHT if pressed else 0
	event.pressed = pressed
	event.position = at
	event.global_position = at
	await _send(event)


func _open_ring(level: Node) -> void:
	var player := level.get_node("World/Player") as Node2D
	var controller: Node = level.get_node("World/Player/PrankController")
	var point := level.get_node("World/Objects/Object010MonitorTastaturFrontal/InteractionPoint") as Node2D
	player.global_position = point.global_position
	controller.focus_point = point
	controller.entries = controller.build_entries(point)
	controller.open_menu()


# The pause key leaves screen 1's handler running (sub_404990 case 1 calls sub_403FB0), and
# escape's own case (0x40410A) and the end-of-frame test for the down arrow and the right
# button (0x4044F9-0x404520) write state 5 without reading the pause bit. The frozen world
# only acts on it once the level runs again, so the ring shuts on the unpause even when the
# key was let go first. The quit prompt never calls sub_403FB0 (0x404914).
func _check_the_ring_cancel_waits_behind_the_pause_key() -> void:
	var saved_size := root.size
	root.size = Vector2i(800, 600)
	var level := _level()
	await process_frame
	var prompts: Node = level.get_node("LevelRuntime/LevelPrompts/Panels")
	var player: Node = level.get_node("World/Player")
	var controller: Node = level.get_node("World/Player/PrankController")
	var cursor: Node = level.get_node("World/Player/MovementArrow")
	player.set_physics_process(false)
	# Inside the console band, where the pointer the pause leaves hidden may well be.
	var console_point := Vector2(400.0, 560.0)

	var cancels := {
		"escape": func() -> void: await _tap(KEY_ESCAPE),
		"the down arrow": func() -> void: await _tap(KEY_DOWN),
		"the right button": func() -> void:
			await _right_button(true, console_point)
			await _right_button(false, console_point),
	}
	for name: String in cancels:
		_open_ring(level)
		_expect(controller.menu_open, "the ring opens on the keyboard (%s)" % name)
		_key(KEY_P)
		await cancels[name].call()
		_expect(paused and controller.menu_open, "the ring stays up, frozen, behind the pause key after %s" % name)
		_expect(cursor.is_menu_captured() and cursor.requested_mouse_mode == Input.MOUSE_MODE_HIDDEN, "and keeps the pointer hidden (%s)" % name)
		_key(KEY_P)
		_expect(not paused, "P resumes the level (%s)" % name)
		_expect(not controller.menu_open and controller.highlighted == -1, "%s pressed and let go behind P shuts the ring on the unpause" % name)
		_expect(not player.menu_open, "and lets go of the player (%s)" % name)
		_expect(
			not cursor.is_menu_captured() and cursor.requested_mouse_mode == Input.MOUSE_MODE_VISIBLE,
			"and hands the pointer back, shown (%s), got captured %s mode %d" % [name, cursor.is_menu_captured(), cursor.requested_mouse_mode]
		)
		_expect(not player.is_mouse_movement_active, "a button let go behind the pause starts no walk (%s)" % name)
		await process_frame

	# Screen 10 reads only its answers, and a key-down it eats is gone for good.
	for name: String in cancels:
		_open_ring(level)
		_key(KEY_Q)
		await cancels[name].call()
		_key(KEY_N)
		await process_frame
		_expect(not paused and controller.menu_open, "%s behind the quit prompt leaves the ring up after N" % name)
		controller.close_menu()
		await process_frame

	# No clears the pause bit however it was set (0x40742F), so a cancel owed from before Q
	# is paid when N lets the level run.
	_open_ring(level)
	_key(KEY_P)
	await _tap(KEY_ESCAPE)
	_key(KEY_Q)
	_expect(prompts.is_quit_prompt_open and controller.menu_open, "Q asks over a ring still owed its cancel")
	_key(KEY_N)
	_expect(not paused and not controller.menu_open, "N lets the level run and the owed cancel shuts the ring")
	_expect(not cursor.is_menu_captured() and cursor.requested_mouse_mode == Input.MOUSE_MODE_VISIBLE, "and the pointer comes back")
	await process_frame

	# The ring can only be cancelled while it is up; an escape behind P with nothing open is
	# not saved for the next ring.
	_key(KEY_P)
	await _tap(KEY_ESCAPE)
	_key(KEY_P)
	_open_ring(level)
	await process_frame
	_expect(controller.menu_open, "an escape behind P with no ring up does not shut a later one")
	controller.close_menu()

	# The duel stops the tree without the pause bit and runs no input handler that cancels.
	_open_ring(level)
	paused = true
	await _tap(KEY_ESCAPE)
	paused = false
	await process_frame
	_expect(controller.menu_open, "escape behind the duel's pause leaves the ring up")
	controller.close_menu()

	paused = false
	root.remove_child(level)
	level.free()
	root.size = saved_size


# sub_403FB0 rebuilds the walk bit from the polled right button every frame (0x403FE4,
# 0x4043CC), so a button pressed behind the pause key or the quit prompt and still held when
# they end walks the player -- once a ring it was cancelling has shut.
func _check_a_button_held_behind_the_pause_walks() -> void:
	var saved_size := root.size
	root.size = Vector2i(800, 600)
	var level := _level()
	await process_frame
	var player: Node = level.get_node("World/Player")
	var controller: Node = level.get_node("World/Player/PrankController")
	var cursor: Node = level.get_node("World/Player/MovementArrow")
	player.set_physics_process(false)
	var point := Vector2(600.0, 150.0)

	for opener: Key in [KEY_P, KEY_Q]:
		var name := OS.get_keycode_string(opener)
		var closer := KEY_P if opener == KEY_P else KEY_N
		_key(opener)
		await _right_button(true, point)
		_expect(not player.is_mouse_movement_active, "a paused player does not walk off a press behind %s" % name)
		_key(closer)
		_expect(player.is_mouse_movement_active, "a right button held behind %s walks the player once the level runs" % name)
		await _right_button(false, point)
		_expect(not player.is_mouse_movement_active, "and letting it go ends the walk (%s)" % name)

		_key(opener)
		await _right_button(true, point)
		await _right_button(false, point)
		_key(closer)
		_expect(not player.is_mouse_movement_active, "a right button let go behind %s starts no walk" % name)

	_open_ring(level)
	_key(KEY_P)
	await _right_button(true, point)
	_key(KEY_P)
	_expect(not controller.menu_open, "a right button held behind P shuts the ring")
	_expect(player.is_mouse_movement_active, "and walks the player")
	_expect(
		not cursor.is_menu_captured() and cursor.requested_mouse_mode == Input.MOUSE_MODE_HIDDEN,
		"with the pointer let go and hidden for the walk, got captured %s mode %d" % [cursor.is_menu_captured(), cursor.requested_mouse_mode]
	)
	await _right_button(false, point)
	_expect(not player.is_mouse_movement_active and cursor.requested_mouse_mode == Input.MOUSE_MODE_VISIBLE, "letting go ends the walk and shows the pointer")

	paused = false
	root.remove_child(level)
	level.free()
	root.size = saved_size


# The quit prompt names its own answer keys, so switching language has to move them. Pressing
# the yes key leaves the level, so the binding is read rather than driven; what is driven is
# that the Polish key stops working.
func _check_the_answer_keys_follow_the_language() -> void:
	var level := _level()
	await process_frame
	var prompts: Node = level.get_node("LevelRuntime/LevelPrompts/Panels")

	_expect(prompts._yes_key == KEY_T, "Polish answers the prompt with T, for Tak")
	_expect(prompts._no_key == KEY_N, "Polish refuses it with N, for Nie")

	_i18n().set_language(&"de")
	await process_frame
	_expect(prompts._yes_key == KEY_J, "German answers the prompt with J, for Ja")
	_expect(prompts._no_key == KEY_N, "German refuses it with N, for Nein")
	_expect(tr(PROMPTS.QUIT_ANSWER).contains("(J)"), "the German prompt names the J it answers to")

	_key(KEY_Q)
	await process_frame
	_expect(prompts.is_quit_prompt_open, "Q still asks whether to leave in German")
	_key(KEY_T)
	await process_frame
	_expect(prompts.is_quit_prompt_open, "T means nothing to the German prompt")

	_i18n().set_language(&"en")
	await process_frame
	_expect(prompts._yes_key == KEY_Y, "English answers the prompt with Y, for Yes")
	_key(KEY_N)
	_expect(not prompts.is_quit_prompt_open and not paused, "N still refuses in English")

	_i18n().set_language(&"pl")
	root.remove_child(level)
	level.free()


# The level is the tree's current scene here, the way ScreenManager runs it: one added under
# the root is never taken out of the tree by a scene change, which is how the yes key's
# null-viewport error went unseen.
func _check_yes_leaves_the_running_level() -> void:
	var manager := root.get_node("ScreenManager")
	var error_log := ErrorLog.new()
	OS.add_logger(error_log)
	for language: StringName in [&"pl", &"en", &"de"]:
		_i18n().set_language(language)
		manager.start_level(1)
		await process_frame
		await process_frame
		var level := current_scene
		if level == null or level.scene_file_path != manager.level_scene_path(1):
			_expect(false, "start_level(1) makes the level the current scene (%s)" % language)
			continue
		var prompts: Node = level.get_node("LevelRuntime/LevelPrompts/Panels")
		var level_ref: WeakRef = weakref(level)
		_key(KEY_Q)
		_expect(prompts.is_quit_prompt_open and paused, "Q asks and pauses in the running level (%s)" % language)

		var mark := error_log.count()
		var handled := _key(prompts._yes_key)
		var errors_on_answer := error_log.since(mark)
		var screen_on_answer: int = manager.current
		var paused_on_answer := paused
		mark = error_log.count()
		for i in range(3):
			await process_frame
		var errors_after_swap := error_log.since(mark)

		_expect(errors_on_answer.is_empty(), "answering yes raises no error (%s): %s" % [language, errors_on_answer])
		_expect(handled, "the yes key is consumed before the level leaves the tree (%s)" % language)
		_expect(
			screen_on_answer == manager.Screen.MAIN_MENU,
			"yes goes to the main menu, as sub_407370's case 3 does (%s)" % language
		)
		_expect(not paused_on_answer, "leaving takes the pause with it (%s)" % language)
		_expect(errors_after_swap.is_empty(), "the scene swap raises no error (%s): %s" % [language, errors_after_swap])
		_expect(level_ref.get_ref() == null, "the level is freed once it is left (%s)" % language)
		_expect(
			current_scene != null and current_scene.scene_file_path == manager.scene_path(manager.Screen.MAIN_MENU),
			"the main menu replaces the level (%s)" % language
		)
	OS.remove_logger(error_log)
	_i18n().set_language(&"pl")


# Yes leaves the level whatever the ring was owed: the teardown (sub_407140) clears the pause
# bit with every other flag, so nothing hands the pointer back over a level on its way out.
func _check_yes_drops_a_cancel_owed_to_the_ring() -> void:
	var manager := root.get_node("ScreenManager")
	var error_log := ErrorLog.new()
	OS.add_logger(error_log)
	manager.start_level(1)
	await process_frame
	await process_frame
	var level := current_scene
	if level == null or level.scene_file_path != manager.level_scene_path(1):
		_expect(false, "start_level(1) makes the level the current scene")
		OS.remove_logger(error_log)
		return
	var prompts: Node = level.get_node("LevelRuntime/LevelPrompts/Panels")
	var controller: Node = level.get_node("World/Player/PrankController")
	var closes := [0]
	controller.menu_closed.connect(func() -> void: closes[0] += 1)
	_open_ring(level)
	_expect(controller.menu_open, "the ring opens in the running level")
	_key(KEY_P)
	await _tap(KEY_ESCAPE)
	_key(KEY_Q)
	_expect(prompts.is_quit_prompt_open and controller.menu_open, "Q asks over a ring still owed its cancel")

	var mark := error_log.count()
	_key(prompts._yes_key)
	var closes_on_answer: int = closes[0]
	for i in range(3):
		await process_frame
	var errors := error_log.since(mark)
	_expect(errors.is_empty(), "answering yes over an owed cancel raises no error: %s" % [errors])
	_expect(closes_on_answer == 0, "yes does not shut the ring, so the pointer is not warped mid-teardown")
	_expect(manager.current == manager.Screen.MAIN_MENU and not paused, "yes still goes to the main menu")
	OS.remove_logger(error_log)


# The autoload exists in the tree even though its global name is not bound at compile time.
func _i18n() -> Node:
	return root.get_node("I18n")
