@tool
class_name CharacterDepthCompositor
extends Sprite2D


const GROUP_NAME := "depth_composited_characters"
const DEPTH_SUFFIX := "-depth.png"
const EMPTY_SCORE := -1.0e30
const DEPTH_SHADER := preload("res://scenes/shared/character_depth.gdshader")

var _color_images: Dictionary = {}
var _depth_images: Dictionary = {}
var _image_bytes: Dictionary = {}
var _opaque_rects: Dictionary = {}
var _warned_paths: Dictionary = {}
var _hidden_sprites: Array[Sprite2D] = []
var _surfaces: Array[Sprite2D] = []
var _surface_textures: Array[ImageTexture] = []
var _surface_signatures: Array[String] = []
var _materials: Dictionary = {}
var _material_depth_paths: Dictionary = {}
var _depth_textures: Dictionary = {}
var _environment_texture: Texture2D
var _environment_applied := -1
var composed_scores := PackedFloat32Array()
var environment_scores := PackedFloat32Array()
var environment_bounds := Rect2()
var _environment_revision := -1
var _environment_instance_id := 0


func _ready() -> void:
	if Engine.is_editor_hint():
		set_process(false)
		return
	centered = false
	visible = false
	z_index = 1


func _exit_tree() -> void:
	_restore_actor_sprites()
	_clear_actor_materials()
	for index in range(1, _surfaces.size()):
		if is_instance_valid(_surfaces[index]):
			_surfaces[index].queue_free()
	_surfaces.clear()
	_surface_textures.clear()
	_surface_signatures.clear()


func _process(_delta: float) -> void:
	update_composition()


func update_composition() -> void:
	_update_environment()
	var actors := _collect_actors()
	# Occlusion against the static world runs per pixel on the GPU; only characters
	# that overlap each other still need a CPU composite to resolve mutual depth.
	# Each connected overlap group composites on its own surface so two distant
	# pairs never share one map-sized image.
	var clusters: Array = []
	for cluster in _overlap_clusters(actors):
		var prepared := _prepare_composite_actors(cluster)
		clusters.append_array(_overlap_clusters(prepared))
	_render_clusters(clusters)


func _overlap_clusters(actors: Array) -> Array:
	var rects: Array[Rect2] = []
	for actor in actors:
		rects.append(_actor_rect(actor))
	var visited: Array[bool] = []
	visited.resize(actors.size())
	var clusters: Array = []
	for index in range(actors.size()):
		if visited[index]:
			continue
		visited[index] = true
		var cluster: Array = [actors[index]]
		var frontier: Array[int] = [index]
		while not frontier.is_empty():
			var current: int = frontier.pop_back()
			for other in range(actors.size()):
				if visited[other] or not rects[current].intersects(rects[other]):
					continue
				visited[other] = true
				cluster.append(actors[other])
				frontier.append(other)
		if cluster.size() >= 2:
			clusters.append(cluster)
	return clusters


func _render_clusters(clusters: Array) -> void:
	var sprites_to_hide: Array[Sprite2D] = []
	var used := 0
	for cluster in clusters:
		var bounds := _calculate_union_bounds(cluster)
		if bounds.size.x <= 0 or bounds.size.y <= 0:
			continue
		var surface := _surface(used)
		var signature := _composite_signature(cluster, bounds)
		if not surface.visible or surface.texture == null or _surface_signatures[used] != signature:
			_set_surface_image(used, _compose_images(cluster, bounds))
			_surface_signatures[used] = signature
		surface.global_position = bounds.position
		surface.visible = true
		used += 1
		for actor in cluster:
			var actor_sprite := actor["sprite"] as Sprite2D
			if actor_sprite != null:
				sprites_to_hide.append(actor_sprite)
	for index in range(used, _surfaces.size()):
		_surfaces[index].visible = false
		_surface_signatures[index] = ""
	_hide_actor_sprites(sprites_to_hide)


func _surface(index: int) -> Sprite2D:
	while _surfaces.size() <= index:
		var surface: Sprite2D = self
		if not _surfaces.is_empty():
			surface = Sprite2D.new()
			surface.centered = false
			surface.z_index = z_index
			surface.texture_filter = texture_filter
			get_parent().add_child(surface, false, Node.INTERNAL_MODE_BACK)
		_surfaces.append(surface)
		_surface_textures.append(null)
		_surface_signatures.append("")
	return _surfaces[index]


func _update_environment() -> void:
	var world_mask := get_node_or_null("../WorldDepthCompositor")
	if world_mask == null:
		if _environment_instance_id != 0:
			_invalidate_surfaces()
		environment_scores = PackedFloat32Array()
		environment_bounds = Rect2()
		_environment_texture = null
		_environment_revision = -1
		_environment_instance_id = 0
		return
	environment_scores = world_mask.depth_scores
	environment_bounds = world_mask.depth_bounds
	_environment_texture = world_mask.depth_texture
	if _environment_revision != world_mask.revision or _environment_instance_id != world_mask.get_instance_id():
		_environment_revision = world_mask.revision
		_environment_instance_id = world_mask.get_instance_id()
		_environment_applied = -1
		_invalidate_surfaces()


func _invalidate_surfaces() -> void:
	for index in range(_surface_signatures.size()):
		_surface_signatures[index] = ""


func compose_images_for_test(actors: Array) -> Dictionary:
	return compose_region(actors, _calculate_union_bounds(actors))


# Composes into an arbitrary window instead of the actors' union. A window is offset from
# the union by whole pixels, so every actor lands on the same pixel either way.
func compose_region(actors: Array, region: Rect2) -> Dictionary:
	var output := _compose_images(actors, region)
	return {
		"bounds": region,
		"image": output,
		"scores": composed_scores,
	}


func union_bounds(actors: Array) -> Rect2:
	return _calculate_union_bounds(actors)


# The pixels _compose_actor writes for this actor, relative to a buffer origin. It repeats
# that function's rounding so a caller can clip to exactly the same rectangle.
func actor_buffer_rect(actor: Dictionary, origin: Vector2) -> Rect2i:
	var actor_position := actor["position"] as Vector2
	var source_rect := _actor_source_rect(actor)
	var dst_origin := Vector2i(
		int(round(actor_position.x - origin.x)),
		int(round(actor_position.y - origin.y))
	)
	return Rect2i(dst_origin + source_rect.position, source_rect.size)


func overlapping_actors_for_test(actors: Array) -> Array:
	return _filter_overlapping_actors(actors)


func clear_image_caches() -> void:
	_color_images.clear()
	_depth_images.clear()
	_image_bytes.clear()
	_opaque_rects.clear()


func _collect_actors() -> Array:
	var actors: Array = []
	var actor_index := 0
	var live_sprites: Dictionary = {}
	for node in get_tree().get_nodes_in_group(GROUP_NAME):
		if not is_instance_valid(node) or not node is Node2D:
			continue
		if not node.is_visible_in_tree() or not get_parent().is_ancestor_of(node) or not node.has_node("Sprite2D"):
			continue

		var sprite := node.get_node("Sprite2D") as Sprite2D
		if sprite == null or sprite.texture == null:
			continue
		if not sprite.visible and not _hidden_sprites.has(sprite):
			continue

		var actor := _make_actor(node, sprite, actor_index)
		if actor.is_empty():
			_clear_actor_material(sprite)
			continue
		actor_index += 1

		live_sprites[sprite.get_instance_id()] = true
		_apply_actor_material(actor)
		actors.append(actor)

	if _materials.size() > live_sprites.size():
		_prune_actor_materials(live_sprites)
	_environment_applied = _environment_revision
	return actors


func _make_actor(node: Node2D, sprite: Sprite2D, actor_index: int) -> Dictionary:
	var color_path := sprite.texture.resource_path
	if color_path == "":
		return {}

	var depth_path := _depth_path_for_texture(color_path)
	if depth_path == "":
		_warn_once(color_path, "Character texture has no depth-map convention: %s" % color_path)
		return {}
	var size := Vector2i(sprite.texture.get_width(), sprite.texture.get_height())
	if size.x <= 0 or size.y <= 0:
		return {}
	var actor := {
		"index": actor_index,
		"node": node,
		"sprite": sprite,
		"color_path": color_path,
		"depth_path": depth_path,
		"position": _sprite_draw_position(sprite, size),
		"size": size,
		# sub_41A2D0: base Z = trunc(49152 - projected_y / 2).
		"base_y": ceilf(float(int(node.global_position.y)) * 0.5),
	}
	if _opaque_rects.has(color_path):
		actor["opaque_rect"] = _opaque_rects[color_path]
	return actor


func _apply_actor_material(actor: Dictionary) -> void:
	var sprite := actor["sprite"] as Sprite2D
	var key := sprite.get_instance_id()
	var material := _materials.get(key) as ShaderMaterial
	if material == null or sprite.material != material:
		material = ShaderMaterial.new()
		material.shader = DEPTH_SHADER
		sprite.material = material
		_materials[key] = material
		_material_depth_paths[key] = ""

	# The world composite is a single sprite drawn after the characters, so a shaded
	# character has to sit above it and let the shader decide the per-pixel result.
	sprite.z_index = z_index
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var actor_position := actor["position"] as Vector2
	material.set_shader_parameter("pixel_snap", actor_position.round() - actor_position)
	var depth_path := String(actor["depth_path"])
	if String(_material_depth_paths.get(key, "")) != depth_path:
		_material_depth_paths[key] = depth_path
		var depth_texture := _depth_texture(depth_path)
		material.set_shader_parameter("depth_map", depth_texture)
		material.set_shader_parameter("depth_map_enabled", depth_texture != null)

	if _environment_applied != _environment_revision:
		material.set_shader_parameter("world_depth", _environment_texture)
		material.set_shader_parameter("world_depth_enabled", _environment_texture != null)
		material.set_shader_parameter("world_depth_origin", environment_bounds.position)
		material.set_shader_parameter("world_depth_size", environment_bounds.size)

	material.set_shader_parameter("base_y", float(actor["base_y"]))


func _depth_texture(path: String) -> Texture2D:
	if not _depth_textures.has(path):
		var texture: Texture2D = null
		if ResourceLoader.exists(path):
			texture = load(path) as Texture2D
		if texture == null:
			_warn_once(path, "Missing character depth map: %s" % path)
		_depth_textures[path] = texture
	return _depth_textures[path] as Texture2D


func _clear_actor_material(sprite: Sprite2D) -> void:
	var key := sprite.get_instance_id()
	if not _materials.has(key):
		return
	if sprite.material == _materials[key]:
		sprite.material = null
		sprite.z_index = 0
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_PARENT_NODE
	_materials.erase(key)
	_material_depth_paths.erase(key)


func _prune_actor_materials(live_sprites: Dictionary) -> void:
	for key in _materials.keys():
		if live_sprites.has(key):
			continue
		var sprite := instance_from_id(key) as Sprite2D
		if is_instance_valid(sprite) and sprite.material == _materials[key]:
			sprite.material = null
			sprite.z_index = 0
			sprite.texture_filter = CanvasItem.TEXTURE_FILTER_PARENT_NODE
		_materials.erase(key)
		_material_depth_paths.erase(key)


func _clear_actor_materials() -> void:
	_prune_actor_materials({})


func _prepare_composite_actors(actors: Array) -> Array:
	var prepared_actors: Array = []
	for actor in actors:
		var prepared_actor: Dictionary = actor.duplicate()
		if not prepared_actor.has("color") or not prepared_actor.has("depth"):
			if not _load_actor_images(prepared_actor):
				continue
		prepared_actors.append(prepared_actor)
	return prepared_actors


func _load_actor_images(actor: Dictionary) -> bool:
	var color_path := String(actor.get("color_path", ""))
	var depth_path := String(actor.get("depth_path", ""))
	if color_path == "" or depth_path == "":
		return actor.has("color") and actor.has("depth")
	var color_image = _load_image(color_path, _color_images)
	if color_image == null:
		return false

	# A few original frames ship no Z plane. The engine blits those without a depth
	# test, so keep the actor and let it paint over whatever the group already holds.
	var depth_image: Image = null
	if ResourceLoader.exists(depth_path) or FileAccess.file_exists(depth_path):
		depth_image = _load_image(depth_path, _depth_images)
		if depth_image == null:
			return false

	if depth_image != null and (color_image.get_width() != depth_image.get_width() or color_image.get_height() != depth_image.get_height()):
		_warn_once(depth_path, "Character depth map dimensions do not match texture: %s" % depth_path)
		return false

	var opaque_rect := _opaque_rect_for_image(color_path, color_image)
	if opaque_rect.size.x <= 0 or opaque_rect.size.y <= 0:
		return false

	actor["color"] = color_image
	actor["depth"] = depth_image
	actor["opaque_rect"] = opaque_rect
	return true


func _load_image(path: String, cache: Dictionary):
	if cache.has(path):
		return cache[path]

	var image_texture: Texture2D
	if ResourceLoader.exists(path):
		image_texture = load(path) as Texture2D
	var image: Image
	if image_texture != null:
		image = image_texture.get_image()
	else:
		image = Image.new()
		if image.load(path) != OK:
			_warn_once(path, "Failed to load image: %s" % path)
			return null

	if image == null:
		_warn_once(path, "Failed to read image: %s" % path)
		return null
	if image.is_compressed():
		image.decompress()

	cache[path] = image
	return image


func _rgba8_bytes(image: Image) -> PackedByteArray:
	var key := image.get_instance_id()
	if _image_bytes.has(key):
		return _image_bytes[key]
	var source := image
	if source.get_format() != Image.FORMAT_RGBA8:
		source = Image.new()
		source.copy_from(image)
		source.convert(Image.FORMAT_RGBA8)
	_image_bytes[key] = source.get_data()
	return _image_bytes[key]


func _depth_path_for_texture(texture_path: String) -> String:
	if not texture_path.ends_with(".png"):
		return ""
	return texture_path.substr(0, texture_path.length() - 4) + DEPTH_SUFFIX


func _sprite_draw_position(sprite: Sprite2D, image_size: Vector2i) -> Vector2:
	var draw_position := sprite.global_position + sprite.offset
	if sprite.centered:
		draw_position -= Vector2(image_size) * 0.5
	return draw_position


func _has_any_overlap(actors: Array) -> bool:
	for left_index in range(actors.size()):
		var left_rect := _actor_rect(actors[left_index])
		for right_index in range(left_index + 1, actors.size()):
			if left_rect.intersects(_actor_rect(actors[right_index])):
				return true
	return false


func _filter_overlapping_actors(actors: Array) -> Array:
	var overlapping_indices := {}
	for left_index in range(actors.size()):
		var left_rect := _actor_rect(actors[left_index])
		for right_index in range(left_index + 1, actors.size()):
			if left_rect.intersects(_actor_rect(actors[right_index])):
				overlapping_indices[left_index] = true
				overlapping_indices[right_index] = true

	var overlapping_actors: Array = []
	for index in range(actors.size()):
		if overlapping_indices.has(index):
			overlapping_actors.append(actors[index])
	return overlapping_actors


func _actor_rect(actor: Dictionary) -> Rect2:
	var source_rect := _actor_source_rect(actor)
	var actor_position := actor["position"] as Vector2
	return Rect2(actor_position + Vector2(source_rect.position), Vector2(source_rect.size))


func _actor_source_rect(actor: Dictionary) -> Rect2i:
	var actor_size := actor["size"] as Vector2i
	if actor.has("opaque_rect"):
		return actor["opaque_rect"] as Rect2i
	return Rect2i(Vector2i.ZERO, actor_size)


func _opaque_rect_for_image(path: String, image: Image) -> Rect2i:
	if _opaque_rects.has(path):
		return _opaque_rects[path] as Rect2i

	var rect := image.get_used_rect()
	_opaque_rects[path] = rect
	return rect


func _calculate_union_bounds(actors: Array) -> Rect2:
	var min_x := 1.0e20
	var min_y := 1.0e20
	var max_x := -1.0e20
	var max_y := -1.0e20

	for actor in actors:
		var actor_rect := _actor_rect(actor)
		min_x = minf(min_x, actor_rect.position.x)
		min_y = minf(min_y, actor_rect.position.y)
		max_x = maxf(max_x, actor_rect.end.x)
		max_y = maxf(max_y, actor_rect.end.y)

	var left := int(floor(min_x))
	var top := int(floor(min_y))
	var right := int(ceil(max_x))
	var bottom := int(ceil(max_y))
	return Rect2(Vector2(left, top), Vector2(right - left, bottom - top))


func _compose_images(actors: Array, bounds: Rect2) -> Image:
	var width := int(bounds.size.x)
	var height := int(bounds.size.y)
	var pixels := PackedByteArray()
	pixels.resize(width * height * 4)

	var scores := PackedFloat32Array()
	scores.resize(width * height)
	scores.fill(EMPTY_SCORE)

	for actor in actors:
		_compose_actor(pixels, scores, bounds.position, width, height, actor)

	composed_scores = scores
	return Image.create_from_data(width, height, false, Image.FORMAT_RGBA8, pixels)


func _compose_actor(pixels: PackedByteArray, scores: PackedFloat32Array, bounds_position: Vector2, width: int, height: int, actor: Dictionary) -> void:
	var color_image := actor["color"] as Image
	var depth_image := actor["depth"] as Image
	var color_bytes := _rgba8_bytes(color_image)
	var depth_bytes := _rgba8_bytes(depth_image) if depth_image != null else PackedByteArray()
	var depth_tested := not depth_bytes.is_empty()
	var source_width := color_image.get_width()
	var actor_position := actor["position"] as Vector2
	var source_rect := _actor_source_rect(actor)
	var source_min := source_rect.position
	var source_max := source_rect.position + source_rect.size
	var base_y := float(actor["base_y"])
	var dst_origin := Vector2i(
		int(round(actor_position.x - bounds_position.x)),
		int(round(actor_position.y - bounds_position.y))
	)
	var bounds_x := int(bounds_position.x)
	var bounds_y := int(bounds_position.y)
	var has_environment := not environment_scores.is_empty()
	var environment_width := int(environment_bounds.size.x)
	var environment_height := int(environment_bounds.size.y)
	var environment_x := int(environment_bounds.position.x)
	var environment_y := int(environment_bounds.position.y)

	# Clamped once instead of per pixel: composing into a small window then costs only the
	# pixels that land inside it.
	var y_start := maxi(source_min.y, -dst_origin.y)
	var y_end := mini(source_max.y, height - dst_origin.y)
	var x_start := maxi(source_min.x, -dst_origin.x)
	var x_end := mini(source_max.x, width - dst_origin.x)

	for source_y in range(y_start, y_end):
		var dst_y := dst_origin.y + source_y
		var source_row := source_y * source_width
		var dst_row := dst_y * width

		for source_x in range(x_start, x_end):
			var dst_x := dst_origin.x + source_x

			var source_index := (source_row + source_x) * 4
			if color_bytes[source_index + 3] == 0:
				continue
			var dst_index := dst_row + dst_x
			if not depth_tested:
				var untested_index := dst_index * 4
				pixels[untested_index] = color_bytes[source_index]
				pixels[untested_index + 1] = color_bytes[source_index + 1]
				pixels[untested_index + 2] = color_bytes[source_index + 2]
				pixels[untested_index + 3] = color_bytes[source_index + 3]
				continue
			if depth_bytes[source_index + 3] == 0:
				continue

			var score := base_y - float(depth_bytes[source_index] | (depth_bytes[source_index + 1] << 8))
			if has_environment:
				var environment_column := bounds_x + dst_x - environment_x
				var environment_row := bounds_y + dst_y - environment_y
				if environment_column >= 0 and environment_row >= 0 and environment_column < environment_width and environment_row < environment_height:
					if score < environment_scores[environment_row * environment_width + environment_column]:
						continue

			if score >= scores[dst_index]:
				scores[dst_index] = score
				var output_index := dst_index * 4
				pixels[output_index] = color_bytes[source_index]
				pixels[output_index + 1] = color_bytes[source_index + 1]
				pixels[output_index + 2] = color_bytes[source_index + 2]
				pixels[output_index + 3] = color_bytes[source_index + 3]


func _set_surface_image(index: int, image: Image) -> void:
	var composite_texture := _surface_textures[index]
	if composite_texture == null or composite_texture.get_width() != image.get_width() or composite_texture.get_height() != image.get_height():
		composite_texture = ImageTexture.create_from_image(image)
		_surface_textures[index] = composite_texture
	else:
		composite_texture.update(image)
	_surfaces[index].texture = composite_texture


func _composite_signature(actors: Array, bounds: Rect2) -> String:
	var parts: Array[String] = [
		"%.3f,%.3f,%.3f,%.3f" % [bounds.position.x, bounds.position.y, bounds.size.x, bounds.size.y],
	]
	for actor in actors:
		var actor_position := actor["position"] as Vector2
		var actor_size := actor["size"] as Vector2i
		var sprite := actor.get("sprite") as Sprite2D
		var texture_path := ""
		if sprite != null and sprite.texture != null:
			texture_path = sprite.texture.resource_path
		parts.append("%s|%.3f|%.3f|%d|%d|%.3f" % [
			texture_path,
			actor_position.x,
			actor_position.y,
			actor_size.x,
			actor_size.y,
			float(actor["base_y"]),
		])
	return ";".join(parts)


func _hide_actor_sprites(sprites_to_hide: Array[Sprite2D]) -> void:
	for actor_sprite in _hidden_sprites:
		if is_instance_valid(actor_sprite) and not sprites_to_hide.has(actor_sprite):
			actor_sprite.visible = true

	_hidden_sprites.clear()
	for actor_sprite in sprites_to_hide:
		actor_sprite.visible = false
		_hidden_sprites.append(actor_sprite)


func _restore_actor_sprites() -> void:
	for actor_sprite in _hidden_sprites:
		if is_instance_valid(actor_sprite):
			actor_sprite.visible = true
	_hidden_sprites.clear()


func _warn_once(key: String, message: String) -> void:
	if _warned_paths.has(key):
		return
	_warned_paths[key] = true
	push_warning(message)
