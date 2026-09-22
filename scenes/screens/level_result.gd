extends Control

# Screens 7 and 8 in the original (sub_407370). Both are a single full-screen image; the
# win screen also starts sound S1100. Either returns to the level tree.

const WIN_TEXTURE := preload("res://images/gui/screens/win.png")
const LOSE_TEXTURE := preload("res://images/gui/screens/lose.png")


func _ready() -> void:
	var screen_manager := get_node_or_null("/root/ScreenManager")
	var won := screen_manager != null and bool(screen_manager.get("last_level_won"))
	($SafeFrame/Image as TextureRect).texture = WIN_TEXTURE if won else LOSE_TEXTURE


func _unhandled_input(event: InputEvent) -> void:
	var key_pressed: bool = event is InputEventKey and event.pressed and not event.echo
	var click: bool = event is InputEventMouseButton and event.pressed
	if key_pressed or click:
		get_viewport().set_input_as_handled()
		var screen_manager := get_node_or_null("/root/ScreenManager")
		if screen_manager != null:
			screen_manager.call("change_to_level_tree")
