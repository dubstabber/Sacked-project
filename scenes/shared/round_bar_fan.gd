class_name RoundBarFan
extends RefCounted

const Float32 := preload("res://scenes/shared/float32.gd")

# CGUIRoundBarTex::Draw (sub_45AEE0) as the original runs it: a fan of triangles around the
# element's centre, each vertex truncated to a whole pixel and texel, filled one by one by
# sub_457400 with its own Bresenham edges, half-open spans and fixed-point texture steps. The
# fan's rim is a polygon, not a circle, and the texels drift against the pixels along a span,
# so neither can be had from a disc test. tools/export_round_bar_goldens.py runs the original
# under emulation, and tests/check_round_bar.gd holds this to its output pixel for pixel.
# See docs/hud-reference.md, "How the stopwatch is swept".

# Wide enough for the stopwatch's radius of 38 on every side of its centre.
const WINDOW := 80
const NONE := -1

var centre: Vector2i
var radius: float
var step: int
var start_angle: float
var source_width: int
# The texture as RGBA8, or empty to track texel indices only.
var source_rgba: PackedByteArray
# The window's top-left pixel, in the same coordinates as centre.
var origin: Vector2i

var _whole_texels := PackedInt32Array()
var _whole_rgba := PackedByteArray()
var _whole_drawn := 0


func _init(p_centre: Vector2i, p_radius: float, p_step: int, p_start_angle: float, p_source_width: int, p_source_rgba := PackedByteArray()) -> void:
	centre = p_centre
	radius = p_radius
	step = p_step
	start_angle = p_start_angle
	source_width = p_source_width
	source_rgba = p_source_rgba
	@warning_ignore("integer_division")
	origin = centre - Vector2i(WINDOW / 2, WINDOW / 2)
	_reset()


# The sweep at one progress value: [texel index per window pixel (NONE where nothing is drawn),
# the window as RGBA8]. Whole triangles depend only on how many there are, so they are kept
# between calls and only the last, partial one is drawn afresh.
func draw(progress: float) -> Array:
	var r := _f32(radius)
	var start := _f32(start_angle)
	var fraction := _f32(clampf(progress, 0.0, 1.0))
	# 0x45B023: 12.56 / (r * 12.56) * step, the angle one triangle spans.
	var angle_step := _f32(12.56 / (r * 12.56) * float(step))
	var end := _f32(fraction * 6.28 + 0.009999999776482582)
	var limit := _f32(end - angle_step)
	var whole_starts: Array[float] = []
	var t := 0.0
	if limit > 0.0:
		while true:
			whole_starts.append(t)
			var next := t + angle_step
			t = _f32(next)
			if not next < limit:
				break
	if whole_starts.size() < _whole_drawn:
		_reset()
	for index in range(_whole_drawn, whole_starts.size()):
		var a0 := whole_starts[index] + start
		var a1 := a0 + angle_step
		_triangle(a0, a0, a1, _f32(a1), r, _whole_texels, _whole_rgba)
	_whole_drawn = whole_starts.size()

	var texels := _whole_texels.duplicate()
	var rgba := _whole_rgba.duplicate()
	var b0 := t + start
	var b1 := end + start
	_triangle(b0, _f32(b0), b1, _f32(b1), r, texels, rgba)
	return [texels, rgba]


func _reset() -> void:
	_whole_texels = PackedInt32Array()
	_whole_texels.resize(WINDOW * WINDOW)
	_whole_texels.fill(NONE)
	_whole_rgba = PackedByteArray()
	_whole_rgba.resize(WINDOW * WINDOW * 4)
	_whole_drawn = 0


# One triangle of the fan, from angle a0 to a1. The x87 code takes sin of the unrounded angle
# and, for every vertex but a whole triangle's first, cos of the angle stored as a float.
func _triangle(a0: float, a0_cos: float, a1: float, a1_cos: float, r: float, texels: PackedInt32Array, rgba: PackedByteArray) -> void:
	var p1 := _vertex(a1, a1_cos, r)
	var p0 := _vertex(a0, a0_cos, r)
	var apex := int(r)
	_fill(
		[p1[0], p0[0], centre.x], [p1[1], p0[1], centre.y],
		[p1[2], p0[2], apex], [p1[3], p0[3], apex],
		texels, rgba
	)


# x = trunc(r sin a + cx), y = trunc(cy - r cos a), u = trunc((sin a + 1) r), v = trunc(r - r cos a)
# (0x45B05C-0x45B112).
func _vertex(a: float, a_cos: float, r: float) -> Array:
	var s := sin(a)
	var c := cos(a_cos) * r
	return [int(r * s + float(centre.x)), int(float(centre.y) - c), int((s + 1.0) * r), int(r - c)]


# sub_457400: sort the corners by row, step a left and a right edge, and fill each row from
# one past the left edge up to and including the right one, rows one past the top down to the
# bottom inclusive. The texel is the left edge's u, v, stepped across the span.
func _fill(xs: Array, ys: Array, us: Array, vs: Array, texels: PackedInt32Array, rgba: PackedByteArray) -> void:
	var top := [xs[0], ys[0], us[0], vs[0]]
	var middle := [xs[1], ys[1], us[1], vs[1]]
	var bottom := [xs[2], ys[2], us[2], vs[2]]
	if top[1] > middle[1]:
		var swap := top
		top = middle
		middle = swap
	if top[1] > bottom[1]:
		var swap := top
		top = bottom
		bottom = swap
	if middle[1] > bottom[1]:
		var swap := middle
		middle = bottom
		bottom = swap
	var cross: int = (bottom[0] - top[0]) * (middle[1] - top[1]) - (middle[0] - top[0]) * (bottom[1] - top[1])
	var left: Dictionary
	var right: Dictionary
	if cross >= 0:
		left = _edge(top, middle)
		right = _edge(top, bottom)
	else:
		left = _edge(top, bottom)
		right = _edge(top, middle)
	var row: int = top[1] + 1
	var last: int = mini(left.y_end, right.y_end)
	while row <= last:
		_span(row, left, right, texels, rgba)
		row += 1
	if cross >= 0:
		left = _edge(middle, bottom)
	else:
		right = _edge(middle, bottom)
	row = maxi(left.y_start, right.y_start) + 1
	while row <= left.y_end:
		_span(row, left, right, texels, rgba)
		row += 1


# sub_456F10. sub_427900 floors the slope's division; the texture steps divide as C does.
func _edge(from: Array, to: Array) -> Dictionary:
	var dy: int = to[1] - from[1]
	var dx: int = to[0] - from[0]
	var edge := {
		"y_start": from[1], "y_end": to[1],
		"u": from[2] << 12, "v": from[3] << 12, "du": 0, "dv": 0,
		"q": -1, "x": from[0], "err": 0, "lo": 0, "hi": 0,
	}
	if dy == 0:
		return edge
	@warning_ignore("integer_division")
	var q := dx / dy
	if dx < 0 and dx % dy != 0:
		q -= 1
	var remainder := dx - dy * q
	edge.q = q
	edge.x = q + from[0]
	edge.lo = remainder
	edge.err = 2 * remainder - dy
	edge.hi = remainder - dy
	edge.du = ((to[2] - from[2]) << 12) / dy
	edge.dv = ((to[3] - from[3]) << 12) / dy
	return edge


# sub_4570F0: hand back this row's x, then step x, the error term and the texture coordinates.
func _step(edge: Dictionary) -> int:
	var x: int = edge.x
	if edge.err < 0:
		edge.x = x + edge.q
		edge.err += edge.lo
	else:
		edge.x = edge.q + x + 1
		edge.err += edge.hi
	edge.u += edge.du
	edge.v += edge.dv
	return x


func _span(row: int, left: Dictionary, right: Dictionary, texels: PackedInt32Array, rgba: PackedByteArray) -> void:
	var x_left := _step(left)
	var x_right := _step(right)
	var count := x_right - x_left + 1
	var du := 0
	var dv := 0
	if x_right - x_left != -1:
		@warning_ignore("integer_division")
		du = (int(right.u) - int(left.u)) / count
		@warning_ignore("integer_division")
		dv = (int(right.v) - int(left.v)) / count
	var u: int = left.u
	var v: int = left.v
	var local_y := row - origin.y
	for x in range(x_left + 1, x_right + 1):
		var local_x := x - origin.x
		if local_x >= 0 and local_x < WINDOW and local_y >= 0 and local_y < WINDOW:
			var texel := (u >> 12) + source_width * (v >> 12)
			var pixel := local_y * WINDOW + local_x
			texels[pixel] = texel
			if not source_rgba.is_empty() and texel >= 0 and texel * 4 + 3 < source_rgba.size():
				rgba[pixel * 4] = source_rgba[texel * 4]
				rgba[pixel * 4 + 1] = source_rgba[texel * 4 + 1]
				rgba[pixel * 4 + 2] = source_rgba[texel * 4 + 2]
				# The 32bpp blit copies the texel whole and nothing reads its fourth byte.
				rgba[pixel * 4 + 3] = 255
		u += du
		v += dv


static func _f32(value: float) -> float:
	return Float32.f32(value)
