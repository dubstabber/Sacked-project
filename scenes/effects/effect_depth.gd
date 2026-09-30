extends RefCounted

# What an effect the player spawned is tested against. Main_RenderUpdate draws the effects list
# after every item and character (0x402B38), and each effect tests its own Z against the buffer
# the walls, the items and the characters filled, writing nothing. The port has no shared Z
# buffer, so an effect tests the world composite for the walls and items, and in place of the
# characters' Z the own depth planes of the depth-composited actors its bounds overlap. This is
# the half that hands them to the shader; scenes/effects/effect_depth.gdshaderinc is the test.
# See docs/map-rendering.md, "Effects drawn after the characters".

# How many actors the shader tests, nearest first; a seventh would not hide the effect.
const MAX_ACTORS := 6
const ACTOR_GROUP := &"depth_composited_characters"

# The level's World, which holds the composites and the actors. An effect is World's own child;
# a slowed agent's green copies sit under the agent, so they name it here.
var world: Node
var _world_mask: Node
var _world_revision := -1
var _characters: Node
var _actor_key: Array = []


# The world composite whenever it changes, and the actors over `bounds` whenever that set does.
func update(effect: CanvasItem, shader_material: ShaderMaterial, bounds: Rect2) -> void:
	if shader_material == null:
		return
	var mask := _world_depth_mask(effect)
	if mask != null and int(mask.get("revision")) != _world_revision:
		_world_revision = int(mask.get("revision"))
		var buffer: Texture2D = mask.get("depth_texture")
		var mask_bounds: Rect2 = mask.get("depth_bounds")
		shader_material.set_shader_parameter("world_depth", buffer)
		shader_material.set_shader_parameter("world_depth_enabled", buffer != null)
		shader_material.set_shader_parameter("world_depth_origin", mask_bounds.position)
		shader_material.set_shader_parameter("world_depth_size", mask_bounds.size)
	var actors := depth_actors(effect, bounds)
	var key: Array = []
	for actor: Dictionary in actors:
		key.append_array([actor["rect"], actor["depth"], actor["base_y"]])
	if key == _actor_key:
		return
	_actor_key = key
	var rects: Array[Vector4] = []
	var bases := PackedFloat32Array()
	for index in range(MAX_ACTORS):
		var actor: Dictionary = actors[index] if index < actors.size() else {}
		var rect: Rect2 = actor.get("rect", Rect2())
		rects.append(Vector4(rect.position.x, rect.position.y, rect.size.x, rect.size.y))
		bases.append(float(actor.get("base_y", 0.0)))
		shader_material.set_shader_parameter("actor_depth_%d" % index, actor.get("depth"))
	shader_material.set_shader_parameter("actor_rect", rects)
	shader_material.set_shader_parameter("actor_base", bases)
	shader_material.set_shader_parameter("actor_count", actors.size())


# The depth-composited actors whose frame overlaps `bounds`, nearest first and at most
# MAX_ACTORS: each one's own depth plane, where it is drawn, and its base score, as
# CharacterDepthCompositor draws it.
func depth_actors(effect: CanvasItem, bounds: Rect2) -> Array:
	var result: Array = []
	if not bounds.has_area() or not effect.is_inside_tree():
		return result
	var level_world := _world(effect)
	var compositor := _character_compositor(effect)
	for node in effect.get_tree().get_nodes_in_group(ACTOR_GROUP):
		var actor := node as Node2D
		if actor == null or not actor.is_visible_in_tree() or not level_world.is_ancestor_of(actor):
			continue
		# The compositor hides the sprites it draws on a surface of its own, so the sprite's
		# own flag says nothing here; the frame stays current.
		var sprite := actor.get_node_or_null("Sprite2D") as Sprite2D
		if sprite == null or sprite.texture == null:
			continue
		var size := sprite.texture.get_size()
		var origin := sprite.global_position + sprite.offset
		if sprite.centered:
			origin -= size * 0.5
		var rect := Rect2(origin.round(), size)
		if not rect.intersects(bounds):
			continue
		var depth: Texture2D = compositor.call("depth_texture_for", sprite) if compositor != null else null
		if depth == null:
			continue
		result.append({
			"rect": rect,
			"depth": depth,
			"base_y": CharacterDepthCompositor.base_score(sprite.global_position.y),
		})
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["base_y"]) > float(b["base_y"]))
	return result.slice(0, MAX_ACTORS)


func _world(effect: CanvasItem) -> Node:
	return world if is_instance_valid(world) else effect.get_parent()


func _world_depth_mask(effect: CanvasItem) -> Node:
	if not is_instance_valid(_world_mask) and _world(effect) != null:
		_world_mask = _world(effect).get_node_or_null("WorldDepthCompositor")
	return _world_mask


func _character_compositor(effect: CanvasItem) -> Node:
	if not is_instance_valid(_characters) and _world(effect) != null:
		_characters = _world(effect).get_node_or_null("CharacterDepthCompositor")
	return _characters
