extends MultiMeshInstance2D

# CSfxSmoke, the cigarette smoke that smoking's state 11 spawns (0x41BE27): an emitter fixed at
# the player's mouth that puffs Strings particles every two seconds until the player's tick
# stops it. Every number here is recovered in docs/player-ability-reference.md, "The smoke".
#
# AbilityController owns it the way the player owns +1052: it calls tick() with the level's
# clock after its own tick, as the effects list game+1960 is ticked after the character list
# (sub_402590, 0x4026BE), and stops and frees it through the player's gate.

const SHADER := preload("res://scenes/effects/smoke.gdshader")
const EffectDepth := preload("res://scenes/effects/effect_depth.gd")
const OriginalData := preload("res://scenes/shared/original_data.gd")
const ViewAngle := preload("res://scenes/shared/view_angle.gd")
const STRINGS_TIMING := "res://resources/effects/strings.json"
# sub_427290's block from 0x471378, the array size and the spawn's and projection's own
# constants, as tools/export_smoke_params.py reads them out of sacked.exe.
const PARAMS_PATH := "res://resources/original/smoke.json"
# The effects pass comes after every character and the bubbles and names they draw
# (Main_RenderUpdate, 0x402B38), and before the rising scores. See docs/map-rendering.md.
const DEPTH_INDEX := 3
# Far past any level's pixels, so the canvas never culls the smoke.
const CULL_REACH := 1.0e6

# One particle is STRIDE float32s in `particles`, as the 104-byte particle keeps its fields
# (sub_426730 stores every one with fstp dword). The *_BIRTH fields are where its ramps start.
enum {
	AGE, POS_X, POS_Y, POS_Z, VEL_X, VEL_Y, VEL_Z,
	SPEED, RISE, SIZE, RED, GREEN, BLUE, ALPHA,
	SPEED_BIRTH, RISE_BIRTH, SIZE_BIRTH, RED_BIRTH, GREEN_BIRTH, BLUE_BIRTH, ALPHA_BIRTH,
	STRIDE,
}
# One instance in MultiMesh.buffer: a 2D transform as two rows of four, the colour, and the
# custom data.
const INSTANCE_FLOATS := 16

static var _frame_images: Array[Image] = []
static var _fps := 0.0
static var _frame_count := 0
# The frames' shared pivot, the negated offset tools/export_gui_assets.py writes for each.
static var _pivot := Vector2.ZERO

# Live particles first, in the order the tick and the draw walk them.
var particles := PackedFloat32Array()
var alive := 0
var emitter := Vector3.ZERO
var emitter_velocity := Vector3.ZERO
# The world pixel of logical (0, 0), which the projection is taken from.
var ground_origin := Vector2.ZERO
# +248 and +244.
var stopped := false
var accumulator := 0.0
# RANMAR (sub_45E1C0) in the original, whose seed is not recovered; only the ranges matter.
# A check swaps in its own sequence.
var random: Callable
# What the last tick handed the draw, one INSTANCE_FLOATS block per live particle, and the
# union of their quads in world pixels.
var instance_buffer := PackedFloat32Array()
var drawn_bounds := Rect2()

var _rng := RandomNumberGenerator.new()
var _seeded := false
var _last_time := 0.0
# The world composite and the characters a particle is tested against.
var _depth := EffectDepth.new()


func _init() -> void:
	_rng.randomize()
	random = _rng.randf
	particles.resize(int(params().get("capacity", 0)) * STRIDE)
	instance_buffer.resize(int(params().get("capacity", 0)) * INSTANCE_FLOATS)


func _ready() -> void:
	_load_strings()
	z_index = DEPTH_INDEX
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var mesh := MultiMesh.new()
	mesh.transform_format = MultiMesh.TRANSFORM_2D
	mesh.use_colors = true
	mesh.use_custom_data = true
	mesh.mesh = _unit_quad()
	mesh.instance_count = int(params().get("capacity", 0))
	mesh.visible_instance_count = 0
	# The canvas keeps the rect it took from the multimesh when this node was first drawn,
	# empty, and a buffer set later does not refresh it, so without a fixed box the smoke
	# would stay culled.
	mesh.custom_aabb = AABB(Vector3(-CULL_REACH, -CULL_REACH, 0.0), Vector3(2.0 * CULL_REACH, 2.0 * CULL_REACH, 0.0))
	multimesh = mesh
	# Stacked into one array so a single draw carries every particle whatever its frame.
	var frames := Texture2DArray.new()
	if not _frame_images.is_empty():
		frames.create_from_images(_frame_images)
	var shader_material := ShaderMaterial.new()
	shader_material.shader = SHADER
	shader_material.set_shader_parameter("frames", frames)
	material = shader_material
	_publish()


# Mode 46 tests each particle's one Z against the Z buffer and never writes it (0x453E20).
func _process(_delta: float) -> void:
	_depth.update(self, material as ShaderMaterial, drawn_bounds)


# sub_41BDA4-0x41BF7E: a = (view * 45 + 180) * 0.017453, the emitter 0.21 tiles along the
# facing and 1.85 units up, and a velocity along the facing that never changes.
func start(ground: Vector2, height: float, view: int, origin: Vector2) -> void:
	var values := params()
	var a := ViewAngle.of_view(view)
	var reach := float(values["mouth_reach"])
	emitter = Vector3(ground.x - reach * sin(a), height + float(values["mouth_height"]), ground.y + reach * cos(a))
	emitter_velocity = Vector3(-reach * sin(a), 0.0, reach * cos(a))
	ground_origin = origin


# vtable slot 8 (0x4268F0): DeltaTime_Calculate against the effect's own last time, seeded on
# the first call, so the first tick advances nothing.
func tick(now: float) -> void:
	var delta := 0.0
	if _seeded:
		delta = now - _last_time
	_seeded = true
	_last_time = now
	advance(delta)


# sub_426730.
func advance(delta: float) -> void:
	var values := params()
	var lifetime := float(values["lifetime"])
	var inverse := float(values["inverse_lifetime"])
	var rise_scale := float(values["rise_scale"])
	var speed_end := float(values["speed"][2])
	var rise_end := float(values["rise"][2])
	var size_end := float(values["size"][2])
	var red_end := float(values["red"][2])
	var green_end := float(values["green"][2])
	var blue_end := float(values["blue"][2])
	var alpha_end := float(values["alpha"][2])
	var index := 0
	while index < alive:
		var p := index * STRIDE
		var age := particles[p + AGE] + delta
		particles[p + AGE] = age
		if age >= lifetime:
			_remove(index)
			continue
		var f := inverse * particles[p + AGE]
		particles[p + RED] = particles[p + RED_BIRTH] + (red_end - particles[p + RED_BIRTH]) * f
		particles[p + GREEN] = particles[p + GREEN_BIRTH] + (green_end - particles[p + GREEN_BIRTH]) * f
		particles[p + BLUE] = particles[p + BLUE_BIRTH] + (blue_end - particles[p + BLUE_BIRTH]) * f
		particles[p + ALPHA] = particles[p + ALPHA_BIRTH] + (alpha_end - particles[p + ALPHA_BIRTH]) * f
		particles[p + SPEED] = particles[p + SPEED_BIRTH] + (speed_end - particles[p + SPEED_BIRTH]) * f
		particles[p + RISE] = particles[p + RISE_BIRTH] + (rise_end - particles[p + RISE_BIRTH]) * f
		particles[p + SIZE] = particles[p + SIZE_BIRTH] + (size_end - particles[p + SIZE_BIRTH]) * f
		var k := delta * particles[p + SPEED]
		particles[p + POS_X] += k * particles[p + VEL_X]
		particles[p + POS_Z] += k * particles[p + VEL_Z]
		var y := particles[p + POS_Y] + k * particles[p + VEL_Y] - delta * particles[p + RISE] * rise_scale
		# The same 0.1 is the floor (0x426830).
		particles[p + POS_Y] = y if y >= rise_scale else rise_scale
		index += 1
	# 0x426861-0x4268DD. A burst is 25 * ceil(acc / 2), so 50 whenever the accumulator has
	# passed 2.0 by any fraction of a frame.
	var interval := float(params()["interval"])
	accumulator += delta
	if accumulator >= interval and not stopped:
		var count := int(floor(float(params()["per_interval"])) * ceil(accumulator / interval))
		for _i in range(count):
			_emit()
		accumulator = 0.0
	_publish()


# sub_426C60: raises the stop flag for good and answers whether no particle is left.
func stop() -> bool:
	stopped = true
	return alive == 0


# One live particle's fields by name, for a check to read.
func particle(index: int) -> Dictionary:
	var p := index * STRIDE
	var names := ["age", "x", "y", "z", "vx", "vy", "vz", "speed", "rise", "size", "red", "green", "blue", "alpha"]
	var births := ["speed0", "rise0", "size0", "red0", "green0", "blue0", "alpha0"]
	var result := {}
	for field in range(names.size()):
		result[names[field]] = particles[p + field]
	for field in range(births.size()):
		result[births[field]] = particles[p + SPEED_BIRTH + field]
	return result


# What the last tick handed the draw for one live particle.
func drawn(index: int) -> Dictionary:
	var b := index * INSTANCE_FLOATS
	return {
		"top_left": Vector2(instance_buffer[b + 3], instance_buffer[b + 7]) + global_position,
		"width": int(instance_buffer[b + 15]),
		"tint": Color(instance_buffer[b + 8], instance_buffer[b + 9], instance_buffer[b + 10], instance_buffer[b + 11]),
		"frame": int(instance_buffer[b + 12]),
		"score": instance_buffer[b + 13],
		"scale": int(instance_buffer[b + 14]),
	}


# sub_4265A0 moves the last particle into the freed slot, and the loop goes on with it.
func _remove(index: int) -> void:
	alive -= 1
	var last := alive * STRIDE
	var p := index * STRIDE
	for field in range(STRIDE):
		particles[p + field] = particles[last + field]


# sub_426600. Eight draws from the generator, in this order; sub_426570 has no slot once all
# are live.
func _emit() -> void:
	if alive * STRIDE >= particles.size():
		return
	var p := alive * STRIDE
	alive += 1
	particles[p + AGE] = _birth("age")
	particles[p + ALPHA_BIRTH] = _birth("alpha")
	particles[p + RISE_BIRTH] = _birth("rise")
	particles[p + SPEED_BIRTH] = _birth("speed")
	particles[p + SIZE_BIRTH] = _birth("size")
	particles[p + RED_BIRTH] = _birth("red")
	particles[p + GREEN_BIRTH] = _birth("green")
	particles[p + BLUE_BIRTH] = _birth("blue")
	for field in range(SPEED, ALPHA + 1):
		particles[p + field] = particles[p + SPEED_BIRTH + field - SPEED]
	particles[p + POS_X] = emitter.x
	particles[p + POS_Y] = emitter.y
	particles[p + POS_Z] = emitter.z
	# Slot 11 (0x4272E0).
	var scale := float(params()["velocity_scale"])
	particles[p + VEL_X] = scale * emitter_velocity.x
	particles[p + VEL_Y] = emitter_velocity.y
	particles[p + VEL_Z] = scale * emitter_velocity.z


func _birth(ramp: String) -> float:
	var values: Array = params()[ramp]
	return float(values[0]) + float(values[1]) * float(random.call())


# SelectFrameFromTime with the particle's own age and the Strings ANIM: floor(8 * age) mod 16.
static func frame_of(age: float) -> int:
	_load_strings()
	if _frame_count <= 0:
		return 0
	return int(floor(age * _fps)) % _frame_count


# sub_426920 and the blitter's scale, once per particle per tick, into the instance buffer:
#   screen   = ground(x, z) - (0, 48 y)
#   s        = max(1, trunc(size * 255)), covering ((s * 63) >> 8) + 1 pixels
#   top_left = trunc(screen + 32 - 32 size) - 32
#   score    = ceil(int(screen.y) / 2) - 48, larger being nearer
# with the tint as the colour, trunc(c0, c1, c2), which the R, G, B, X back buffer reads as
# red, green and blue (sub_42D1E0), and the frame, score, scale and width as custom data.
func _publish() -> void:
	_load_strings()
	var height_pixels := float(params()["height_pixels"])
	var scale_units := float(params()["scale_units"])
	var first := true
	for index in range(alive):
		var p := index * STRIDE
		var ground := ground_origin + IsoDirection.ground_to_screen(Vector2(particles[p + POS_X], particles[p + POS_Z]))
		var size := particles[p + SIZE]
		var screen_x := ground.x
		var screen_y := ground.y - height_pixels * particles[p + POS_Y]
		var scale := maxi(1, int(size * scale_units))
		var width := float(((scale * 63) >> 8) + 1)
		var shift := _pivot - _pivot * size
		var left := floorf(screen_x + shift.x) - _pivot.x
		var top := floorf(screen_y + shift.y) - _pivot.y
		var b := index * INSTANCE_FLOATS
		instance_buffer[b] = width
		instance_buffer[b + 1] = 0.0
		instance_buffer[b + 2] = 0.0
		instance_buffer[b + 3] = left - global_position.x
		instance_buffer[b + 4] = 0.0
		instance_buffer[b + 5] = width
		instance_buffer[b + 6] = 0.0
		instance_buffer[b + 7] = top - global_position.y
		instance_buffer[b + 8] = floorf(particles[p + RED]) / 255.0
		instance_buffer[b + 9] = floorf(particles[p + GREEN]) / 255.0
		instance_buffer[b + 10] = floorf(particles[p + BLUE]) / 255.0
		instance_buffer[b + 11] = 1.0
		instance_buffer[b + 12] = float(frame_of(particles[p + AGE]))
		instance_buffer[b + 13] = CharacterDepthCompositor.base_score(screen_y) - height_pixels
		instance_buffer[b + 14] = float(scale)
		instance_buffer[b + 15] = width
		var quad := Rect2(left, top, width, width)
		drawn_bounds = quad if first else drawn_bounds.merge(quad)
		first = false
	if first:
		drawn_bounds = Rect2()
	if multimesh == null:
		return
	multimesh.visible_instance_count = alive
	multimesh.buffer = instance_buffer


static func params() -> Dictionary:
	return OriginalData.load_original(PARAMS_PATH)


# The Strings ANIM (CO_EFFECT.OGD 0x23CFDA: 8 fps, 16 frames of 64 x 64), as
# tools/export_gui_assets.py exported it.
static func _load_strings() -> void:
	if _frame_count > 0:
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(STRINGS_TIMING))
	if not parsed is Dictionary:
		push_error("Smoke: %s is unreadable" % STRINGS_TIMING)
		return
	_fps = float(parsed.get("fps", 0.0))
	var images: Array[Image] = []
	var pivot := Vector2.ZERO
	for frame in parsed.get("frames", []):
		var offset: Array = frame.get("offset", [0, 0])
		var frame_pivot := -Vector2(float(offset[0]), float(offset[1]))
		if images.is_empty():
			pivot = frame_pivot
		elif frame_pivot != pivot:
			push_error("Smoke: frame %s has pivot %s, the first has %s" % [frame["texture"], frame_pivot, pivot])
			return
		var texture := load(String(frame["texture"])) as Texture2D
		var image := texture.get_image() if texture != null else null
		if image == null:
			push_error("Smoke: frame %s is missing" % frame["texture"])
			return
		if image.is_compressed():
			image.decompress()
		image.convert(Image.FORMAT_RGBA8)
		images.append(image)
	_pivot = pivot
	_frame_count = images.size()
	_frame_images = images


static func _unit_quad() -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
