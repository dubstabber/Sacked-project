extends SceneTree

# Structure, for every imported level. check_level_1_map.gd stays the golden fixture that
# pins level 1 against the original screenshot and the wall atlas order; this one asserts
# only what has to hold for any level the importer emits, so a newly imported level is
# covered the moment its manifest lands.

const LevelDir := "res://resources/levels"
const NpcScriptPath := "res://scenes/npc/npc.gd"
const ActivityPointScriptPath := "res://scenes/npc/npc_activity_point.gd"
const MapObjectScriptPath := "res://scenes/shared/map_object.gd"
const FloorScriptPath := "res://scenes/shared/floor_tile_layer.gd"

var _failed := false
var _level: Node


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var labels := _imported_levels()
	if labels.is_empty():
		_fail("no level manifests found in %s" % LevelDir)
		return
	for label: String in labels:
		await _check_level(label)
		if _failed:
			_free_level()
			return
		if label.ends_with("s"):
			_check_variant(label)
			if _failed:
				return
	print("Checked %d level scene(s): %s" % [labels.size(), labels])
	quit(0)


# "5" is a level, "5s" the second scene its points-mode file earns. Each level is followed
# by its own variant so a failure names the two together.
func _imported_levels() -> Array[String]:
	var numbers: Array[int] = []
	var variants := {}
	var dir := DirAccess.open(LevelDir)
	if dir == null:
		return []
	for file in dir.get_files():
		var name := file.trim_suffix(".remap")
		if not (name.begins_with("level_") and name.ends_with(".json")):
			continue
		var digits := name.trim_prefix("level_").trim_suffix(".json")
		if digits.is_valid_int():
			numbers.append(int(digits))
		elif digits.ends_with("s") and digits.trim_suffix("s").is_valid_int():
			variants[int(digits.trim_suffix("s"))] = true
	numbers.sort()
	var labels: Array[String] = []
	for number: int in numbers:
		labels.append(str(number))
		if variants.has(number):
			labels.append("%ds" % number)
	return labels


func _check_level(label: String) -> void:
	var manifest := _read_json("%s/level_%s.json" % [LevelDir, label])
	if manifest.is_empty():
		_fail("level %s manifest could not be read" % label)
		return
	var scene_path := "res://scenes/level_%s.tscn" % label
	if not ResourceLoader.exists(scene_path):
		_fail("level %s has no scene at %s" % [label, scene_path])
		return
	var scene := load(scene_path) as PackedScene
	_level = scene.instantiate()
	_disable_npcs_before_start()
	root.add_child(_level)
	await process_frame

	var world: Node = _level.get_node_or_null("World")
	if world == null:
		_fail("level %s has no World node" % label)
		return

	var floor_layer := _require_tile_layer(world, "FloorTileMapLayer", label)
	var wall_layer := _require_tile_layer(world, "WallTileMapLayer", label)
	var glass_layer := _require_tile_layer(world, "GlassTileMapLayer", label)
	if _failed:
		return
	for layer in [floor_layer, wall_layer, glass_layer]:
		_check_tile_layout(layer, label)
		if _failed:
			return
	# check_floor_bake.gd pins what the bake draws; every level only has to use it.
	if floor_layer.get_script() == null or floor_layer.get_script().resource_path != FloorScriptPath or floor_layer.enabled:
		_fail("level %s FloorTileMapLayer should draw through the floor bake" % label)
		return
	_check_tile_axes(floor_layer, label)
	_check_tile_cells(manifest, world, label)
	if _failed:
		return
	_check_visible_bounds(manifest, label)
	if _failed:
		return
	_check_objects(world, manifest, floor_layer, label)
	if _failed:
		return
	_check_activity_points(world, manifest, floor_layer, label)
	if _failed:
		return
	_check_player(world, manifest, floor_layer, label)
	if _failed:
		return
	_check_npcs(world, manifest, label)
	if _failed:
		return
	_check_conditions(manifest, label)
	if _failed:
		return
	_free_level()


func _require_tile_layer(world: Node, node_name: String, label: String) -> TileMapLayer:
	var layer := world.get_node_or_null(node_name) as TileMapLayer
	if layer == null:
		_fail("level %s has no %s" % [label, node_name])
	return layer


func _check_tile_layout(layer: TileMapLayer, label: String) -> void:
	if layer.tile_set == null:
		_fail("level %s %s has no TileSet" % [label, layer.name])
		return
	if layer.tile_set.tile_shape != TileSet.TILE_SHAPE_ISOMETRIC:
		_fail("level %s %s should use isometric tiles" % [label, layer.name])
		return
	if layer.tile_set.tile_layout != TileSet.TILE_LAYOUT_DIAMOND_DOWN:
		_fail("level %s %s should use diamond-down isometric layout" % [label, layer.name])
		return
	if layer.tile_set.tile_size != Vector2i(96, 48):
		_fail("level %s %s should use the original 96x48 map grid" % [label, layer.name])


func _check_tile_axes(layer: TileMapLayer, label: String) -> void:
	var origin := layer.map_to_local(Vector2i.ZERO)
	if not (layer.map_to_local(Vector2i(1, 0)) - origin).is_equal_approx(Vector2(48.0, 24.0)):
		_fail("level %s x tile axis mismatch" % label)
		return
	if not (layer.map_to_local(Vector2i(0, 1)) - origin).is_equal_approx(Vector2(-48.0, 24.0)):
		_fail("level %s y tile axis mismatch" % label)


func _check_tile_cells(manifest: Dictionary, world: Node, label: String) -> void:
	for layer_data: Dictionary in manifest.get("tile_layers", []):
		var layer_name := String(layer_data.get("name", ""))
		var layer := world.get_node_or_null(layer_name) as TileMapLayer
		if layer == null:
			_fail("level %s has no %s" % [label, layer_name])
			return
		var expected: int = (layer_data.get("cells", []) as Array).size()
		if layer.get_used_cells().size() != expected:
			_fail("level %s %s cell count: expected %d got %d" % [label, layer_name, expected, layer.get_used_cells().size(),
			])
			return


func _check_visible_bounds(manifest: Dictionary, label: String) -> void:
	var map_data: Dictionary = manifest.get("map", {})
	var visible_width := int(map_data.get("visible_width", 0))
	var visible_height := int(map_data.get("visible_height", 0))
	if visible_width != maxi(int(map_data.get("width", 0)) - 1, 0):
		_fail("level %s visible width should be width - 1" % label)
		return
	if visible_height != maxi(int(map_data.get("height", 0)) - 1, 0):
		_fail("level %s visible height should be height - 1" % label)
		return
	for layer_data: Dictionary in manifest.get("tile_layers", []):
		for cell_data in layer_data.get("cells", []):
			var cell := _vector2i(cell_data.get("cell", [0, 0]))
			if cell.x >= visible_width or cell.y >= visible_height:
				_fail("level %s %s has a padding cell at %s" % [label, String(layer_data.get("name", "")), cell])
				return


func _check_objects(world: Node, manifest: Dictionary, floor_layer: TileMapLayer, label: String) -> void:
	var objects_node := world.get_node_or_null("Objects")
	if objects_node == null:
		_fail("level %s has no Objects node" % label)
		return
	var entries: Array = manifest.get("objects", [])
	if objects_node.get_child_count() != entries.size():
		_fail("level %s object node count: expected %d got %d" % [label, entries.size(), objects_node.get_child_count(),
		])
		return
	# PARKED_RECORDS in tools/import_original_level.py leaves out what the original's 4:3 view
	# never shows. Such a record lies off the map by the original's own lookup, sub_412AE0 on
	# (int)(x + 0.5), (int)(y + 0.5), and must not reach the scene.
	var map_data: Dictionary = manifest.get("map", {})
	for parked: Dictionary in manifest.get("parked_items", []):
		var instance_id := int(parked.get("instance_id", -1))
		var tile := _vector2(parked.get("tile_position", [0.0, 0.0]))
		var cell := Vector2i(int(tile.x + 0.5), int(tile.y + 0.5))
		if cell.x >= 0 and cell.y >= 0 and cell.x < int(map_data.get("width", 0)) and cell.y < int(map_data.get("height", 0)):
			_fail("level %s parks instance %d although it stands on the map" % [label, instance_id])
			return
		for object_data: Dictionary in entries:
			if int(object_data.get("instance_id", -1)) == instance_id:
				_fail("level %s lists parked instance %d among its objects" % [label, instance_id])
				return
		for child in objects_node.get_children():
			if int(child.get_meta("original_instance_id", -1)) == instance_id:
				_fail("level %s scene still holds parked instance %d as %s" % [label, instance_id, child.name])
				return
	for object_data: Dictionary in entries:
		var object_name := String(object_data.get("node_name", ""))
		var object_node := objects_node.get_node_or_null(object_name) as Node2D
		if object_node == null:
			_fail("level %s missing object node %s" % [label, object_name])
			return
		if object_node.get_script() == null or object_node.get_script().resource_path != MapObjectScriptPath:
			_fail("level %s %s is not a MapObject" % [label, object_name])
			return
		var expected_position := _tile_to_local(_vector2(object_data.get("tile_position", [0.0, 0.0])), floor_layer)
		if not object_node.position.is_equal_approx(expected_position):
			_fail("level %s %s position: expected %s got %s" % [label, object_name, expected_position, object_node.position,
			])
			return
		var sprite := object_node.get_node_or_null("Sprite2D") as Sprite2D
		if sprite == null or sprite.texture == null:
			_fail("level %s %s has no Sprite2D texture" % [label, object_name])
			return
		if sprite.centered:
			_fail("level %s %s sprite should keep the original top-left origin" % [label, object_name])
			return
		if sprite.texture.resource_path != String(object_data.get("texture", "")):
			_fail("level %s %s texture mismatch" % [label, object_name])
			return
		if not sprite.offset.is_equal_approx(-_vector2(object_data.get("pivot", [0.0, 0.0]))):
			_fail("level %s %s pivot offset mismatch" % [label, object_name])
			return
		# A prefab built before its mask existed silently loses world occlusion, which is
		# why the four import steps have to run in order.
		if object_node.get("depth_texture") == null:
			_fail("level %s %s has no depth texture; export_world_depth_maps.py must run before the scene is built" % [label, object_name,
			])
			return


func _check_activity_points(world: Node, manifest: Dictionary, floor_layer: TileMapLayer, label: String) -> void:
	var collision_grid: Dictionary = manifest.get("collision_grid", {})
	var width := int(collision_grid.get("width", 0))
	var rooms: Array = collision_grid.get("room_ids", [])
	for object_data: Dictionary in manifest.get("objects", []):
		var object_name := String(object_data.get("node_name", ""))
		var point := world.get_node_or_null("Objects/%s/InteractionPoint" % object_name) as Marker2D
		if point == null or point.get_script() == null or point.get_script().resource_path != ActivityPointScriptPath:
			_fail("level %s %s has no NPC activity point" % [label, object_name])
			return
		var expected := floor_layer.to_global(_tile_to_local(_vector2(object_data.get("interaction_tile_position", [0.0, 0.0])), floor_layer))
		if not point.global_position.is_equal_approx(expected):
			_fail("level %s %s interaction point mismatch" % [label, object_name])
			return
		if not point.is_in_group("npc_activity_points"):
			_fail("level %s %s is not discoverable as an NPC target" % [label, object_name])
			return
		var kind := String(object_data.get("kind", "0x0")).hex_to_int()
		if int(point.get("item_type")) != ((kind >> 4) & 0xFFF):
			_fail("level %s %s item type mismatch" % [label, object_name])
			return
		if bool(point.get("active")) != (int(object_data.get("object_category", -1)) == 5):
			_fail("level %s %s active flag mismatch" % [label, object_name])
			return
		# item+196, which sub_41B240 reads to decide which side to step the player onto.
		if int(point.get("orientation")) != int(object_data.get("variant", 0)):
			_fail("level %s %s orientation mismatch" % [label, object_name])
			return
		var tile_position := _vector2(object_data.get("tile_position", [0.0, 0.0]))
		var cell := Vector2i(floori(tile_position.x + 0.5), floori(tile_position.y + 0.5))
		# Two-dimensional, like build_level_scene.gd's own guard: level 11's points-mode
		# file parks an item off the left edge, and a flat index would read that negative
		# column as a cell on the row above.
		var height := int(collision_grid.get("height", 0))
		if cell.x >= 0 and cell.y >= 0 and cell.x < width and cell.y < height:
			if int(point.get("room_id")) != int(rooms[cell.x + width * cell.y]):
				_fail("level %s %s room id mismatch" % [label, object_name])
				return
		var expected_actions := PackedInt32Array()
		for action_id: int in object_data.get("action_ids", []):
			expected_actions.append(int(action_id))
		if point.get("action_ids") != expected_actions:
			_fail("level %s %s prank action ids mismatch" % [label, object_name])
			return


func _check_player(world: Node, manifest: Dictionary, floor_layer: TileMapLayer, label: String) -> void:
	var player := world.get_node_or_null("Player") as Node2D
	if player == null:
		_fail("level %s has no Player" % label)
		return
	var player_spawn_id := int(manifest.get("player_spawn_id", 0))
	for spawn: Dictionary in manifest.get("spawns", []):
		if int(spawn.get("spawn_id", -1)) == player_spawn_id:
			var expected := _tile_to_local(_vector2(spawn.get("tile_position", [0.0, 0.0])), floor_layer)
			if not player.position.is_equal_approx(expected):
				_fail("level %s player spawn: expected %s got %s" % [label, expected, player.position])
			return
	_fail("level %s manifest has no spawn for the player" % label)


func _check_npcs(world: Node, manifest: Dictionary, label: String) -> void:
	var entries: Array = manifest.get("npcs", [])
	var count := 0
	for child in world.get_children():
		if child.get_script() != null and child.get_script().resource_path == NpcScriptPath:
			count += 1
	if count != entries.size():
		_fail("level %s NPC count: manifest has %d, scene has %d" % [label, entries.size(), count])
		return
	for entry: Dictionary in entries:
		var npc_name := String(entry.get("node_name", ""))
		var npc := world.get_node_or_null(npc_name) as CharacterBody2D
		if npc == null:
			_fail("level %s missing NPC %s" % [label, npc_name])
			return
		var profile := npc.get("profile") as Resource
		if profile == null:
			_fail("level %s NPC %s has no character profile" % [label, npc_name])
			return
		if String(profile.get("id")) != String(entry.get("profile_id", "")):
			_fail("level %s NPC %s profile: expected %s got %s" % [label, npc_name, String(entry.get("profile_id", "")), String(profile.get("id")),
			])
			return


func _check_conditions(manifest: Dictionary, label: String) -> void:
	var conditions: Dictionary = manifest.get("conditions", {})
	for mode: String in ["time", "points"]:
		var condition: Dictionary = conditions.get(mode, {})
		var limit := float(condition.get("time_limit_seconds", 0.0))
		var target := int(condition.get("score_target", 0))
		# sub_412FB0 only stores a CONDITION inside these ranges.
		if limit < 1.0 or limit > 3600.0:
			_fail("level %s %s time limit %f is outside the original's range" % [label, mode, limit])
			return
		if target < 1 or target > 99999:
			_fail("level %s %s score target %d is outside the original's range" % [label, mode, target])
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


# A points-mode variant exists only where the S file moves the map. It has to be a real
# second layout, and it has to keep both CONDITIONs so a restart in either mode still
# knows its target.
func _check_variant(label: String) -> void:
	var manifest := _read_json("%s/level_%s.json" % [LevelDir, label])
	var plain_label := label.trim_suffix("s")
	var plain := _read_json("%s/level_%s.json" % [LevelDir, plain_label])
	if manifest.is_empty() or plain.is_empty():
		_fail("level %s has no level %s beside it" % [label, plain_label])
		return
	if String(manifest.get("game_mode", "")) != "points":
		_fail("level %s should be marked as the points-mode build" % label)
		return
	if not String(manifest.get("source", "")).ends_with("s.col"):
		_fail("level %s should be built from the points-mode S file" % label)
		return
	if manifest.get("conditions") != plain.get("conditions"):
		_fail("level %s should carry the same two CONDITIONs as level %s" % [label, plain_label])
		return
	if manifest.get("objects") == plain.get("objects") and manifest.get("tile_layers") == plain.get("tile_layers"):
		_fail("level %s has the same map as level %s and should not exist" % [label, plain_label])
		return
