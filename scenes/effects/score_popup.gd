extends Node2D

# The score numbers that float off whatever earned them. sub_40A0D0 queues one,
# sub_40A310 ages every one of them by the frame delta and drops the expired, and
# sub_40A390 draws them. See docs/hud-reference.md.

const FONT := preload("res://images/gui/fonts/score-digits.png")

# CO_EFFECT_FONT_SCORE is 13 glyphs of 24x32 side by side. sub_40A0D0 stores each character
# as `c - 44` and the draw sources it at `24 * (byte - 1)`, so '-' lands on glyph 0, '.' and
# '/' on the two blanks, and '0'..'9' on glyphs 3..12.
const GLYPH_SIZE := Vector2(24.0, 32.0)
const GLYPH_BIAS := 45
const GLYPH_COUNT := 13
# The draw steps 25 pixels per character, one more than a glyph is wide.
const GLYPH_ADVANCE := 25.0
# Each character lags the one before it by 16 steps of the animation tables, and a phase of
# one second is 256 steps.
const GLYPH_PHASE_STEP := 16
const PHASE_SCALE := 256.0
# sub_40A310 drops a number once its phase reaches four.
const LIFETIME := 4.0

# sub_409E40 fills both tables once at startup rather than shipping them as data. They are
# 1280 entries long, which is exactly what a 15-character number at the last live phase can
# reach (1023 + 16 * 14).
const TABLE_SIZE := 1280
const ALPHA_RAMP_END := 64
const ALPHA_HOLD_END := 768
const ALPHA_FADE_END := 1024
# The wobble is a sine of one turn per 256 steps.
const WOBBLE_RATE := 0.024543693

# The number starts one world unit above whatever earned it, and the draw scales a unit of
# height by 59 screen pixels.
const SPAWN_HEIGHT := 59.0
# Drawn after the world and its agents, so over the composite, the characters and a bubble.
const DEPTH_INDEX := 3

var _rise: PackedFloat32Array = PackedFloat32Array()
var _alpha: PackedInt32Array = PackedInt32Array()
var _popups: Array = []


func _enter_tree() -> void:
	add_to_group("score_popups")


func _ready() -> void:
	z_index = DEPTH_INDEX
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_build_tables()


func _process(delta: float) -> void:
	if _popups.is_empty():
		return
	advance(delta)


# Split out so a test can age the numbers without a running tree. sub_40A310 advances every
# phase first and only then drops whatever has run out.
func advance(delta: float) -> void:
	var kept: Array = []
	for popup in _popups:
		popup["phase"] += delta
		if popup["phase"] < LIFETIME:
			kept.append(popup)
	_popups = kept
	queue_redraw()


# sub_40A0D0. The position is where the score was earned, in world pixels.
func spawn(world_position: Vector2, value: int) -> void:
	var glyphs := PackedInt32Array()
	for character in str(value):
		var glyph := character.unicode_at(0) - GLYPH_BIAS
		if glyph < 0 or glyph >= GLYPH_COUNT:
			continue
		glyphs.append(glyph)
	if glyphs.is_empty():
		return
	_popups.append({
		"position": world_position - Vector2(0.0, SPAWN_HEIGHT),
		"glyphs": glyphs,
		"phase": 0.0,
	})
	queue_redraw()


func live_count() -> int:
	return _popups.size()


func rise_at(index: int) -> float:
	return _rise[index] if index >= 0 and index < _rise.size() else 0.0


func alpha_at(index: int) -> int:
	return _alpha[index] if index >= 0 and index < _alpha.size() else 0


func _draw() -> void:
	for popup in _popups:
		var origin: Vector2 = popup["position"]
		var glyphs: PackedInt32Array = popup["glyphs"]
		var base := float(popup["phase"]) * PHASE_SCALE
		for ordinal in range(glyphs.size()):
			var index := int(base + float(GLYPH_PHASE_STEP * ordinal))
			if index < 0 or index >= TABLE_SIZE:
				continue
			var alpha := _alpha[index]
			if alpha <= 0:
				continue
			var source := Rect2(Vector2(GLYPH_SIZE.x * float(glyphs[ordinal]), 0.0), GLYPH_SIZE)
			var at := origin + Vector2(GLYPH_ADVANCE * float(ordinal), -_rise[index])
			draw_texture_rect_region(FONT, Rect2(at, GLYPH_SIZE), source, Color(1.0, 1.0, 1.0, float(alpha) / 255.0))


# sub_409E40, which the original runs once when the player is built.
func _build_tables() -> void:
	_rise.resize(TABLE_SIZE)
	_alpha.resize(TABLE_SIZE)
	for index in range(TABLE_SIZE):
		var phase := float(index) / PHASE_SCALE
		var height := clampf(phase, 0.0, 2.0)
		if phase < 2.0:
			# A straight climb for the first two seconds, stored as a whole pixel count.
			_rise[index] = float(int(height * 72.0))
		else:
			# Then it hangs, bobbing on a sine whose amplitude the same clamp caps at a half.
			var wobble := (sin(float(index) * WOBBLE_RATE) + 1.0) * 0.5 * (clampf(phase, 0.5, 1.0) * 0.5)
			_rise[index] = float(int((height + wobble) * 64.0))
		if index < ALPHA_RAMP_END:
			_alpha[index] = 4 * index
		elif index < ALPHA_HOLD_END:
			_alpha[index] = 255
		elif index < ALPHA_FADE_END:
			# The original writes `-1 - index` into a byte, which is this fade.
			_alpha[index] = (-1 - index) & 0xFF
		else:
			_alpha[index] = 0
