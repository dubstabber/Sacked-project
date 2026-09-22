extends Control

# Screens 7 and 8 in the original (`CWinScreen` and `CLooseScreen`). Each is its own
# full-screen picture plus two buttons at the same two places; neither draws any text of its
# own, so there is no score or time here.
#
# Where the second button leads differs, and the win screen's caption is misleading:
# `Następny poziom` goes back to the **level tree**, where whatever this win just opened has
# turned from locked to playable. See docs/shell-reference.md.
#
# The original starts S1100 on entering this screen; the port already plays it from
# LevelAudio the moment the level reports its win, which is the same beat.

const WIN_TEXTURE := preload("res://images/gui/screens/win.png")
const LOSE_TEXTURE := preload("res://images/gui/screens/lose.png")

@onready var _screens: Node = get_node_or_null("/root/ScreenManager")

var _won := false


func _ready() -> void:
	_won = _screens != null and bool(_screens.get("last_level_won"))
	($SafeFrame/Image as TextureRect).texture = WIN_TEXTURE if _won else LOSE_TEXTURE

	($SafeFrame/Back/Label as Label).text = "common.main_menu"
	($SafeFrame/Forward/Label as Label).text = "result.next_level" if _won else "result.retry"
	($SafeFrame/Back as TextureButton).pressed.connect(_on_back_pressed)
	($SafeFrame/Forward as TextureButton).pressed.connect(_on_forward_pressed)


func _on_back_pressed() -> void:
	if _screens != null:
		_screens.call("change_to_main_menu")


func _on_forward_pressed() -> void:
	if _screens == null:
		return
	# A win returns to the tree; a loss reloads the same level from zero.
	if _won:
		_screens.call("change_to_level_tree")
	else:
		_screens.call("restart_level")
