extends Control

# The original's screen 11, `CSoundSetup` (built by sub_425050, answered by sub_403F20 case
# 11): the effects volume on the left and the music on the right, each a display-only box
# with an arrow either side, over the main menu's own picture. An arrow moves its volume by
# 5 and clamps it to 0..100; Domyślne puts back effects 75 and music 65. Every change is
# applied at once, so the music follows while Menu1 plays and the effects apply to the next
# sound started. The boxes show a bare number, as sub_425A10's "%d" does.
#
# The language and display rows under them are the port's own: the original ships one
# language per build and has no display option. Domyślne leaves both alone.
# See docs/sound-reference.md.

@onready var _store: Node = get_node_or_null("/root/SettingsStore")
@onready var _screens: Node = get_node_or_null("/root/ScreenManager")
@onready var _i18n: Node = get_node_or_null("/root/I18n")
@onready var _effects_value: Label = $SafeFrame/EffectsBox/Value
@onready var _music_value: Label = $SafeFrame/MusicBox/Value
@onready var _language_value: Label = $SafeFrame/LanguageBox/Value
@onready var _display_value: Label = $SafeFrame/DisplayBox/Value


func _ready() -> void:
	# A number is not a key, so it must not go through the translation table.
	_effects_value.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_music_value.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_connect_button("EffectsDown", _step_effects.bind(-1))
	_connect_button("EffectsUp", _step_effects.bind(1))
	_connect_button("MusicDown", _step_music.bind(-1))
	_connect_button("MusicUp", _step_music.bind(1))
	_connect_button("LanguageDown", _step_language.bind(-1))
	_connect_button("LanguageUp", _step_language.bind(1))
	_connect_button("DisplayDown", _toggle_display)
	_connect_button("DisplayUp", _toggle_display)
	_connect_button("Defaults", _on_defaults_pressed)
	_connect_button("MainMenu", _on_main_menu_pressed)
	if _store != null:
		_store.settings_changed.connect(_fill)
	_fill()


func _connect_button(node_name: String, callback: Callable) -> void:
	($SafeFrame.get_node(node_name) as TextureButton).pressed.connect(callback)


func _fill() -> void:
	if _store == null:
		return
	_effects_value.text = str(_store.effects_volume())
	_music_value.text = str(_store.music_volume())
	# Keys, so the two boxes follow a language change on their own.
	_language_value.text = "language.%s" % String(_current_language())
	_display_value.text = "sound.fullscreen" if _store.is_fullscreen() else "sound.windowed"


func _step_effects(direction: int) -> void:
	if _store != null:
		_store.step_effects(direction)


func _step_music(direction: int) -> void:
	if _store != null:
		_store.step_music(direction)


func _step_language(direction: int) -> void:
	if _store == null or _i18n == null:
		return
	var languages: Array = _i18n.SUPPORTED
	var index := languages.find(_current_language())
	_store.set_language(languages[posmod(index + direction, languages.size())])


func _toggle_display() -> void:
	if _store != null:
		_store.toggle_fullscreen()


func _current_language() -> StringName:
	return _i18n.current_language() if _i18n != null else &"pl"


func _on_defaults_pressed() -> void:
	if _store != null:
		_store.reset_audio_defaults()


func _on_main_menu_pressed() -> void:
	if _screens != null:
		_screens.change_to_main_menu()
