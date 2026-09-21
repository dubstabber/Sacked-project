extends SceneTree


const Level1Scene := preload("res://scenes/level_1.tscn")
const ManifestPath := "res://resources/levels/level_1.json"
const TileAtlasPath := "res://resources/tilemaps/sacked-tile-atlases.json"
const NpcScriptPath := "res://scenes/npc/npc.gd"
const NpcBrainScriptPath := "res://scenes/npc/npc_brain.gd"
const ActivityPointScriptPath := "res://scenes/npc/npc_activity_point.gd"
const DirectionScript := preload("res://scenes/shared/iso_direction.gd")
const ExpectedWallTileOrder := [
	"walls-wall-vert",
	"walls-wall-horz",
	"walls-corner-top-left",
	"walls-corner-top-right",
	"walls-corner-bottom-left",
	"walls-corner-bottom-right",
	"walls-tj-left",
	"walls-tj-right",
	"walls-tj-top",
	"walls-tj-bottom",
	"walls-cross",
	"walls-wall-thick-left",
	"walls-wall-thick-right",
	"walls-wall-thick-top",
	"walls-wall-thick-bottom",
	"walls-corner-thick-top-left",
	"walls-corner-thick-top-right",
	"walls-corner-thick-bottom-left",
	"walls-corner-thick-bottom-right",
	"walls-tj-thick-left",
	"walls-tj-thick-right",
	"walls-tj-thick-top",
	"walls-tj-thick-bottom",
]
const ExpectedWallTextureOrigins := [
	[0, 73],
	[0, 73],
	[0, 73],
	[9, 73],
	[-9, 73],
	[0, 82],
	[0, 73],
	[0, 73],
	[0, 73],
	[0, 73],
	[0, 73],
	[9, 73],
	[-9, 64],
	[-9, 73],
	[9, 64],
	[0, 73],
	[-9, 64],
	[9, 64],
	[0, 64],
	[9, 73],
	[-9, 64],
	[-9, 73],
	[9, 64],
]
const ExpectedObjectSources := {
	8: "CO_OBJECTS_B_RO_SCHREIBTISCH02_IDLE_000_Schreibtisch02#000",
	12: "CO_OBJECTS_B_RO_SCHREIBTISCH01_IDLE_180_Schreibtisch01#180",
	19: "CO_OBJECTS_CHEF_SCHREIBTISCH02_IDLE_180_ChefSchreibtisch02#180",
}
# Sprite top-left pixels matched in debug1.png, cropped to the 800x600 game view.
const ReferenceCameraOffset := Vector2(556, -20)
const ReferenceObjectPixels := {
	19: Vector2(114, 210),
	20: Vector2(37, 135),
	41: Vector2(169, 213),
	50: Vector2(264, 119),
	51: Vector2(201, 121),
	53: Vector2(406, 259),
	56: Vector2(642, 122),
	62: Vector2(585, 101),
	71: Vector2(217, 386),
	77: Vector2(131, 189),
	78: Vector2(346, 327),
}

var _level
var _failed := false
var _brain_defaults: Dictionary = {}


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var manifest := _read_manifest()
	if manifest.is_empty():
		_fail("Level 1 manifest could not be read")
		return
	_check_wall_tile_manifest()
	if _failed:
		return

	_level = Level1Scene.instantiate()
	_disable_npcs_before_start()
	root.add_child(_level)
	await process_frame

	var world: Node = _level.get_node_or_null("World")
	if world == null:
		_fail("Level 1 has no World node")
		return

	var floor_layer := _require_tile_layer(world, "FloorTileMapLayer")
	var wall_layer := _require_tile_layer(world, "WallTileMapLayer")
	var glass_layer := _require_tile_layer(world, "GlassTileMapLayer")
	if _failed:
		return
	_check_tile_layout(floor_layer)
	_check_tile_layout(wall_layer)
	_check_tile_layout(glass_layer)
	_check_original_tile_axes(floor_layer)
	if _failed:
		return

	var map_data: Dictionary = manifest.get("map", {})
	_expect_equal(int(map_data.get("width", 0)), 16, "map width")
	_expect_equal(int(map_data.get("height", 0)), 16, "map height")
	_expect_equal(int(map_data.get("visible_width", 0)), 15, "visible map width")
	_expect_equal(int(map_data.get("visible_height", 0)), 15, "visible map height")
	_expect_equal(String(manifest.get("source", "")), "extract-sacked-assets/sacked/Levels/LEVEL_00.col", "original source level")
	_expect_equal(floor_layer.get_used_cells().size(), 225, "floor cell count")
	_expect_equal(wall_layer.get_used_cells().size(), 86, "wall cell count")
	_expect_equal(glass_layer.get_used_cells().size(), 0, "glass cell count")
	if _failed:
		return

	_check_visible_tile_bounds(manifest)
	if _failed:
		return
	_check_wall_tiles(wall_layer, manifest, floor_layer)
	if _failed:
		return
	_check_objects(world, manifest, floor_layer)
	if _failed:
		return
	_check_activity_points(world, manifest, floor_layer)
	if _failed:
		return
	_check_player(world, manifest, floor_layer)
	if _failed:
		return
	_check_npcs(world, manifest, floor_layer)
	if _failed:
		return
	_check_debug_overlay()
	if _failed:
		return

	_free_level()
	quit(0)


func _read_manifest() -> Dictionary:
	return _read_json(ManifestPath)


func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		return parsed
	return {}


func _check_wall_tile_manifest() -> void:
	var tile_manifest := _read_json(TileAtlasPath)
	var walls: Dictionary = tile_manifest.get("atlases", {}).get("walls", {})
	var tiles: Array = walls.get("tiles", [])
	_expect_equal(tiles.size(), ExpectedWallTileOrder.size(), "wall atlas tile count")
	if _failed:
		return
	for index in range(ExpectedWallTileOrder.size()):
		_expect_equal(String(tiles[index].get("tile_key", "")), String(ExpectedWallTileOrder[index]), "wall tile id %d" % (index + 1))
		_expect_equal(_int_array(tiles[index].get("texture_origin", [])), ExpectedWallTextureOrigins[index], "wall tile origin %d" % (index + 1))
		if _failed:
			return


func _require_tile_layer(world: Node, node_name: String) -> TileMapLayer:
	var layer := world.get_node_or_null(node_name) as TileMapLayer
	if layer == null:
		_fail("Level 1 missing TileMapLayer: %s" % node_name)
	return layer


func _check_tile_layout(layer: TileMapLayer) -> void:
	if layer.tile_set == null:
		_fail("%s has no TileSet" % layer.name)
		return
	if layer.tile_set.tile_shape != TileSet.TILE_SHAPE_ISOMETRIC:
		_fail("%s should use isometric tiles" % layer.name)
		return
	if layer.tile_set.tile_layout != TileSet.TILE_LAYOUT_DIAMOND_DOWN:
		_fail("%s should use diamond-down isometric layout" % layer.name)
		return
	if layer.tile_set.tile_size != Vector2i(96, 48):
		_fail("%s should use the original 96x48 map grid" % layer.name)
		return


func _check_original_tile_axes(layer: TileMapLayer) -> void:
	var origin := layer.map_to_local(Vector2i.ZERO)
	var x_axis := layer.map_to_local(Vector2i(1, 0)) - origin
	var y_axis := layer.map_to_local(Vector2i(0, 1)) - origin
	if not x_axis.is_equal_approx(Vector2(48.0, 24.0)):
		_fail("Level 1 x tile axis mismatch: expected (48, 24), got %s" % x_axis)
		return
	if not y_axis.is_equal_approx(Vector2(-48.0, 24.0)):
		_fail("Level 1 y tile axis mismatch: expected (-48, 24), got %s" % y_axis)


func _check_visible_tile_bounds(manifest: Dictionary) -> void:
	var map_data: Dictionary = manifest.get("map", {})
	var visible_width := int(map_data.get("visible_width", 0))
	var visible_height := int(map_data.get("visible_height", 0))
	for layer in manifest.get("tile_layers", []):
		for cell_data in layer.get("cells", []):
			var cell := _vector2i(cell_data.get("cell", [0, 0]))
			if cell.x >= visible_width or cell.y >= visible_height:
				_fail("%s has a visible padding cell at %s" % [String(layer.get("name", "")), cell])
				return


func _check_wall_tiles(wall_layer: TileMapLayer, manifest: Dictionary, floor_layer: TileMapLayer) -> void:
	var tile_manifest := _read_json(TileAtlasPath)
	var atlases: Dictionary = tile_manifest.get("atlases", {})
	var walls: Dictionary = atlases.get("walls", {})
	var cell_size := _vector2i(walls.get("cell_size", [0, 0]))
	_expect_equal(cell_size, Vector2i(96, 176), "wall atlas region size")
	var tiles_by_coords := _wall_tiles_by_coords(walls)
	for cell_data in _tile_layer_cells(manifest, "WallTileMapLayer"):
		var cell := _vector2i(cell_data.get("cell", [0, 0]))
		var tile_data := wall_layer.get_cell_tile_data(cell)
		if tile_data == null:
			_fail("Missing wall tile at %s" % cell)
			return
		if not wall_layer.map_to_local(cell).is_equal_approx(floor_layer.map_to_local(cell)):
			_fail("Wall tile at %s does not align with floor grid" % cell)
			return
		var atlas_coords := _vector2i(cell_data.get("atlas_coords", [0, 0]))
		_expect_equal(wall_layer.get_cell_atlas_coords(cell), atlas_coords, "wall atlas coordinates at %s" % cell)
		_expect_equal(wall_layer.get_cell_source_id(cell), int(cell_data.get("source_id", -1)), "wall source at %s" % cell)
		if _failed:
			return
		var tile_info: Dictionary = tiles_by_coords.get(_coords_key(atlas_coords), {})
		var expected_offset := -_vector2(tile_info.get("pivot", [0, 0])) - _vector2(tile_info.get("paste_offset", [0, 0]))
		var actual_offset := -Vector2(cell_size) * 0.5 - Vector2(tile_data.texture_origin)
		if not actual_offset.is_equal_approx(expected_offset):
			_fail("Wall tile at %s offset mismatch: expected %s got %s" % [cell, expected_offset, actual_offset])
			return
		var source := wall_layer.tile_set.get_source(wall_layer.get_cell_source_id(cell)) as TileSetAtlasSource
		if source == null:
			_fail("Wall tile at %s has no atlas source" % cell)
			return
		var expected_region := Rect2i(atlas_coords * cell_size, cell_size)
		if source.get_tile_texture_region(atlas_coords) != expected_region:
			_fail("Wall tile at %s region mismatch: expected %s got %s" % [cell, expected_region, source.get_tile_texture_region(atlas_coords)])
			return


func _tile_layer_cells(manifest: Dictionary, layer_name: String) -> Array:
	for layer in manifest.get("tile_layers", []):
		if String(layer.get("name", "")) == layer_name:
			return layer.get("cells", [])
	return []


func _wall_tiles_by_coords(atlas: Dictionary) -> Dictionary:
	var result := {}
	for tile in atlas.get("tiles", []):
		result[_coords_key(_vector2i(tile.get("atlas_coords", [0, 0])))] = tile
	return result


func _coords_key(coords: Vector2i) -> String:
	return "%d,%d" % [coords.x, coords.y]


func _check_objects(world: Node, manifest: Dictionary, floor_layer: TileMapLayer) -> void:
	var objects_node := world.get_node_or_null("Objects")
	if objects_node == null:
		_fail("Level 1 has no Objects node")
		return
	var object_entries: Array = manifest.get("objects", [])
	_expect_equal(object_entries.size(), 71, "object entry count")
	if _failed:
		return
	_expect_equal(objects_node.get_child_count(), object_entries.size(), "object node count")
	if _failed:
		return

	for object_data in object_entries:
		var object_node := objects_node.get_node_or_null(String(object_data.get("node_name", ""))) as Node2D
		if object_node == null:
			_fail("Missing object node: %s" % String(object_data.get("node_name", "")))
			return
		var expected_position := _tile_position_to_local(_vector2(object_data.get("tile_position", [0.0, 0.0])), floor_layer)
		if not object_node.position.is_equal_approx(expected_position):
			_fail("%s position mismatch: expected %s got %s" % [object_node.name, expected_position, object_node.position])
			return
		if int(object_node.get_meta("original_object_category", -1)) != int(object_data.get("object_category", -1)):
			_fail("%s category metadata mismatch" % object_node.name)
			return
		if String(object_node.get_meta("original_source_sprite", "")) != String(object_data.get("source_sprite", "")):
			_fail("%s source sprite metadata mismatch" % object_node.name)
			return
		var instance_id := int(object_data.get("instance_id", -1))
		if ExpectedObjectSources.has(instance_id):
			if String(object_data.get("source_sprite", "")) != String(ExpectedObjectSources[instance_id]):
				_fail("%s source sprite mismatch: expected %s got %s" % [
					object_node.name,
					String(ExpectedObjectSources[instance_id]),
					String(object_data.get("source_sprite", "")),
				])
				return
		var sprite := object_node.get_node_or_null("Sprite2D") as Sprite2D
		if sprite == null or sprite.texture == null:
			_fail("%s has no Sprite2D texture" % object_node.name)
			return
		if sprite.centered:
			_fail("%s sprite should use top-left origin plus original pivot offset" % object_node.name)
			return
		if sprite.texture.resource_path != String(object_data.get("texture", "")):
			_fail("%s texture mismatch" % object_node.name)
			return
		var expected_offset := -_vector2(object_data.get("pivot", [0.0, 0.0]))
		if not sprite.offset.is_equal_approx(expected_offset):
			_fail("%s pivot offset mismatch: expected %s got %s" % [object_node.name, expected_offset, sprite.offset])
			return
		if ReferenceObjectPixels.has(instance_id):
			var reference_pixel: Vector2 = ReferenceObjectPixels[instance_id]
			var projected_pixel := object_node.position + sprite.position + sprite.offset - floor_layer.map_to_local(Vector2i.ZERO) + ReferenceCameraOffset
			# The original truncates projection before subtracting camera offsets.
			if (projected_pixel - reference_pixel).abs().x > 1.1 or (projected_pixel - reference_pixel).abs().y > 1.1:
				_fail("%s original screenshot position mismatch: expected near %s got %s" % [object_node.name, reference_pixel, projected_pixel])
				return


func _check_player(world: Node, manifest: Dictionary, floor_layer: TileMapLayer) -> void:
	var player := world.get_node_or_null("Player") as Node2D
	if player == null:
		_fail("Level 1 has no Player")
		return
	var spawn := _player_spawn(manifest)
	var expected_position := _tile_position_to_local(_vector2(spawn.get("tile_position", [0.0, 0.0])), floor_layer)
	if not player.position.is_equal_approx(expected_position):
		_fail("Player spawn mismatch: expected %s got %s" % [expected_position, player.position])
		return
	if int(player.get_meta("original_spawn_id", -1)) != int(manifest.get("player_spawn_id", 0)):
		_fail("Player original_spawn_id metadata mismatch")


func _player_spawn(manifest: Dictionary) -> Dictionary:
	var player_spawn_id := int(manifest.get("player_spawn_id", 0))
	for spawn in manifest.get("spawns", []):
		if int(spawn.get("spawn_id", -1)) == player_spawn_id:
			return spawn
	return {}


func _disable_npcs_before_start() -> void:
	var world: Node = _level.get_node_or_null("World")
	if world == null:
		return
	for child in world.get_children():
		if child.get_script() == null or child.get_script().resource_path != NpcScriptPath:
			continue
		child.set_physics_process(false)
		var brain := child.get_node_or_null("Brain")
		if brain != null:
			_brain_defaults[String(child.name)] = brain.get("enabled")
			brain.set("enabled", false)
			brain.set_physics_process(false)


func _check_activity_points(world: Node, manifest: Dictionary, floor_layer: TileMapLayer) -> void:
	var collision_grid: Dictionary = manifest["collision_grid"]
	var width := int(collision_grid["width"])
	var rooms: Array = collision_grid["room_ids"]
	for object_data: Dictionary in manifest["objects"]:
		var object_name := String(object_data["node_name"])
		var point := world.get_node_or_null("Objects/%s/InteractionPoint" % object_name) as Marker2D
		if point == null or point.get_script() == null or point.get_script().resource_path != ActivityPointScriptPath:
			_fail("%s has no authored NPC activity point" % object_name)
			return
		var expected_position := floor_layer.to_global(_tile_position_to_local(_vector2(object_data["interaction_tile_position"]), floor_layer))
		if not point.global_position.is_equal_approx(expected_position):
			_fail("%s interaction point should use the original transformed DAT offset: expected %s got %s" % [object_name, expected_position, point.global_position])
			return
		var kind := String(object_data["kind"]).hex_to_int()
		var tile_position := _vector2(object_data["tile_position"])
		var cell := Vector2i(floori(tile_position.x + 0.5), floori(tile_position.y + 0.5))
		var expected := {
			"category": (kind >> 16) & 0xFF,
			"item_type": (kind >> 4) & 0xFFF,
			"room_id": int(rooms[cell.x + width * cell.y]),
			"active": int(object_data["object_category"]) == 5,
		}
		for field: String in expected:
			_expect_equal(point.get(field), expected[field], "%s activity %s" % [object_name, field])
			if _failed:
				return
		_expect_equal(point.is_in_group("npc_activity_points"), true, "%s participates in NPC target discovery" % object_name)
		if _failed:
			return
		var expected_actions := PackedInt32Array()
		for action_id: int in object_data.get("action_ids", []):
			expected_actions.append(int(action_id))
		_expect_equal(point.get("action_ids"), expected_actions, "%s prank action ids" % object_name)
		if _failed:
			return


func _check_npcs(world: Node, manifest: Dictionary, floor_layer: TileMapLayer) -> void:
	var entries: Array = manifest.get("npcs", [])
	_expect_equal(entries.size(), 3, "original NPC manifest count")
	if _failed:
		return
	var count := 0
	for child in world.get_children():
		if child.get_script() != null and child.get_script().resource_path == NpcScriptPath:
			count += 1
	_expect_equal(count, 3, "NPCs directly under World")
	if _failed:
		return
	var object_names: Dictionary = {}
	for object_data: Dictionary in manifest["objects"]:
		object_names[int(object_data["instance_id"])] = String(object_data["node_name"])
	var profiles: Array[String] = []
	for entry: Dictionary in entries:
		var npc_name := String(entry["node_name"])
		var npc := world.get_node_or_null(npc_name) as CharacterBody2D
		if npc == null or npc.get_script() == null or npc.get_script().resource_path != NpcScriptPath:
			_fail("Missing original NPC: %s" % npc_name)
			return
		var expected_position := _tile_position_to_local(_vector2(entry["tile_position"]), floor_layer)
		if not npc.position.is_equal_approx(expected_position):
			_fail("%s spawn mismatch: expected %s got %s" % [npc_name, expected_position, npc.position])
			return
		var profile := npc.get("profile") as Resource
		if profile == null:
			_fail("%s has no character profile" % npc_name)
			return
		profiles.append(String(profile.get("id")))
		var expected := {
			"profile_path": String(entry["profile"]),
			"profile_id": String(entry["profile_id"]),
			"spawn_id": int(entry["spawn_id"]),
			"instance_id": int(entry["instance_id"]),
			"brain_enabled": true,
		}
		var actual := {
			"profile_path": profile.resource_path,
			"profile_id": String(profile.get("id")),
			"spawn_id": int(npc.get_meta("original_spawn_id", -1)),
			"instance_id": int(npc.get_meta("original_instance_id", -1)),
			"brain_enabled": _brain_defaults.get(npc_name, false),
		}
		for field: String in expected:
			_expect_equal(actual[field], expected[field], "%s %s" % [npc_name, field])
			if _failed:
				return
		var expected_direction: Vector2 = DirectionScript.get_screen_directions()[int(entry["initial_direction_index"])]
		var initial_direction: Vector2 = npc.get("initial_direction")
		var last_direction: Vector2 = npc.get("last_direction")
		if not initial_direction.is_equal_approx(expected_direction) or not last_direction.is_equal_approx(expected_direction):
			_fail("%s should start facing the original direction index 0" % npc_name)
			return
		var brain := npc.get_node_or_null("Brain")
		if brain == null or brain.get_script() == null or brain.get_script().resource_path != NpcBrainScriptPath:
			_fail("%s has no NPC brain" % npc_name)
			return
		for field: String in ["assigned_workstation", "assigned_chair"]:
			var reference = brain.get(field)
			if not reference is NodePath:
				_fail("%s %s is not an authored NodePath" % [npc_name, field])
				return
			var instance_id = entry[field + "_instance_id"]
			if instance_id == null:
				_expect_equal(reference.is_empty(), true, "%s has no original %s assignment" % [npc_name, field])
			else:
				var object_name: String = object_names[int(instance_id)]
				var point := world.get_node("Objects/%s/InteractionPoint" % object_name)
				_expect_equal(brain.get_node_or_null(reference), point, "%s %s resolves to the original object" % [npc_name, field])
			if _failed:
				return
	profiles.sort()
	_expect_equal(profiles, ["boss", "female-employee-1", "male-employee-1"] as Array[String], "original character roster")


func _check_debug_overlay() -> void:
	var fps_counter: Label = _level.get_node_or_null("DebugOverlay/FPSCounter")
	if fps_counter == null:
		_fail("Level 1 has no FPS counter")
		return
	if fps_counter.get_script() == null:
		_fail("FPS counter has no script")


func _tile_position_to_local(tile_position: Vector2, floor_layer: TileMapLayer) -> Vector2:
	var origin := floor_layer.map_to_local(Vector2i.ZERO)
	var x_axis := floor_layer.map_to_local(Vector2i(1, 0)) - origin
	var y_axis := floor_layer.map_to_local(Vector2i(0, 1)) - origin
	return origin + x_axis * tile_position.x + y_axis * tile_position.y


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


func _int_array(value) -> Array:
	if not value is Array:
		return []
	var values := []
	for item in value:
		values.append(int(item))
	return values


func _expect_equal(actual, expected, label: String) -> void:
	if actual != expected:
		_fail("%s mismatch: expected %s got %s" % [label, str(expected), str(actual)])


func _free_level() -> void:
	if _level == null:
		return
	if _level.get_parent() != null:
		_level.get_parent().remove_child(_level)
	_level.free()
	_level = null


func _fail(message: String) -> void:
	if _failed:
		return
	_failed = true
	_free_level()
	push_error(message)
	quit(1)
