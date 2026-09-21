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
	_check_mode_selection()
	_check_player_name_rules()
	_check_result_routing()
	await _check_result_screen_shows_the_outcome()

	_manager.reset_player_setup()
	_manager.selected_game_mode = &"time"
	_manager.last_level_won = false
	if _failures == 0:
		print("Screen flow: scene paths, game-mode selection, name rules and result routing passed")
	quit(1 if _failures else 0)


func _expect(condition: bool, label: String) -> void:
	if not condition:
		_failures += 1
		push_error(label)


func _check_screens_resolve() -> void:
	for screen: int in ScreenManagerScript.Screen.values():
		var path: String = ScreenManagerScript._SCENE_PATHS[screen]
		_expect(ResourceLoader.exists(path), "screen %d resolves to %s" % [screen, path])


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


func _check_result_screen_shows_the_outcome() -> void:
	var scene := load("res://scenes/screens/level_result.tscn") as PackedScene
	for won in [true, false]:
		_manager.last_level_won = won
		var result := scene.instantiate()
		root.add_child(result)
		await process_frame
		var image := result.get_node("Image") as TextureRect
		var expected := "win.png" if won else "lose.png"
		_expect(
			image.texture != null and image.texture.resource_path.ends_with(expected),
			"the result screen shows %s" % expected
		)
		root.remove_child(result)
		result.free()
