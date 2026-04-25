extends Control

const _PLAYER_NAME_MAX_LENGTH := 16

const _TEXTURE_PATHS := {
	&"jobless": {
		&"active": "res://images/gui/screens/character_select_jobless_active.png",
		&"high": "res://images/gui/screens/character_select_jobless_high.png",
		&"passive": "res://images/gui/screens/character_select_jobless_passive.png",
	},
	&"anne": {
		&"active": "res://images/gui/screens/character_select_anne_active.png",
		&"high": "res://images/gui/screens/character_select_anne_high.png",
		&"passive": "res://images/gui/screens/character_select_anne_passive.png",
	},
}

@onready var _jobless_button: TextureButton = $JoblessButton
@onready var _anne_button: TextureButton = $AnneButton
@onready var _name_edit: LineEdit = $NameEdit
@onready var _defaults_button: TextureButton = $DefaultsButton
@onready var _main_menu_button: TextureButton = $MainMenuButton
@onready var _continue_button: TextureButton = $ContinueButton


func _ready() -> void:
	_jobless_button.pressed.connect(_select_character.bind(&"jobless"))
	_anne_button.pressed.connect(_select_character.bind(&"anne"))
	_defaults_button.pressed.connect(_on_defaults_pressed)
	_main_menu_button.pressed.connect(_on_main_menu_pressed)
	_continue_button.pressed.connect(_on_continue_pressed)
	_name_edit.text_submitted.connect(_on_name_submitted)
	_name_edit.max_length = _PLAYER_NAME_MAX_LENGTH
	_name_edit.text = ""
	_select_character(StringName(_screen_manager().get("selected_character")))


func _select_character(character_id: StringName) -> void:
	_screen_manager().call("select_character", character_id)
	if _name_edit.text.strip_edges() == "":
		_screen_manager().call("set_player_name", "")
	_update_character_buttons()
	_update_name_placeholder()


func _update_character_buttons() -> void:
	_apply_character_textures(_jobless_button, &"jobless")
	_apply_character_textures(_anne_button, &"anne")


func _apply_character_textures(button: TextureButton, character_id: StringName) -> void:
	var texture_set: Dictionary = _TEXTURE_PATHS[character_id]
	if StringName(_screen_manager().get("selected_character")) == character_id:
		button.texture_normal = load(texture_set[&"active"]) as Texture2D
		button.texture_hover = load(texture_set[&"active"]) as Texture2D
	else:
		button.texture_normal = load(texture_set[&"passive"]) as Texture2D
		button.texture_hover = load(texture_set[&"high"]) as Texture2D
	button.texture_pressed = load(texture_set[&"active"]) as Texture2D


func _on_defaults_pressed() -> void:
	_screen_manager().call("reset_player_setup")
	_name_edit.text = ""
	_update_character_buttons()
	_update_name_placeholder()


func _on_main_menu_pressed() -> void:
	_screen_manager().call("set_player_name", _name_edit.text)
	_screen_manager().call("change_to_main_menu")


func _on_continue_pressed() -> void:
	_screen_manager().call("set_player_name", _name_edit.text)
	_screen_manager().call("change_to_level_tree")


func _on_name_submitted(_new_text: String) -> void:
	_on_continue_pressed()


func _update_name_placeholder() -> void:
	_name_edit.placeholder_text = String(_screen_manager().call("get_default_player_name"))


func _screen_manager() -> Node:
	return get_node("/root/ScreenManager")
