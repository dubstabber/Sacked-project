extends Node2D

# What sub_41D500 paints first while player+1044 is up (0x41D514-0x41D5A8): a four-corner
# gradient over the world pass's clip, which sub_4584D0 averages half and half with the scene
# because the weight is 0. It is painted at the player's place in the character list, and the
# player is always the list's first entry, so the floor, the field-of-view tint, the walls and
# the items lie under it and every character, effect and the HUD over it. AbilityController
# makes it the player's first child and shows it with +1044. See
# docs/player-ability-reference.md, "The overlay".

const SHADER := preload("res://scenes/player/slowdown_overlay.gdshader")
const Slowdown := preload("res://scenes/npc/slowdown.gd")
# The z CharacterDepthCompositor gives every depth-composited sprite, characters and looping
# items alike, which draw in tree order: the items under World/Objects, then the player, then
# the agents. As the player's first child the overlay comes after the items and before every
# character, and after the floor (-20), the field of view (-10), the walls (-5), the glass (-4),
# the world composite and the shadows (0).
const DRAW_Z := 1
# Far past any level, so the quad covers the canvas wherever the camera stands; the shader works
# from the pixel on screen.
const COVER := 1.0e5

var _shader_material := ShaderMaterial.new()
var _canvas := Vector2.ZERO


func _ready() -> void:
	z_index = DRAW_Z
	z_as_relative = false
	_shader_material.shader = SHADER
	material = _shader_material
	var params := Slowdown.params()
	var corners: Array = params.get("overlay_corners", [])
	for index in range(mini(corners.size(), 4)):
		var corner: Array = corners[index]
		_shader_material.set_shader_parameter(
			["top_left", "top_right", "bottom_left", "bottom_right"][index],
			Vector3(float(corner[0]), float(corner[1]), float(corner[2]))
		)
	_shader_material.set_shader_parameter("fixed_one", float(params.get("overlay_fixed_one", 4096)))
	var screen: Array = params.get("overlay_rect", [0, 0])
	_shader_material.set_shader_parameter("original_clip", Vector2(world_clip(Vector2(float(screen[0]), float(screen[1]))).size))
	fit()


func _process(_delta: float) -> void:
	if visible and get_viewport_rect().size != _canvas:
		fit()


# The world pass's clip on this canvas, Main_RenderUpdate's (1, 1, w - 1, h - 91) with the port's
# width and height, and the canvas size the shader maps the screen onto. The shader spreads that
# clip over the original's 799 x 509, whose size its steps come from.
func fit() -> void:
	_canvas = get_viewport_rect().size
	var clip := world_clip(_canvas)
	_shader_material.set_shader_parameter("canvas_size", _canvas)
	_shader_material.set_shader_parameter("clip", Vector4(clip.position.x, clip.position.y, clip.size.x, clip.size.y))


static func world_clip(canvas: Vector2) -> Rect2i:
	var params := Slowdown.params()
	var clip: Array = params.get("world_clip", [0, 0, 0, 0])
	return Rect2i(int(clip[0]), int(clip[1]), int(canvas.x) - int(clip[2]), int(canvas.y) - int(clip[3]))


func _draw() -> void:
	draw_rect(Rect2(-COVER, -COVER, 2.0 * COVER, 2.0 * COVER), Color.WHITE)
