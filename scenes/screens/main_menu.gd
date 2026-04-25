extends Control

const _BUTTON_LABELS := [
	"Gra na czas",
	"Gra na punkty",
	"Najlepsze wyniki",
	"Imiona",
	"Dźwięk i muzyka",
	"Wyjście",
]


func _ready() -> void:
	for i in _BUTTON_LABELS.size():
		var btn: TextureButton = get_node("Buttons/Button%d" % (i + 1))
		btn.get_node("Label").text = _BUTTON_LABELS[i]
		btn.pressed.connect(_on_button_pressed.bind(i))
	$Music.play()


func _on_button_pressed(index: int) -> void:
	match index:
		0:
			ScreenManager.change_to(ScreenManager.Screen.LEVEL_TREE)
		5:
			get_tree().quit()
		_:
			print("[main_menu] stub: %s" % _BUTTON_LABELS[index])
