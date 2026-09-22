extends Control

# Interim. The original's screen 15 is a real tree: 21 nodes over its own backdrop, each
# drawn free, locked or played, leading to the level-description screen rather than straight
# into the level. That needs the unlock rule and the saved progress behind it, neither of
# which is recovered yet, so this lists whatever levels have been imported.


var _levels: Array[int] = []


func _ready() -> void:
	var box := $VBox as VBoxContainer
	var back := $VBox/Back as Button
	_levels = ScreenManager.available_levels()
	for level in _levels:
		var button := Button.new()
		button.name = "Level%d" % level
		button.custom_minimum_size = Vector2(240, 48)
		box.add_child(button)
		box.move_child(button, back.get_index())
		button.pressed.connect(ScreenManager.start_level.bind(level))
	_name_levels()
	back.pressed.connect(_on_back_pressed)


# A formatted string is not a key, so it cannot auto-translate and has to be rebuilt.
func _name_levels() -> void:
	for level in _levels:
		var button := get_node_or_null("VBox/Level%d" % level) as Button
		if button != null:
			button.text = tr(&"level_tree.level_n") % level


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		_name_levels()


func _on_back_pressed() -> void:
	ScreenManager.change_to(ScreenManager.Screen.MAIN_MENU)
