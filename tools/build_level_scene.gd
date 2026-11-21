extends SceneTree


const DEFAULT_MANIFEST_PATH := "res://resources/levels/level_1.json"
const DEFAULT_SCENE_PATH := "res://scenes/level_1.tscn"
const PLAYER_SCENE := "res://scenes/player/player.tscn"
const DEPTH_COMPOSITOR_SCRIPT := "res://scenes/shared/character_depth_compositor.gd"
const WORLD_DEPTH_COMPOSITOR_SCRIPT := "res://scenes/shared/world_depth_compositor.gd"
const MAP_TILE_LAYER_SCRIPT := "res://scenes/shared/map_tile_layer.gd"
const FLOOR_TILE_LAYER_SCRIPT := "res://scenes/shared/floor_tile_layer.gd"
const MAP_OBJECT_SCENE := "res://scenes/shared/map_object.tscn"
const FPS_COUNTER_SCRIPT := "res://scenes/debug/fps_counter.gd"
const COLLISION_MAP_SCRIPT := "res://scenes/shared/collision_map_layer.gd"
const COLLISION_TILESET := "res://resources/tilemaps/sacked-collision.tres"
const OVERLAY_MAP_SCRIPT := "res://scenes/shared/overlay_map_layer.gd"
const ROOM_TILESET := "res://resources/tilemaps/sacked-rooms.tres"
const SIGHT_TILESET := "res://resources/tilemaps/sacked-sight.tres"
# The room diamond's alternatives are rooms 0-31, the rooms a goal mask can name.
const ROOM_LIMIT := 32
const NPC_SCENE := "res://scenes/npc/npc.tscn"
const NPC_BRAIN_SCRIPT := "res://scenes/npc/npc_brain.gd"
const THOUGHT_BUBBLE_SCRIPT := "res://scenes/npc/thought_bubble.gd"
const ACTIVITY_POINT_SCRIPT := "res://scenes/npc/npc_activity_point.gd"
const LEVEL_RUNTIME_SCENE := "res://scenes/level/level_runtime.tscn"

var _object_prefabs: Dictionary = {}
var _prefab_paths: Dictionary = {}
var _interaction_overrides := 0
# Object instances whose InteractionPoint the level places apart from the prefab's, which the
# packed scene only keeps for an editable instance.
var _editable_objects: Array[Node] = []


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

	var scene_root := _build_scene(manifest)
	var packed := PackedScene.new()
	var pack_error := packed.pack(scene_root)
	if pack_error != OK:
		push_error("Failed to pack level scene: %s" % error_string(pack_error))
		quit(1)
		return

	var save_error := ResourceSaver.save(packed, scene_path)
	if save_error != OK:
		push_error("Failed to save %s: %s" % [scene_path, error_string(save_error)])
		scene_root.free()
		quit(1)
		return

	print("Saved %s (%d interaction points placed apart from their prefab's)" % [scene_path, _interaction_overrides])
	scene_root.free()
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
	var scene_root := Node.new()
	scene_root.name = "Main"

	var world := Node2D.new()
	world.name = "World"
	scene_root.add_child(world)

	var floor_layer: TileMapLayer = null
	for layer_data in manifest.get("tile_layers", []):
		var layer := _build_tile_layer(layer_data)
		world.add_child(layer)
		if layer.name == "FloorTileMapLayer":
			floor_layer = layer

	if floor_layer == null:
		push_error("Level manifest did not create FloorTileMapLayer")
		return scene_root

	var objects := _build_objects(manifest, floor_layer)
	world.add_child(objects)
	world.add_child(_build_collision_layer(manifest))
	world.add_child(_build_room_layer(manifest))
	world.add_child(_build_sight_layer(manifest))

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

	scene_root.add_child(_build_level_runtime(manifest))
	scene_root.add_child(_build_debug_overlay())
	_assign_owner(scene_root, scene_root)
	for object_node in _editable_objects:
		scene_root.set_editable_instance(object_node, true)
	return scene_root


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
	layer.set("map_size", Vector2i(int(collision_grid.get("width", 0)), int(collision_grid.get("height", 0))))
	return layer


# INFODATA bits 16-23, painted: each cell of a room other than 0 carries the room diamond's
# alternative tile of that number. An unpainted cell is room 0.
func _build_room_layer(manifest: Dictionary) -> TileMapLayer:
	var layer := _overlay_layer("RoomTileMapLayer", ROOM_TILESET, 9)
	layer.set("label_cells", true)
	var collision_grid: Dictionary = manifest.get("collision_grid", {})
	var width := int(collision_grid.get("width", 0))
	var rooms: Array = collision_grid.get("room_ids", [])
	for index in range(rooms.size()):
		var room := int(rooms[index])
		if room >= ROOM_LIMIT:
			push_error("Room %d at cell %d is past the %d rooms the room diamond has" % [room, index, ROOM_LIMIT])
		elif room != 0:
			@warning_ignore("integer_division")
			layer.set_cell(Vector2i(index % width, index / width), 0, Vector2i.ZERO, room)
	return layer


# INFODATA bit 1. Painted apart from the movement cells: they overlap almost everywhere, but a
# few cells block one and not the other.
func _build_sight_layer(manifest: Dictionary) -> TileMapLayer:
	var layer := _overlay_layer("SightTileMapLayer", SIGHT_TILESET, 11)
	for cell in manifest.get("collision_grid", {}).get("sight_blocked_cells", []):
		layer.set_cell(_vector2i(cell), 0, Vector2i.ZERO)
	return layer


func _overlay_layer(layer_name: String, tileset_path: String, z: int) -> TileMapLayer:
	var layer := TileMapLayer.new()
	layer.name = layer_name
	layer.script = load(OVERLAY_MAP_SCRIPT)
	layer.tile_set = load(tileset_path) as TileSet
	layer.z_index = z
	layer.set_meta("_edit_lock_", true)
	# Saved hidden, so the editor opens on the art and the movement cells as before; the eye
	# beside the layer shows it for painting.
	layer.visible = false
	return layer


func _build_tile_layer(layer_data: Dictionary) -> TileMapLayer:
	var layer := TileMapLayer.new()
	layer.name = String(layer_data.get("name", "TileMapLayer"))
	if layer.name == "WallTileMapLayer":
		layer.script = load(MAP_TILE_LAYER_SCRIPT)
	elif layer.name == "FloorTileMapLayer":
		layer.script = load(FLOOR_TILE_LAYER_SCRIPT)
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
		var prefab := _object_prefab(object_data, floor_layer)
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
		# The prefab carries the point; its room is read off the painted rooms at run time.
		# Where float32 puts this one apart from the prefab's offset, the level keeps the exact
		# place the point has always had: an NPC's route ends at floori(x + 0.5) of it, and
		# 211 points sit on a half-cell boundary.
		var interaction := object_node.get_node("InteractionPoint") as Node2D
		var exact := _tile_position_to_local(_vector2(object_data["interaction_tile_position"]), floor_layer) - object_node.position
		if interaction.position != exact:
			interaction.position = exact
			_interaction_overrides += 1
			_editable_objects.append(object_node)
	return objects


# One prefab per sprite, pivot and kind: the object's look and the gameplay its record gives it,
# so one dragged into a map is a working object. A texture two kinds share gets a prefab per
# kind, named by the importer (assign_prefab_names in tools/import_original_level.py).
func _object_prefab(object_data: Dictionary, floor_layer: TileMapLayer) -> PackedScene:
	var texture_path := String(object_data.get("texture", ""))
	var pivot := _vector2(object_data.get("pivot", [0, 0]))
	var basename := String(object_data.get("prefab", texture_path.get_file().get_basename()))
	var key := "%s|%s|%s" % [texture_path, pivot, basename]
	if _object_prefabs.has(key):
		return _object_prefabs[key]
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
	# What the object is, for the editor's palette; nothing at run time reads these.
	object_node.set_meta("display_name", String(object_data.get("display_name", "")))
	object_node.set_meta("object_category", int(object_data.get("object_category", -1)))
	var interaction := _interaction_point(object_data)
	# The kind's oriented DAT offset. Each level builds in a process of its own and saves the
	# prefabs it places, so the offset has to come out the same whichever instance a level meets
	# first: the manifests round each object's two tiles to six decimals, which leaves an
	# offset of 0.7 as 0.699999 on some of them.
	var offset := _vector2(object_data["interaction_tile_position"]) - _vector2(object_data["tile_position"])
	interaction.position = _tile_offset_to_local(offset.snapped(Vector2(0.0001, 0.0001)), floor_layer)
	object_node.add_child(interaction)
	interaction.owner = object_node
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


# The object's CO_OBJECTS.DAT record, as the NPCs and the pranks read it. Its room is left at
# -1, to be read off the painted rooms wherever the object stands.
func _interaction_point(object_data: Dictionary) -> Marker2D:
	var interaction := Marker2D.new()
	interaction.name = "InteractionPoint"
	interaction.script = load(ACTIVITY_POINT_SCRIPT)
	var kind := String(object_data["kind"]).hex_to_int()
	interaction.set("category", (kind >> 16) & 0xff)
	interaction.set("group", (kind >> 24) & 0xff)
	interaction.set("item_type", (kind >> 4) & 0xfff)
	interaction.set("active", int(object_data["object_category"]) == 5)
	# item+196, the object's quarter-turn index. sub_41B240's selector-5 branch reads it
	# to pick which side the player steps onto. See docs/player-action-reference.md.
	interaction.set("orientation", int(object_data.get("variant", 0)))
	var action_ids := PackedInt32Array()
	for action_id in object_data.get("action_ids", []):
		action_ids.append(int(action_id))
	interaction.set("action_ids", action_ids)
	return interaction


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
		npc.set_meta("original_tile_position", _vector2(npc_data["tile_position"]))
		var brain := Node.new()
		brain.name = "Brain"
		brain.script = load(NPC_BRAIN_SCRIPT)
		# The importer ran the level start's desk search (build_npcs); NPCStartup runs it at
		# run time only for an agent that has not had it, as for the template's coworker.
		if not bool(npc_data.get("runtime_desk", false)):
			brain.set_meta("startup_assigned", true)
		for field in ["assigned_workstation", "assigned_chair"]:
			var instance_id = npc_data.get(field + "_instance_id")
			if instance_id != null:
				brain.set(field, NodePath("../../Objects/%s/InteractionPoint" % object_names[int(instance_id)]))
		npc.add_child(brain)
		var bubble := Sprite2D.new()
		bubble.name = "ThoughtBubble"
		bubble.script = load(THOUGHT_BUBBLE_SCRIPT)
		npc.add_child(bubble)
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


func _tile_offset_to_local(offset: Vector2, floor_layer: TileMapLayer) -> Vector2:
	var origin := floor_layer.map_to_local(Vector2i.ZERO)
	return (floor_layer.map_to_local(Vector2i(1, 0)) - origin) * offset.x + (floor_layer.map_to_local(Vector2i(0, 1)) - origin) * offset.y


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
