@tool
extends Node2D


const COMPOSITOR := preload("res://scenes/shared/character_depth_compositor.gd")

var depth_scores := PackedFloat32Array()
var depth_bounds := Rect2()
var depth_texture: ImageTexture
var revision := 0

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
	_signature = signature
	_restore_sources()
	if actors.is_empty():
		_composite.texture = null
		depth_scores = PackedFloat32Array()
		depth_bounds = Rect2()
		depth_texture = null
	else:
		var result: Dictionary = _image_compositor.compose_images_for_test(actors)
		depth_bounds = result.bounds
		depth_scores = result.scores
		_composite.texture = ImageTexture.create_from_image(result.image)
		depth_texture = _score_texture(depth_bounds, depth_scores)
		_composite.global_position = depth_bounds.position
		for source in sources:
			RenderingServer.canvas_item_set_visible(source.get_canvas_item(), false)
			_hidden_items.append(source)
	revision += 1


func _collect_actors(sources: Array[CanvasItem]) -> Array:
	var actors: Array = []
	for node in get_tree().get_nodes_in_group("depth_world_tiles"):
		if not _belongs_to_world(node):
			continue
		var layer := node as TileMapLayer
		if layer == null or layer.tile_set == null:
			continue
		if not layer.changed.is_connected(_mark_dirty):
			layer.changed.connect(_mark_dirty)
		var layer_actors := _tile_actors(layer)
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
func _score_texture(bounds: Rect2, scores: PackedFloat32Array) -> ImageTexture:
	var width := int(bounds.size.x)
	var height := int(bounds.size.y)
	if width <= 0 or height <= 0 or scores.size() != width * height:
		return null
	return ImageTexture.create_from_image(
		Image.create_from_data(width, height, false, Image.FORMAT_RF, scores.to_byte_array())
	)


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
	actor["key"] = "%s:%s" % [color_texture.get_instance_id(), depth_texture.get_instance_id()]
	return true


func _image(texture: Texture2D) -> Image:
	var key := texture.get_instance_id()
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


func _invalidate_images() -> void:
	_images.clear()
	_regions.clear()
	_opaque_rects.clear()
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


func _actor_signature(actors: Array) -> String:
	var parts := PackedStringArray()
	for actor in actors:
		parts.append("%s:%s:%s" % [actor.key, actor.position, actor.base_y])
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
