extends Sprite2D

# CPisspuddle, the puddle urinating's state 21 builds a short way ahead of the player
# (0x41C305-0x41C4A3): one translucent sprite that grows through its 11-frame clip once, drawn
# after the characters and tested against the Z the walls, items and characters wrote. The
# player's tick spreads and fades it from ten seconds on the shared effect clock and deletes it
# after seventeen, so that part is AbilityController's, which calls grow(). Every number here is
# recovered in docs/player-ability-reference.md, "The puddle: CPisspuddle".
#
# AbilityController owns it the way the player owns +1080, and calls tick() with the level's
# clock after its own tick, as the effects list game+1960 is ticked after the character list
# (sub_402590, 0x4026BE).

const SHADER := preload("res://scenes/effects/puddle.gdshader")
const EffectDepth := preload("res://scenes/effects/effect_depth.gd")
const Float32 := preload("res://scenes/shared/float32.gd")
const OriginalData := preload("res://scenes/shared/original_data.gd")
const PlayerTimer := preload("res://scenes/player/player_timer.gd")
const ViewAngle := preload("res://scenes/shared/view_angle.gd")
# CO_CHARS_JOBLESS_PISSPUDDLE_000, which sub_41D630 names for both characters (0x41D716).
const LIBRARY_PATH := "res://scenes/effects/puddle_animations.res"
const CLIP := &"puddle"
# The constants state 21, the player's tick, the draw and the projection read, as
# tools/export_puddle_params.py reads them out of sacked.exe.
const PARAMS_PATH := "res://resources/original/puddle.json"
# The effects pass comes after every character and the bubbles and names they draw
# (Main_RenderUpdate, 0x402B38). See docs/map-rendering.md.
const DEPTH_INDEX := 3

# Each frame's colour, Z plane, pivot, size and start time, loaded once for every puddle.
static var frames: Array[Dictionary] = []

# Where it lies, in logical x/z, and how far up: what sub_42B330 is handed.
var ground := Vector2.ZERO
var height := 0.0
# The world pixel of logical (0, 0), which the projection is taken from.
var ground_origin := Vector2.ZERO
# Its clip's start (+0x228), the clock at the tick state 21 built it. The clip is the
# puddle's own; the original shares one, which only one puddle at a time makes harmless.
var start := 0.0
# +0x3C/+0x40 and +900, float32 fields that the player's tick writes after ten seconds.
var spread := 1.0
var alpha := 0.0
# What the last tick drew: the frame, the projected anchor, the base score and the quad.
var clip_frame := -1
var anchor := Vector2.ZERO
var depth_base := 0.0
var drawn_rect := Rect2()

var _shader_material := ShaderMaterial.new()
var _depth := EffectDepth.new()
# The process frame the puddle entered the tree in, which runs none of its _process.
var _entered_frame := -1


func _init() -> void:
	load_frames()
	centered = false
	z_index = DEPTH_INDEX
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_shader_material.shader = SHADER
	material = _shader_material
	alpha = Float32.f32(float(params().get("alpha", 0.0)))


func _enter_tree() -> void:
	_entered_frame = Engine.get_process_frames()


# Mode 22 tests the puddle's Z against the Z buffer and never writes it (0x435B70). _publish()
# sets the test up for the frame state 21 builds it in, which has no _process of its own; on
# every later frame this does it instead, once, after the controller's tick and the characters
# that move later in the frame.
func _process(_delta: float) -> void:
	_depth.update(self, _shader_material, drawn_rect)


# State 21 (0x41C350-0x41C3F4): a = (view * 45 + 180) * 0.017453, and d tiles along it, 0.2 for
# Anne (+988 set) and 0.6 for Jo, 0.1 units up. Slot 7 (sub_41A290, 0x41C498) resets the scale
# to 1, and the clip starts on the clock (0x41C444).
func place(player_ground: Vector2, view: int, anne: bool, origin: Vector2, now: float) -> void:
	var values := params()
	var a := ViewAngle.of_view(view)
	var reach := float(values["reach_anne"] if anne else values["reach_jo"])
	ground = Vector2(Float32.f32(player_ground.x - reach * sin(a)), Float32.f32(player_ground.y + reach * cos(a)))
	height = float(values["height"])
	ground_origin = origin
	start = now
	spread = 1.0
	clip_frame = -1


# The player tick's branch past ten seconds (0x41D168-0x41D1AB): s = 1 + 0.08 (age - 10), which
# sub_42B450 clamps to 0.01, and +900 = 0.7 - 0.085 (age - 10), each stored as a float.
func grow(age: float) -> void:
	var values := params()
	var past := age - grow_after()
	spread = maxf(Float32.f32(past * float(values["grow_rate"]) + float(values["base_scale"])), float(values["min_scale"]))
	alpha = Float32.f32(float(values["fade_from"]) - past * float(values["fade_rate"]))


# vtable slot 8 with the level's clock: the clip's frame, then the draw's projection.
func tick(now: float) -> void:
	clip_frame = frame_at(now - start)
	_publish()


# CObjectAnim_SelectFrameFromTime with the loop flag state 21 cleared (0x41C435): frame
# trunc(elapsed * 8), holding the last from 1.25 s on.
func frame_at(elapsed: float) -> int:
	var index := 0
	for candidate in range(frames.size()):
		if float(frames[candidate]["time"]) > elapsed:
			break
		index = candidate
	return index


func frame_count() -> int:
	return frames.size()


# sub_41E1C0 hands the blitter (char)trunc(+900 * 256) (0x41E1DC-0x41E1F1).
func alpha_byte() -> int:
	return int(alpha * float(params()["fixed_units"])) & 0xFF


# And max(1, trunc(s * 256)) (0x41E1F6-0x41E22C).
func scale_units() -> int:
	return maxi(1, int(spread * float(params()["fixed_units"])))


# sub_41A2D0 and sub_41E1C0, with world pixels for the camera-relative ones:
#   anchor   = ground(x, z) - (0, 24 y)
#   base     = ceil(int(anchor.y) / 2), the score of a Z of 0 there
#   top_left = trunc(trunc(anchor) + pivot - pivot * s) - pivot
#   quad     = ((size - 1) * S >> 8) + 1 each way, S = scale_units()
func _publish() -> void:
	if clip_frame < 0 or clip_frame >= frames.size():
		return
	var data := frames[clip_frame]
	var size: Vector2 = data["size"]
	var pivot: Vector2 = data["pivot"]
	anchor = ground_origin + IsoDirection.ground_to_screen(ground) - Vector2(0.0, float(params()["height_pixels"]) * height)
	depth_base = CharacterDepthCompositor.base_score(anchor.y)
	var units := scale_units()
	var drawn := Vector2(((int(size.x) - 1) * units >> 8) + 1, ((int(size.y) - 1) * units >> 8) + 1)
	var top_left := (anchor.floor() + pivot - pivot * spread).floor() - pivot
	drawn_rect = Rect2(top_left, drawn)
	texture = data["texture"]
	global_position = top_left
	scale = drawn / size
	_shader_material.set_shader_parameter("depth_plane", data["depth"])
	_shader_material.set_shader_parameter("depth_base", depth_base)
	_shader_material.set_shader_parameter("alpha_byte", float(alpha_byte()))
	_shader_material.set_shader_parameter("scale_units", float(units))
	_shader_material.set_shader_parameter("drawn_size", drawn)
	if Engine.get_process_frames() == _entered_frame:
		_depth.update(self, _shader_material, drawn_rect)


static func load_frames() -> void:
	if not frames.is_empty():
		return
	var library := load(LIBRARY_PATH) as AnimationLibrary
	var animation := library.get_animation(CLIP) if library != null and library.has_animation(CLIP) else null
	if animation == null:
		push_error("Puddle: %s has no %s clip" % [LIBRARY_PATH, CLIP])
		return
	var textures := animation.find_track(NodePath("Sprite2D:texture"), Animation.TYPE_VALUE)
	var offsets := animation.find_track(NodePath("Sprite2D:offset"), Animation.TYPE_VALUE)
	if textures < 0 or offsets < 0:
		push_error("Puddle: the %s clip drives no texture and pivot" % CLIP)
		return
	for index in range(animation.track_get_key_count(textures)):
		var frame_texture := animation.track_get_key_value(textures, index) as Texture2D
		frames.append({
			"time": animation.track_get_key_time(textures, index),
			"texture": frame_texture,
			"depth": load(frame_texture.resource_path.get_basename() + "-depth.png") as Texture2D,
			"pivot": -(animation.track_get_key_value(offsets, index) as Vector2),
			"size": frame_texture.get_size(),
		})


static func params() -> Dictionary:
	return OriginalData.load_original(PARAMS_PATH)


# The ten seconds on the shared effect clock (0x41D15B-0x41D199) are flt_4652F4, the same 10.0
# every timed state turns a record's tenths into hundredths with, so it is read from the
# player's clock constants rather than from puddle.json.
static func grow_after() -> float:
	return PlayerTimer.factor("tenths_to_hundredths")
