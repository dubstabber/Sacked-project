extends Control


func _ready() -> void:
	$AdvanceTimer.timeout.connect(_advance)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		_advance()
	elif event is InputEventMouseButton and event.pressed:
		_advance()


func _advance() -> void:
	set_process_input(false)
	ScreenManager.change_to(ScreenManager.Screen.MAIN_MENU)
