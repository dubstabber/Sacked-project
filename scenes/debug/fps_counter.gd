extends Label

# The frame rate, in the corner of every generated level. Hidden until the key under Esc (the
# toggle_fps action) shows it; ScreenManager keeps the choice for the session, so the next
# level shows it too. A level run without the autoloads, as the headless checks do, keeps it
# hidden.

@export var update_interval_seconds := 0.25

var _elapsed := 0.0


func _ready() -> void:
	# Updated under a pause too, so the count stays honest while the round menu is open.
	process_mode = Node.PROCESS_MODE_ALWAYS
	var screens := get_node_or_null("/root/ScreenManager")
	if screens != null and screens.has_signal("fps_shown_changed"):
		screens.fps_shown_changed.connect(_show)
		_show(bool(screens.get("fps_shown")))
	else:
		_show(false)


func _show(shown: bool) -> void:
	visible = shown
	set_process(shown)
	if shown:
		_elapsed = 0.0
		_update_text()


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed < update_interval_seconds:
		return

	_elapsed = 0.0
	_update_text()


func _update_text() -> void:
	text = "FPS: %d" % int(round(Engine.get_frames_per_second()))
