extends SceneTree


const DEFAULT_MANIFEST_PATH := "res://resources/tilemaps/sacked-tile-atlases.json"
const ATLAS_ORDER := ["floor", "walls", "glass"]
const TILE_SHAPE := TileSet.TILE_SHAPE_ISOMETRIC
const TILE_LAYOUT := TileSet.TILE_LAYOUT_DIAMOND_DOWN
const TILE_SIZE := Vector2i(96, 48)
const SOURCE_ID := 3


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var manifest_path := _manifest_path()
	var manifest := _read_json(manifest_path)
	if manifest.is_empty():
		quit(1)
		return

	var atlases: Dictionary = manifest.get("atlases", {})
	for atlas_name in ATLAS_ORDER:
		if not atlases.has(atlas_name):
			push_error("Tile atlas manifest is missing '%s'" % atlas_name)
			quit(1)
			return
		if not _save_tileset(atlas_name, atlases[atlas_name]):
			quit(1)
			return

	quit(0)


func _manifest_path() -> String:
	var user_args := OS.get_cmdline_user_args()
	if user_args.size() > 0:
		return String(user_args[0])
	return DEFAULT_MANIFEST_PATH


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


func _save_tileset(atlas_name: String, atlas: Dictionary) -> bool:
	var image_path := String(atlas.get("image", ""))
	var tileset_path := String(atlas.get("tileset", ""))
	var texture := load(image_path) as Texture2D
	if texture == null:
		push_error("Failed to load atlas texture for %s: %s" % [atlas_name, image_path])
		return false

	var source := TileSetAtlasSource.new()
	source.texture = texture
	source.texture_region_size = _vector2i(atlas.get("cell_size", [0, 0]))
	var tile_set := TileSet.new()
	tile_set.tile_shape = TILE_SHAPE
	tile_set.tile_layout = TILE_LAYOUT
	tile_set.tile_size = TILE_SIZE
	tile_set.add_custom_data_layer()
	tile_set.set_custom_data_layer_name(0, "depth_base_offset")
	tile_set.set_custom_data_layer_type(0, TYPE_FLOAT)
	tile_set.add_source(source, SOURCE_ID)

	for tile in atlas.get("tiles", []):
		var atlas_coords := _vector2i(tile.get("atlas_coords", [0, 0]))
		source.create_tile(atlas_coords)
		var tile_data := source.get_tile_data(atlas_coords, 0)
		if tile_data == null:
			push_error("Failed to create tile %s at %s" % [atlas_name, atlas_coords])
			return false
		var pivot := _vector2i(tile.get("pivot", [0, 0]))
		var paste_offset := _vector2i(tile.get("paste_offset", [0, 0]))
		tile_data.texture_origin = pivot + paste_offset - source.texture_region_size / 2
		tile_data.set_custom_data("depth_base_offset", -36.0 if atlas_name == "walls" else 0.0)

	var save_error := ResourceSaver.save(tile_set, tileset_path)
	if save_error != OK:
		push_error("Failed to save %s: %s" % [tileset_path, error_string(save_error)])
		return false

	print("Saved %s" % tileset_path)
	return true


func _vector2i(value) -> Vector2i:
	if value is Vector2i:
		return value
	if value is Array and value.size() >= 2:
		return Vector2i(int(value[0]), int(value[1]))
	return Vector2i.ZERO
