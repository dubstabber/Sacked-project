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

# The main menu animates three things every frame (sub_423630, sub_423710, sub_423AE0), with
# the constants tools/export_menu_animation.py reads out of sacked.exe. See "What every menu
# screen shares" in docs/shell-reference.md.
const OriginalData := preload("res://scenes/shared/original_data.gd")
const _ANIM_PATH := "res://resources/original/menu_animation.json"

# The character orbits a radius-32 circle about these (mov ecx, 40h / mov edx, 20h in
# sub_423AE0); its top-left is the anchor, so centered is false.
const _CHAR_CENTRE := Vector2(64.0, 32.0)

@onready var _background: Sprite2D = $SafeFrame/Background
@onready var _char: Sprite2D = $SafeFrame/Char

var _buttons: Array[TextureButton] = []
var _button_base_y: Array[float] = []

var _rotation_step := 0.0
var _sway_amplitude := 0.0
var _button_base_x := 0.0
var _button_phase_step := 0.0
var _char_orbit_rate := 0.0
var _char_orbit_amplitude := 0.0

# The swirl's angle (menu+1260, += a fixed step a frame) and the sway/orbit phase (menu+1264,
# += the frame delta), both starting at 0 as the ctor zeroes them.
var _angle := 0.0
var _phase := 0.0


func _ready() -> void:
	var anim := OriginalData.load_original(_ANIM_PATH)
	_rotation_step = float(anim.get("background_rotation_step", 0.0))
	_sway_amplitude = float(anim.get("button_sway_amplitude", 0.0))
	_button_base_x = float(anim.get("button_base_x", 0.0))
	_button_phase_step = float(anim.get("button_phase_step", 0.0))
	_char_orbit_rate = float(anim.get("char_orbit_rate", 0.0))
	_char_orbit_amplitude = float(anim.get("char_orbit_amplitude", 0.0))

	for i in _BUTTON_KEYS.size():
		var btn: TextureButton = get_node("SafeFrame/Buttons/Button%d" % (i + 1))
		btn.get_node("Label").text = _BUTTON_KEYS[i]
		btn.pressed.connect(_on_button_pressed.bind(i))
		_buttons.append(btn)
		_button_base_y.append(btn.position.y)

	_apply_animation()


func _process(delta: float) -> void:
	# menu+1260 += 0.01 a frame (sub_423710); menu+1264 += the clock's frame delta (sub_423630).
	_angle += _rotation_step
	_phase += delta
	_apply_animation()


func _apply_animation() -> void:
	_background.rotation = _angle

	# Button i's x = sin(i * 2*pi/10 + phase) * 32 + 380 (sub_423630); its y keeps its row.
	for i in _buttons.size():
		var x := sin(float(i) * _button_phase_step + _phase) * _sway_amplitude + _button_base_x
		_buttons[i].position = Vector2(x, _button_base_y[i])

	# The character orbits (64, 32) at pi/4 (sub_423AE0): x = 64 - sin(phase*rate)*(-32),
	# y = 32 - cos(phase*rate)*32.
	var a := _phase * _char_orbit_rate
	_char.position = Vector2(
		_CHAR_CENTRE.x - sin(a) * _char_orbit_amplitude,
		_CHAR_CENTRE.y - cos(a) * _sway_amplitude,
	)


func _on_button_pressed(index: int) -> void:
	match index:
		0:
			get_node("/root/ScreenManager").call("start_game_setup", &"time")
		1:
			get_node("/root/ScreenManager").call("start_game_setup", &"points")
		2:
			get_node("/root/ScreenManager").call("change_to_highscores")
		3:
			get_node("/root/ScreenManager").call("change_to_coworker_names")
		4:
			get_node("/root/ScreenManager").call("change_to_sound_setup")
		5:
			get_tree().quit()
