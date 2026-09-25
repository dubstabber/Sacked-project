extends SceneTree

# Screen 11 as recovered in docs/sound-reference.md: the element rects from the table at
# 0x4710F8, arrows that step a volume by 5 and clamp it, a bare number in each box, Domyślne
# putting back effects 75 and music 65, and Główne menu going back to screen 3. Also the
# port's language and display rows. The live store is pointed at a file of the check's own.

const SCREEN := preload("res://scenes/screens/sound_setup.tscn")
const ScreenManagerScript := preload("res://autoloads/screen_manager.gd")
const TEST_PATH := "user://check_sound_setup.cfg"

# The rects the original builds, as (x, y, width, height) inside the 800x600 frame.
const RECOVERED_RECTS := {
	"Title": Rect2(64, 16, 672, 64),
	"EffectsSymbol": Rect2(32, 128, 336, 208),
	"MusicSymbol": Rect2(432, 128, 336, 208),
	"EffectsDown": Rect2(32, 368, 64, 48),
	"EffectsBox": Rect2(112, 368, 176, 48),
	"EffectsUp": Rect2(305, 368, 64, 48),
	"MusicDown": Rect2(432, 368, 64, 48),
	"MusicBox": Rect2(512, 368, 176, 48),
	"MusicUp": Rect2(705, 368, 64, 48),
	"MainMenu": Rect2(16, 536, 160, 48),
	"Defaults": Rect2(624, 536, 160, 48),
}

var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var store: Node = root.get_node_or_null("SettingsStore")
	var manager: Node = root.get_node_or_null("ScreenManager")
	var i18n: Node = root.get_node_or_null("I18n")
	if store == null or manager == null or i18n == null:
		push_error("the SettingsStore, ScreenManager and I18n autoloads are available")
		quit(1)
		return
	await process_frame
	var restore_path: String = store.path
	var restore_language: StringName = i18n.current_language()
	store.path = TEST_PATH
	DirAccess.remove_absolute(TEST_PATH)
	store.reload()
	store.apply_audio()
	i18n.set_language(&"pl")

	var screen := SCREEN.instantiate()
	root.add_child(screen)
	await process_frame

	_check_the_recovered_layout(screen)
	_check_the_boxes_open_on_the_defaults(screen)
	_check_the_arrows_step_and_clamp(screen)
	_check_defaults_restore_the_volumes(screen, store)
	_check_the_language_row(screen, i18n)
	_check_the_display_row(screen, store)
	_check_the_screen_keeps_menu1(manager)
	_check_main_menu_leaves(screen, manager)

	screen.queue_free()
	await process_frame
	i18n.set_language(restore_language)
	store.path = restore_path
	store.reload()
	store.apply_audio()
	DirAccess.remove_absolute(TEST_PATH)
	if _failures == 0:
		print("Sound setup: the recovered layout, 5-step clamped volumes, Defaults, the language and display rows and the way back passed")
	quit(1 if _failures else 0)


func _expect(condition: bool, label: String) -> void:
	if not condition:
		_failures += 1
		push_error(label)


func _press(screen: Node, button: String, times := 1) -> void:
	var node := screen.get_node("SafeFrame/%s" % button) as TextureButton
	for i in times:
		node.pressed.emit()


func _value(screen: Node, box: String) -> String:
	return (screen.get_node("SafeFrame/%s/Value" % box) as Label).text


func _bus_linear(bus: StringName) -> float:
	var index := AudioServer.get_bus_index(bus)
	if index < 0 or AudioServer.is_bus_mute(index):
		return 0.0
	return db_to_linear(AudioServer.get_bus_volume_db(index))


func _check_the_recovered_layout(screen: Node) -> void:
	for node_name: String in RECOVERED_RECTS:
		var control := screen.get_node_or_null("SafeFrame/%s" % node_name) as Control
		_expect(control != null, "screen 11 has %s" % node_name)
		if control != null:
			_expect(
				control.get_rect().is_equal_approx(RECOVERED_RECTS[node_name]),
				"%s sits at its recovered rect %s, got %s" % [node_name, RECOVERED_RECTS[node_name], control.get_rect()]
			)
	var title := screen.get_node("SafeFrame/Title") as Label
	_expect(title.text == "sound.title", "the title is slot 221")
	_expect(title.atr(title.text) == "Konfiguracja dźwięku i muzyki", "the Polish title reads as the original's")
	var background := screen.get_node("SafeFrame/Background") as TextureRect
	_expect(
		background.texture.resource_path == "res://images/gui/screens/menu_background.png",
		"the background is the main menu's own picture"
	)


func _check_the_boxes_open_on_the_defaults(screen: Node) -> void:
	_expect(_value(screen, "EffectsBox") == "75", "effects open at the original's 75, got %s" % _value(screen, "EffectsBox"))
	_expect(_value(screen, "MusicBox") == "65", "music opens at the original's 65, got %s" % _value(screen, "MusicBox"))


func _check_the_arrows_step_and_clamp(screen: Node) -> void:
	_press(screen, "EffectsUp")
	_expect(_value(screen, "EffectsBox") == "80", "one right arrow adds 5 to the effects")
	_press(screen, "EffectsUp", 5)
	_expect(_value(screen, "EffectsBox") == "100", "the effects stop at 100, got %s" % _value(screen, "EffectsBox"))
	_expect(absf(_bus_linear(&"SFX") - 1.0) < 0.001, "the effects bus follows at once")
	_press(screen, "MusicDown")
	_expect(_value(screen, "MusicBox") == "60", "one left arrow takes 5 off the music")
	_press(screen, "MusicDown", 13)
	_expect(_value(screen, "MusicBox") == "0", "the music stops at 0, got %s" % _value(screen, "MusicBox"))
	_expect(AudioServer.is_bus_mute(AudioServer.get_bus_index(&"Music")), "music at 0 mutes its bus")
	_press(screen, "MusicUp")
	_expect(_value(screen, "MusicBox") == "5", "the music comes back up from 0")
	_expect(absf(_bus_linear(&"Music") - 0.05) < 0.001, "the music bus unmutes at once")


func _check_defaults_restore_the_volumes(screen: Node, store: Node) -> void:
	store.set_fullscreen(true)
	_press(screen, "Defaults")
	_expect(_value(screen, "EffectsBox") == "75", "Domyślne puts the effects back to 75")
	_expect(_value(screen, "MusicBox") == "65", "Domyślne puts the music back to 65")
	_expect(store.is_fullscreen(), "Domyślne leaves the port's display row alone")
	store.set_fullscreen(false)


func _check_the_language_row(screen: Node, i18n: Node) -> void:
	var title := screen.get_node("SafeFrame/Title") as Label
	_expect(_value(screen, "LanguageBox") == "language.pl", "the language row shows the running language")
	_press(screen, "LanguageUp")
	_expect(i18n.current_language() == &"en", "the right arrow moves to the next language")
	_expect(_value(screen, "LanguageBox") == "language.en", "the language box follows")
	_expect(title.atr(title.text) == "Sound and music settings", "the screen's own title follows the language")
	_press(screen, "LanguageUp")
	_press(screen, "LanguageUp")
	_expect(i18n.current_language() == &"pl", "the languages wrap round")
	_press(screen, "LanguageDown")
	_expect(i18n.current_language() == &"de", "the left arrow wraps the other way")
	i18n.set_language(&"pl")


func _check_the_display_row(screen: Node, store: Node) -> void:
	_expect(_value(screen, "DisplayBox") == "sound.windowed", "the display row opens windowed")
	_press(screen, "DisplayUp")
	_expect(store.is_fullscreen(), "the display row switches to full screen")
	_expect(_value(screen, "DisplayBox") == "sound.fullscreen", "the display box follows")
	_press(screen, "DisplayDown")
	_expect(not store.is_fullscreen(), "either arrow switches back")


func _check_the_screen_keeps_menu1(manager: Node) -> void:
	# Case 11 starts no track, so the Menu1 the main menu started keeps playing.
	_expect(
		manager._menu_music_for(ScreenManagerScript.Screen.SOUND_SETUP) == load("res://audio/music/menu1.ogg"),
		"the sound setup keeps Menu1 playing"
	)


func _check_main_menu_leaves(screen: Node, manager: Node) -> void:
	_press(screen, "MainMenu")
	_expect(manager.current == ScreenManagerScript.Screen.MAIN_MENU, "Główne menu goes back to screen 3")
