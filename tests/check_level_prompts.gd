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
	await _check_the_answer_keys_follow_the_language()
	await _check_yes_leaves_the_running_level()
	paused = false
	if _failures == 0:
		print("Level prompts: pause stops the clock, the panel restates the level, and the quit prompt pauses it and answers T/N")
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


# The autoload exists in the tree even though its global name is not bound at compile time.
func _i18n() -> Node:
	return root.get_node("I18n")
