extends Node

enum Screen {
	BOOT_LOADING,
	MAIN_MENU,
	CHARACTER_SELECT,
	LEVEL_TREE,
	LEVEL_DESCRIPTION,
	LEVEL,
	LEVEL_RESULT,
	HIGHSCORES,
}

# Screen.LEVEL resolves through selected_level instead, so it has no entry here.
const _SCENE_PATHS := {
	Screen.BOOT_LOADING: "res://scenes/screens/boot_loading.tscn",
	Screen.MAIN_MENU: "res://scenes/screens/main_menu.tscn",
	Screen.CHARACTER_SELECT: "res://scenes/screens/character_select.tscn",
	Screen.LEVEL_TREE: "res://scenes/screens/level_tree.tscn",
	Screen.LEVEL_DESCRIPTION: "res://scenes/screens/level_description.tscn",
	Screen.LEVEL_RESULT: "res://scenes/screens/level_result.tscn",
	Screen.HIGHSCORES: "res://scenes/screens/highscores.tscn",
}

# The original's level tree offers buttons 1 to 21; sub_408D00 turns button n into the
# original's level index n - 1. See docs/game-rules-reference.md.
const LEVEL_COUNT := 21

const _PROFILES := {
	&"jobless": preload("res://scenes/player/profiles/jobless.tres"),
	&"anne": preload("res://scenes/player/profiles/anne.tres"),
}

# sub_407370 asks for a track on four cases only: Menu1 on the loading and menu screens,
# Menu2 on the coworker-names and highscore screens. Every other screen keeps what is
# already playing, which is why the tree and the description screen are on this list too.
const _MENU1: AudioStream = preload("res://audio/music/menu1.ogg")
const _MENU2: AudioStream = preload("res://audio/music/menu2.ogg")

const DEFAULT_CHARACTER: StringName = &"jobless"
const DEFAULT_PLAYER_NAMES := {
	&"jobless": "Jo Bless",
	&"anne": "Anne Employed",
}
const PLAYER_NAME_MAX_LENGTH := 16

var current: Screen = Screen.BOOT_LOADING
var selected_level := 1
var selected_game_mode: StringName = &"time"
var last_level_won := false
# game+19052: how many duels have happened. The duel about to start is two casts longer than
# this, and the counter itself stops at nine. See docs/minigame-reference.md.
var duels_fought := 0
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
	_menu_music_player.bus = &"Music"
	_menu_music_player.finished.connect(_on_menu_music_finished)
	add_child(_menu_music_player)
	_sync_menu_music()


func change_to(screen: Screen) -> void:
	current = screen
	_sync_menu_music()
	get_tree().change_scene_to_file(scene_path(screen))


func scene_path(screen: Screen) -> String:
	if screen == Screen.LEVEL:
		return level_scene_path(selected_level)
	return String(_SCENE_PATHS[screen])


func level_scene_path(level: int) -> String:
	return "res://scenes/level_%d.tscn" % level


# ResourceLoader rather than a directory listing, so this also answers in an exported build.
func is_level_available(level: int) -> bool:
	if level < 1 or level > LEVEL_COUNT:
		return false
	return ResourceLoader.exists(level_scene_path(level))


func available_levels() -> Array[int]:
	var levels: Array[int] = []
	for level in range(1, LEVEL_COUNT + 1):
		if is_level_available(level):
			levels.append(level)
	return levels


# sub_403F20's case 15: a tree node opens the description screen, which is the only route
# into a level. The button for a locked level is inert rather than absent, so the guard is
# here rather than at the click.
func open_level_description(level: int) -> void:
	if level < 1 or level > LEVEL_COUNT:
		push_warning("No level %d" % level)
		return
	selected_level = level
	change_to(Screen.LEVEL_DESCRIPTION)


func start_level(level: int) -> void:
	if not is_level_available(level):
		push_warning("No imported level %d" % level)
		return
	selected_level = level
	change_to(Screen.LEVEL)


func change_to_main_menu() -> void:
	change_to(Screen.MAIN_MENU)


func change_to_level_tree() -> void:
	change_to(Screen.LEVEL_TREE)


func change_to_highscores() -> void:
	change_to(Screen.HIGHSCORES)


# sub_407370's case 9: tear the level down and load the same .col again. It keeps nothing --
# the sequence is the one case 1 runs on a fresh start -- and it lands on screen 1, not 9.
func restart_level() -> void:
	change_to(Screen.LEVEL)


const DUEL_EXTRA_CASTS := 2
const DUEL_COUNT_LIMIT := 9


# sub_406430 hands the duel the counter plus two, then advances it and clamps it, so each
# time the player is caught the sequence they have to repeat is one longer.
func begin_duel() -> int:
	var casts := duels_fought + DUEL_EXTRA_CASTS
	duels_fought = mini(duels_fought + 1, DUEL_COUNT_LIMIT)
	return casts


# A level reports its own outcome; sub_407370 sends both results to their own screen.
# sub_406E70 records on the way past, and only for a win -- the loss path writes nothing.
func report_level_finished(won: bool, score: int = 0, elapsed_seconds: float = 0.0) -> void:
	last_level_won = won
	var progress := get_node_or_null("/root/ProgressStore")
	if progress != null:
		progress.call(
			"record_result", selected_level, selected_game_mode, won, score, elapsed_seconds, player_name
		)
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
	var wanted := _menu_music_for(current)
	if wanted == null:
		_menu_music_player.stop()
		return
	if _menu_music_player.stream != wanted:
		_menu_music_player.stream = wanted
		_menu_music_player.play()
	elif not _menu_music_player.playing:
		_menu_music_player.play()


func _menu_music_for(screen: Screen) -> AudioStream:
	if screen == Screen.HIGHSCORES:
		return _MENU2
	if _is_menu_screen(screen):
		return _MENU1
	return null


func _is_menu_screen(screen: Screen) -> bool:
	# sub_407370 starts Menu1 for the menu and keeps it running across the screens that
	# follow: the tree and the description screen ask for no music of their own.
	return (
		screen == Screen.MAIN_MENU
		or screen == Screen.CHARACTER_SELECT
		or screen == Screen.LEVEL_TREE
		or screen == Screen.LEVEL_DESCRIPTION
	)


func _on_menu_music_finished() -> void:
	if _menu_music_for(current) != null:
		_menu_music_player.play()


func toggle_window_mode() -> void:
	var mode := DisplayServer.window_get_mode()
	if mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
