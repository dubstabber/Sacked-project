extends SceneTree


const DEFAULT_MANIFEST_PATH := "res://resources/levels/level_1.json"
const DEFAULT_SCENE_PATH := "res://scenes/level_1.tscn"
const TILE_SIZE := Vector2(94.0, 48.0)
const PLAYER_SCENE := "res://scenes/player/player.tscn"
const DEPTH_COMPOSITOR_SCRIPT := "res://scenes/shared/character_depth_compositor.gd"
const FPS_COUNTER_SCRIPT := "res://scenes/debug/fps_counter.gd"


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var manifest_path := DEFAULT_MANIFEST_PATH
	var scene_path := DEFAULT_SCENE_PATH
	if args.size() >= 1:
		manifest_path = String(args[0])
	if args.size() >= 2:
		scene_path = String(args[1])

	var manifest := _read_json(manifest_path)
	if manifest.is_empty():
		quit(1)
		return

	var root := _build_scene(manifest)
	var packed := PackedScene.new()
	var pack_error := packed.pack(root)
	if pack_error != OK:
		push_error("Failed to pack level scene: %s" % error_string(pack_error))
		quit(1)
		return

	var save_error := ResourceSaver.save(packed, scene_path)
	if save_error != OK:
		push_error("Failed to save %s: %s" % [scene_path, error_string(save_error)])
		root.free()
		quit(1)
		return

	print("Saved %s" % scene_path)
	root.free()
	quit(0)


func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Failed to open %s" % path)
		return {}

	var parsed = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		return parsed

	push_error("Failed to parse %s" % path)
	return {}


func _resource_path(path: String) -> String:
	if path.begins_with("res://") or path.begins_with("user://"):
		return path
	if path == "":
		return path
	return "res://%s" % path


func _build_scene(manifest: Dictionary) -> Node:
	var root := Node.new()
	root.name = "Main"

	var world := Node2D.new()
	world.name = "World"
	root.add_child(world)

	var atlas_manifest := _read_json(_resource_path(String(manifest.get("tile_atlas_manifest", ""))))
	var floor_layer: TileMapLayer = null
	for layer_data in manifest.get("tile_layers", []):
		if String(layer_data.get("name", "")) == "WallTileMapLayer":
			if floor_layer == null:
				push_error("Wall layer appeared before FloorTileMapLayer")
				continue
			world.add_child(_build_wall_sprite_layer(layer_data, atlas_manifest, floor_layer))
			continue
		var layer := _build_tile_layer(layer_data)
		world.add_child(layer)
		if layer.name == "FloorTileMapLayer":
			floor_layer = layer

	if floor_layer == null:
		push_error("Level manifest did not create FloorTileMapLayer")
		return root

	var objects := _build_objects(manifest, floor_layer)
	world.add_child(objects)

	var player := _build_player(manifest, floor_layer)
	world.add_child(player)

	var compositor := Sprite2D.new()
	compositor.name = "CharacterDepthCompositor"
	compositor.script = load(DEPTH_COMPOSITOR_SCRIPT)
	world.add_child(compositor)

	root.add_child(_build_debug_overlay())
	_assign_owner(root, root)
	return root


func _build_tile_layer(layer_data: Dictionary) -> TileMapLayer:
	var layer := TileMapLayer.new()
	layer.name = String(layer_data.get("name", "TileMapLayer"))
	layer.tile_set = load(String(layer_data.get("tileset", ""))) as TileSet
	layer.z_index = int(layer_data.get("z_index", 0))
	for cell_data in layer_data.get("cells", []):
		var cell := _vector2i(cell_data.get("cell", [0, 0]))
		var atlas_coords := _vector2i(cell_data.get("atlas_coords", [0, 0]))
		var source_id := int(cell_data.get("source_id", -1))
		layer.set_cell(cell, source_id, atlas_coords, 0)
	return layer


func _build_wall_sprite_layer(layer_data: Dictionary, atlas_manifest: Dictionary, floor_layer: TileMapLayer) -> Node2D:
	var layer := Node2D.new()
	layer.name = "WallSprites"
	layer.z_index = int(layer_data.get("z_index", 0))

	var atlases: Dictionary = atlas_manifest.get("atlases", {})
	var wall_atlas: Dictionary = atlases.get("walls", {})
	var atlas_texture := load(String(wall_atlas.get("image", ""))) as Texture2D
	if atlas_texture == null:
		push_error("Failed to load wall atlas texture")
		return layer

	var cell_size := _vector2i(wall_atlas.get("cell_size", [0, 0]))
	var tiles_by_coords := _tiles_by_coords(wall_atlas)
	for cell_data in layer_data.get("cells", []):
		var atlas_coords := _vector2i(cell_data.get("atlas_coords", [0, 0]))
		var tile_info: Dictionary = tiles_by_coords.get(_coords_key(atlas_coords), {})
		var sprite := Sprite2D.new()
		sprite.name = "Wall%02d_%02d_%02d" % [
			int(cell_data.get("tile_id", 0)),
			int(_vector2i(cell_data.get("cell", [0, 0])).x),
			int(_vector2i(cell_data.get("cell", [0, 0])).y),
		]
		sprite.centered = false
		sprite.texture = _atlas_region_texture(atlas_texture, atlas_coords, cell_size)
		var cell := _vector2i(cell_data.get("cell", [0, 0]))
		sprite.position = _tile_position_to_local(Vector2(cell), floor_layer)
		sprite.offset = -_vector2(tile_info.get("pivot", [0, 0])) - _vector2(tile_info.get("paste_offset", [0, 0]))
		sprite.set_meta("original_tile_id", int(cell_data.get("tile_id", 0)))
		sprite.set_meta("original_cell", cell)
		layer.add_child(sprite)
	return layer


func _tiles_by_coords(atlas: Dictionary) -> Dictionary:
	var result := {}
	for tile in atlas.get("tiles", []):
		result[_coords_key(_vector2i(tile.get("atlas_coords", [0, 0])))] = tile
	return result


func _coords_key(coords: Vector2i) -> String:
	return "%d,%d" % [coords.x, coords.y]


func _atlas_region_texture(atlas_texture: Texture2D, atlas_coords: Vector2i, cell_size: Vector2i) -> AtlasTexture:
	var texture := AtlasTexture.new()
	texture.atlas = atlas_texture
	texture.region = Rect2(Vector2(atlas_coords * cell_size), Vector2(cell_size))
	return texture


func _build_objects(manifest: Dictionary, floor_layer: TileMapLayer) -> Node2D:
	var objects := Node2D.new()
	objects.name = "Objects"
	objects.z_index = 0
	for object_data in manifest.get("objects", []):
		var object_node := Node2D.new()
		object_node.name = String(object_data.get("node_name", "Object"))
		object_node.position = _tile_position_to_local(_vector2(object_data.get("tile_position", [0.0, 0.0])), floor_layer)
		object_node.set_meta("original_kind", String(object_data.get("kind", "")))
		object_node.set_meta("original_object_id", String(object_data.get("object_id", "")))
		object_node.set_meta("original_object_category", int(object_data.get("object_category", -1)))
		object_node.set_meta("original_sprite_name", String(object_data.get("sprite_name", "")))
		object_node.set_meta("original_source_sprite", String(object_data.get("source_sprite", "")))

		var sprite := Sprite2D.new()
		sprite.name = "Sprite2D"
		sprite.centered = false
		sprite.texture = load(String(object_data.get("texture", ""))) as Texture2D
		if sprite.texture != null:
			var pivot := _vector2(object_data.get("pivot", [float(sprite.texture.get_width()) * 0.5, float(sprite.texture.get_height())]))
			sprite.offset = -pivot
		object_node.add_child(sprite)
		objects.add_child(object_node)
	return objects


func _build_player(manifest: Dictionary, floor_layer: TileMapLayer) -> Node2D:
	var player_scene := load(PLAYER_SCENE) as PackedScene
	var player := player_scene.instantiate() as Node2D
	player.name = "Player"
	var spawn := _player_spawn(manifest)
	player.position = _tile_position_to_local(_vector2(spawn.get("tile_position", [0.0, 0.0])), floor_layer)
	player.set_meta("original_spawn_id", int(spawn.get("spawn_id", 0)))
	return player


func _player_spawn(manifest: Dictionary) -> Dictionary:
	var player_spawn_id := int(manifest.get("player_spawn_id", 0))
	for spawn in manifest.get("spawns", []):
		if int(spawn.get("spawn_id", -1)) == player_spawn_id:
			return spawn
	push_error("Missing player spawn id %d" % player_spawn_id)
	return {}


func _tile_position_to_local(tile_position: Vector2, floor_layer: TileMapLayer) -> Vector2:
	var origin := floor_layer.map_to_local(Vector2i.ZERO)
	var x_axis := floor_layer.map_to_local(Vector2i(1, 0)) - origin
	var y_axis := floor_layer.map_to_local(Vector2i(0, 1)) - origin
	return origin + x_axis * tile_position.x + y_axis * tile_position.y


func _build_debug_overlay() -> CanvasLayer:
	var overlay := CanvasLayer.new()
	overlay.name = "DebugOverlay"
	overlay.layer = 100

	var fps_counter := Label.new()
	fps_counter.name = "FPSCounter"
	fps_counter.offset_left = 8.0
	fps_counter.offset_top = 6.0
	fps_counter.offset_right = 108.0
	fps_counter.offset_bottom = 32.0
	fps_counter.text = "FPS: --"
	fps_counter.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	fps_counter.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	fps_counter.add_theme_constant_override("shadow_offset_x", 1)
	fps_counter.add_theme_constant_override("shadow_offset_y", 1)
	fps_counter.script = load(FPS_COUNTER_SCRIPT)
	overlay.add_child(fps_counter)
	return overlay


func _assign_owner(node: Node, owner: Node) -> void:
	for child in node.get_children():
		child.owner = owner
		if String(child.scene_file_path) == "":
			_assign_owner(child, owner)


func _vector2(value) -> Vector2:
	if value is Vector2:
		return value
	if value is Array and value.size() >= 2:
		return Vector2(float(value[0]), float(value[1]))
	return Vector2.ZERO


func _vector2i(value) -> Vector2i:
	if value is Vector2i:
		return value
	if value is Array and value.size() >= 2:
		return Vector2i(int(value[0]), int(value[1]))
	return Vector2i.ZERO
