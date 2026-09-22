extends Control

# The two panels Main_RenderUpdate draws over a running level: the pause panel, which
# restates what the level asks for, and the quit confirmation. Both are centred on x 400 of
# the original's 800-wide viewport with a two-pixel drop shadow; see
# docs/game-rules-reference.md. The port recentres them on the live width, which is the same
# x on a 4:3 canvas -- see docs/widescreen.md.

# (49, 232)-(750, 372) for the pause panel, (49, 150)-(750, 230) for the quit prompt.
const ORIGINAL_WIDTH := 800.0
const PAUSE_PANEL := Rect2(49, 232, 701, 140)
const QUIT_PANEL := Rect2(49, 150, 701, 80)
const SHADOW_OFFSET := Vector2(2, 2)
const PANEL_COLOR := Color(0.0, 0.0, 0.0, 0.6)
const SHADOW_COLOR := Color(0.078, 0.078, 0.078)
const PAUSE_COLOR := Color(250.0 / 255.0, 190.0 / 255.0, 100.0 / 255.0)
const PROMPT_COLOR := Color(250.0 / 255.0, 250.0 / 255.0, 250.0 / 255.0)
const LABEL_COLOR := Color(1.0, 1.0, 1.0)

# Slots 156-161 and 167 of the original's text table; see docs/strings-reference.md.
const PAUSED := &"prompt.paused"
const QUIT_QUESTION := &"prompt.quit_question"
const QUIT_ANSWER := &"prompt.quit_answer"
# The original answers this prompt with the initials its own wording names, so the keys are
# part of the translation rather than constants: T/N in Polish, Y/N in English, J/N in German.
const QUIT_YES_KEY := &"prompt.quit_yes_key"
const QUIT_NO_KEY := &"prompt.quit_no_key"

var is_paused := false
var is_quit_prompt_open := false

var _session: Node
var _yes_key := KEY_NONE
var _no_key := KEY_NONE


func _ready() -> void:
	# Both panels have to keep drawing and taking keys while the tree itself is stopped.
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_session = get_tree().get_first_node_in_group("level_session")
	_bind_answer_keys()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var key := (event as InputEventKey).keycode
	if is_quit_prompt_open:
		if key == _yes_key:
			_leave_level()
		elif key == _no_key:
			is_quit_prompt_open = false
			queue_redraw()
		else:
			return
		get_viewport().set_input_as_handled()
		return
	if key == KEY_Q:
		is_quit_prompt_open = true
	elif key == KEY_P:
		set_paused(not is_paused)
	else:
		return
	queue_redraw()
	get_viewport().set_input_as_handled()


# sub_403780 returns immediately while the pause bit is set, so the clock, the console and
# every agent stop together; only the drawing carries on.
func set_paused(paused: bool) -> void:
	is_paused = paused
	get_tree().paused = paused
	queue_redraw()


func _leave_level() -> void:
	is_quit_prompt_open = false
	set_paused(false)
	var screen_manager := get_node_or_null("/root/ScreenManager")
	if screen_manager != null:
		screen_manager.call("change_to_level_tree")


func _draw() -> void:
	if is_paused:
		_draw_panel(panel_rect(PAUSE_PANEL))
		var lines := _goal_lines()
		_draw_centred(lines[0], PAUSE_PANEL.position.y + 10.0, PAUSE_COLOR)
		_draw_centred(lines[1], PAUSE_PANEL.position.y + 35.0, PAUSE_COLOR)
		_draw_centred(tr(PAUSED), PAUSE_PANEL.position.y + 85.0, LABEL_COLOR)
	if is_quit_prompt_open:
		_draw_panel(panel_rect(QUIT_PANEL))
		_draw_centred(tr(QUIT_QUESTION), QUIT_PANEL.position.y + 10.0, PROMPT_COLOR)
		_draw_centred(tr(QUIT_ANSWER), QUIT_PANEL.position.y + 35.0, PROMPT_COLOR)


# The panel restates the level's own CONDITION, in the wording its mode uses.
func _goal_lines() -> Array:
	var limit := 1200.0
	var target := 10000
	var mode := &"time"
	if _session != null:
		limit = float(_session.limit_seconds())
		target = int(_session.target_score())
		mode = _session.mode
	return GoalText.lines(mode, limit, target)


# The recovered rects are x 49..750 of an 800-wide viewport; a wider canvas moves them by
# half of what it added, so they stay centred and keep their original width.
func panel_rect(panel: Rect2) -> Rect2:
	return Rect2(panel.position + Vector2((size.x - ORIGINAL_WIDTH) * 0.5, 0.0), panel.size)


func _draw_panel(panel: Rect2) -> void:
	draw_rect(panel, PANEL_COLOR)


func _draw_centred(text: String, top: float, color: Color) -> void:
	var font := ThemeDB.fallback_font
	var font_size := ThemeDB.fallback_font_size
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var origin := Vector2(size.x * 0.5 - width * 0.5, top + float(font_size))
	draw_string(font, origin + SHADOW_OFFSET, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, SHADOW_COLOR)
	draw_string(font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


# The label a key is drawn as, not its position, so a German player presses the J their own
# prompt names.
func _bind_answer_keys() -> void:
	_yes_key = OS.find_keycode_from_string(tr(QUIT_YES_KEY))
	_no_key = OS.find_keycode_from_string(tr(QUIT_NO_KEY))


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		_bind_answer_keys()
		queue_redraw()
