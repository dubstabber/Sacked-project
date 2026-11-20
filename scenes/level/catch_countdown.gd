extends Control

# The duel countdown, m_pTime: a CGUIFNumber digit strip (sub_45C190), not Arial text. Each of
# the two digits is blitted out of CO_GUI_CONSOLE_NUMBERS 14 px wide, sourced at y = 25 * digit
# (the pitch +108 = 25), and a changed digit eases toward its new row by 4 px a frame
# (+120 = 4.0, with +112 clear), so a digit that changes slides through the strip. Digit i sits
# at x = (i + 1) * 14 + i * 3 from m_pTime's own (370, 60) (0x45C38E-0x45C3A5), which lands the
# two digits at 384 and 401. See docs/minigame-reference.md, "The countdown is a digit strip",
# and docs/hud-reference.md, "The digit strip".

const STRIP := preload("res://images/gui/hud/numbers.png")
const CELL_W := 14
const PITCH := 25
const GAP := 3
const EASE := 4.0
const DIGITS := 2

var value := 0: set = _set_value

var _targets := PackedFloat32Array([0.0, 0.0])
var _offsets := PackedFloat32Array([0.0, 0.0])
var _settled := false


func digit_x(index: int) -> float:
	# The local x of digit `index`'s left edge; add the node's position for the frame coordinate.
	return float((index + 1) * CELL_W + index * GAP)


func _set_value(new_value: int) -> void:
	value = clampi(new_value, 0, 99)
	var text := "%02d" % value
	for i in DIGITS:
		_targets[i] = float(int(text[i]) * PITCH)
	# The first value shown snaps; later changes roll.
	if not _settled:
		for i in DIGITS:
			_offsets[i] = _targets[i]
		_settled = true
	queue_redraw()


func _process(_delta: float) -> void:
	var moved := false
	for i in DIGITS:
		var next := move_toward(_offsets[i], _targets[i], EASE)
		if next != _offsets[i]:
			_offsets[i] = next
			moved = true
	if moved:
		queue_redraw()


func _draw() -> void:
	for i in DIGITS:
		draw_texture_rect_region(
			STRIP,
			Rect2(digit_x(i), 0.0, float(CELL_W), float(PITCH)),
			Rect2(0.0, _offsets[i], float(CELL_W), float(PITCH)),
		)
