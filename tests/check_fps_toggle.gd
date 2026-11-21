extends SceneTree

# The FPS label in the corner of every level is hidden until the key under Esc (the toggle_fps
# action) shows it, and ScreenManager keeps the choice for the session:
#
# - a level starts with its label hidden;
# - the key shows it and hides it again, bare or with Shift (~ on an English layout);
# - the next level keeps what was chosen;
# - a name box being typed into keeps its ` and the label stays as it was.

const LEVEL := preload("res://scenes/level_1.tscn")

var _failures := 0
var _manager: Node


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_manager = root.get_node_or_null("ScreenManager")
	if _manager == null:
		push_error("the ScreenManager autoload is missing")
		quit(1)
		return
	_manager.set_fps_shown(false)

	var level := await _add_level()
	var label := level.get_node("DebugOverlay/FPSCounter") as Label
	_expect(not label.visible, "a level starts with its FPS label hidden")

	await _press(false)
	_expect(label.visible and _manager.fps_shown, "the key under Esc shows it")
	_expect(label.text.begins_with("FPS: "), "counting")
	await _press(true)
	_expect(not label.visible and not _manager.fps_shown, "and, with Shift as ~ is typed in English, hides it again")

	await _press(false)
	root.remove_child(level)
	level.free()
	var next := await _add_level()
	_expect((next.get_node("DebugOverlay/FPSCounter") as Label).visible, "the next level keeps the label shown")

	var box := LineEdit.new()
	root.add_child(box)
	box.grab_focus()
	await process_frame
	await _press(false)
	_expect(box.text == "`", "a name box being typed into keeps its `, got %s" % box.text)
	_expect(_manager.fps_shown, "and the label stays as it was")
	root.remove_child(box)
	box.free()

	root.remove_child(next)
	next.free()
	_manager.set_fps_shown(false)
	if _failures == 0:
		print("FPS toggle: hidden by default, the key under Esc with or without Shift, kept for the next level, and left to a name box passed")
	quit(1 if _failures else 0)


func _add_level() -> Node:
	var level := LEVEL.instantiate()
	(level.get_node("LevelRuntime") as Node).set("enabled", false)
	root.add_child(level)
	await process_frame
	return level


func _press(shift: bool) -> void:
	for pressed in [true, false]:
		var key := InputEventKey.new()
		key.physical_keycode = KEY_QUOTELEFT
		key.keycode = KEY_ASCIITILDE if shift else KEY_QUOTELEFT
		key.unicode = 0x7E if shift else 0x60
		key.shift_pressed = shift
		key.pressed = pressed
		Input.parse_input_event(key)
		await process_frame
	await process_frame


func _expect(condition: bool, label: String) -> void:
	if not condition:
		_failures += 1
		push_error(label)
