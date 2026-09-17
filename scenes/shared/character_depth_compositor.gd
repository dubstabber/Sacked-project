@tool
class_name CharacterDepthCompositor
extends Sprite2D


const GROUP_NAME := "depth_composited_characters"
const DEPTH_SUFFIX := "-depth.png"
const EMPTY_SCORE := -1.0e30

var _color_images: Dictionary = {}
var _depth_images: Dictionary = {}
var _opaque_rects: Dictionary = {}
var _warned_paths: Dictionary = {}
var _hidden_sprites: Array[Sprite2D] = []
var _composite_texture: ImageTexture
var _last_composite_signature := ""
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


func _process(_delta: float) -> void:
	update_composition()


func update_composition() -> void:
	_update_environment()
	var actors := _collect_actors()
	var uses_environment := not environment_scores.is_empty()
	var composite_actors := actors if uses_environment else _filter_overlapping_actors(actors)
	var minimum_count := 1 if uses_environment else 2
	if composite_actors.size() < minimum_count:
		_disable_composite()
		return
	composite_actors = _prepare_composite_actors(composite_actors)
	if not uses_environment:
		composite_actors = _filter_overlapping_actors(composite_actors)
	if composite_actors.size() < minimum_count:
		_disable_composite()
		return

	var bounds := _calculate_union_bounds(composite_actors)
	if bounds.size.x <= 0 or bounds.size.y <= 0:
		_disable_composite()
		return

	var signature := _composite_signature(composite_actors, bounds)
	if visible and _composite_texture != null and signature == _last_composite_signature:
		global_position = bounds.position
		_hide_actor_sprites(composite_actors)
		return

	var output := _compose_images(composite_actors, bounds)
	_set_composite_image(output)
	global_position = bounds.position
	visible = true
	_last_composite_signature = signature
	_hide_actor_sprites(composite_actors)


func _update_environment() -> void:
	var world_mask := get_node_or_null("../WorldDepthCompositor")
	if world_mask == null:
		if _environment_instance_id != 0:
			_last_composite_signature = ""
		environment_scores = PackedFloat32Array()
		environment_bounds = Rect2()
		_environment_revision = -1
		_environment_instance_id = 0
		return
	environment_scores = world_mask.depth_scores
	environment_bounds = world_mask.depth_bounds
	if _environment_revision != world_mask.revision or _environment_instance_id != world_mask.get_instance_id():
		_environment_revision = world_mask.revision
		_environment_instance_id = world_mask.get_instance_id()
		_last_composite_signature = ""


func compose_images_for_test(actors: Array) -> Dictionary:
	var bounds := _calculate_union_bounds(actors)
	var output := _compose_images(actors, bounds)
	return {
		"bounds": bounds,
		"image": output,
		"scores": composed_scores,
	}


func overlapping_actors_for_test(actors: Array) -> Array:
	return _filter_overlapping_actors(actors)


func _collect_actors() -> Array:
	var actors: Array = []
	var actor_index := 0
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
		actor_index += 1
		if actor.is_empty():
			continue

		actors.append(actor)

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
	if not ResourceLoader.exists(depth_path) and not FileAccess.file_exists(depth_path):
		_warn_once(depth_path, "Missing character depth map: %s" % depth_path)
		return false

	var color_image = _load_image(color_path, _color_images)
	var depth_image = _load_image(depth_path, _depth_images)
	if color_image == null or depth_image == null:
		return false

	if color_image.get_width() != depth_image.get_width() or color_image.get_height() != depth_image.get_height():
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
	var output := Image.create(width, height, false, Image.FORMAT_RGBA8)
	output.fill(Color(0.0, 0.0, 0.0, 0.0))

	var scores := PackedFloat32Array()
	scores.resize(width * height)
	for index in range(scores.size()):
		scores[index] = EMPTY_SCORE

	for actor in actors:
		_compose_actor(output, scores, bounds.position, width, actor)

	composed_scores = scores
	return output


func _compose_actor(output: Image, scores: PackedFloat32Array, bounds_position: Vector2, width: int, actor: Dictionary) -> void:
	var color_image := actor["color"] as Image
	var depth_image := actor["depth"] as Image
	var actor_position := actor["position"] as Vector2
	var source_rect := _actor_source_rect(actor)
	var source_min := source_rect.position
	var source_max := source_rect.position + source_rect.size
	var base_y := float(actor["base_y"])
	var output_height := output.get_height()
	var output_width := output.get_width()
	var dst_origin := Vector2i(
		int(round(actor_position.x - bounds_position.x)),
		int(round(actor_position.y - bounds_position.y))
	)

	for source_y in range(source_min.y, source_max.y):
		var dst_y := dst_origin.y + source_y
		if dst_y < 0 or dst_y >= output_height:
			continue

		for source_x in range(source_min.x, source_max.x):
			var dst_x := dst_origin.x + source_x
			if dst_x < 0 or dst_x >= output_width:
				continue

			var color := color_image.get_pixel(source_x, source_y)
			if color.a <= 0.0:
				continue

			var depth_pixel := depth_image.get_pixel(source_x, source_y)
			if depth_pixel.a <= 0.0:
				continue

			var score := base_y - float(_decode_depth(depth_pixel))
			if not environment_scores.is_empty():
				var world_pixel := Vector2i(bounds_position) + Vector2i(dst_x, dst_y) - Vector2i(environment_bounds.position)
				if world_pixel.x >= 0 and world_pixel.y >= 0 and world_pixel.x < int(environment_bounds.size.x) and world_pixel.y < int(environment_bounds.size.y):
					if score < environment_scores[world_pixel.y * int(environment_bounds.size.x) + world_pixel.x]:
						continue
			var dst_index := dst_y * width + dst_x
			if score >= scores[dst_index]:
				scores[dst_index] = score
				output.set_pixel(dst_x, dst_y, color)


func _decode_depth(depth_pixel: Color) -> int:
	var low := int(round(depth_pixel.r * 255.0))
	var high := int(round(depth_pixel.g * 255.0))
	return low | (high << 8)


func _set_composite_image(image: Image) -> void:
	if _composite_texture == null or _composite_texture.get_width() != image.get_width() or _composite_texture.get_height() != image.get_height():
		_composite_texture = ImageTexture.create_from_image(image)
	else:
		_composite_texture.update(image)
	texture = _composite_texture


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


func _hide_actor_sprites(actors: Array) -> void:
	var sprites_to_hide: Array[Sprite2D] = []
	for actor in actors:
		var actor_sprite := actor["sprite"] as Sprite2D
		if actor_sprite != null:
			sprites_to_hide.append(actor_sprite)

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


func _disable_composite() -> void:
	_restore_actor_sprites()
	_last_composite_signature = ""
	visible = false


func _warn_once(key: String, message: String) -> void:
	if _warned_paths.has(key):
		return
	_warned_paths[key] = true
	push_warning(message)
