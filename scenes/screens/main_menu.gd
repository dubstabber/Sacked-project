extends Control

# The six entries sub_407370's screen 3 builds, in its own order. A Label translates its
# own text, so the key goes in as-is and follows the language live.
const _BUTTON_KEYS := [
	"menu.time_game",
	"menu.points_game",
	"menu.highscores",
	"menu.names",
	"menu.sound",
	"menu.quit",
]


func _ready() -> void:
	for i in _BUTTON_KEYS.size():
		var btn: TextureButton = get_node("SafeFrame/Buttons/Button%d" % (i + 1))
		btn.get_node("Label").text = _BUTTON_KEYS[i]
		btn.pressed.connect(_on_button_pressed.bind(i))


func _on_button_pressed(index: int) -> void:
	match index:
		0:
			get_node("/root/ScreenManager").call("start_game_setup", &"time")
		1:
			get_node("/root/ScreenManager").call("start_game_setup", &"points")
		2:
			get_node("/root/ScreenManager").call("change_to_highscores")
		5:
			get_tree().quit()
		_:
			print("[main_menu] stub: %s" % tr(_BUTTON_KEYS[index]))
