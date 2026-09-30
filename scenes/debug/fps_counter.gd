extends Label


@export var update_interval_seconds := 0.25

var _elapsed := 0.0


func _ready() -> void:
	# Every generated level carries this label; only debug builds, the editor and the headless
	# checks among them, show it.
	if not OS.is_debug_build():
		hide()
		set_process(false)
		return
	_update_text()


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed < update_interval_seconds:
		return

	_elapsed = 0.0
	_update_text()


func _update_text() -> void:
	text = "FPS: %d" % int(round(Engine.get_frames_per_second()))
