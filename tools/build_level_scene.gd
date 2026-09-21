extends SceneTree


const DEFAULT_MANIFEST_PATH := "res://resources/levels/level_1.json"
const DEFAULT_SCENE_PATH := "res://scenes/level_1.tscn"
const PLAYER_SCENE := "res://scenes/player/player.tscn"
const DEPTH_COMPOSITOR_SCRIPT := "res://scenes/shared/character_depth_compositor.gd"
const WORLD_DEPTH_COMPOSITOR_SCRIPT := "res://scenes/shared/world_depth_compositor.gd"
const MAP_TILE_LAYER_SCRIPT := "res://scenes/shared/map_tile_layer.gd"
const MAP_OBJECT_SCENE := "res://scenes/shared/map_object.tscn"
const FPS_COUNTER_SCRIPT := "res://scenes/debug/fps_counter.gd"
const COLLISION_MAP_SCRIPT := "res://scenes/shared/collision_map_layer.gd"
const COLLISION_TILESET := "res://resources/tilemaps/sacked-collision.tres"
const NPC_SCENE := "res://scenes/npc/npc.tscn"
const NPC_BRAIN_SCRIPT := "res://scenes/npc/npc_brain.gd"
const ACTIVITY_POINT_SCRIPT := "res://scenes/npc/npc_activity_point.gd"
const LEVEL_RUNTIME_SCENE := "res://scenes/level/level_runtime.tscn"

var _object_prefabs: Dictionary = {}
var _prefab_paths: Dictionary = {}


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


func _build_scene(manifest: Dictionary) -> Node:
	var root := Node.new()
	root.name = "Main"

	var world := Node2D.new()
	world.name = "World"
	root.add_child(world)

	var floor_layer: TileMapLayer = null
	for layer_data in manifest.get("tile_layers", []):
		var layer := _build_tile_layer(layer_data)
		world.add_child(layer)
		if layer.name == "FloorTileMapLayer":
			floor_layer = layer

	if floor_layer == null:
		push_error("Level manifest did not create FloorTileMapLayer")
		return root

	var objects := _build_objects(manifest, floor_layer)
	world.add_child(objects)
	world.add_child(_build_collision_layer(manifest))

	var player := _build_player(manifest, floor_layer)
	world.add_child(player)
	_build_npcs(manifest, floor_layer, world)

	var world_compositor := Node2D.new()
	world_compositor.name = "WorldDepthCompositor"
	world_compositor.script = load(WORLD_DEPTH_COMPOSITOR_SCRIPT)
	world.add_child(world_compositor)

	var compositor := Sprite2D.new()
	compositor.name = "CharacterDepthCompositor"
	compositor.script = load(DEPTH_COMPOSITOR_SCRIPT)
	world.add_child(compositor)

	root.add_child(_build_level_runtime(manifest))
	root.add_child(_build_debug_overlay())
	_assign_owner(root, root)
	return root


# The session, and later the console, live in a hand-authored scene so the generated level
# only has to carry the level's own CONDITION values.
func _build_level_runtime(manifest: Dictionary) -> Node:
	var session := (load(LEVEL_RUNTIME_SCENE) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
	var conditions: Dictionary = manifest.get("conditions", {})
	var time_mode: Dictionary = conditions.get("time", {})
	var points_mode: Dictionary = conditions.get("points", {})
	session.set("time_mode_limit_seconds", float(time_mode.get("time_limit_seconds", 0.0)))
	session.set("time_mode_score_target", int(time_mode.get("score_target", 0)))
	session.set("points_mode_limit_seconds", float(points_mode.get("time_limit_seconds", 0.0)))
	session.set("points_mode_score_target", int(points_mode.get("score_target", 0)))
	return session


func _build_collision_layer(manifest: Dictionary) -> TileMapLayer:
	var layer := TileMapLayer.new()
	layer.name = "CollisionTileMapLayer"
	layer.script = load(COLLISION_MAP_SCRIPT)
	layer.tile_set = load(COLLISION_TILESET) as TileSet
	layer.z_index = 10
	# Locked so painting collision cells in the editor cannot drag the layer itself.
	layer.set_meta("_edit_lock_", true)
	var collision_grid: Dictionary = manifest.get("collision_grid", {})
	for cell in collision_grid.get("blocked_cells", []):
		layer.set_cell(_vector2i(cell), 0, Vector2i.ZERO)
	return layer


func _build_tile_layer(layer_data: Dictionary) -> TileMapLayer:
	var layer := TileMapLayer.new()
	layer.name = String(layer_data.get("name", "TileMapLayer"))
	if layer.name == "WallTileMapLayer":
		layer.script = load(MAP_TILE_LAYER_SCRIPT)
	layer.tile_set = load(String(layer_data.get("tileset", ""))) as TileSet
	layer.z_index = int(layer_data.get("z_index", 0))
	for cell_data in layer_data.get("cells", []):
		var cell := _vector2i(cell_data.get("cell", [0, 0]))
		var atlas_coords := _vector2i(cell_data.get("atlas_coords", [0, 0]))
		var source_id := int(cell_data.get("source_id", -1))
		layer.set_cell(cell, source_id, atlas_coords, 0)
	return layer


func _build_objects(manifest: Dictionary, floor_layer: TileMapLayer) -> Node2D:
	var objects := Node2D.new()
	objects.name = "Objects"
	objects.z_index = 0
	for object_data in manifest.get("objects", []):
		var prefab := _object_prefab(object_data)
		if prefab == null:
			continue
		var object_node := prefab.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE) as Node2D
		object_node.name = String(object_data.get("node_name", "Object"))
		object_node.position = _tile_position_to_local(_vector2(object_data.get("tile_position", [0.0, 0.0])), floor_layer)
		object_node.set_meta("original_kind", String(object_data.get("kind", "")))
		object_node.set_meta("original_object_id", String(object_data.get("object_id", "")))
		object_node.set_meta("original_object_category", int(object_data.get("object_category", -1)))
		object_node.set_meta("original_sprite_name", String(object_data.get("sprite_name", "")))
		object_node.set_meta("original_source_sprite", String(object_data.get("source_sprite", "")))
		object_node.set_meta("original_tile_position", _vector2(object_data.get("tile_position", [0.0, 0.0])))
		object_node.set_meta("original_height", float(object_data.get("height", 0.0)))
		object_node.set_meta("original_instance_id", int(object_data.get("instance_id", 0)))
		objects.add_child(object_node)
		var interaction := Marker2D.new()
		interaction.name = "InteractionPoint"
		interaction.script = load(ACTIVITY_POINT_SCRIPT)
		interaction.position = _tile_position_to_local(_vector2(object_data["interaction_tile_position"]), floor_layer) - object_node.position
		var kind := String(object_data["kind"]).hex_to_int()
		interaction.set("category", (kind >> 16) & 0xff)
		interaction.set("item_type", (kind >> 4) & 0xfff)
		interaction.set("active", int(object_data["object_category"]) == 5)
		var action_ids := PackedInt32Array()
		for action_id in object_data.get("action_ids", []):
			action_ids.append(int(action_id))
		interaction.set("action_ids", action_ids)
		var tile := _vector2(object_data["tile_position"])
		var collision: Dictionary = manifest["collision_grid"]
		var cell := Vector2i(floori(tile.x + 0.5), floori(tile.y + 0.5))
		if cell.x >= 0 and cell.y >= 0 and cell.x < int(collision["width"]) and cell.y < int(collision["height"]):
			interaction.set("room_id", int(collision["room_ids"][cell.y * int(collision["width"]) + cell.x]))
		object_node.add_child(interaction)
	return objects


func _object_prefab(object_data: Dictionary) -> PackedScene:
	var texture_path := String(object_data.get("texture", ""))
	var pivot := _vector2(object_data.get("pivot", [0, 0]))
	var key := "%s|%s" % [texture_path, pivot]
	if _object_prefabs.has(key):
		return _object_prefabs[key]
	var basename := texture_path.get_file().get_basename()
	var prefab_path := "res://scenes/objects/%s.tscn" % basename
	if _prefab_paths.has(prefab_path):
		prefab_path = "res://scenes/objects/%s-pivot-%d-%d.tscn" % [basename, int(pivot.x), int(pivot.y)]
	_prefab_paths[prefab_path] = key
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(prefab_path.get_base_dir()))
	var object_scene := load(MAP_OBJECT_SCENE) as PackedScene
	var object_node := object_scene.instantiate() as Node2D
	object_node.name = basename.to_pascal_case()
	object_node.set("color_texture", load(texture_path))
	var depth_path := texture_path.get_basename() + "-depth.png"
	if ResourceLoader.exists(depth_path):
		object_node.set("depth_texture", load(depth_path))
	object_node.set("pivot", pivot)
	var packed := PackedScene.new()
	var pack_error := packed.pack(object_node)
	object_node.free()
	if pack_error != OK:
		push_error("Failed to pack %s: %s" % [prefab_path, error_string(pack_error)])
		return null
	var save_error := ResourceSaver.save(packed, prefab_path)
	if save_error != OK:
		push_error("Failed to save %s: %s" % [prefab_path, error_string(save_error)])
		return null
	var prefab := load(prefab_path) as PackedScene
	_object_prefabs[key] = prefab
	return prefab


func _build_player(manifest: Dictionary, floor_layer: TileMapLayer) -> Node2D:
	var player_scene := load(PLAYER_SCENE) as PackedScene
	var player := player_scene.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE) as Node2D
	player.name = "Player"
	var spawn := _player_spawn(manifest)
	player.position = _tile_position_to_local(_vector2(spawn.get("tile_position", [0.0, 0.0])), floor_layer)
	player.set_meta("original_spawn_id", int(spawn.get("spawn_id", 0)))
	return player


func _build_npcs(manifest: Dictionary, floor_layer: TileMapLayer, world: Node2D) -> void:
	var npc_scene := load(NPC_SCENE) as PackedScene
	var object_names: Dictionary = {}
	for object_data in manifest.get("objects", []):
		object_names[int(object_data["instance_id"])] = String(object_data["node_name"])
	for npc_data in manifest.get("npcs", []):
		var npc := npc_scene.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE) as Node2D
		npc.name = String(npc_data["node_name"])
		npc.position = _tile_position_to_local(_vector2(npc_data["tile_position"]), floor_layer)
		npc.set("profile", load(npc_data["profile"]))
		npc.set("initial_direction", IsoDirection.get_screen_directions()[int(npc_data["initial_direction_index"])])
		npc.set_meta("original_spawn_id", int(npc_data["spawn_id"]))
		npc.set_meta("original_instance_id", int(npc_data["instance_id"]))
		var brain := Node.new()
		brain.name = "Brain"
		brain.script = load(NPC_BRAIN_SCRIPT)
		for field in ["assigned_workstation", "assigned_chair"]:
			var instance_id = npc_data.get(field + "_instance_id")
			if instance_id != null:
				brain.set(field, NodePath("../../Objects/%s/InteractionPoint" % object_names[int(instance_id)]))
		npc.add_child(brain)
		world.add_child(npc)


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
		if child.owner == null:
			child.owner = owner
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
