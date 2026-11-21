extends SceneTree

# Writes the two TileSets a level paints its INFODATA rooms and sight blockers with, so both
# can be painted and seen in the editor like the movement cells (docs/map-authoring.md):
#
#   resources/tilemaps/sacked-rooms.tres  one diamond, alternative n = room n for 0-31, each
#                                         tinted its own colour and named in a custom layer
#   resources/tilemaps/sacked-sight.tres  one diamond, a cell that blocks sight
#
#   ./Godot_v4.7.2-stable_linux.x86_64 --headless --script tools/build_editor_tilesets.gd
#
# A room is INFODATA bits 16-23, but the archetypes' goal masks are 32 bits wide, so only
# rooms 0-31 can ever be allowed to anyone. The three names are the rooms the lamps' smoke
# names (docs/player-ability-reference.md); the rest are numbers.

const ROOM_COUNT := 32
const ROOM_NAMES := {3: "waiting room", 4: "server room", 8: "boss office"}
const ROOMS_PATH := "res://resources/tilemaps/sacked-rooms.tres"
const SIGHT_PATH := "res://resources/tilemaps/sacked-sight.tres"
const ROOM_CELL := "res://images/tilemaps/room-cell.svg"
const SIGHT_CELL := "res://images/tilemaps/sight-cell.svg"
const GOLDEN_ANGLE := 0.381966


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := _save(_rooms(), ROOMS_PATH) or _save(_sight(), SIGHT_PATH)
	quit(1 if failed else 0)


func _tileset() -> TileSet:
	var tileset := TileSet.new()
	tileset.tile_shape = TileSet.TILE_SHAPE_ISOMETRIC
	tileset.tile_layout = TileSet.TILE_LAYOUT_DIAMOND_DOWN
	tileset.tile_size = Vector2i(96, 48)
	return tileset


func _source(texture_path: String) -> TileSetAtlasSource:
	var source := TileSetAtlasSource.new()
	source.texture = load(texture_path)
	source.texture_region_size = Vector2i(96, 48)
	source.create_tile(Vector2i.ZERO)
	return source


func _rooms() -> TileSet:
	var tileset := _tileset()
	tileset.add_custom_data_layer()
	tileset.set_custom_data_layer_name(0, "room")
	tileset.set_custom_data_layer_type(0, TYPE_INT)
	tileset.add_custom_data_layer()
	tileset.set_custom_data_layer_name(1, "room_name")
	tileset.set_custom_data_layer_type(1, TYPE_STRING)
	var source := _source(ROOM_CELL)
	tileset.add_source(source, 0)
	for room in range(ROOM_COUNT):
		if room > 0:
			source.create_alternative_tile(Vector2i.ZERO, room)
		var tile := source.get_tile_data(Vector2i.ZERO, room)
		# Room 0 is what an unpainted cell already is, so it is drawn faint.
		tile.modulate = Color(0.6, 0.6, 0.6, 0.35) if room == 0 else Color.from_hsv(fmod(room * GOLDEN_ANGLE, 1.0), 0.75, 1.0, 0.8)
		tile.set_custom_data("room", room)
		tile.set_custom_data("room_name", String(ROOM_NAMES.get(room, "room %d" % room)))
	return tileset


func _sight() -> TileSet:
	var tileset := _tileset()
	tileset.add_source(_source(SIGHT_CELL), 0)
	return tileset


func _save(tileset: TileSet, path: String) -> bool:
	var error := ResourceSaver.save(tileset, path)
	if error != OK:
		push_error("Failed to save %s: %s" % [path, error_string(error)])
		return true
	print("Saved %s" % path)
	return false
