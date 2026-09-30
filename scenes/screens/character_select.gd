extends Control

const _PLAYER_NAME_MAX_LENGTH := 16
# sub_424D50 draws slot 219 in the clip (138, 454, 208, 56) at 0x470F98, starting at (140, 463)
# where NameLabel sits: 206 px of room on the first line and the whole 208 on the next. Its
# copy starts 5 px in, 203 px of room, and breaks the same in every language. See
# docs/shell-reference.md.
const NAME_PROMPT := &"highscore.name_prompt"
const NAME_PROMPT_WIDTH := 208.0
const NAME_PROMPT_START := 2.0
const GdiTextWrap := preload("res://scenes/shared/gdi_text_wrap.gd")
const GuiInput := preload("res://scenes/shared/gui_input.gd")

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

@onready var _jobless_button: TextureButton = $SafeFrame/JoblessButton
@onready var _anne_button: TextureButton = $SafeFrame/AnneButton
@onready var _name_edit: LineEdit = $SafeFrame/NameEdit
@onready var _name_shadow: Label = $SafeFrame/NameShadow
@onready var _name_prompt: Label = $SafeFrame/NameLabel
@onready var _defaults_button: TextureButton = $SafeFrame/DefaultsButton
@onready var _main_menu_button: TextureButton = $SafeFrame/MainMenuButton
@onready var _continue_button: TextureButton = $SafeFrame/ContinueButton


func _ready() -> void:
	_jobless_button.pressed.connect(_select_character.bind(&"jobless"))
	_anne_button.pressed.connect(_select_character.bind(&"anne"))
	_defaults_button.pressed.connect(_on_defaults_pressed)
	_main_menu_button.pressed.connect(_on_main_menu_pressed)
	_continue_button.pressed.connect(_on_continue_pressed)
	_name_edit.text_submitted.connect(_on_name_submitted)
	_name_edit.text_changed.connect(_on_name_changed)
	_name_edit.max_length = _PLAYER_NAME_MAX_LENGTH
	# sub_407D60 opens on the stored character with the stored name in the box (0x407dc3,
	# 0x407dd6). The port's fallback name stays a placeholder rather than typed text.
	var stored_name := String(_screen_manager().get("player_name"))
	_set_name_box("" if stored_name == String(_screen_manager().call("get_default_player_name")) else stored_name)
	_update_character_buttons()
	_update_name_placeholder()
	_fill_name_prompt()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_fill_name_prompt()


func _fill_name_prompt() -> void:
	_name_prompt.text = GdiTextWrap.break_lines(
		tr(NAME_PROMPT), _name_prompt.get_theme_font(&"font"), _name_prompt.get_theme_font_size(&"font_size"),
		NAME_PROMPT_WIDTH - NAME_PROMPT_START, NAME_PROMPT_WIDTH
	)


# Buttons 1 and 2 set the character and save the profile with the name already stored, not
# the box. An empty stored name follows the character's own default, which is the port's.
func _select_character(character_id: StringName) -> void:
	var manager := _screen_manager()
	var had_default: bool = String(manager.get("player_name")) == String(manager.call("get_default_player_name"))
	manager.call("select_character", character_id)
	if had_default:
		manager.call("set_player_name", "")
	manager.call("save_player_setup")
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


# Button 4 only empties the box (sub_424EA0 with the empty string at 0x473CF4). It keeps the
# character and saves nothing.
func _on_defaults_pressed() -> void:
	_set_name_box("")
	_update_name_placeholder()


# Button 3 leaves without copying the box, so anything typed is dropped.
func _on_main_menu_pressed() -> void:
	_screen_manager().call("change_to_main_menu")


# Button 5 copies the box into the profile, saves it and opens the tree.
func _on_continue_pressed() -> void:
	_screen_manager().call("set_player_name", _name_edit.text)
	_screen_manager().call("save_player_setup")
	_screen_manager().call("change_to_level_tree")


func _on_name_submitted(_new_text: String) -> void:
	_on_continue_pressed()


# The box is a CGUIInput (sub_45C5E0 at 0x424AFF) in the menu's Arial 32 (+1168, 0x424C7D),
# drawn and keyed as scenes/shared/gui_input.gd says.
func _set_name_box(text: String) -> void:
	GuiInput.show_text(_name_edit, _name_shadow, text)


func _on_name_changed(text: String) -> void:
	GuiInput.take_text(_name_edit, _name_shadow, text)


func _update_name_placeholder() -> void:
	_name_edit.placeholder_text = String(_screen_manager().call("get_default_player_name"))


func _screen_manager() -> Node:
	return get_node("/root/ScreenManager")
