@tool
extends Node2D


const COMPOSITOR := preload("res://scenes/shared/character_depth_compositor.gd")

var depth_scores := PackedFloat32Array()
var depth_bounds := Rect2()
var depth_texture: ImageTexture
var revision := 0
var partial_rebuilds := 0
var full_rebuilds := 0

var _composite: Sprite2D
var _image_compositor: Sprite2D
var _images: Dictionary = {}
var _depth_textures: Dictionary = {}
var _regions: Dictionary = {}
var _opaque_rects: Dictionary = {}
var _hidden_items: Array[CanvasItem] = []
var _signature := ""
var _dirty := true
var _warned: Dictionary = {}
# The composited buffers are kept so a change can be repainted in place. GDScript only ever
# writes into small scratch images that native blit_rect copies in, which keeps the large
# buffers off the copy-on-write path that sharing them with the character mask would put
# them on.
var _color_image: Image
var _score_image: Image
var _snapshot: Dictionary = {}
var _order: Array = []
var _tile_actors_cache: Dictionary = {}


func _ready() -> void:
	if not is_instance_valid(_composite):
		_composite = Sprite2D.new()
		_composite.centered = false
		_composite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(_composite, false, Node.INTERNAL_MODE_BACK)
	_image_compositor = COMPOSITOR.new()
	if not Engine.is_editor_hint():
		get_tree().node_added.connect(_on_tree_changed)
		get_tree().node_removed.connect(_on_tree_changed)
	_dirty = true
	call_deferred("rebuild")


func _exit_tree() -> void:
	if not Engine.is_editor_hint() and get_tree() != null:
		if get_tree().node_added.is_connected(_on_tree_changed):
			get_tree().node_added.disconnect(_on_tree_changed)
		if get_tree().node_removed.is_connected(_on_tree_changed):
			get_tree().node_removed.disconnect(_on_tree_changed)
	_restore_sources()
	if is_instance_valid(_image_compositor):
		_image_compositor.free()
	_image_compositor = null
	_composite.texture = null
	depth_scores = PackedFloat32Array()
	depth_bounds = Rect2()
	depth_texture = null
	_color_image = null
	_score_image = null
	_snapshot.clear()
	_order.clear()
	_tile_actors_cache.clear()
	_signature = ""
	_dirty = true
	request_ready()


func _process(_delta: float) -> void:
	if not _dirty:
		return
	rebuild()


func _on_tree_changed(node: Node) -> void:
	if node.is_in_group("depth_world_tiles") or node.is_in_group("depth_world_objects"):
		_dirty = true


func _mark_dirty() -> void:
	_dirty = true


func rebuild() -> void:
	if not is_instance_valid(_composite):
		return
	_dirty = false
	var sources: Array[CanvasItem] = []
	var actors := _collect_actors(sources)
	var signature := _actor_signature(actors)
	if signature == _signature:
		return
	if _rebuild_dirty_rects(actors, sources, signature):
		return
	_rebuild_everything(actors, sources, signature)


func _rebuild_everything(actors: Array, sources: Array[CanvasItem], signature: String) -> void:
	_signature = signature
	_restore_sources()
	if actors.is_empty():
		_composite.texture = null
		_color_image = null
		_score_image = null
		depth_scores = PackedFloat32Array()
		depth_bounds = Rect2()
		depth_texture = null
		_snapshot.clear()
		_order.clear()
	else:
		var bounds: Rect2 = _image_compositor.union_bounds(actors)
		var result: Dictionary = _image_compositor.compose_region(actors, bounds)
		depth_bounds = bounds
		depth_scores = result.scores
		_color_image = result.image
		_score_image = _score_image_for(bounds, depth_scores)
		_composite.texture = ImageTexture.create_from_image(_color_image)
		depth_texture = ImageTexture.create_from_image(_score_image) if _score_image != null else null
		_composite.global_position = depth_bounds.position
		# The buffer may have moved, so no remembered rectangle survives a full recomposite.
		_snapshot.clear()
		_remember(actors)
		_hide_sources(sources)
	full_rebuilds += 1
	revision += 1


# Repaints only the pixels that actually changed. A pixel depends solely on the actors
# covering it and on their order, so recomposing every actor that intersects a dirty
# rectangle reproduces the full rebuild exactly inside it and touches nothing outside.
func _rebuild_dirty_rects(actors: Array, sources: Array[CanvasItem], signature: String) -> bool:
	if _color_image == null or _score_image == null or _snapshot.is_empty() or actors.is_empty():
		return false
	if depth_texture == null or not (_composite.texture is ImageTexture):
		return false
	# The stored rectangles are relative to the current origin, so the buffer may grow into
	# a full rebuild but never moves or shrinks under them.
	if not depth_bounds.encloses(_image_compositor.union_bounds(actors)):
		return false
	var ids := []
	for actor in actors:
		ids.append(actor["id"])
	if not _order_is_preserved(ids):
		return false

	var rects := _dirty_rects(actors, ids)
	if rects.is_empty():
		return false
	var dirty_area := 0
	for rect in rects:
		dirty_area += rect.size.x * rect.size.y
	if dirty_area * 2 > int(depth_bounds.size.x) * int(depth_bounds.size.y):
		return false

	for rect in rects:
		_recompose_rect(rect, actors)
	_signature = signature
	depth_scores = _score_image.get_data().to_float32_array()
	(_composite.texture as ImageTexture).update(_color_image)
	depth_texture.update(_score_image)
	_restore_sources()
	_hide_sources(sources)
	_remember(actors)
	partial_rebuilds += 1
	revision += 1
	return true


func _recompose_rect(rect: Rect2i, actors: Array) -> void:
	var origin := depth_bounds.position
	var covering: Array = []
	for actor in actors:
		if rect.intersects(_image_compositor.actor_buffer_rect(actor, origin)):
			covering.append(actor)
	var region := Rect2(origin + Vector2(rect.position), Vector2(rect.size))
	var result: Dictionary = _image_compositor.compose_region(covering, region)
	var scores := _score_image_for(region, result.scores)
	if scores == null:
		return
	var window := Rect2i(Vector2i.ZERO, rect.size)
	# blit_rect overwrites rather than blends, so this also clears what used to be there.
	_color_image.blit_rect(result.image, window, rect.position)
	_score_image.blit_rect(scores, window, rect.position)


func _dirty_rects(actors: Array, ids: Array) -> Array[Rect2i]:
	var origin := depth_bounds.position
	var rects: Array[Rect2i] = []
	var live := {}
	for index in range(actors.size()):
		var id = ids[index]
		live[id] = true
		var previous = _snapshot.get(id)
		if previous == null:
			rects.append(_image_compositor.actor_buffer_rect(actors[index], origin))
		elif previous["signature"] != _signature_for(actors[index]):
			rects.append(_image_compositor.actor_buffer_rect(actors[index], origin))
			rects.append(previous["rect"])
	for id in _snapshot:
		if not live.has(id):
			rects.append(_snapshot[id]["rect"])
	return _merge_rects(rects)


func _merge_rects(rects: Array[Rect2i]) -> Array[Rect2i]:
	var buffer := Rect2i(Vector2i.ZERO, Vector2i(int(depth_bounds.size.x), int(depth_bounds.size.y)))
	var merged: Array[Rect2i] = []
	for rect in rects:
		var candidate := rect.intersection(buffer)
		if candidate.size.x <= 0 or candidate.size.y <= 0:
			continue
		var again := true
		while again:
			again = false
			for index in range(merged.size() - 1, -1, -1):
				if merged[index].grow(1).intersects(candidate):
					candidate = candidate.merge(merged[index])
					merged.remove_at(index)
					again = true
		merged.append(candidate)
	return merged


func _order_is_preserved(ids: Array) -> bool:
	var live := {}
	for id in ids:
		live[id] = true
	var before: Array = []
	for id in _order:
		if live.has(id):
			before.append(id)
	var after: Array = []
	for id in ids:
		if _snapshot.has(id):
			after.append(id)
	return before == after


func _remember(actors: Array) -> void:
	var origin := depth_bounds.position
	var previous := _snapshot
	_snapshot = {}
	_order.clear()
	for actor in actors:
		var id = actor["id"]
		var signature := _signature_for(actor)
		# An actor that did not change still covers the rectangle it covered before, and
		# the origin it was measured against only moves on a full recomposite.
		var known = previous.get(id)
		var rect: Rect2i
		if known != null and known["signature"] == signature:
			rect = known["rect"]
		else:
			rect = _image_compositor.actor_buffer_rect(actor, origin)
		_snapshot[id] = {"signature": signature, "rect": rect}
		_order.append(id)


# Recomposes the whole buffer without touching anything, so a test can hold the incremental
# result against what a full rebuild would have produced.
func compose_reference_for_test() -> Dictionary:
	var sources: Array[CanvasItem] = []
	return _image_compositor.compose_region(_collect_actors(sources), depth_bounds)


func _hide_sources(sources: Array[CanvasItem]) -> void:
	for source in sources:
		RenderingServer.canvas_item_set_visible(source.get_canvas_item(), false)
		_hidden_items.append(source)


func _collect_actors(sources: Array[CanvasItem]) -> Array:
	var actors: Array = []
	for node in get_tree().get_nodes_in_group("depth_world_tiles"):
		if not _belongs_to_world(node):
			continue
		var layer := node as TileMapLayer
		if layer == null or layer.tile_set == null:
			continue
		if not layer.changed.is_connected(_invalidate_tile_actors):
			layer.changed.connect(_invalidate_tile_actors)
		# Walking every painted cell costs more than composing a prank's dirty rectangle,
		# and the walls never change while one plays. Keyed by transform so a moved layer
		# still rebuilds.
		var cache_key := "%d:%s" % [layer.get_instance_id(), layer.global_transform]
		var layer_actors: Array = _tile_actors_cache.get(cache_key, [])
		if layer_actors.is_empty():
			layer_actors = _tile_actors(layer)
			_tile_actors_cache[cache_key] = layer_actors
		if not layer_actors.is_empty():
			sources.append(layer)
			actors.append_array(layer_actors)
	for node in get_tree().get_nodes_in_group("depth_world_objects"):
		if not _belongs_to_world(node) or not node.has_method("get_depth_actor"):
			continue
		if node.has_signal("changed") and not node.changed.is_connected(_mark_dirty):
			node.changed.connect(_mark_dirty)
		var actor: Dictionary = node.get_depth_actor()
		if _prepare_actor(actor):
			actors.append(actor)
			sources.append(actor.sprite)
	for index in range(actors.size()):
		actors[index]["index"] = index
	return actors


# The character shader samples these scores per pixel; R32F keeps the exact CPU value.
func _score_image_for(bounds: Rect2, scores: PackedFloat32Array) -> Image:
	var width := int(bounds.size.x)
	var height := int(bounds.size.y)
	if width <= 0 or height <= 0 or scores.size() != width * height:
		return null
	return Image.create_from_data(width, height, false, Image.FORMAT_RF, scores.to_byte_array())


func _belongs_to_world(node: Node) -> bool:
	if not (node is Node2D and get_parent().is_ancestor_of(node) and node.is_visible_in_tree()):
		return false
	if not node.visibility_changed.is_connected(_mark_dirty):
		node.visibility_changed.connect(_mark_dirty)
	return true


func _tile_actors(layer: TileMapLayer) -> Array:
	var actors: Array = []
	var cells := layer.get_used_cells()
	cells.sort_custom(func(a: Vector2i, b: Vector2i): return a.y < b.y or (a.y == b.y and a.x < b.x))
	for cell in cells:
		var source := layer.tile_set.get_source(layer.get_cell_source_id(cell)) as TileSetAtlasSource
		if source == null or source.texture == null:
			continue
		var coords := layer.get_cell_atlas_coords(cell)
		var tile := layer.get_cell_tile_data(cell)
		var region := source.get_tile_texture_region(coords)
		var color := _image(source.texture)
		var depth_path := source.texture.resource_path.get_basename() + "-depth.png"
		var depth_texture := _depth_texture(depth_path)
		if depth_texture == null:
			_warn_once(depth_path, "Missing tile depth mask: %s" % depth_path)
			continue
		var depth := _image(depth_texture)
		if color == null or depth == null or color.get_size() != depth.get_size():
			continue
		var anchor := layer.to_global(layer.map_to_local(cell))
		var base_offset := 0.0
		if layer.tile_set.get_custom_data_layer_by_name("depth_base_offset") >= 0:
			base_offset = float(tile.get_custom_data("depth_base_offset"))
		var color_region := _region(color, region)
		var actor := {
			"color": color_region,
			"depth": _region(depth, region),
			"position": anchor - Vector2(region.size) * 0.5 - Vector2(tile.texture_origin),
			"size": region.size,
			"base_y": ceilf(float(int(anchor.y)) * 0.5) + base_offset,
			"key": "%s:%s:%s" % [source.texture.resource_path, coords, layer.get_cell_alternative_tile(cell)],
			"id": "%d:%d:%d" % [layer.get_instance_id(), cell.x, cell.y],
		}
		actor["opaque_rect"] = _opaque_rect(color_region)
		actors.append(actor)
	return actors


func _prepare_actor(actor: Dictionary) -> bool:
	if actor.is_empty():
		return false
	var color_texture := actor.get("color") as Texture2D
	var depth_texture := actor.get("depth") as Texture2D
	if color_texture == null or depth_texture == null:
		_warn_once(str(actor.get("node")), "Map object needs both a color texture and a depth mask.")
		return false
	var color := _image(color_texture)
	var depth := _image(depth_texture)
	if color == null or depth == null or color.get_size() != depth.get_size():
		_warn_once(color_texture.resource_path, "Map object color and depth mask dimensions must match: %s" % color_texture.resource_path)
		return false
	actor["color"] = color
	actor["depth"] = depth
	actor["size"] = color.get_size()
	actor["opaque_rect"] = _opaque_rect(color)
	actor["key"] = "%s:%s" % [_texture_key(color_texture), _texture_key(depth_texture)]
	actor["id"] = (actor["node"] as Node).get_instance_id()
	return true


# Frames of an object state clip are reloaded by path, so keying on the path keeps a second
# load of the same image out of a fresh GPU readback and out of a spurious change signature.
func _texture_key(texture: Texture2D) -> String:
	var path := texture.resource_path
	return path if path != "" else str(texture.get_instance_id())


func _image(texture: Texture2D) -> Image:
	var key := _texture_key(texture)
	if not _images.has(key):
		if not texture.changed.is_connected(_invalidate_images):
			texture.changed.connect(_invalidate_images)
		var image := texture.get_image()
		if image != null and image.is_compressed():
			image.decompress()
		_images[key] = image
	return _images[key]


func _depth_texture(path: String) -> Texture2D:
	if not _depth_textures.has(path) and ResourceLoader.exists(path):
		_depth_textures[path] = load(path) as Texture2D
	return _depth_textures.get(path) as Texture2D


func _invalidate_tile_actors() -> void:
	_tile_actors_cache.clear()
	_dirty = true


func _invalidate_images() -> void:
	_images.clear()
	_regions.clear()
	_opaque_rects.clear()
	_tile_actors_cache.clear()
	if is_instance_valid(_image_compositor):
		_image_compositor.clear_image_caches()
	_signature = ""
	_dirty = true


func _region(image: Image, region: Rect2i) -> Image:
	var key := "%s:%s" % [image.get_instance_id(), region]
	if not _regions.has(key):
		_regions[key] = image.get_region(region)
	return _regions[key]


func _opaque_rect(image: Image) -> Rect2i:
	var key := image.get_instance_id()
	if not _opaque_rects.has(key):
		_opaque_rects[key] = image.get_used_rect()
	return _opaque_rects[key]


func _signature_for(actor: Dictionary) -> String:
	return "%s:%s:%s" % [actor.key, actor.position, actor.base_y]


func _actor_signature(actors: Array) -> String:
	var parts := PackedStringArray()
	for actor in actors:
		parts.append(_signature_for(actor))
	return "|".join(parts)


func _restore_sources() -> void:
	for item in _hidden_items:
		if is_instance_valid(item):
			RenderingServer.canvas_item_set_visible(item.get_canvas_item(), item.is_visible_in_tree())
	_hidden_items.clear()


func _warn_once(key: String, message: String) -> void:
	if _warned.has(key):
		return
	_warned[key] = true
	push_warning(message)
