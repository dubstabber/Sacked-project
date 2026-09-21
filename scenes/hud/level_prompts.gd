extends Control

# The two panels Main_RenderUpdate draws over a running level: the pause panel, which
# restates what the level asks for, and the quit confirmation. Both are centred on x 400
# with a two-pixel drop shadow; see docs/game-rules-reference.md.

# (49, 232)-(750, 372) for the pause panel, (49, 150)-(750, 230) for the quit prompt.
const PAUSE_PANEL := Rect2(49, 232, 701, 140)
const QUIT_PANEL := Rect2(49, 150, 701, 80)
const SHADOW_OFFSET := Vector2(2, 2)
const PANEL_COLOR := Color(0.0, 0.0, 0.0, 0.6)
const SHADOW_COLOR := Color(0.078, 0.078, 0.078)
const PAUSE_COLOR := Color(250.0 / 255.0, 190.0 / 255.0, 100.0 / 255.0)
const PROMPT_COLOR := Color(250.0 / 255.0, 250.0 / 255.0, 250.0 / 255.0)
const LABEL_COLOR := Color(1.0, 1.0, 1.0)

# The strings as the Polish release ships them.
const TIME_GOAL := "Aby ukończyć ten poziom, musisz zdobyć"
const TIME_GOAL_FORMAT := "%d punktów w ciągu %d minut."
const POINTS_GOAL_FORMAT := "Zdobądź jak najwięcej puntków w ciągu %d minut."
const POINTS_TARGET_FORMAT := "Potrzebujesz przynajmniej %d punktów!"
const PAUSED := "Pauza"
const QUIT_QUESTION := "Czy na pewno chcesz wyjść?"
const QUIT_ANSWER := "(T)ak lub (N)ie"

var is_paused := false
var is_quit_prompt_open := false

var _session: Node


func _ready() -> void:
	# Both panels have to keep drawing and taking keys while the tree itself is stopped.
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_session = get_tree().get_first_node_in_group("level_session")


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var key := (event as InputEventKey).keycode
	if is_quit_prompt_open:
		# The original answers this prompt with the initials of Tak and Nie.
		if key == KEY_T:
			_leave_level()
		elif key == KEY_N:
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
		_draw_panel(PAUSE_PANEL)
		var lines := _goal_lines()
		_draw_centred(lines[0], PAUSE_PANEL.position.y + 10.0, PAUSE_COLOR)
		_draw_centred(lines[1], PAUSE_PANEL.position.y + 35.0, PAUSE_COLOR)
		_draw_centred(PAUSED, PAUSE_PANEL.position.y + 85.0, LABEL_COLOR)
	if is_quit_prompt_open:
		_draw_panel(QUIT_PANEL)
		_draw_centred(QUIT_QUESTION, QUIT_PANEL.position.y + 10.0, PROMPT_COLOR)
		_draw_centred(QUIT_ANSWER, QUIT_PANEL.position.y + 35.0, PROMPT_COLOR)


# The panel restates the level's own CONDITION, in the wording its mode uses.
func _goal_lines() -> Array:
	var limit := 1200.0
	var target := 10000
	var mode := &"time"
	if _session != null:
		limit = float(_session.limit_seconds())
		target = int(_session.target_score())
		mode = _session.mode
	var minutes := int(limit / 60.0)
	if mode == &"points":
		return [POINTS_GOAL_FORMAT % minutes, POINTS_TARGET_FORMAT % target]
	return [TIME_GOAL, TIME_GOAL_FORMAT % [target, minutes]]


func _draw_panel(panel: Rect2) -> void:
	draw_rect(panel, PANEL_COLOR)


func _draw_centred(text: String, top: float, color: Color) -> void:
	var font := ThemeDB.fallback_font
	var size := ThemeDB.fallback_font_size
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var origin := Vector2(400.0 - width * 0.5, top + float(size))
	draw_string(font, origin + SHADOW_OFFSET, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, SHADOW_COLOR)
	draw_string(font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
