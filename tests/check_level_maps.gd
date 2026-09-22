extends SceneTree

# Structure, for every imported level. check_level_1_map.gd stays the golden fixture that
# pins level 1 against the original screenshot and the wall atlas order; this one asserts
# only what has to hold for any level the importer emits, so a newly imported level is
# covered the moment its manifest lands.

const LevelDir := "res://resources/levels"
const NpcScriptPath := "res://scenes/npc/npc.gd"
const ActivityPointScriptPath := "res://scenes/npc/npc_activity_point.gd"
const MapObjectScriptPath := "res://scenes/shared/map_object.gd"

var _failed := false
var _level: Node


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var numbers := _imported_levels()
	if numbers.is_empty():
		_fail("no level manifests found in %s" % LevelDir)
		return
	for number: int in numbers:
		await _check_level(number)
		if _failed:
			_free_level()
			return
	print("Checked %d level scene(s): %s" % [numbers.size(), numbers])
	quit(0)


func _imported_levels() -> Array[int]:
	var numbers: Array[int] = []
	var dir := DirAccess.open(LevelDir)
	if dir == null:
		return numbers
	for file in dir.get_files():
		var name := file.trim_suffix(".remap")
		if name.begins_with("level_") and name.ends_with(".json"):
			var digits := name.trim_prefix("level_").trim_suffix(".json")
			if digits.is_valid_int():
				numbers.append(int(digits))
	numbers.sort()
	return numbers


func _check_level(number: int) -> void:
	var manifest := _read_json("%s/level_%d.json" % [LevelDir, number])
	if manifest.is_empty():
		_fail("level %d manifest could not be read" % number)
		return
	var scene_path := "res://scenes/level_%d.tscn" % number
	if not ResourceLoader.exists(scene_path):
		_fail("level %d has no scene at %s" % [number, scene_path])
		return
	var scene := load(scene_path) as PackedScene
	_level = scene.instantiate()
	_disable_npcs_before_start()
	root.add_child(_level)
	await process_frame

	var world: Node = _level.get_node_or_null("World")
	if world == null:
		_fail("level %d has no World node" % number)
		return

	var floor_layer := _require_tile_layer(world, "FloorTileMapLayer", number)
	var wall_layer := _require_tile_layer(world, "WallTileMapLayer", number)
	var glass_layer := _require_tile_layer(world, "GlassTileMapLayer", number)
	if _failed:
		return
	for layer in [floor_layer, wall_layer, glass_layer]:
		_check_tile_layout(layer, number)
		if _failed:
			return
	_check_tile_axes(floor_layer, number)
	_check_tile_cells(manifest, world, number)
	if _failed:
		return
	_check_visible_bounds(manifest, number)
	if _failed:
		return
	_check_objects(world, manifest, floor_layer, number)
	if _failed:
		return
	_check_activity_points(world, manifest, floor_layer, number)
	if _failed:
		return
	_check_player(world, manifest, floor_layer, number)
	if _failed:
		return
	_check_npcs(world, manifest, number)
	if _failed:
		return
	_check_conditions(manifest, number)
	if _failed:
		return
	_free_level()


func _require_tile_layer(world: Node, node_name: String, number: int) -> TileMapLayer:
	var layer := world.get_node_or_null(node_name) as TileMapLayer
	if layer == null:
		_fail("level %d has no %s" % [number, node_name])
	return layer


func _check_tile_layout(layer: TileMapLayer, number: int) -> void:
	if layer.tile_set == null:
		_fail("level %d %s has no TileSet" % [number, layer.name])
		return
	if layer.tile_set.tile_shape != TileSet.TILE_SHAPE_ISOMETRIC:
		_fail("level %d %s should use isometric tiles" % [number, layer.name])
		return
	if layer.tile_set.tile_layout != TileSet.TILE_LAYOUT_DIAMOND_DOWN:
		_fail("level %d %s should use diamond-down isometric layout" % [number, layer.name])
		return
	if layer.tile_set.tile_size != Vector2i(96, 48):
		_fail("level %d %s should use the original 96x48 map grid" % [number, layer.name])


func _check_tile_axes(layer: TileMapLayer, number: int) -> void:
	var origin := layer.map_to_local(Vector2i.ZERO)
	if not (layer.map_to_local(Vector2i(1, 0)) - origin).is_equal_approx(Vector2(48.0, 24.0)):
		_fail("level %d x tile axis mismatch" % number)
		return
	if not (layer.map_to_local(Vector2i(0, 1)) - origin).is_equal_approx(Vector2(-48.0, 24.0)):
		_fail("level %d y tile axis mismatch" % number)


func _check_tile_cells(manifest: Dictionary, world: Node, number: int) -> void:
	for layer_data: Dictionary in manifest.get("tile_layers", []):
		var layer_name := String(layer_data.get("name", ""))
		var layer := world.get_node_or_null(layer_name) as TileMapLayer
		if layer == null:
			_fail("level %d has no %s" % [number, layer_name])
			return
		var expected: int = (layer_data.get("cells", []) as Array).size()
		if layer.get_used_cells().size() != expected:
			_fail("level %d %s cell count: expected %d got %d" % [
				number, layer_name, expected, layer.get_used_cells().size(),
			])
			return


func _check_visible_bounds(manifest: Dictionary, number: int) -> void:
	var map_data: Dictionary = manifest.get("map", {})
	var visible_width := int(map_data.get("visible_width", 0))
	var visible_height := int(map_data.get("visible_height", 0))
	if visible_width != maxi(int(map_data.get("width", 0)) - 1, 0):
		_fail("level %d visible width should be width - 1" % number)
		return
	if visible_height != maxi(int(map_data.get("height", 0)) - 1, 0):
		_fail("level %d visible height should be height - 1" % number)
		return
	for layer_data: Dictionary in manifest.get("tile_layers", []):
		for cell_data in layer_data.get("cells", []):
			var cell := _vector2i(cell_data.get("cell", [0, 0]))
			if cell.x >= visible_width or cell.y >= visible_height:
				_fail("level %d %s has a padding cell at %s" % [number, String(layer_data.get("name", "")), cell])
				return


func _check_objects(world: Node, manifest: Dictionary, floor_layer: TileMapLayer, number: int) -> void:
	var objects_node := world.get_node_or_null("Objects")
	if objects_node == null:
		_fail("level %d has no Objects node" % number)
		return
	var entries: Array = manifest.get("objects", [])
	if objects_node.get_child_count() != entries.size():
		_fail("level %d object node count: expected %d got %d" % [
			number, entries.size(), objects_node.get_child_count(),
		])
		return
	for object_data: Dictionary in entries:
		var object_name := String(object_data.get("node_name", ""))
		var object_node := objects_node.get_node_or_null(object_name) as Node2D
		if object_node == null:
			_fail("level %d missing object node %s" % [number, object_name])
			return
		if object_node.get_script() == null or object_node.get_script().resource_path != MapObjectScriptPath:
			_fail("level %d %s is not a MapObject" % [number, object_name])
			return
		var expected_position := _tile_to_local(_vector2(object_data.get("tile_position", [0.0, 0.0])), floor_layer)
		if not object_node.position.is_equal_approx(expected_position):
			_fail("level %d %s position: expected %s got %s" % [
				number, object_name, expected_position, object_node.position,
			])
			return
		var sprite := object_node.get_node_or_null("Sprite2D") as Sprite2D
		if sprite == null or sprite.texture == null:
			_fail("level %d %s has no Sprite2D texture" % [number, object_name])
			return
		if sprite.centered:
			_fail("level %d %s sprite should keep the original top-left origin" % [number, object_name])
			return
		if sprite.texture.resource_path != String(object_data.get("texture", "")):
			_fail("level %d %s texture mismatch" % [number, object_name])
			return
		if not sprite.offset.is_equal_approx(-_vector2(object_data.get("pivot", [0.0, 0.0]))):
			_fail("level %d %s pivot offset mismatch" % [number, object_name])
			return
		# A prefab built before its mask existed silently loses world occlusion, which is
		# why the four import steps have to run in order.
		if object_node.get("depth_texture") == null:
			_fail("level %d %s has no depth texture; export_world_depth_maps.py must run before the scene is built" % [
				number, object_name,
			])
			return


func _check_activity_points(world: Node, manifest: Dictionary, floor_layer: TileMapLayer, number: int) -> void:
	var collision_grid: Dictionary = manifest.get("collision_grid", {})
	var width := int(collision_grid.get("width", 0))
	var rooms: Array = collision_grid.get("room_ids", [])
	for object_data: Dictionary in manifest.get("objects", []):
		var object_name := String(object_data.get("node_name", ""))
		var point := world.get_node_or_null("Objects/%s/InteractionPoint" % object_name) as Marker2D
		if point == null or point.get_script() == null or point.get_script().resource_path != ActivityPointScriptPath:
			_fail("level %d %s has no NPC activity point" % [number, object_name])
			return
		var expected := floor_layer.to_global(_tile_to_local(_vector2(object_data.get("interaction_tile_position", [0.0, 0.0])), floor_layer))
		if not point.global_position.is_equal_approx(expected):
			_fail("level %d %s interaction point mismatch" % [number, object_name])
			return
		if not point.is_in_group("npc_activity_points"):
			_fail("level %d %s is not discoverable as an NPC target" % [number, object_name])
			return
		var kind := String(object_data.get("kind", "0x0")).hex_to_int()
		if int(point.get("item_type")) != ((kind >> 4) & 0xFFF):
			_fail("level %d %s item type mismatch" % [number, object_name])
			return
		if bool(point.get("active")) != (int(object_data.get("object_category", -1)) == 5):
			_fail("level %d %s active flag mismatch" % [number, object_name])
			return
		# item+196, which sub_41B240 reads to decide which side to step the player onto.
		if int(point.get("orientation")) != int(object_data.get("variant", 0)):
			_fail("level %d %s orientation mismatch" % [number, object_name])
			return
		var tile_position := _vector2(object_data.get("tile_position", [0.0, 0.0]))
		var cell := Vector2i(floori(tile_position.x + 0.5), floori(tile_position.y + 0.5))
		var index := cell.x + width * cell.y
		if index >= 0 and index < rooms.size() and int(point.get("room_id")) != int(rooms[index]):
			_fail("level %d %s room id mismatch" % [number, object_name])
			return
		var expected_actions := PackedInt32Array()
		for action_id: int in object_data.get("action_ids", []):
			expected_actions.append(int(action_id))
		if point.get("action_ids") != expected_actions:
			_fail("level %d %s prank action ids mismatch" % [number, object_name])
			return


func _check_player(world: Node, manifest: Dictionary, floor_layer: TileMapLayer, number: int) -> void:
	var player := world.get_node_or_null("Player") as Node2D
	if player == null:
		_fail("level %d has no Player" % number)
		return
	var player_spawn_id := int(manifest.get("player_spawn_id", 0))
	for spawn: Dictionary in manifest.get("spawns", []):
		if int(spawn.get("spawn_id", -1)) == player_spawn_id:
			var expected := _tile_to_local(_vector2(spawn.get("tile_position", [0.0, 0.0])), floor_layer)
			if not player.position.is_equal_approx(expected):
				_fail("level %d player spawn: expected %s got %s" % [number, expected, player.position])
			return
	_fail("level %d manifest has no spawn for the player" % number)


func _check_npcs(world: Node, manifest: Dictionary, number: int) -> void:
	var entries: Array = manifest.get("npcs", [])
	var count := 0
	for child in world.get_children():
		if child.get_script() != null and child.get_script().resource_path == NpcScriptPath:
			count += 1
	if count != entries.size():
		_fail("level %d NPC count: manifest has %d, scene has %d" % [number, entries.size(), count])
		return
	for entry: Dictionary in entries:
		var npc_name := String(entry.get("node_name", ""))
		var npc := world.get_node_or_null(npc_name) as CharacterBody2D
		if npc == null:
			_fail("level %d missing NPC %s" % [number, npc_name])
			return
		var profile := npc.get("profile") as Resource
		if profile == null:
			_fail("level %d NPC %s has no character profile" % [number, npc_name])
			return
		if String(profile.get("id")) != String(entry.get("profile_id", "")):
			_fail("level %d NPC %s profile: expected %s got %s" % [
				number, npc_name, String(entry.get("profile_id", "")), String(profile.get("id")),
			])
			return


func _check_conditions(manifest: Dictionary, number: int) -> void:
	var conditions: Dictionary = manifest.get("conditions", {})
	for mode: String in ["time", "points"]:
		var condition: Dictionary = conditions.get(mode, {})
		var limit := float(condition.get("time_limit_seconds", 0.0))
		var target := int(condition.get("score_target", 0))
		# sub_412FB0 only stores a CONDITION inside these ranges.
		if limit < 1.0 or limit > 3600.0:
			_fail("level %d %s time limit %f is outside the original's range" % [number, mode, limit])
			return
		if target < 1 or target > 99999:
			_fail("level %d %s score target %d is outside the original's range" % [number, mode, target])
			return


# The same projection build_level_scene.gd:291 uses. Interpolating within the containing
# cell instead accumulates about 1.5e-5 of error on a long map, which is enough to fail
# is_equal_approx against a position the builder wrote with this formula.
func _tile_to_local(tile_position: Vector2, floor_layer: TileMapLayer) -> Vector2:
	var origin := floor_layer.map_to_local(Vector2i.ZERO)
	var x_axis := floor_layer.map_to_local(Vector2i(1, 0)) - origin
	var y_axis := floor_layer.map_to_local(Vector2i(0, 1)) - origin
	return origin + x_axis * tile_position.x + y_axis * tile_position.y


func _disable_npcs_before_start() -> void:
	var world: Node = _level.get_node_or_null("World")
	if world == null:
		return
	for child in world.get_children():
		if child.get_script() != null and child.get_script().resource_path == NpcScriptPath:
			var brain := child.get_node_or_null("Brain")
			if brain != null:
				brain.set("enabled", false)


func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}


func _vector2(value) -> Vector2:
	if value is Array and value.size() >= 2:
		return Vector2(float(value[0]), float(value[1]))
	return Vector2.ZERO


func _vector2i(value) -> Vector2i:
	if value is Array and value.size() >= 2:
		return Vector2i(int(value[0]), int(value[1]))
	return Vector2i.ZERO


func _free_level() -> void:
	if _level != null:
		if _level.get_parent() != null:
			root.remove_child(_level)
		_level.free()
		_level = null


func _fail(message: String) -> void:
	_failed = true
	push_error(message)
	printerr(message)
	_free_level()
	quit(1)
