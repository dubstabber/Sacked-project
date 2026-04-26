extends Label


@export var update_interval_seconds := 0.25

var _elapsed := 0.0


func _ready() -> void:
	_update_text()


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed < update_interval_seconds:
		return

	_elapsed = 0.0
	_update_text()


func _update_text() -> void:
	text = "FPS: %d" % int(round(Engine.get_frames_per_second()))
