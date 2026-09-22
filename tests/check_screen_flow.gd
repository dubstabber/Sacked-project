extends SceneTree


const ScreenManagerScript := preload("res://autoloads/screen_manager.gd")

var _failures := 0
var _manager: Node


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	# Autoloads are live under --script, so use the real one rather than a second copy:
	# the screens resolve it by path and would find the autoload, not the copy.
	_manager = root.get_node_or_null("ScreenManager")
	if _manager == null:
		push_error("the ScreenManager autoload is missing")
		quit(1)
		return
	await process_frame

	_check_screens_resolve()
	_check_level_selection()
	_check_mode_selection()
	_check_player_name_rules()
	_check_result_routing()
	_check_the_tree_reaches_a_level_through_its_description()
	_check_each_screen_asks_for_its_own_music()
	await _check_result_screen_shows_the_outcome()
	await _check_lost_level_returns_to_a_fresh_run()
	await _check_the_name_box_carries_the_original_caption()

	_manager.reset_player_setup()
	_manager.selected_game_mode = &"time"
	_manager.last_level_won = false
	if _failures == 0:
		print("Screen flow: scene paths, level selection, mode selection, name rules, result routing, the name caption and the retry round trip passed")
	quit(1 if _failures else 0)


func _expect(condition: bool, label: String) -> void:
	if not condition:
		_failures += 1
		push_error(label)


func _check_screens_resolve() -> void:
	for screen: int in ScreenManagerScript.Screen.values():
		var path: String = _manager.scene_path(screen)
		_expect(ResourceLoader.exists(path), "screen %d resolves to %s" % [screen, path])


func _check_level_selection() -> void:
	_expect(_manager.selected_level == 1, "the first level is selected by default")
	_expect(_manager.is_level_available(1), "level 1 is imported")
	_expect(not _manager.is_level_available(0), "level 0 is not a level")
	_expect(not _manager.is_level_available(ScreenManagerScript.LEVEL_COUNT + 1), "there are only 21 levels")

	var levels: Array = _manager.available_levels()
	_expect(not levels.is_empty(), "the tree offers the imported levels")
	_expect(int(levels[0]) == 1, "the imported levels are listed in order")
	for level: int in levels:
		_expect(
			String(_manager.level_scene_path(level)) == "res://scenes/level_%d.tscn" % level,
			"level %d resolves to its own scene" % level
		)

	# An unimported level is refused rather than sending the game to a missing scene.
	var last := int(levels[levels.size() - 1])
	_manager.selected_level = last
	_manager.start_level(ScreenManagerScript.LEVEL_COUNT)
	if not _manager.is_level_available(ScreenManagerScript.LEVEL_COUNT):
		_expect(_manager.selected_level == last, "an unimported level leaves the selection alone")
	_manager.selected_level = 1


func _check_mode_selection() -> void:
	# The original writes the S-file flag from the first two main-menu buttons; the port
	# keeps the same two modes. See docs/game-rules-reference.md.
	_expect(_manager.selected_game_mode == &"time", "the default mode is the time game")
	_manager.start_game_setup(&"points")
	_expect(_manager.selected_game_mode == &"points", "the points game is selectable")
	_manager.selected_game_mode = &"time"


func _check_player_name_rules() -> void:
	_manager.select_character(&"anne")
	_expect(_manager.selected_character == &"anne", "a known character is selectable")
	_manager.select_character(&"nobody")
	_expect(_manager.selected_character == &"anne", "an unknown character is rejected")
	_manager.set_player_name("   ")
	_expect(_manager.player_name == _manager.get_default_player_name(), "a blank name falls back to the default")
	_manager.set_player_name("A very long name indeed")
	_expect(_manager.player_name.length() <= ScreenManagerScript.PLAYER_NAME_MAX_LENGTH, "names are truncated")
	_manager.reset_player_setup()
	_expect(_manager.selected_character == ScreenManagerScript.DEFAULT_CHARACTER, "the setup resets")


func _check_result_routing() -> void:
	_expect(not _manager.last_level_won, "no result is recorded before a level ends")
	_manager.last_level_won = true
	_expect(_manager.last_level_won, "a win is recorded for the result screen")
	_manager.last_level_won = false


# sub_407370 asks for a track on four cases only: Menu1 for the loading and menu screens and
# Menu2 for the coworker-names and highscore screens. Everything downstream of the menu keeps
# what is already playing, and a level stops it.
func _check_each_screen_asks_for_its_own_music() -> void:
	var menu1 := load("res://audio/music/menu1.ogg")
	var menu2 := load("res://audio/music/menu2.ogg")
	for screen: int in [
		ScreenManagerScript.Screen.MAIN_MENU,
		ScreenManagerScript.Screen.CHARACTER_SELECT,
		ScreenManagerScript.Screen.LEVEL_TREE,
		ScreenManagerScript.Screen.LEVEL_DESCRIPTION,
	]:
		_expect(_manager._menu_music_for(screen) == menu1, "screen %d keeps Menu1 playing" % screen)
	_expect(
		_manager._menu_music_for(ScreenManagerScript.Screen.HIGHSCORES) == menu2,
		"the highscore board is the one shell screen that changes the track"
	)
	for screen: int in [ScreenManagerScript.Screen.LEVEL, ScreenManagerScript.Screen.LEVEL_RESULT]:
		_expect(_manager._menu_music_for(screen) == null, "screen %d plays no menu music" % screen)


# sub_403F20's case 15 sends a tree node to the description screen, and its case 16 sends
# Kontynuuj into the level. There is no route from the tree straight into a level.
func _check_the_tree_reaches_a_level_through_its_description() -> void:
	var before: int = _manager.selected_level
	_manager.open_level_description(2)
	_expect(
		_manager.current == ScreenManagerScript.Screen.LEVEL_DESCRIPTION,
		"a tree node opens the description screen"
	)
	_expect(_manager.selected_level == 2, "the description screen is told which level it describes")

	_manager.start_level(2)
	_expect(_manager.current == ScreenManagerScript.Screen.LEVEL, "Kontynuuj starts the level it describes")

	# A level with no scene still gets a description screen; only the start is refused.
	_manager.open_level_description(ScreenManagerScript.LEVEL_COUNT)
	_expect(
		_manager.current == ScreenManagerScript.Screen.LEVEL_DESCRIPTION,
		"an unimported level still opens its description"
	)
	_manager.selected_level = before


# The whole way round: a lost level reaches the result screen, Powtórz restarts it, and the
# next run starts from zero and still reports its own outcome.
func _check_lost_level_returns_to_a_fresh_run() -> void:
	var scene := load("res://scenes/level_1.tscn") as PackedScene

	var first := scene.instantiate()
	var lost: Node = first.get_node_or_null("LevelRuntime")
	if lost == null:
		_expect(false, "the level scene carries its session")
		first.free()
		return
	lost.enabled = false
	root.add_child(first)
	await process_frame
	lost.mode = &"time"
	lost.add_score(lost.target_score() - 1)
	lost.advance(lost.limit_seconds() + 1.0)
	_expect(lost.is_finished and not lost.won, "the clock passing the limit loses the level")
	_expect(not _manager.last_level_won, "the autoload records the loss")
	_expect(_manager.current == ScreenManagerScript.Screen.LEVEL_RESULT, "a finished level shows the result screen")
	root.remove_child(first)
	first.free()

	var result := (load("res://scenes/screens/level_result.tscn") as PackedScene).instantiate()
	root.add_child(result)
	await process_frame
	# A loss offers Powtórz, which sub_407370's case 9 turns into a clean reload of the
	# same level rather than a trip back through the tree.
	(result.get_node("SafeFrame/Forward") as TextureButton).pressed.emit()
	await process_frame
	_expect(_manager.current == ScreenManagerScript.Screen.LEVEL, "Powtórz restarts the level that was lost")
	root.remove_child(result)
	result.free()

	var second := scene.instantiate()
	var again: Node = second.get_node_or_null("LevelRuntime")
	again.enabled = false
	root.add_child(second)
	await process_frame
	_expect(again.score == 0, "the next run starts with no score")
	_expect(again.elapsed == 0.0 and not again.is_finished, "the next run starts with a fresh clock")
	again.mode = &"time"
	again.add_score(again.target_score())
	again.advance(1.0)
	_expect(_manager.last_level_won, "the next run reports its own outcome")
	root.remove_child(second)
	second.free()


func _check_result_screen_shows_the_outcome() -> void:
	var scene := load("res://scenes/screens/level_result.tscn") as PackedScene
	for won in [true, false]:
		_manager.last_level_won = won
		var result := scene.instantiate()
		root.add_child(result)
		await process_frame
		var image := result.get_node("SafeFrame/Image") as TextureRect
		var expected := "win.png" if won else "lose.png"
		_expect(
			image.texture != null and image.texture.resource_path.ends_with(expected),
			"the result screen shows %s" % expected
		)
		root.remove_child(result)
		result.free()


# Slot 219 is the character-select screen's own caption for the name box, not an invention:
# the original draws it over two lines to the left of the box.
func _check_the_name_box_carries_the_original_caption() -> void:
	var i18n: Node = root.get_node_or_null("I18n")
	if i18n == null:
		_expect(false, "the I18n autoload is available to the screens")
		return
	var restore: StringName = i18n.current_language()
	i18n.set_language(&"pl")
	var screen := (load("res://scenes/screens/character_select.tscn") as PackedScene).instantiate()
	root.add_child(screen)
	await process_frame
	var caption: Label = screen.get_node_or_null("SafeFrame/NameLabel")
	_expect(caption != null, "the character-select screen labels its name box")
	if caption != null:
		_expect(caption.text == "highscore.name_prompt", "the caption is the original's slot 219")
		_expect(
			caption.atr(caption.text) == "Imię do tabeli najlepszych wyników",
			"slot 219 reads what the original's screen 12 shows"
		)
		_expect(
			caption.autowrap_mode != TextServer.AUTOWRAP_OFF,
			"the caption wraps, because it is two lines wide in the original"
		)
	root.remove_child(screen)
	screen.free()
	i18n.set_language(restore)

