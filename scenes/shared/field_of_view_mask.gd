extends RefCounted

# The selected colleague's field of view, built as sub_428BC0 builds it every frame: a
# 113 x 113 mask at eight texels per tile around the agent, hidden where the floor is out of
# sight, made of the cone (sub_428270), the shadows of sight-blocking cells stamped from the
# tables sub_427DC0 builds (resources/original/fov_tables.json) and the radius disc
# (sub_429770), then turned into the blue each texel adds (sub_429830). Every step reproduces
# the original bit for bit, float32 roundings included; tests/check_field_of_view.gd holds it
# to masks the original itself built under emulation. See docs/field-of-view-reference.md.
#
# The result is the original's, the route to it is not: GDScript is far too slow to walk the
# 12769 bytes the way the original's C does every frame. So the disc and the fills of the
# octants the cone misses are cached images, spans are written with Image.fill_rect, the
# shadow walk looks each cell up once instead of once per sample, and the texels are computed
# eight at a time in the bytes of one integer.

const Float32 := preload("res://scenes/shared/float32.gd")
const ViewAngle := preload("res://scenes/shared/view_angle.gd")

const SIDE := 113
const CENTRE := 56
const TEXELS := SIDE * SIDE
const TABLES_PATH := "res://resources/original/fov_tables.json"
const HIDDEN := Color(1.0, 0.0, 0.0)
# Eight texel lanes of one 64-bit integer, each 0 or 1 once masked.
const LANES := 0x0101010101010101
const FULL_TEXEL_LANES := 0x4040404040404040

# The octants in the order sub_428BC0 walks them, with the axis the walk steps along first
# and the signs of x and z. Only hidden texels are written, so the order changes nothing.
const WALK := [
	[0x01, true, 1, -1], [0x80, true, -1, -1], [0x08, true, 1, 1], [0x10, true, -1, 1],
	[0x02, false, 1, -1], [0x04, false, 1, 1], [0x40, false, -1, -1], [0x20, false, -1, 1],
]
# sub_428270's jump tables 0x428B78 (low sector) and 0x428B98 (high): the sector's edge line
# C-D in texel offsets from the centre, and the corner A of the clip triangle.
const EDGE_TOP := [-56.0, -56.0, 56.0, -56.0]
const EDGE_RIGHT := [56.0, -56.0, 56.0, 56.0]
const EDGE_BOTTOM := [-56.0, 56.0, 56.0, 56.0]
const EDGE_LEFT := [-56.0, -56.0, -56.0, 56.0]
const LOW_CLIP := [
	[EDGE_TOP, 56, 0], [EDGE_RIGHT, 112, 0], [EDGE_RIGHT, 112, 56], [EDGE_BOTTOM, 112, 112],
	[EDGE_BOTTOM, 56, 112], [EDGE_LEFT, 0, 112], [EDGE_LEFT, 0, 56], [EDGE_TOP, 0, 0],
]
const HIGH_CLIP := [
	[EDGE_TOP, 112, 0], [EDGE_RIGHT, 112, 56], [EDGE_RIGHT, 112, 112], [EDGE_BOTTOM, 56, 112],
	[EDGE_BOTTOM, 0, 112], [EDGE_LEFT, 0, 56], [EDGE_LEFT, 0, 0], [EDGE_TOP, 56, 0],
]
# The absent-octant fill (0x428856-0x428B67): a pair of absent octants is one 56 x 56 block,
# a lone one a triangle of 56 spans.
const PAIRS := [[0x03, 0x01, 0x02], [0x0C, 0x04, 0x08], [0x30, 0x10, 0x20], [0xC0, 0x40, 0x80]]
const BLOCKS := {0x03: Rect2i(56, 1, 56, 56), 0x0C: Rect2i(56, 56, 56, 56), 0x30: Rect2i(1, 56, 56, 56), 0xC0: Rect2i(1, 1, 56, 56)}

static var _tables_loaded := false
# Per sample r(r - 1)/2 + j: where its spans start in _spans, which holds a, b pairs for the
# rows k = r - 1 to 55 in order.
static var _sample_start := PackedInt32Array()
static var _spans := PackedByteArray()
# 1 << each span end, so a stamp is one subtraction.
static var _span_bits := PackedInt64Array()
static var _distances := PackedFloat64Array()
# The position of each single bit, for splitting a row of shadow bits into spans.
static var _bit_index := {}

# The original's float32 constants, each rounded to the float32 it is so that its bits match
# the image's. load_tables() reads them. From fov_tables.json: the sector constant 0.022222
# (0x4667D4; not 1/45, see "The cone"; its exact negation at 0x4667D0 serves a negative edge),
# the 12.0 of the node's gate (flt_4652CC), the 7.0 of its diamond (0x4667B8), and the 8.0 that
# turns the radius into texels (0x465878) and the 0.125 the shadow walk steps by (0x465854).
# From view_angles.json, since the smoke and the puddle read it too: the degree constant
# 0.017453 (0x465540; not pi/180). The 0.5, the frame's 56, 112 and 113, 0.0 and -1000.0 stay
# literals: each is exact, and the goldens pin the mask bit for bit. See "The tables" in
# docs/field-of-view-reference.md.
static var INVERSE_45 := 0.0
static var DEGREES := 0.0
static var GATE_TILES := 0.0
static var REACH_TILES := 0.0
static var TEXELS_PER_TILE := 0.0
static var SAMPLE_STEP := 0.0

# The octants the cone touched, as sub_428270 returns them.
var octants := 0
# Byte 2 of each image dword, the blue the draw adds: 0, 8, ... 64, 113 * row + column.
var texels := PackedByteArray()
# The mask itself, 113 x 113 in FORMAT_R8: 255 hidden, 0 visible; row follows logical z and
# column x.
var image := Image.create_empty(SIDE, SIDE, false, Image.FORMAT_R8)

var _radius_texels := NAN
var _radius_image: Image
var _templates := {}
# sub_427930's edge state, [start row, end row, x, q, error, r, r - dy], for the two edges.
var _left := PackedInt32Array([0, 0, 0, 0, 0, 0, 0])
var _right := PackedInt32Array([0, 0, 0, 0, 0, 0, 0])
var _hit_x := 0.0
var _hit_y := 0.0
var _shadow_rows := PackedInt64Array()
var _shadow_key := []
var _shadow_cache := {}
var _major_cells := PackedInt32Array()
var _row_first := PackedInt32Array()
var _row_last := PackedInt32Array()


func _init() -> void:
	load_tables()
	texels.resize(TEXELS)
	_major_cells.resize(57)
	_row_first.resize(SIDE)
	_row_last.resize(SIDE)


static func load_tables() -> bool:
	if _tables_loaded:
		return true
	var file := FileAccess.open(TABLES_PATH, FileAccess.READ)
	if file == null:
		push_error("Failed to open %s" % TABLES_PATH)
		return false
	var data = JSON.parse_string(file.get_as_text())
	if not data is Dictionary:
		push_error("Failed to parse %s" % TABLES_PATH)
		return false
	INVERSE_45 = Float32.f32(float(data["sector_scale"]))
	GATE_TILES = Float32.f32(float(data["gate_tiles"]))
	REACH_TILES = Float32.f32(float(data["reach_tiles"]))
	TEXELS_PER_TILE = Float32.f32(float(data["texels_per_tile"]))
	SAMPLE_STEP = Float32.f32(float(data["sample_step"]))
	DEGREES = ViewAngle.degrees_to_radians()
	_sample_start.clear()
	_spans.clear()
	_span_bits.clear()
	for sample: Array in data["samples"]:
		_sample_start.append(_spans.size())
		for value in sample[3]:
			_spans.append(int(value))
			_span_bits.append(1 << int(value))
	_distances.clear()
	for row: Array in data["distances"]:
		for value in row:
			_distances.append(Float32.f32(float(value)))
	for bit in 63:
		_bit_index[1 << bit] = bit
	_tables_loaded = true
	return true


# sub_428BC0(x, z, radius, heading, cone): the agent's raw position, its notice radius in
# tiles, its eased heading and its cone, each rounded to the float32 the original keeps.
# sight is a row-major grid of the map's cells, nonzero where INFODATA bit 1 blocks sight;
# every cell outside it is clear, as sub_412AE0 answers for a cell off the map.
func build(x: float, z: float, radius: float, heading: float, cone: float, sight: PackedByteArray, width: int, height: int) -> void:
	x = Float32.f32(x)
	z = Float32.f32(z)
	heading = Float32.f32(heading)
	cone = Float32.f32(cone)
	var radius_texels := Float32.f32(Float32.f32(radius) * TEXELS_PER_TILE)
	if radius_texels != _radius_texels:
		_radius_texels = radius_texels
		_radius_image = _radius_mask(radius_texels)
		_templates.clear()
	octants = _cone(heading, cone)
	_shadows(x, z, sight, width, height)
	_build_texels(image.get_data())


func is_hidden(row: int, column: int) -> bool:
	return image.get_pixel(column, row).r > 0.0


# The mask as the original leaves it in memory: 1 hidden, 0 visible.
func hidden_bytes() -> PackedByteArray:
	var bytes := image.get_data()
	for index in bytes.size():
		bytes[index] = 1 if bytes[index] != 0 else 0
	return bytes


func texel(row: int, column: int) -> int:
	return texels[SIDE * row + column]


# sub_428270. The clear, the fills of the absent octants and the radius OR that sub_429800
# adds last only ever set texels, so they come in as one cached image per set of absent
# octants; the two clip triangles are drawn over it.
func _cone(heading: float, cone: float) -> int:
	var half := cone * 0.5
	var low := Float32.f32(heading - half)
	var high := Float32.f32(half + heading)
	var low_sector: int = (-1 - int(low * -INVERSE_45)) if low < 0.0 else int(low * INVERSE_45)
	var high_sector := int(high * INVERSE_45)
	var count := high_sector - low_sector
	low_sector &= 7
	high_sector &= 7
	var bits := 1 << low_sector
	var sector := low_sector
	for _step in count:
		sector = (sector + 1) & 7
		bits |= 1 << sector
	image.copy_from(_template(bits))
	_clip(low, LOW_CLIP[low_sector])
	_clip(high, HIGH_CLIP[high_sector])
	return bits


func _template(bits: int) -> Image:
	if _templates.has(bits):
		return _templates[bits]
	var template: Image = _radius_image.duplicate()
	for pair: Array in PAIRS:
		if bits & pair[0] == 0:
			template.fill_rect(BLOCKS[pair[0]], HIDDEN)
			continue
		for bit: int in [pair[1], pair[2]]:
			if bits & bit == 0:
				for m in 56:
					template.fill_rect(_octant_span(bit, m), HIDDEN)
	_templates[bits] = template
	return template


# Span m of an absent octant's fill, m = 0 to 55, as (column, row, width, height).
static func _octant_span(bit: int, m: int) -> Rect2i:
	match bit:
		0x01:
			return Rect2i(56, 56 - m, m + 1, 1)
		0x02:
			return Rect2i(56 + m, 56 - m, 1, m + 1)
		0x04:
			return Rect2i(56 + m, 56, 1, m + 1)
		0x08:
			return Rect2i(56, 56 + m, m + 1, 1)
		0x10:
			return Rect2i(56 - m, 56 + m, m + 1, 1)
		0x20:
			return Rect2i(56 - m, 56, 1, m + 1)
		0x40:
			return Rect2i(56 - m, 56 - m, 1, m + 1)
	return Rect2i(56 - m, 56 - m, m + 1, 1)


func _clip(angle: float, clip: Array) -> void:
	var turn := angle * DEGREES
	var edge: Array = clip[0]
	_intersect(0.0, 0.0, Float32.f32(-sin(turn)), Float32.f32(cos(turn)), edge[0], edge[1], edge[2], edge[3])
	var x := Float32.f32(_hit_x + 56.0)
	var y := _hit_y + 56.0
	if x < 0.0:
		x = 0.0
	if y < 0.0:
		y = 0.0
	if not x < 113.0:
		x = 112.0
	if not y < 113.0:
		y = 112.0
	_triangle(clip[1], clip[2], int(x), int(y), CENTRE, CENTRE)


# sub_427C80: line A-B against line C-D, rounding to float32 where the original stores.
func _intersect(ax: float, ay: float, bx: float, by: float, cx: float, cy: float, dx: float, dy: float) -> void:
	var c_minus_d_y := cy - dy
	var step_x := Float32.f32(bx - ax)
	var step_y := Float32.f32(by - ay)
	var c_minus_d_x := cx - dx
	var det := step_x * c_minus_d_y - c_minus_d_x * step_y
	if det == 0.0:
		_hit_x = -1000.0
		_hit_y = -1000.0
		return
	det = Float32.f32(det)
	var from_a_y := cy - ay
	var from_a_x := cx - ax
	var numerator_u := Float32.f32(from_a_y * step_x - from_a_x * step_y)
	var t := Float32.f32((from_a_x * c_minus_d_y - from_a_y * c_minus_d_x) / det)
	var u := numerator_u / det
	_hit_x = Float32.f32((bx - ax) * t + ax)
	_hit_y = Float32.f32(u * (dy - cy) + cy)


# sub_427990: fills the triangle, skipping its top vertex's row and filling columns xl + 1 to
# xr + 1 of each row, as the original does.
func _triangle(x0: int, y0: int, x1: int, y1: int, x2: int, y2: int) -> void:
	if y0 > y1:
		var swap_x := x0
		var swap_y := y0
		x0 = x1
		y0 = y1
		x1 = swap_x
		y1 = swap_y
	if y0 > y2:
		var swap_x := x0
		var swap_y := y0
		x0 = x2
		y0 = y2
		x2 = swap_x
		y2 = swap_y
	if y1 > y2:
		var swap_x := x1
		var swap_y := y1
		x1 = x2
		y1 = y2
		x2 = swap_x
		y2 = swap_y
	var cross := (x2 - x0) * (y1 - y0) - (y2 - y0) * (x1 - x0)
	_left.fill(0)
	_right.fill(0)
	if cross >= 0:
		_edge(_left, x0, y0, x1, y1)
		_edge(_right, x0, y0, x2, y2)
	else:
		_edge(_left, x0, y0, x2, y2)
		_edge(_right, x0, y0, x1, y1)
	_fill_rows(_left[0] + 1, mini(_left[1], _right[1]))
	# The v1-v2 edge replaces v0-v1; a flat one keeps the old stepping state.
	if cross < 0:
		_edge(_right, x1, y1, x2, y2)
	else:
		_edge(_left, x1, y1, x2, y2)
	_fill_rows(maxi(_left[0], _right[0]) + 1, _left[1])


# Rows first to last of the triangle, stepping both edges as sub_427930's step does.
func _fill_rows(first: int, last: int) -> void:
	if first > last:
		return
	var left_x := _left[2]
	var left_q := _left[3]
	var left_error := _left[4]
	var left_r := _left[5]
	var left_back := _left[6]
	var right_x := _right[2]
	var right_q := _right[3]
	var right_error := _right[4]
	var right_r := _right[5]
	var right_back := _right[6]
	for y in range(first, last + 1):
		if right_x < 112:
			image.fill_rect(Rect2i(left_x + 1, y, right_x - left_x + 1, 1), HIDDEN)
		else:
			_fill_span(y, left_x, right_x)
		if left_error < 0:
			left_x += left_q
			left_error += left_r
		else:
			left_x += left_q + 1
			left_error += left_back
		if right_error < 0:
			right_x += right_q
			right_error += right_r
		else:
			right_x += right_q + 1
			right_error += right_back
	_left[2] = left_x
	_left[4] = left_error
	_right[2] = right_x
	_right[4] = right_error


# sub_427930, with sub_427900's floor division.
static func _edge(state: PackedInt32Array, x0: int, y0: int, x1: int, y1: int) -> void:
	state[0] = y0
	state[1] = y1
	if y1 == y0:
		return
	var dx := x1 - x0
	var dy := y1 - y0
	@warning_ignore("integer_division")
	var q := dx / dy
	if dx % dy != 0 and (dx < 0) != (dy < 0):
		q -= 1
	var r := dx - dy * q
	state[3] = q
	state[5] = r
	state[2] = q + x0
	state[4] = 2 * r - dy
	state[6] = r - dy


# The original writes xr - xl + 1 bytes from 113 * row + xl + 1, so a span that ends on
# column 112 runs on into column 0 of the next row. A byte past the last row lands in the
# allocation's slack, which nothing reads.
func _fill_span(row: int, left: int, right: int) -> void:
	var start := SIDE * row + left + 1
	var finish := mini(start + right - left + 1, TEXELS)
	while start < finish:
		@warning_ignore("integer_division")
		var line := start / SIDE
		var end := mini(finish, SIDE * (line + 1))
		image.fill_rect(Rect2i(start - SIDE * line, line, end - start, 1), HIDDEN)
		start = end


# sub_428BC0's walk. The original tests each sample's cell and stamps that sample's spans. A
# cell holds up to 64 samples, so each distinct cell is looked up once, and the samples of a
# blocked stretch of cells are stamped together: their spans join into one per row k, which
# tests/test_fov_tables.py checks the tables allow. The spans are gathered as bits in the
# octant's own frame and written once per row.
func _shadows(x: float, z: float, sight: PackedByteArray, width: int, height: int) -> void:
	var near_x := Float32.f32(x + 0.5)
	var near_z := Float32.f32(z + 0.5)
	# The shadows do not depend on the heading, so a standing agent's are kept for every octant
	# it has walked; only the cone changes from frame to frame.
	var key := [near_x, near_z, sight, width, height]
	if key != _shadow_key:
		_shadow_key = key
		_shadow_cache.clear()
	for walk: Array in WALK:
		var bit: int = walk[0]
		if octants & bit == 0:
			continue
		if not _shadow_cache.has(bit):
			_shadow_cache[bit] = _octant_shadow(walk, near_x, near_z, sight, width, height)
		_write_shadow(_shadow_cache[bit], walk[1], walk[2], walk[3])


func _octant_shadow(walk: Array, near_x: float, near_z: float, sight: PackedByteArray, width: int, height: int) -> PackedInt64Array:
	var along_z: bool = walk[1]
	var sign_x: int = walk[2]
	var sign_z: int = walk[3]
	var major_near := near_z if along_z else near_x
	var major_sign := sign_z if along_z else sign_x
	var minor_near := near_x if along_z else near_z
	var minor_sign := sign_x if along_z else sign_z
	# The very sums the original truncates, so each cell is its cell exactly.
	for r in range(1, 57):
		_major_cells[r] = int(major_near + major_sign * ((r - 1) * SAMPLE_STEP))
	# The minor cells as runs of j, [cell, first j, last j]; the cell only steps one way.
	var groups := PackedInt32Array()
	for j in 56:
		var minor := int(minor_near + minor_sign * (j * SAMPLE_STEP))
		if j > 0 and minor == groups[groups.size() - 3]:
			groups[groups.size() - 1] = j
		else:
			groups.append_array([minor, j, j])
	_shadow_rows = PackedInt64Array()
	_shadow_rows.resize(56)
	# The major cell steps one way too, so equal cells are consecutive.
	var r := 1
	while r <= 56:
		var major := _major_cells[r]
		var last_r := r
		while last_r < 56 and _major_cells[last_r + 1] == major:
			last_r += 1
		var runs := _blocked_runs(groups, along_z, major, sight, width, height)
		for index in range(0, runs.size(), 2):
			var first := runs[index]
			var last := runs[index + 1]
			# Rows r that reach only part of the run hold samples j up to r - 1.
			for partial in range(maxi(r, first + 1), mini(last_r, last) + 1):
				_stamp_row(partial, first, partial - 1)
			var whole := maxi(r, last + 1)
			if whole <= last_r:
				_stamp_block(whole, last_r, first, last)
		r = last_r + 1
	return _shadow_rows


# The stretches of j, first and last, whose cells on this major cell block sight.
static func _blocked_runs(groups: PackedInt32Array, along_z: bool, major: int, sight: PackedByteArray, width: int, height: int) -> PackedInt32Array:
	var runs := PackedInt32Array()
	for index in range(0, groups.size(), 3):
		var minor := groups[index]
		var cell_x := minor if along_z else major
		var cell_z := major if along_z else minor
		if cell_x < 0 or cell_z < 0 or cell_x >= width or cell_z >= height or sight[cell_z * width + cell_x] == 0:
			continue
		if not runs.is_empty() and runs[runs.size() - 1] == groups[index + 1] - 1:
			runs[runs.size() - 1] = groups[index + 2]
		else:
			runs.append(groups[index + 1])
			runs.append(groups[index + 2])
	return runs


# The samples j = first to last of row r, side by side, stamp on each row k the one span from
# the first one's a to the last one's b.
func _stamp_row(r: int, first: int, last: int) -> void:
	@warning_ignore("integer_division")
	var base := r * (r - 1) / 2
	var low := _sample_start[base + first]
	var high := _sample_start[base + last] + 1
	for k in range(r - 1, 56):
		_shadow_rows[k] |= _span_bits[high] - _span_bits[low]
		low += 2
		high += 2


# Every sample j = first to last of rows r = near to far. On row k their spans join into one
# that runs from the a of the farthest row reaching k to the b of the nearest row: a and b
# never grow as r does, and the spans of neighbouring rows overlap.
func _stamp_block(near: int, far: int, first: int, last: int) -> void:
	@warning_ignore("integer_division")
	var high := _sample_start[near * (near - 1) / 2 + last] + 1
	for k in range(near - 1, far - 1):
		# Row k + 1 is the farthest to reach row k, and row k is its first.
		@warning_ignore("integer_division")
		var low := _sample_start[(k + 1) * k / 2 + first]
		_shadow_rows[k] |= _span_bits[high] - _span_bits[low]
		high += 2
	@warning_ignore("integer_division")
	var low := _sample_start[far * (far - 1) / 2 + first]
	for k in range(far - 1, 56):
		_shadow_rows[k] |= _span_bits[high] - _span_bits[low]
		low += 2
		high += 2


func _write_shadow(rows: PackedInt64Array, along_z: bool, sign_x: int, sign_z: int) -> void:
	for k in 56:
		var bits := rows[k]
		while bits != 0:
			var lowest := bits & -bits
			var carried := bits + lowest
			var start: int = _bit_index[lowest]
			var end: int = _bit_index[carried & -carried]
			bits &= carried
			var width := end - start
			if along_z:
				var row := 56 + sign_z * k
				image.fill_rect(Rect2i(56 + start if sign_x > 0 else 56 - end, row, width, 1), HIDDEN)
			else:
				var column := 56 + sign_x * k
				image.fill_rect(Rect2i(column, 56 + start if sign_z > 0 else 56 - end, 1, width), HIDDEN)


# sub_429770: everything hidden but a disc of radius R8 texels at row 56, column 57. The last
# byte stays clear because sub_429770 fills, and sub_429800 ORs, 0xC78 dwords.
func _radius_mask(radius_texels: float) -> Image:
	var bytes := PackedByteArray()
	bytes.resize(0x35E1)
	bytes.fill(255)
	var base := SIDE * 56 + 57
	var index := 0
	for i in 57:
		for j in 57:
			if not _distances[index] > radius_texels:
				bytes[base - SIDE * i - j] = 0
				bytes[base - SIDE * i + j] = 0
				bytes[base + SIDE * i - j] = 0
				bytes[base + SIDE * i + j] = 0
			index += 1
	bytes[TEXELS - 1] = 0
	bytes.resize(TEXELS)
	return Image.create_from_data(SIDE, SIDE, false, Image.FORMAT_R8, bytes)


# sub_429830: 64 - 32 * hidden - 8 * (hidden 4-neighbours), for rows and columns 1 to 111;
# the outer ring stays 0. Eight texels at a time, one per byte of an integer, over the rows
# and columns within one texel of a visible one: everywhere else it comes to 0.
func _build_texels(mask: PackedByteArray) -> void:
	texels.fill(0)
	var first_visible := mask.find(0)
	if first_visible < 0:
		return
	var last_visible := mask.rfind(0)
	@warning_ignore("integer_division")
	var top := first_visible / SIDE
	@warning_ignore("integer_division")
	var bottom := last_visible / SIDE
	for row in range(top, bottom + 1):
		var start := SIDE * row
		var first := mask.find(0, start)
		if first < 0 or first >= start + SIDE:
			_row_first[row] = SIDE
			_row_last[row] = -1
			continue
		_row_first[row] = first - start
		_row_last[row] = mask.rfind(0, start + SIDE - 1) - start
	for row in range(maxi(1, top - 1), mini(111, bottom + 1) + 1):
		var low := SIDE
		var high := -1
		for near in [row - 1, row, row + 1]:
			if near < top or near > bottom or _row_last[near] < 0:
				continue
			var reach := 1 if near == row else 0
			low = mini(low, _row_first[near] - reach)
			high = maxi(high, _row_last[near] + reach)
		if high < 0:
			continue
		low = maxi(low, 1)
		high = mini(high, 111)
		if low > high:
			continue
		var column := low
		while column <= high:
			# The last group of a row is moved back to end on column 111, never past it.
			var at := SIDE * row + mini(column, 104)
			var hidden := mask.decode_u64(at) & LANES
			var around := (mask.decode_u64(at - 1) & LANES) + (mask.decode_u64(at + 1) & LANES) \
				+ (mask.decode_u64(at - SIDE) & LANES) + (mask.decode_u64(at + SIDE) & LANES)
			texels.encode_s64(at, FULL_TEXEL_LANES - 32 * hidden - 8 * around)
			column += 8
