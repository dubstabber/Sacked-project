extends Node

enum Screen {
	BOOT_LOADING,
	MAIN_MENU,
	LEVEL_TREE,
	LEVEL_1,
}

const _SCENE_PATHS := {
	Screen.BOOT_LOADING: "res://scenes/screens/boot_loading.tscn",
	Screen.MAIN_MENU: "res://scenes/screens/main_menu.tscn",
	Screen.LEVEL_TREE: "res://scenes/screens/level_tree.tscn",
	Screen.LEVEL_1: "res://scenes/level_1.tscn",
}

const _PROFILES := {
	&"jobless": preload("res://scenes/player/profiles/jobless.tres"),
	&"anne": preload("res://scenes/player/profiles/anne.tres"),
}

var current: Screen = Screen.BOOT_LOADING
var selected_character: StringName = &"jobless"


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F1:
		toggle_window_mode()
		get_viewport().set_input_as_handled()


func change_to(screen: Screen) -> void:
	current = screen
	get_tree().change_scene_to_file(_SCENE_PATHS[screen])


func change_to_level_tree() -> void:
	change_to(Screen.LEVEL_TREE)


func select_character(character_id: StringName) -> void:
	selected_character = character_id


func get_selected_profile() -> Resource:
	return _PROFILES.get(selected_character, _PROFILES[&"jobless"])


func toggle_window_mode() -> void:
	var mode := DisplayServer.window_get_mode()
	if mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
