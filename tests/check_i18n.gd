extends SceneTree

# Language selection: how the language is resolved at boot, that all three load, and that
# the two places the port cannot simply translate -- the painted console art and the quit
# prompt's answer keys -- follow it. See docs/strings-reference.md.

const ConsoleScene := preload("res://scenes/hud/console.tscn")

const STRINGS_PATH := "res://resources/original/strings.json"
const TRANSLATIONS_PATH := "res://resources/i18n/translations.json"
const SETTINGS_PATH := "user://check_i18n_settings.cfg"

const I18N_SCRIPT := preload("res://autoloads/i18n.gd")

var _failures := 0
var _restore: StringName = &"pl"


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_restore = _i18n().current_language()

	_check_resolution_order()
	_check_every_language_loads()
	await _check_the_console_follows_the_language()
	_check_the_answer_keys_are_typeable()
	_check_the_font_can_draw_every_string()

	_i18n().set_language(_restore)
	if _failures == 0:
		print("Language selection: resolution order, three loaded languages, the console swap and font coverage passed")
	quit(1 if _failures else 0)


func _expect(condition: bool, label: String) -> void:
	if not condition:
		_failures += 1
		push_error(label)


func _check_resolution_order() -> void:
	var none := PackedStringArray()
	var english := PackedStringArray(["--lang=en"])
	var nonsense := PackedStringArray(["--lang=qq"])

	_expect(I18N_SCRIPT.resolve_language(english, "", "de") == &"en", "the command line wins")
	_expect(I18N_SCRIPT.resolve_language(nonsense, "", "de") == &"de", "an unsupported --lang is ignored")
	_expect(I18N_SCRIPT.resolve_language(none, "", "de") == &"de", "the machine's language is used next")
	_expect(I18N_SCRIPT.resolve_language(none, "", "fr") == &"pl", "an unsupported machine language falls back to Polish")
	_expect(I18N_SCRIPT.resolve_language(none, "", "") == &"pl", "no answer at all falls back to Polish")
	_expect(I18N_SCRIPT.resolve_language(PackedStringArray(["--lang=EN"]), "", "pl") == &"en", "--lang is case insensitive")

	# A saved choice beats the machine but loses to the command line.
	var config := ConfigFile.new()
	config.set_value("locale", "language", "de")
	config.save(SETTINGS_PATH)
	_expect(I18N_SCRIPT.resolve_language(none, SETTINGS_PATH, "en") == &"de", "the saved language beats the machine")
	_expect(I18N_SCRIPT.resolve_language(english, SETTINGS_PATH, "pl") == &"en", "the command line beats the saved language")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_PATH))
	_expect(I18N_SCRIPT.resolve_language(none, SETTINGS_PATH, "en") == &"en", "a missing settings file is not an answer")


func _check_every_language_loads() -> void:
	# Polish and German are both the retail builds' own wording; only English is authored.
	var expected := {
		&"pl": "Gra na czas",
		&"en": "Time game",
		&"de": "Zeitmodus",
	}
	for language: StringName in I18N_SCRIPT.SUPPORTED:
		_i18n().set_language(language)
		_expect(_i18n().current_language() == language, "%s is selectable" % language)
		_expect(
			tr(&"menu.time_game") == expected[language],
			"%s reads the menu as %s, got %s" % [language, expected[language], tr(&"menu.time_game")]
		)
		_expect(tr(&"app.window_title") != "app.window_title", "%s has a window title" % language)
		# A key that comes back as itself means the table never reached this language.
		_expect(tr(&"level.1.title") != "level.1.title", "%s names level 1" % language)
		_expect(tr(&"action.1.name") != "action.1.name", "%s names the prank actions" % language)

	_i18n().set_language(&"de")
	_expect(tr(&"app.window_title") == "Gefeuert! - Dein letzter Tag", "the German title is the original's own")
	_expect(tr(&"prompt.paused") == "Spiel angehalten", "German pause wording comes from Gefeuert.exe")
	_expect(tr(&"difficulty.6") == "Mach dein Testament", "German difficulty wording comes from Gefeuert.exe")
	_expect(tr(&"level.1.title") == "Der erste letzte Tag", "German level titles come from Gefeuert.exe")
	_i18n().set_language(&"pl")
	_expect(tr(&"character.anne") == "Anne Employed", "a proper noun is not translated")


# The console art has "czas" and "wynik" painted in, so Polish uses the art and every other
# language uses the erased copy plus two Labels.
func _check_the_console_follows_the_language() -> void:
	var console := ConsoleScene.instantiate()
	root.add_child(console)
	await process_frame

	var frame := console.get_node("Band/Frame") as Sprite2D
	var labels: Array = [console.get_node("Band/TimeLabel"), console.get_node("Band/ScoreLabel")]

	_i18n().set_language(&"pl")
	await process_frame
	_expect(frame.texture == console.PAINTED_FRAME, "Polish uses the art with the words painted in")
	for label: Label in labels:
		_expect(not label.visible, "Polish draws no label over the painted word")

	for language: StringName in [&"en", &"de"]:
		_i18n().set_language(language)
		await process_frame
		_expect(frame.texture == console.UNLABELLED_FRAME, "%s uses the erased console art" % language)
		for label: Label in labels:
			_expect(label.visible, "%s draws its own word" % language)
			_expect(label.atr(label.text) != label.text, "%s translates the painted word" % language)

	_expect(
		console.PAINTED_FRAME.get_size() == console.UNLABELLED_FRAME.get_size(),
		"both console frames are the same size, so nothing else shifts"
	)

	_i18n().set_language(&"pl")
	root.remove_child(console)
	console.free()


# Whatever letter a language names in its quit prompt has to be a key a keyboard can send.
func _check_the_answer_keys_are_typeable() -> void:
	for language: StringName in I18N_SCRIPT.SUPPORTED:
		_i18n().set_language(language)
		for key in [&"prompt.quit_yes_key", &"prompt.quit_no_key"]:
			var initial := tr(key)
			var keycode := OS.find_keycode_from_string(initial)
			_expect(keycode != KEY_NONE, "%s's %s (%s) is a real key" % [language, key, initial])
			_expect(tr(&"prompt.quit_answer").contains("(%s)" % initial), "%s names %s in its answer" % [language, initial])


# Godot's default font carries Polish and German; this turns that from an assumption into a
# fact, and will fail loudly if a theme font is ever introduced that does not.
func _check_the_font_can_draw_every_string() -> void:
	var font := ThemeDB.fallback_font
	if font == null:
		_expect(false, "there is no fallback font to check")
		return
	var source: Dictionary = _read_json(STRINGS_PATH).get("strings", {})
	var authored := _read_json(TRANSLATIONS_PATH)
	var missing := {}
	for key: String in source:
		var texts := [String((source[key] as Dictionary).get("pl", ""))]
		var entry: Dictionary = authored.get(key, {})
		for language in ["en", "de"]:
			texts.append(String(entry.get(language, "")))
		for text: String in texts:
			for index in text.length():
				var character := text[index]
				if character != " " and not font.has_char(character.unicode_at(0)):
					missing[character] = key
	_expect(missing.is_empty(), "the default font cannot draw %s" % str(missing))


func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}


# The autoload exists in the tree even though its global name is not bound at compile time.
func _i18n() -> Node:
	return root.get_node("I18n")
