extends Control

# The two panels Main_RenderUpdate draws over a level: the pause panel, which restates what
# the level asks for, whenever the pause bit is set (0x402D13), and the quit confirmation
# while the screen is 10 (0x403478). Opening the prompt sets that same bit, so the two are up
# together. Both are centred on x 400 of the original's 800-wide viewport with a two-pixel
# drop shadow; see docs/game-rules-reference.md. The port recentres them on the live width,
# which is the same x on a 4:3 canvas -- see docs/widescreen.md.

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
# Screen 10 also takes Enter and Space for no (sub_404990, 0x404955). Only the main Enter:
# the table at 0x4734CC gives the numpad's its own engine code, which the prompt ignores.
const QUIT_NO_ALSO: Array[Key] = [KEY_ENTER, KEY_SPACE]

var is_paused := false
var is_quit_prompt_open := false

var _session: Node
var _yes_key := KEY_NONE
var _no_key := KEY_NONE
# The ring's cancel, pressed behind the pause key and still owed when the level runs again.
var _ring_cancel_owed := false


func _ready() -> void:
	# Both panels have to keep drawing and taking keys while the tree itself is stopped.
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_session = get_tree().get_first_node_in_group("level_session")
	_bind_answer_keys()


func _unhandled_input(event: InputEvent) -> void:
	_note_ring_cancel(event)
	if not (event is InputEventKey):
		return
	# Answering yes changes scene, and change_scene_to_file takes the level out of the tree
	# before it returns, so the viewport has to be in hand first.
	var viewport := get_viewport()
	var key := (event as InputEventKey).keycode
	var is_press: bool = event.pressed and not event.echo
	if is_quit_prompt_open:
		# Screen 10 reads nothing but its own answers (sub_404990, 0x404930), so no other key
		# reaches the level paused behind it -- the pause key included.
		viewport.set_input_as_handled()
		if is_press:
			_answer_quit_prompt(key)
		return
	if not is_press or _is_catch_running():
		return
	if key == KEY_Q:
		# sub_407370's case 10 sets the pause bit on the way in (0x4075AF).
		is_quit_prompt_open = true
		set_paused(true)
	elif key == KEY_P:
		set_paused(not is_paused)
	else:
		return
	viewport.set_input_as_handled()


func _answer_quit_prompt(key: Key) -> void:
	if key == _yes_key:
		_leave_level()
	elif key == _no_key or QUIT_NO_ALSO.has(key):
		# sub_407370's case 1, coming from screen 10, clears the pause bit whether or not the
		# pause key had set it before Q (0x40742F).
		is_quit_prompt_open = false
		set_paused(false)


# sub_403780 returns immediately while the pause bit is set, so the clock, the console and
# every agent stop together; only the drawing carries on.
func set_paused(paused: bool) -> void:
	if not paused:
		_pay_ring_cancel()
	is_paused = paused
	get_tree().paused = paused
	queue_redraw()


# The pause key leaves screen 1's handler running (sub_404990 case 1 calls sub_403FB0), and
# neither escape's own case (0x40410A) nor the end-of-frame test for a held down arrow or
# right button (0x4044F9-0x404520) reads the pause bit, so the ring's cancel still writes
# state 5 behind it. Only the frozen world leaves state 5 (sub_41B240, gated at 0x4025B7),
# so the cancel waits for the unpause even when the key was let go first. Screen 10 never
# calls sub_403FB0 (0x404914), so nothing is noted behind the quit prompt.
func _note_ring_cancel(event: InputEvent) -> void:
	if not is_paused or is_quit_prompt_open:
		return
	var cancels := (
		event.is_action_pressed("ui_cancel")
		or event.is_action_pressed("move_down")
		or event.is_action_pressed("mouse-movement")
	)
	if not cancels:
		return
	var controller := _ring_controller()
	if controller != null and controller.get("menu_open") == true:
		_ring_cancel_owed = true


# Paid before the tree runs again, so the ring lets go of the pointer while the pause still
# has it hidden. No clears the pause bit however it was set (0x40742F), so a cancel owed from
# before Q is paid by N too.
func _pay_ring_cancel() -> void:
	if not _ring_cancel_owed:
		return
	_ring_cancel_owed = false
	var controller := _ring_controller()
	if controller != null and controller.get("menu_open") == true:
		controller.call("close_menu")


func _ring_controller() -> Node:
	return get_tree().get_first_node_in_group("player_actions")


# sub_407370's case 3: the main menu, after the teardown (sub_407140) that clears the pause
# bit with every other flag -- and with it any cancel still owed to the ring, so leaving
# never hands the pointer back over a level on its way out.
func _leave_level() -> void:
	is_quit_prompt_open = false
	_ring_cancel_owed = false
	set_paused(false)
	var screen_manager := get_node_or_null("/root/ScreenManager")
	if screen_manager != null:
		screen_manager.call("change_to_main_menu")


# sub_403FB0 refuses Q and the pause key while the player is caught (screen 4; 0x40412F,
# 0x404150), and sub_404990 does not call it at all during the duel that follows (screen 5).
func _is_catch_running() -> bool:
	if _session == null:
		return false
	var watch := _session.get_node_or_null("CatchWatch")
	return watch != null and watch.get("caught_by") != null


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
