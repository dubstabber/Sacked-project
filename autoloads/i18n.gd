extends Node

# Language selection. Two retail builds exist, so Polish and German are both generated from
# their own executables by tools/export_strings.py rather than typed out. Only English is
# authored, along with the handful of strings neither build has wording for.
# See docs/strings-reference.md.
#
# There is no in-game language screen yet, so the language is resolved once at boot.

signal language_changed(language: StringName)

const SOURCE_LANGUAGE: StringName = &"pl"
const SUPPORTED: Array[StringName] = [&"pl", &"en", &"de"]

const STRINGS_PATH := "res://resources/original/strings.json"
const TRANSLATIONS_PATH := "res://resources/i18n/translations.json"
const SETTINGS_PATH := "user://settings.cfg"
const LANGUAGE_ARGUMENT := "--lang="

var _loaded := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_translations()
	set_language(resolve_language(OS.get_cmdline_user_args(), SETTINGS_PATH, OS.get_locale_language()))


# Command line first, then whatever the player last chose, then the machine, then Polish.
static func resolve_language(
	user_args: PackedStringArray, settings_path: String, os_language: String
) -> StringName:
	var candidates := [
		language_from_args(user_args),
		language_from_settings(settings_path),
		os_language,
	]
	for candidate: String in candidates:
		var language := StringName(candidate.strip_edges().to_lower())
		if SUPPORTED.has(language):
			return language
	return SOURCE_LANGUAGE


# Godot keeps its own options ahead of "--", so the game's own flags live after it:
#   ./Godot_v4.7.2-stable_linux.x86_64 . -- --lang=en
static func language_from_args(user_args: PackedStringArray) -> String:
	for argument in user_args:
		if argument.begins_with(LANGUAGE_ARGUMENT):
			return argument.substr(LANGUAGE_ARGUMENT.length())
	return ""


static func language_from_settings(settings_path: String) -> String:
	var config := ConfigFile.new()
	if config.load(settings_path) != OK:
		return ""
	return String(config.get_value("locale", "language", ""))


func load_translations() -> void:
	if _loaded:
		return
	var source: Dictionary = _read_json(STRINGS_PATH).get("strings", {})
	var authored := _read_json(TRANSLATIONS_PATH)
	for language in SUPPORTED:
		var translation := Translation.new()
		translation.locale = String(language)
		for key: String in source:
			var text := _text_for(source, authored, key, language)
			if text != "":
				translation.add_message(key, text)
		TranslationServer.add_translation(translation)
	_loaded = true


# The generated table wins wherever it has the language, so an authored file cannot drift
# away from what the retail builds actually say.
func _text_for(source: Dictionary, authored: Dictionary, key: String, language: StringName) -> String:
	var generated := String((source[key] as Dictionary).get(String(language), ""))
	if generated != "":
		return generated
	return String((authored.get(key, {}) as Dictionary).get(String(language), ""))


func set_language(language: StringName) -> void:
	if not SUPPORTED.has(language):
		push_warning("Unsupported language: %s" % String(language))
		return
	TranslationServer.set_locale(String(language))
	DisplayServer.window_set_title(tr(&"app.window_title"))
	language_changed.emit(language)


func current_language() -> StringName:
	return StringName(TranslationServer.get_locale().substr(0, 2))


# Cycling the language exercises every NOTIFICATION_TRANSLATION_CHANGED handler in the game,
# which is the only way to see a running level change language. F1 is already fullscreen.
func _input(event: InputEvent) -> void:
	if not OS.is_debug_build():
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F2:
		var index := SUPPORTED.find(current_language())
		set_language(SUPPORTED[(index + 1) % SUPPORTED.size()])
		get_viewport().set_input_as_handled()


func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("Missing string table: %s" % path)
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}
