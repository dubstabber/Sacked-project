extends SceneTree


const LEVEL_SCENE := preload("res://scenes/level_1.tscn")
const COLLISION_LAYER := preload("res://scenes/shared/collision_map_layer.gd")
const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const NPC_SCENE := preload("res://scenes/npc/npc.tscn")
const PLAYER_PROFILE := preload("res://scenes/player/profiles/jobless.tres")
const NPC_PROFILE := preload("res://scenes/npc/profiles/boss.tres")
const EPSILON := 0.015

var _failures := 0
var _tile_set: TileSet


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await _check_original_map()
	if _tile_set == null:
		quit(1)
		return
	_check_stopping_and_sliding()
	_check_corners_and_fast_movement()
	_check_arbitrary_direction_clearance()
	_check_authored_cells_and_scene_round_trip()
	await _check_character_runtime(false)
	await _check_character_runtime(true)
	await _check_npc_arrival_does_not_cross_wall()
	if _failures == 0:
		print("Map collisions: original grid, walls, furniture, sliding, corners, authoring and player/NPC runtime passed")
	quit(1 if _failures else 0)


func _check_original_map() -> void:
	var level := LEVEL_SCENE.instantiate()
	root.add_child(level)
	var player := level.get_node("World/Player") as CharacterBody2D
	player.set_physics_process(false)
	_silence_player(player)
	await process_frame
	var layer := level.get_node_or_null("World/CollisionTileMapLayer") as TileMapLayer
	if layer == null:
		_expect(false, "reference level has an authored collision layer")
		level.free()
		return
	_tile_set = layer.tile_set
	_expect(layer.get_used_cells().size() == 117, "reference collision layer preserves all 117 INFODATA blockers")
	_expect(not layer.visible, "collision painting overlay is hidden while playing")
	var floor_layer := level.get_node("World/FloorTileMapLayer") as TileMapLayer
	_expect(layer.map_to_local(Vector2i(12, 9)) == floor_layer.map_to_local(Vector2i(12, 9)), "collision and floor tile coordinates agree")
	for cell in [Vector2i(5, 4), Vector2i(1, 1), Vector2i(7, 10), Vector2i(15, 6), Vector2i(15, 8)]:
		_expect(layer.get_cell_source_id(cell) >= 0, "original wall, furniture or padding cell %s blocks movement" % cell)
	for cell in [Vector2i(3, 4), Vector2i(4, 4), Vector2i(1, 5), Vector2i(1, 8), Vector2i(8, 3), Vector2i(8, 10), Vector2i(12, 9)]:
		_expect(layer.get_cell_source_id(cell) == -1, "original doorway, decoration or sight-only cell %s stays passable" % cell)
	_expect_vector(_tile_position(layer, player.global_position), Vector2(12, 9), "original player spawn uses the free cell")
	for direction in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
		_expect_vector(_allowed_motion(layer, Vector2(12, 9), direction * 0.05), direction * 0.05, "player can leave the original spawn")
	_expect_vector(_allowed_motion(layer, Vector2(3, 4), Vector2.RIGHT), Vector2.RIGHT, "the two-cell doorway remains traversable")
	_expect(_allowed_motion(layer, Vector2(4, 4), Vector2.RIGHT).x < 0.16, "walking from the doorway stops at the wall")
	_expect(absf(_allowed_motion(layer, Vector2(8, 10), Vector2.LEFT).x) < 0.16, "walking into the furniture cluster stops")
	level.free()


func _check_stopping_and_sliding() -> void:
	var world := _make_world()
	var layer := _add_layer(world)
	_paint_wall(layer, 2)
	_expect_vector(_allowed_motion(layer, Vector2.ZERO, Vector2(4, 0)), Vector2(1.14, 0), "the feet stop before the wall using the original clearance")
	_expect_vector(_allowed_motion(layer, Vector2.ZERO, Vector2(3, 1)), Vector2(1.14, 1), "movement along an isometric wall preserves the free axis")
	_expect_vector(_allowed_motion(layer, Vector2(4, 0), Vector2(-4, 0)), Vector2(-1.14, 0), "wall collision works from the opposite side")
	_expect_vector(_allowed_motion(layer, Vector2(0, 0), Vector2(0, 4)), Vector2(0, 4), "a clear corridor permits the complete motion")
	var stopped := Vector2(1.14, 0)
	for index in range(50):
		stopped += _allowed_motion(layer, stopped, Vector2(0.08, 0))
	_expect(stopped.x <= 1.15, "sustained pressure never pushes the character through a wall")
	world.free()


func _check_corners_and_fast_movement() -> void:
	var world := _make_world()
	var layer := _add_layer(world)
	layer.set_cell(Vector2i(1, 0), 0, Vector2i.ZERO)
	layer.set_cell(Vector2i(0, 1), 0, Vector2i.ZERO)
	var corner := _allowed_motion(layer, Vector2.ZERO, Vector2(4, 4))
	_expect(corner.x <= 0.15 and corner.y <= 0.15, "a diagonal cannot squeeze between touching blocked cells")
	layer.clear()
	_paint_wall(layer, 2)
	_expect_vector(_allowed_motion(layer, Vector2.ZERO, Vector2(80, 0)), Vector2(1.14, 0), "large motion cannot tunnel through a one-cell wall")
	layer.clear()
	_paint_wall(layer, -2)
	_expect_vector(_allowed_motion(layer, Vector2.ZERO, Vector2(-80, 0)), Vector2(-1.14, 0), "negative map coordinates use the same collision clearance")
	world.free()


func _check_authored_cells_and_scene_round_trip() -> void:
	var world := _make_world()
	world.position = Vector2(211, -87)
	var layer := _add_layer(world)
	layer.position = Vector2(173, 91)
	layer.set_cell(Vector2i(32, 30), 0, Vector2i.ZERO)
	_expect_vector(_allowed_motion(layer, Vector2(30, 30), Vector2(4, 0)), Vector2(1.14, 0), "painted cells work beyond the original map and under translated parents")
	layer.erase_cell(Vector2i(32, 30))
	_expect_vector(_allowed_motion(layer, Vector2(30, 30), Vector2(4, 0)), Vector2(4, 0), "erasing a painted cell opens the path immediately")
	layer.set_cell(Vector2i(32, 30), 0, Vector2i.ZERO)
	layer.enabled = false
	_expect_vector(_allowed_motion(layer, Vector2(30, 30), Vector2(4, 0)), Vector2(4, 0), "disabling the collision layer opens the path")
	layer.enabled = true
	layer.owner = world
	var authored_scene := PackedScene.new()
	_expect(authored_scene.pack(world) == OK, "an authored collision layer can be saved as a scene")
	world.free()
	var restored := authored_scene.instantiate()
	root.add_child(restored)
	var restored_layer := restored.get_node("CollisionTileMapLayer") as TileMapLayer
	_expect(restored_layer.get_used_cells() == [Vector2i(32, 30)], "a custom scene retains exactly its authored cells")
	_expect_vector(_allowed_motion(restored_layer, Vector2(30, 30), Vector2(4, 0)), Vector2(1.14, 0), "saved collision cells work without loading a level manifest")
	_expect_vector(_allowed_motion(restored_layer, Vector2(-100, -100), Vector2(2, 0)), Vector2(2, 0), "there is no implicit boundary copied from the original map")
	restored.free()


func _check_arbitrary_direction_clearance() -> void:
	var world := _make_world()
	var layer := _add_layer(world)
	for cell in [Vector2i(2, 0), Vector2i(2, 1), Vector2i(2, 2), Vector2i(-1, -1), Vector2i(0, -1), Vector2i(-1, 0)]:
		layer.set_cell(cell, 0, Vector2i.ZERO)
	var start := Vector2(0.918382, -0.397224)
	var requested := Vector2(0.271305, 2.181145)
	var final_position := start + _allowed_motion(layer, start, requested)
	_expect(final_position.x <= 1.15, "an arbitrary direction cannot enter the wall through a corner")
	_expect(absf(final_position.y - 1.783921) <= EPSILON, "an arbitrary direction preserves its free movement along the wall")
	for cell in layer.get_used_cells():
		var distance := (final_position - Vector2(cell)).abs()
		_expect(distance.x >= 0.85 or distance.y >= 0.85, "the complete foot rectangle stays outside blocked cell %s" % cell)
	world.free()


func _check_character_runtime(is_npc: bool) -> void:
	var world := _make_world()
	var layer := _add_layer(world)
	_paint_wall(layer, 2)
	var unrelated_world := _make_world()
	_paint_wall(_add_layer(unrelated_world), 1)
	var actor: CharacterBody2D = NPC_SCENE.instantiate() if is_npc else PLAYER_SCENE.instantiate()
	actor.profile = NPC_PROFILE if is_npc else PLAYER_PROFILE
	actor.position = _world_position(layer, Vector2.ZERO)
	actor.move_speed = 600.0
	if is_npc:
		actor.patrol_offsets = [Vector2(800, 0)] as Array[Vector2]
		actor.pause_seconds = 0.0
	world.add_child(actor)
	if not is_npc:
		_silence_player(actor)
		Input.action_press("move_right")
	for frame in range(40):
		await physics_frame
	actor.set_physics_process(false)
	if not is_npc:
		Input.action_release("move_right")
		_silence_player(actor)
	var final_tile := _tile_position(layer, actor.global_position)
	var label := "NPC" if is_npc else "player"
	_expect(final_tile.x > 1.0 and final_tile.x <= 1.15, "%s actually stops at the wall during physics frames: %s" % [label, final_tile])
	_expect(final_tile.y < -1.5, "%s continues along the wall instead of freezing: %s" % [label, final_tile])
	var shape_node := actor.get_node("CollisionShape2D") as CollisionShape2D
	_expect_vector(shape_node.position, Vector2.ZERO, "%s native collision shape is anchored at the feet" % label)
	var shape := shape_node.shape as ConvexPolygonShape2D
	_expect(shape != null, "%s native collision footprint follows the isometric ground plane" % label)
	if shape != null:
		for point in shape.points:
			_expect(absf(point.x) <= 33.61 and absf(point.y) <= 16.81, "%s footprint stays within the original 0.35-tile radius" % label)
	world.free()
	unrelated_world.free()


func _check_npc_arrival_does_not_cross_wall() -> void:
	var world := _make_world()
	var layer := _add_layer(world)
	_paint_wall(layer, 2)
	var npc := NPC_SCENE.instantiate() as CharacterBody2D
	npc.profile = NPC_PROFILE
	npc.position = _world_position(layer, Vector2(1.13, 0))
	var target := _world_position(layer, Vector2(1.2, 0))
	npc.patrol_offsets = [target - npc.position] as Array[Vector2]
	npc.pause_seconds = 100.0
	world.add_child(npc)
	for frame in range(10):
		await physics_frame
	npc.set_physics_process(false)
	var final_tile := _tile_position(layer, npc.global_position)
	_expect(final_tile.x <= 1.15, "NPC arrival cannot snap its feet into the wall: %s" % final_tile)
	_expect(npc.global_position.distance_to(target) > 1.0, "NPC stays before a blocked patrol target inside its arrival distance")
	_expect(npc._pause_remaining == 0.0, "NPC does not mark a blocked patrol target as reached")
	world.free()


func _make_world() -> Node2D:
	var world := Node2D.new()
	world.name = "World"
	root.add_child(world)
	return world


func _add_layer(world: Node2D) -> TileMapLayer:
	var layer := COLLISION_LAYER.new() as TileMapLayer
	layer.name = "CollisionTileMapLayer"
	layer.tile_set = _tile_set
	world.add_child(layer)
	return layer


func _paint_wall(layer: TileMapLayer, x: int) -> void:
	for y in range(-12, 13):
		layer.set_cell(Vector2i(x, y), 0, Vector2i.ZERO)


func _world_position(layer: TileMapLayer, tile: Vector2) -> Vector2:
	return layer.to_global(layer.map_to_local(Vector2i.ZERO) + Vector2(48 * (tile.x - tile.y), 24 * (tile.x + tile.y)))


func _tile_position(layer: TileMapLayer, world_position: Vector2) -> Vector2:
	var relative := layer.to_local(world_position) - layer.map_to_local(Vector2i.ZERO)
	return Vector2(relative.x / 96 + relative.y / 48, -relative.x / 96 + relative.y / 48)


func _allowed_motion(layer: TileMapLayer, from_tile: Vector2, motion: Vector2) -> Vector2:
	var from_world := _world_position(layer, from_tile)
	var requested := _world_position(layer, from_tile + motion) - from_world
	var allowed: Vector2 = layer.constrain_motion(from_world, requested)
	return _tile_position(layer, from_world + allowed) - from_tile


func _silence_player(player: Node) -> void:
	var footsteps := player.get_node("FootstepPlayer")
	footsteps.stop_footsteps()
	footsteps.stream = null


func _expect_vector(actual: Vector2, expected: Vector2, label: String) -> void:
	_expect(actual.distance_to(expected) <= EPSILON, "%s: expected %s, got %s" % [label, expected, actual])


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
