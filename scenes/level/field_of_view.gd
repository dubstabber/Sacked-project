extends Node2D

# The floor the selected colleague can see, tinted blue. Main_RenderUpdate calls sub_402260
# right after the floor (0x402993). For the one agent the player last clicked (agent+1788),
# while the agent is less than 12 tiles from the player on both axes, sub_4179B0 builds the
# field-of-view mask from its eased heading and sub_417440 hands it to sub_4298E0, which adds
# it to the floor. Walls, items, characters and everything after them are painted over it.
# See docs/field-of-view-reference.md.

const MASK := preload("res://scenes/shared/field_of_view_mask.gd")
const SHADER := preload("res://scenes/shared/field_of_view.gdshader")
const AGENT_GROUP := &"npc_agents"
const PLAYER_GROUP := &"player_actions"

# The original's raster steps stop short of the far edge and never reach texel 113, so the
# affine mapping that fits it best puts the right, bottom and left corners at 112/113. See
# "The draw".
const FAR_UV := 112.0 / 113.0
# Above the floor bake (z -20), below the walls (-5), the glass (-4), the world composite (0)
# and every character, effect and HUD layer: the original paints it after the floor and
# before everything else.
const DRAW_Z := -10

# The agent whose field of view is drawn, or null when nothing is.
var agent: Node2D = null
# How many mask builds there have been; a build runs only when an input moved.
var builds := 0
var mask := MASK.new()
var texture := ImageTexture.new()

var _texel_image: Image
var _material := ShaderMaterial.new()
var _level: Node
var _layer: CollisionMapLayer
var _player: Node2D
var _sight := PackedByteArray()
var _sight_width := 0
var _sight_height := 0
var _inputs := []
var _points := PackedVector2Array()
var _uvs := PackedVector2Array([Vector2(0.0, 0.0), Vector2(FAR_UV, 0.0), Vector2(FAR_UV, FAR_UV), Vector2(0.0, FAR_UV)])
var _colors := PackedColorArray([Color.WHITE])


func _ready() -> void:
	z_index = DRAW_Z
	z_as_relative = false
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	texture_repeat = CanvasItem.TEXTURE_REPEAT_DISABLED
	_material.shader = SHADER
	material = _material
	_texel_image = Image.create_empty(MASK.SIDE, MASK.SIDE, false, Image.FORMAT_R8)
	texture.set_image(_texel_image)
	visible = false
	call_deferred("_bind")


func _bind() -> void:
	_level = get_parent().get_parent() if get_parent() != null else null
	_player = null
	for actions in get_tree().get_nodes_in_group(PLAYER_GROUP):
		if _in_level(actions):
			_player = actions.get_parent() as Node2D
			break
	_layer = CollisionMapLayer.of(_player)
	_read_sight()


func _in_level(node: Node) -> bool:
	return _level == null or _level.is_ancestor_of(node)


# INFODATA bit 1 over the map's own width and height; a cell off the map never blocks.
func _read_sight() -> void:
	_sight = PackedByteArray()
	_sight_width = 0
	_sight_height = 0
	if _layer == null:
		return
	var size: Vector2i = _layer.get("room_grid_size")
	_sight = _layer.sight_grid()
	_sight_width = size.x
	_sight_height = size.y


func _process(_delta: float) -> void:
	var selected := _selected_agent()
	var brain := selected.get_node_or_null("Brain") if selected != null else null
	# The radius and cone come from the profile once the brain has read it.
	if brain == null or not brain.has_method("is_initialized") or not brain.is_initialized():
		_hide()
		return
	var at: Vector2 = _layer.to_grid_position(selected.global_position)
	var player_at: Vector2 = _layer.to_grid_position(_player.global_position)
	if not passes_gate(at, player_at):
		_hide()
		return
	var inputs := [at.x, at.y, brain.notice_radius_tiles(), float(selected.get("notice_heading")), brain.notice_cone_degrees(), _sight]
	if inputs != _inputs:
		_inputs = inputs
		mask.build(at.x, at.y, inputs[2], inputs[3], inputs[4], _sight, _sight_width, _sight_height)
		_texel_image.set_data(MASK.SIDE, MASK.SIDE, false, Image.FORMAT_R8, mask.texels)
		texture.update(_texel_image)
		builds += 1
	# The diamond's 7.0 (0x4667B8), which tools/export_fov_tables.py writes beside the tables.
	var reach := MASK.REACH_TILES
	var points := PackedVector2Array([
		_ground(at + Vector2(-reach, -reach)),
		_ground(at + Vector2(reach, -reach)),
		_ground(at + Vector2(reach, reach)),
		_ground(at + Vector2(-reach, reach)),
	])
	if points != _points or agent != selected:
		_points = points
		queue_redraw()
	agent = selected
	visible = true


# Agent minus player on each axis, signed and strict: an agent far off toward -x or -z still
# passes, which the original does too. Each fcomp sets C0 for "less" and for unordered, so a
# NaN passes as well (0x4022CF, 0x4022E0).
static func passes_gate(agent_at: Vector2, player_at: Vector2) -> bool:
	MASK.load_tables()
	# The 12.0 at flt_4652CC, written beside the tables.
	var gate := MASK.GATE_TILES
	return not (agent_at.x - player_at.x >= gate) and not (agent_at.y - player_at.y >= gate)


func _hide() -> void:
	agent = null
	visible = false


# At most one: selecting a colleague clears the flag on every other (sub_403780, 0x403A18).
func _selected_agent() -> Node2D:
	if _layer == null or _player == null:
		return null
	for node in get_tree().get_nodes_in_group(AGENT_GROUP):
		if node.get("selected") == true and _in_level(node):
			return node as Node2D
	return null


# The ground point of a logical (x, z) in this node's space, through the map's own axes.
func _ground(grid: Vector2) -> Vector2:
	return to_local(_layer.from_grid_position(grid))


# Top, right, bottom and left: the ground points (x -+ 7, z -+ 7) around the agent's raw
# position, with u along +x and v along +z.
func corners() -> PackedVector2Array:
	return _points


func _draw() -> void:
	if _points.size() == 4:
		draw_polygon(_points, _colors, _uvs, texture)
