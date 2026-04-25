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

var current: Screen = Screen.BOOT_LOADING


func change_to(screen: Screen) -> void:
	current = screen
	get_tree().change_scene_to_file(_SCENE_PATHS[screen])
