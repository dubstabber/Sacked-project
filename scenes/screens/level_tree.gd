extends Control


func _ready() -> void:
	$VBox/Level1.pressed.connect(_on_level_1_pressed)
	$VBox/Back.pressed.connect(_on_back_pressed)


func _on_level_1_pressed() -> void:
	ScreenManager.change_to(ScreenManager.Screen.LEVEL_1)


func _on_back_pressed() -> void:
	ScreenManager.change_to(ScreenManager.Screen.MAIN_MENU)
