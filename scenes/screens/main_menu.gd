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


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return

	match event.keycode:
		KEY_J:
			_select_debug_character(&"jobless")
		KEY_A:
			_select_debug_character(&"anne")


func _on_button_pressed(index: int) -> void:
	match index:
		0:
			get_node("/root/ScreenManager").call("change_to_level_tree")
		5:
			get_tree().quit()
		_:
			print("[main_menu] stub: %s" % _BUTTON_LABELS[index])


func _select_debug_character(character_id: StringName) -> void:
	get_node("/root/ScreenManager").call("select_character", character_id)
	print("[main_menu] selected character: %s" % character_id)
