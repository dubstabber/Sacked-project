extends SceneTree

# The coworkers' names, as recovered in docs/names-reference.md: fifteen records in seven
# fixed pools, and screen 13, which shows one pool at a time, saves the shown boxes on every
# button and puts back only the shown pool's defaults. The live store is pointed at a file of
# the check's own.

const SCREEN := preload("res://scenes/screens/coworker_names.tscn")
const STORE_SCRIPT := preload("res://autoloads/settings_store.gd")
const ScreenManagerScript := preload("res://autoloads/screen_manager.gd")
const TEST_PATH := "user://check_coworker_names.cfg"

# The table at 0x470538, as (x, y, width, height) inside the 800x600 frame.
const RECOVERED_RECTS := {
	"Title": Rect2(64, 16, 672, 64),
	"Previous": Rect2(226, 194, 64, 48),
	"Next": Rect2(512, 194, 64, 48),
	"Portrait": Rect2(320, 88, 160, 240),
	"NameBox0": Rect2(232, 336, 352, 44),
	"NameBox1": Rect2(232, 396, 352, 44),
	"NameBox2": Rect2(232, 456, 352, 44),
	"MainMenu": Rect2(16, 536, 160, 48),
	"Defaults": Rect2(624, 536, 160, 48),
}
const PROFILES := [
	&"boss", &"secretary", &"janitor",
	&"male-employee-1", &"male-employee-2", &"female-employee-1", &"female-employee-2",
]

var _failures := 0
var _store: Node


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_store = root.get_node_or_null("SettingsStore")
	var manager: Node = root.get_node_or_null("ScreenManager")
	if _store == null or manager == null:
		push_error("the SettingsStore and ScreenManager autoloads are available")
		quit(1)
		return
	await process_frame
	var restore_path: String = _store.path
	_store.path = TEST_PATH
	DirAccess.remove_absolute(TEST_PATH)
	_store.reload()

	_check_the_table()
	_check_the_store_keeps_a_pool()

	var screen := SCREEN.instantiate()
	root.add_child(screen)
	await process_frame
	_check_the_recovered_layout(screen)
	_check_the_screen_opens_on_the_boss(screen)
	_check_the_arrows_cycle_the_pools(screen)
	_check_an_edit_is_saved_by_the_next_button(screen)
	_check_defaults_restore_the_shown_pool_only(screen)
	_check_an_empty_box_is_saved_empty(screen)
	await _check_sharp_s_is_refused(screen)
	_check_the_screen_plays_menu2(manager)
	_check_main_menu_saves_and_leaves(screen, manager)

	screen.queue_free()
	await process_frame
	_store.path = restore_path
	_store.reload()
	DirAccess.remove_absolute(TEST_PATH)
	if _failures == 0:
		print("Coworker names: fifteen names in seven pools, screen 13's layout, arrows, saving, Defaults and Menu2 passed")
	quit(1 if _failures else 0)


func _expect(condition: bool, label: String) -> void:
	if not condition:
		_failures += 1
		push_error(label)


func _press(screen: Node, button: String, times := 1) -> void:
	for i in times:
		(screen.get_node("SafeFrame/%s" % button) as TextureButton).pressed.emit()


func _box(screen: Node, i: int) -> LineEdit:
	return screen.get_node("SafeFrame/NameBox%d" % i) as LineEdit


func _type(screen: Node, i: int, text: String) -> void:
	var box := _box(screen, i)
	box.text = ""
	box.caret_column = 0
	box.insert_text_at_caret(text)


func _portrait(screen: Node) -> String:
	return (screen.get_node("SafeFrame/Portrait") as TextureRect).texture.resource_path


func _check_the_table() -> void:
	_expect(CoworkerNames.type_count() == 7, "seven name pools")
	_expect(CoworkerNames.placeholder() == "DEFAULT NAME", "an empty pool hands out the original's placeholder")
	_expect(CoworkerNames.max_length() == 16, "a name holds 16 characters")
	var sizes := []
	for type in range(1, 8):
		sizes.append(CoworkerNames.pool_size(type))
		_expect(CoworkerNames.profile_id(type) == PROFILES[type - 1], "pool %d belongs to %s" % [type, PROFILES[type - 1]])
	_expect(sizes == [1, 1, 1, 3, 3, 3, 3], "one name each for the boss, secretary and janitor, three per coworker variant")
	_expect(CoworkerNames.defaults_for(1) == PackedStringArray(["Roy Behr"]), "the boss is Roy Behr")
	_expect(
		CoworkerNames.defaults_for(7) == PackedStringArray(["Clare Grube", "Klara Fall", "Bette Nesser"]),
		"the second female variant's pool is Clare Grube, Klara Fall, Bette Nesser"
	)


func _check_the_store_keeps_a_pool() -> void:
	_expect(_store.names_for_type(4) == CoworkerNames.defaults_for(4), "an unsaved pool reads as the defaults")
	_store.set_names_for_type(4, PackedStringArray(["A", "a name far longer than sixteen", "C"]))
	var reopened: Node = STORE_SCRIPT.new()
	reopened.path = TEST_PATH
	reopened.reload()
	_expect(
		reopened.names_for_type(4) == PackedStringArray(["A", "a name far longe", "C"]),
		"a saved pool survives a restart, each name cut to 16, got %s" % reopened.names_for_type(4)
	)
	reopened.free()
	_store.reset_names_for_type(4)
	_expect(_store.names_for_type(4) == CoworkerNames.defaults_for(4), "resetting a pool brings its defaults back")


func _check_the_recovered_layout(screen: Node) -> void:
	for node_name: String in RECOVERED_RECTS:
		var control := screen.get_node_or_null("SafeFrame/%s" % node_name) as Control
		_expect(control != null, "screen 13 has %s" % node_name)
		if control != null:
			_expect(
				control.get_rect().is_equal_approx(RECOVERED_RECTS[node_name]),
				"%s sits at its recovered rect %s, got %s" % [node_name, RECOVERED_RECTS[node_name], control.get_rect()]
			)
	var title := screen.get_node("SafeFrame/Title") as Label
	_expect(title.text == "names.title", "the title is slot 209")
	for i in 3:
		_expect(_box(screen, i).max_length == 16, "name box %d takes 16 characters" % i)
		var font := _box(screen, i).get_theme_font(&"font")
		var font_size := _box(screen, i).get_theme_font_size(&"font_size")
		_expect(font.get_height(font_size) <= 44.0, "name box %d's text fits the recovered 44 px" % i)


func _check_the_screen_opens_on_the_boss(screen: Node) -> void:
	_expect(screen.shown_type() == 1, "the screen opens on the boss")
	_expect(_box(screen, 0).text == "Roy Behr", "the first box holds the boss's name, got %s" % _box(screen, 0).text)
	_expect(not _box(screen, 1).visible and not _box(screen, 2).visible, "the boss has one box")
	_expect(
		not (screen.get_node("SafeFrame/NameFrame1") as CanvasItem).visible
			and not (screen.get_node("SafeFrame/NameFrame2") as CanvasItem).visible,
		"a hidden box takes its frame with it"
	)
	_expect(_portrait(screen) == "res://images/gui/menu/portrait-boss.png", "the boss's portrait is shown")
	_expect(_box(screen, 0).has_focus(), "the first box has the focus")


func _check_the_arrows_cycle_the_pools(screen: Node) -> void:
	_press(screen, "Next")
	_expect(screen.shown_type() == 2, "the right arrow moves to the secretary")
	_expect(_box(screen, 0).text == "Martha Pfahl", "the secretary's name is shown")
	_press(screen, "Next", 5)
	_expect(screen.shown_type() == 7, "five more reach the second female variant")
	_expect(_box(screen, 1).visible and _box(screen, 2).visible, "a coworker pool shows all three boxes")
	_expect(_box(screen, 1).text == "Klara Fall", "the pool's second name is in the second box")
	_expect(_portrait(screen) == "res://images/gui/menu/portrait-female-employee-2.png", "the pool's own portrait is shown")
	_press(screen, "Next")
	_expect(screen.shown_type() == 1, "the right arrow wraps from the last pool to the boss")
	_press(screen, "Previous")
	_expect(screen.shown_type() == 7, "the left arrow wraps from the boss to the last pool")
	_press(screen, "Next")
	_expect(_store.names_for_type(7) == CoworkerNames.defaults_for(7), "paging past a pool saves what it shows")


func _check_an_edit_is_saved_by_the_next_button(screen: Node) -> void:
	_type(screen, 0, "Bo Ss")
	_expect(_store.names_for_type(1) == CoworkerNames.defaults_for(1), "typing alone saves nothing")
	_press(screen, "Next")
	_expect(_store.names_for_type(1) == PackedStringArray(["Bo Ss"]), "the arrow saves the shown boxes first")
	_press(screen, "Previous")
	_expect(_box(screen, 0).text == "Bo Ss", "coming back shows the saved name")


func _check_defaults_restore_the_shown_pool_only(screen: Node) -> void:
	_press(screen, "Next")
	_type(screen, 0, "Sekretarka")
	_press(screen, "Previous")
	_type(screen, 0, "Unsaved")
	_press(screen, "Defaults")
	_expect(_box(screen, 0).text == "Roy Behr", "Domyślne puts the boss's name back and drops the typing")
	_expect(_store.names_for_type(1) == CoworkerNames.defaults_for(1), "the boss's pool is the default again")
	_expect(_store.names_for_type(2) == PackedStringArray(["Sekretarka"]), "Domyślne leaves the other pools alone")
	_store.reset_names_for_type(2)


func _check_an_empty_box_is_saved_empty(screen: Node) -> void:
	_type(screen, 0, "")
	_press(screen, "Next")
	_expect(_store.names_for_type(1) == PackedStringArray([""]), "an empty box is saved as an empty name")
	_press(screen, "Previous")
	_press(screen, "Defaults")


# Typed through the input pipeline, since setting the text or inserting it from code raises
# no text_changed.
func _check_sharp_s_is_refused(screen: Node) -> void:
	var box := _box(screen, 0)
	box.text = ""
	box.grab_focus()
	box.edit()
	for character in "Straße":
		var key := InputEventKey.new()
		key.pressed = true
		key.unicode = character.unicode_at(0)
		Input.parse_input_event(key)
		await process_frame
	# The box raises text_changed deferred, a frame after the key lands.
	await process_frame
	_expect(box.text == "Strae", "the box refuses ß as sub_45C880 does, got %s" % box.text)
	var shadow := screen.get_node("SafeFrame/NameShadow0") as Label
	_expect(shadow.text == box.text, "the shadow follows what is typed, got %s under %s" % [shadow.text, box.text])
	box.unedit()
	_press(screen, "Defaults")


func _check_the_screen_plays_menu2(manager: Node) -> void:
	_expect(
		manager._menu_music_for(ScreenManagerScript.Screen.COWORKER_NAMES) == load("res://audio/music/menu2.ogg"),
		"screen 13 starts Menu2, as sub_4079C0 does"
	)


func _check_main_menu_saves_and_leaves(screen: Node, manager: Node) -> void:
	_press(screen, "Next")
	_type(screen, 0, "Ed")
	_press(screen, "MainMenu")
	_expect(_store.names_for_type(2) == PackedStringArray(["Ed"]), "Główne menu saves the shown pool first")
	_expect(manager.current == ScreenManagerScript.Screen.MAIN_MENU, "Główne menu goes back to screen 3")
