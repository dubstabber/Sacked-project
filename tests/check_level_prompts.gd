extends SceneTree

# Pause and the quit confirmation, as Main_RenderUpdate draws them and sub_403780 reacts to
# them; see docs/game-rules-reference.md.

const PROMPTS := preload("res://scenes/hud/level_prompts.gd")

const I18N_SCRIPT := preload("res://autoloads/i18n.gd")

var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	# Pinned so the assertions read one language whatever the machine's locale is.
	_i18n().set_language(&"pl")
	await _check_pause_stops_the_level()
	await _check_quit_prompt()
	await _check_the_answer_keys_follow_the_language()
	paused = false
	if _failures == 0:
		print("Level prompts: pause stops the clock, the panel restates the level, and the quit prompt answers T/N")
	quit(1 if _failures else 0)


func _expect(condition: bool, label: String) -> void:
	if not condition:
		_failures += 1
		push_error(label)


func _key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	root.push_input(event)


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
	var prompts: Node = level.get_node("LevelRuntime/LevelPrompts/Panels")
	var manager := root.get_node_or_null("ScreenManager")

	_key(KEY_Q)
	await process_frame
	_expect(prompts.is_quit_prompt_open, "Q asks whether to leave")
	_expect(not paused, "the level keeps running behind the quit prompt")

	_key(KEY_N)
	await process_frame
	_expect(not prompts.is_quit_prompt_open, "N dismisses the prompt")

	_key(KEY_Q)
	await process_frame
	_key(KEY_T)
	await process_frame
	_expect(not prompts.is_quit_prompt_open, "T closes the prompt")
	if manager != null:
		_expect(manager.current == manager.Screen.LEVEL_TREE, "T leaves for the level tree")

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

	_i18n().set_language(&"pl")
	root.remove_child(level)
	level.free()


# The autoload exists in the tree even though its global name is not bound at compile time.
func _i18n() -> Node:
	return root.get_node("I18n")
