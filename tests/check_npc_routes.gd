extends SceneTree


const NPC_SCENE := preload("res://scenes/npc/npc.tscn")
const BOSS_PROFILE := preload("res://scenes/npc/profiles/boss.tres")
const EMPLOYEE_PROFILE := preload("res://scenes/npc/profiles/male-employee-1.tres")
const ROUTE_SCRIPT := preload("res://scenes/npc/npc_route.gd")
const WAYPOINT_SCRIPT := preload("res://scenes/npc/npc_waypoint.gd")
const COLLISION_SCRIPT := preload("res://scenes/shared/collision_map_layer.gd")
const COLLISION_TILESET := preload("res://resources/tilemaps/sacked-collision.tres")
const EPSILON := 0.02

var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await _check_shared_stationary_route()
	await _check_collision_detour()
	await _check_unreachable_destination()
	await _check_seated_activity_and_cancellation()
	await _check_missing_seated_view_uses_original_fallback()
	if _failures == 0:
		print("NPC routes: independent shared routes, waypoint order, waits, facing, completion, detours, failure and seated activities passed")
	quit(1 if _failures else 0)


func _check_shared_stationary_route() -> void:
	var world := _make_world()
	var route := ROUTE_SCRIPT.new()
	route.name = "SharedRoute"
	route.position = Vector2(40, 40)
	route.loop = false
	world.add_child(route)
	var first := _add_waypoint(route, "ZFirst", Vector2.ZERO, 0.2, Vector2(-48, -24))
	var second := _add_waypoint(route, "ASecond", Vector2(96, 0), 0.0, Vector2.ZERO)
	var last := _add_waypoint(route, "Last", Vector2(96, 48), 0.1, Vector2(48, 24))
	var decoration := Marker2D.new()
	route.add_child(decoration)
	_expect(route.get_waypoints() == [first, second, last], "route order follows waypoint child order and ignores ordinary markers")
	var original_positions := [first.global_position, second.global_position, last.global_position]
	var fast := _make_npc(first.global_position, 8.0)
	fast.route_path = NodePath("../SharedRoute")
	var slow := _make_npc(first.global_position - Vector2(96, 0), 4.0)
	slow.route_path = NodePath("../SharedRoute")
	var fast_events := _route_events(fast)
	var slow_events := _route_events(slow)
	world.add_child(fast)
	world.add_child(slow)
	await _wait_until(func(): return not fast_events.visits.is_empty(), 30, "first NPC reaches the first waypoint")
	if fast_events.visits.is_empty():
		world.free()
		return
	_expect(slow_events.visits.is_empty(), "another NPC sharing the route keeps its own waypoint progress")
	for frame in range(5):
		await physics_frame
		_expect_vector(fast.global_position, first.global_position, "NPC remains at its waypoint during the authored wait")
		_expect_vector(fast.last_direction, Vector2(-48, -24).normalized(), "waypoint facing applies while waiting")
	await _wait_until(func(): return fast_events.finished == 1 and slow_events.finished == 1, 180, "both NPCs finish the non-looping route")
	for events in [fast_events, slow_events]:
		_expect(events.visits == [0, 1, 2], "each NPC visits every waypoint once in authored order")
		if events.times.size() >= 2:
			var elapsed := float(events.times[1] - events.times[0]) / Engine.physics_ticks_per_second
			_expect(elapsed >= 0.2, "waypoint wait duration elapses before reaching the next point")
	if not slow_events.times.is_empty():
		_expect(fast_events.times[0] < slow_events.times[0], "shared route does not share arrival timing")
	_expect_vector(fast.global_position, last.global_position, "first NPC stops at the final waypoint")
	_expect_vector(slow.global_position, last.global_position, "second NPC stops at the final waypoint")
	for frame in range(5):
		await physics_frame
	_expect(fast_events.finished == 1 and slow_events.finished == 1, "non-looping routes emit completion exactly once")
	_expect(first.global_position == original_positions[0] and second.global_position == original_positions[1] and last.global_position == original_positions[2], "route markers stay fixed while both NPCs move")
	world.free()


func _check_collision_detour() -> void:
	var world := _make_world()
	var layer := _make_corridor(world, true)
	var npc := _make_npc(_world_position(layer, Vector2(1, 1)), 8.0)
	world.add_child(npc)
	var events := _navigation_events(npc)
	var target := _world_position(layer, Vector2(5, 1))
	npc.navigate_to(target)
	var crossed_gap := false
	for frame in range(240):
		await physics_frame
		var position := _tile_position(layer, npc.global_position)
		if absf(position.x - 3.0) < 0.3 and absf(position.y - 4.0) < 0.15:
			crossed_gap = true
		_expect_footprint_clear(layer, position)
		if events.reached > 0 or events.failed > 0:
			break
	_expect(events.reached == 1 and events.failed == 0, "NPC reaches its destination through the available passage")
	_expect(crossed_gap, "NPC detours through the wall gap instead of cutting across blocked cells")
	_expect_vector(npc.global_position, target, "navigation reaches the exact requested point")
	world.free()


func _check_unreachable_destination() -> void:
	var world := _make_world()
	var layer := _make_corridor(world, false)
	var start := _world_position(layer, Vector2(1, 1))
	var npc := _make_npc(start, 8.0)
	world.add_child(npc)
	var events := _navigation_events(npc)
	npc.navigate_to(_world_position(layer, Vector2(5, 1)))
	await _wait_until(func(): return events.failed > 0, 20, "an enclosed destination reports navigation failure")
	for frame in range(5):
		await physics_frame
	_expect(events.failed == 1 and events.reached == 0, "unreachable destination never emits false arrival")
	_expect_vector(npc.global_position, start, "failed navigation does not teleport or enter a blocked passage")
	world.free()


func _check_seated_activity_and_cancellation() -> void:
	var world := _make_world()
	var npc := _make_npc(Vector2(80, 80), 1.5)
	npc.profile = EMPLOYEE_PROFILE
	world.add_child(npc)
	var events := {"finished": 0, "frame": -1}
	npc.activity_finished.connect(func():
		events.finished += 1
		events.frame = Engine.get_physics_frames()
	)
	var return_position := npc.global_position
	var seat := Vector2(200, 180)
	var start_frame := Engine.get_physics_frames()
	_expect(npc.start_activity(&"sit-use", 0.3, Vector2(48, 24), seat, return_position), "employee can begin the original seated work animation")
	_expect_vector(npc.global_position, seat, "seated activity uses the chair anchor")
	await process_frame
	await process_frame
	var first_texture: Texture2D = npc.sprite.texture
	_expect(first_texture.resource_path.contains("male-employee-1-sit-use-down-right"), "activity selects the correct sitting direction")
	for frame in range(8):
		await physics_frame
		_expect_vector(npc.global_position, seat, "seated activity remains anchored while its animation plays")
	_expect(npc.sprite.texture != first_texture, "seated animation advances through the imported frame sequence")
	_expect(String(npc.animation_player.current_animation) == "male-employee-1-actions/male-employee-1-sit-use-down-right", "activity is playing the action library rather than the walking loop")
	await _wait_until(func(): return events.finished == 1, 35, "timed seated activity finishes")
	var elapsed := float(events.frame - start_frame) / Engine.physics_ticks_per_second
	_expect(absf(elapsed - 0.3) <= 2.0 / Engine.physics_ticks_per_second, "seated activity respects its authored duration")
	_expect_vector(npc.global_position, return_position, "finishing the seated activity restores the standing approach position")
	_expect(npc.current_activity == &"idle", "finished activity returns to idle")
	_expect(npc.start_activity(&"sit-idle", 10.0, Vector2(-48, -24), seat, return_position), "employee can start a second seated activity")
	for frame in range(3):
		await physics_frame
	npc.cancel_commands()
	_expect_vector(npc.global_position, return_position, "cancelling a seated action restores its standing position")
	_expect(npc.current_activity == &"idle" and npc.velocity == Vector2.ZERO, "cancellation clears movement and activity state")
	for frame in range(3):
		await physics_frame
	_expect(events.finished == 1, "cancellation does not emit a false activity completion")
	world.free()


func _check_missing_seated_view_uses_original_fallback() -> void:
	var world := _make_world()
	var npc := _make_npc(Vector2(80, 80), 1.5)
	npc.profile = EMPLOYEE_PROFILE
	world.add_child(npc)
	var events := {"finished": 0, "frame": -1}
	npc.activity_finished.connect(func():
		events.finished += 1
		events.frame = Engine.get_physics_frames()
	)
	var start_frame := Engine.get_physics_frames()
	_expect(npc.start_activity(&"sit-use", 0.2, Vector2.RIGHT), "a missing seated direction selects the original fallback instead of skipping the action")
	_expect(String(npc.animation_controller.current_animation).ends_with("sit-use-up-right"), "missing seated view falls back to original view 000")
	_expect_vector(npc.last_direction, Vector2.RIGHT, "view fallback preserves the NPC's requested facing")
	for frame in range(5):
		await physics_frame
	_expect(events.finished == 0 and npc.current_activity == &"sit-use", "fallback action remains active for its full wait")
	await _wait_until(func(): return events.finished == 1, 20, "fallback action eventually finishes")
	var elapsed := float(events.frame - start_frame) / Engine.physics_ticks_per_second
	_expect(absf(elapsed - 0.2) <= 2.0 / Engine.physics_ticks_per_second, "fallback view does not shorten the activity duration")
	world.free()


func _make_world() -> Node2D:
	var world := Node2D.new()
	root.add_child(world)
	return world


func _make_npc(position: Vector2, speed: float) -> CharacterBody2D:
	var npc := NPC_SCENE.instantiate() as CharacterBody2D
	npc.profile = BOSS_PROFILE
	npc.position = position
	npc.move_speed_tiles = speed
	return npc


func _add_waypoint(route: Node2D, node_name: String, position: Vector2, wait: float, facing: Vector2) -> Marker2D:
	var waypoint := WAYPOINT_SCRIPT.new()
	waypoint.name = node_name
	waypoint.position = position
	waypoint.wait_seconds = wait
	waypoint.facing = facing
	route.add_child(waypoint)
	return waypoint


func _route_events(npc: Node) -> Dictionary:
	var events := {"visits": [], "times": [], "finished": 0}
	npc.waypoint_reached.connect(func(index: int):
		events.visits.append(index)
		events.times.append(Engine.get_physics_frames())
	)
	npc.route_finished.connect(func(): events.finished += 1)
	return events


func _navigation_events(npc: Node) -> Dictionary:
	var events := {"reached": 0, "failed": 0}
	npc.destination_reached.connect(func(): events.reached += 1)
	npc.navigation_failed.connect(func(): events.failed += 1)
	return events


func _make_corridor(world: Node2D, open_gap: bool) -> TileMapLayer:
	var layer := COLLISION_SCRIPT.new() as TileMapLayer
	layer.tile_set = COLLISION_TILESET
	world.add_child(layer)
	for coordinate in range(-1, 8):
		for cell in [Vector2i(-1, coordinate), Vector2i(7, coordinate), Vector2i(coordinate, -1), Vector2i(coordinate, 7)]:
			layer.set_cell(cell, 0, Vector2i.ZERO)
	for y in range(7):
		if y != 4 or not open_gap:
			layer.set_cell(Vector2i(3, y), 0, Vector2i.ZERO)
	return layer


func _world_position(layer: TileMapLayer, tile: Vector2) -> Vector2:
	return layer.to_global(layer.map_to_local(Vector2i.ZERO) + Vector2(48 * (tile.x - tile.y), 24 * (tile.x + tile.y)))


func _tile_position(layer: TileMapLayer, position: Vector2) -> Vector2:
	var relative := layer.to_local(position) - layer.map_to_local(Vector2i.ZERO)
	return Vector2(relative.x / 96 + relative.y / 48, -relative.x / 96 + relative.y / 48)


func _expect_footprint_clear(layer: TileMapLayer, position: Vector2) -> void:
	for cell in layer.get_used_cells():
		var distance := (position - Vector2(cell)).abs()
		if distance.x < 0.8499 and distance.y < 0.8499:
			_expect(false, "NPC footprint overlaps blocked cell %s while navigating at %s" % [cell, position])
			return


func _wait_until(condition: Callable, max_frames: int, message: String) -> void:
	for frame in range(max_frames):
		if condition.call():
			return
		await physics_frame
	_expect(condition.call(), message)


func _expect_vector(actual: Vector2, expected: Vector2, label: String) -> void:
	_expect(actual.distance_to(expected) <= EPSILON, "%s: expected %s, got %s" % [label, expected, actual])


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
