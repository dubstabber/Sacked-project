extends Node2D

# sub_417460's three green copies of a slowed agent's frame (0x41762D-0x41772F), drawn after its
# sprite, bubble, name and shadow on every rendered frame while agent+1792 is up. Each copy takes
# rand() % 4 - 2 for y and then rand() % 6 - 3 for x, is tested 2 depth units nearer than the
# agent without writing depth, and mode 54 (0x43B050) blends a brightened green tint of the frame
# at 120/256 over what is there. The agent shows and hides this node with its flag. See
# docs/player-ability-reference.md, "The green copies".

const SHADER := preload("res://scenes/npc/slowed_copies.gdshader")
const EffectDepth := preload("res://scenes/effects/effect_depth.gd")
const Slowdown := preload("res://scenes/npc/slowdown.gd")

# rand(): 0 to 32767, as the C runtime's. A check can fix it.
static var random: Callable = func() -> int: return randi() & 0x7FFF

# Each copy's offset from the frame's own top left, in the order they were drawn.
var offsets: Array[Vector2i] = []
# The world pixel the agent's frame is drawn at, and the frame the copies were drawn from.
var anchor := Vector2.ZERO
var frame: Texture2D
# ceil(int(y) / 2) of the agent's anchor plus 2: the score of a Z of 0 on the copies.
var depth_base := 0.0
# Where the copies were drawn, which the depth test's actors are gathered over.
var drawn_bounds := Rect2()

var _sprite: Sprite2D
var _shader_material := ShaderMaterial.new()
var _depth := EffectDepth.new()


func _ready() -> void:
	# Main_RenderUpdate draws on under the pause panel, the quit prompt and the caught banner,
	# where only the world tick stops, so the copies go on rolling fresh offsets over the frozen
	# frame. This reads the frame and the depth inputs and changes nothing else.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_sprite = get_parent().get_node_or_null("Sprite2D") as Sprite2D
	_depth.world = get_parent().get_parent()
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_shader_material.shader = SHADER
	material = _shader_material
	var params := Slowdown.params()
	var tint: Array = params.get("copy_tint", [255, 255, 255])
	_shader_material.set_shader_parameter("tint", Vector3(float(tint[0]), float(tint[1]), float(tint[2])))
	_shader_material.set_shader_parameter("brightness", float(params.get("copy_brightness", 0)))
	_shader_material.set_shader_parameter("brightness_limit", float(params.get("copy_brightness_limit", 255)))
	_shader_material.set_shader_parameter("weight", float(params.get("copy_weight", 0)))
	_shader_material.set_shader_parameter("full_weight", float(params.get("copy_full_weight", 255)))
	set_process(is_visible_in_tree())


# Only a slowed agent draws copies, so only then does this run every frame, paused or not.
func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and is_node_ready():
		set_process(is_visible_in_tree())
		refresh()


func _process(_delta: float) -> void:
	refresh()


# Fresh offsets for every copy, the frame the agent shows now and the depth test for it.
func refresh() -> void:
	offsets.clear()
	frame = null
	drawn_bounds = Rect2()
	if is_visible_in_tree() and _sprite != null and _sprite.texture != null:
		_prepare()
	queue_redraw()


func _prepare() -> void:
	var params := Slowdown.params()
	var jitter_y: Array = params.get("copy_jitter_y", [1, 0])
	var jitter_x: Array = params.get("copy_jitter_x", [1, 0])
	frame = _sprite.texture
	# CharacterDepthCompositor draws the frame at its rounded top left.
	anchor = (_sprite.global_position + _sprite.offset).round()
	var size := frame.get_size()
	for _copy in range(int(params.get("copy_count", 0))):
		var y := int(random.call()) % int(jitter_y[0]) + int(jitter_y[1])
		var x := int(random.call()) % int(jitter_x[0]) + int(jitter_x[1])
		offsets.append(Vector2i(x, y))
		var rect := Rect2(anchor + Vector2(x, y), size)
		drawn_bounds = rect if not drawn_bounds.has_area() else drawn_bounds.merge(rect)
	depth_base = CharacterDepthCompositor.base_score(_sprite.global_position.y) - float(params.get("copy_depth_offset", 0))
	var plane := _depth_plane()
	_shader_material.set_shader_parameter("depth_plane", plane)
	_shader_material.set_shader_parameter("depth_plane_enabled", plane != null)
	_shader_material.set_shader_parameter("depth_base", depth_base)
	_depth.update(self, _shader_material, drawn_bounds)


func _depth_plane() -> Texture2D:
	var compositor := _depth.world.get_node_or_null("CharacterDepthCompositor") if _depth.world != null else null
	return compositor.call("depth_texture_for", _sprite) if compositor != null else null


func _draw() -> void:
	if frame == null:
		return
	for offset in offsets:
		draw_texture(frame, to_local(anchor + Vector2(offset)))
