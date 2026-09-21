extends Node

enum Screen {
	BOOT_LOADING,
	MAIN_MENU,
	CHARACTER_SELECT,
	LEVEL_TREE,
	LEVEL_1,
	LEVEL_RESULT,
}

const _SCENE_PATHS := {
	Screen.BOOT_LOADING: "res://scenes/screens/boot_loading.tscn",
	Screen.MAIN_MENU: "res://scenes/screens/main_menu.tscn",
	Screen.CHARACTER_SELECT: "res://scenes/screens/character_select.tscn",
	Screen.LEVEL_TREE: "res://scenes/screens/level_tree.tscn",
	Screen.LEVEL_1: "res://scenes/level_1.tscn",
	Screen.LEVEL_RESULT: "res://scenes/screens/level_result.tscn",
}

const _PROFILES := {
	&"jobless": preload("res://scenes/player/profiles/jobless.tres"),
	&"anne": preload("res://scenes/player/profiles/anne.tres"),
}

const _MENU_MUSIC_STREAM: AudioStream = preload("res://audio/music/menu1.ogg")

const DEFAULT_CHARACTER: StringName = &"jobless"
const DEFAULT_PLAYER_NAMES := {
	&"jobless": "Jo Bless",
	&"anne": "Anne Employed",
}
const PLAYER_NAME_MAX_LENGTH := 16

var current: Screen = Screen.BOOT_LOADING
var selected_game_mode: StringName = &"time"
var last_level_won := false
var selected_character: StringName = DEFAULT_CHARACTER
var player_name: String = get_default_player_name(DEFAULT_CHARACTER)
var _menu_music_player: AudioStreamPlayer


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F1:
		toggle_window_mode()
		get_viewport().set_input_as_handled()


func _ready() -> void:
	_menu_music_player = AudioStreamPlayer.new()
	_menu_music_player.name = "MenuMusic"
	_menu_music_player.stream = _MENU_MUSIC_STREAM
	_menu_music_player.volume_db = -6.0
	_menu_music_player.finished.connect(_on_menu_music_finished)
	add_child(_menu_music_player)
	_sync_menu_music()


func change_to(screen: Screen) -> void:
	current = screen
	_sync_menu_music()
	get_tree().change_scene_to_file(_SCENE_PATHS[screen])


func change_to_main_menu() -> void:
	change_to(Screen.MAIN_MENU)


func change_to_level_tree() -> void:
	change_to(Screen.LEVEL_TREE)


# A level reports its own outcome; sub_407370 sends both results to their own screen.
func report_level_finished(won: bool) -> void:
	last_level_won = won
	change_to(Screen.LEVEL_RESULT)


func start_game_setup(game_mode: StringName) -> void:
	selected_game_mode = game_mode
	change_to(Screen.CHARACTER_SELECT)


func select_character(character_id: StringName) -> void:
	if not _PROFILES.has(character_id):
		push_warning("Unknown character profile: %s" % String(character_id))
		return
	selected_character = character_id


func set_player_name(new_name: String) -> void:
	player_name = new_name.strip_edges().substr(0, PLAYER_NAME_MAX_LENGTH)
	if player_name == "":
		player_name = get_default_player_name(selected_character)


func reset_player_setup() -> void:
	selected_character = DEFAULT_CHARACTER
	player_name = get_default_player_name(selected_character)


func get_default_player_name(character_id: StringName = selected_character) -> String:
	return String(DEFAULT_PLAYER_NAMES.get(character_id, DEFAULT_PLAYER_NAMES[DEFAULT_CHARACTER]))


func get_selected_profile() -> Resource:
	return _PROFILES.get(selected_character, _PROFILES[&"jobless"])


func _sync_menu_music() -> void:
	if _menu_music_player == null:
		return
	if _is_menu_screen(current):
		if not _menu_music_player.playing:
			_menu_music_player.play()
	else:
		_menu_music_player.stop()


func _is_menu_screen(screen: Screen) -> bool:
	return screen == Screen.MAIN_MENU or screen == Screen.CHARACTER_SELECT or screen == Screen.LEVEL_TREE


func _on_menu_music_finished() -> void:
	if _is_menu_screen(current):
		_menu_music_player.play()


func toggle_window_mode() -> void:
	var mode := DisplayServer.window_get_mode()
	if mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
