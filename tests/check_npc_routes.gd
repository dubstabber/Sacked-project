extends SceneTree


const NPC_SCENE := preload("res://scenes/npc/npc.tscn")
const BOSS_PROFILE := preload("res://scenes/npc/profiles/boss.tres")
const EMPLOYEE_PROFILE := preload("res://scenes/npc/profiles/male-employee-1.tres")
const ROUTE_SCRIPT := preload("res://scenes/npc/npc_route.gd")
const WAYPOINT_SCRIPT := preload("res://scenes/npc/npc_waypoint.gd")
const COLLISION_SCRIPT := preload("res://scenes/shared/collision_map_layer.gd")
const COLLISION_TILESET := preload("res://resources/tilemaps/sacked-collision.tres")
const EPSILON := 0.02

class CountingLayer extends CollisionMapLayer:
	var lookups := 0

	func is_blocked(cell: Vector2i) -> bool:
		lookups += 1
		return super(cell)

var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await _check_shared_stationary_route()
	await _check_collision_detour()
	await _check_unreachable_destination()
	await _check_step_back_from_a_return_point()
	await _check_other_entities_block_routes()
	await _check_retries_do_not_search_again()
	await _check_seated_activity_and_cancellation()
	await _check_missing_seated_view_uses_original_fallback()
	await _check_turning_the_view()
	await _check_fidgeting()
	if _failures == 0:
		print("NPC routes: independent shared routes, waypoint order, waits, facing, completion, detours, failure, stepping back off a return point, other entities as obstacles, retries that search nothing new, seated activities, turning the view and IDLE#2 passed")
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


# sub_4161E0 and sub_416090 leave an agent on the exact interaction point, which can be flush
# against a wall or inside a blocked cell. sub_416D50 plans from the rounded cell and
# sub_41EE70 never tests it, so the agent steps back onto that cell's centre and walks on.
func _check_step_back_from_a_return_point() -> void:
	for start_tile in [Vector2(1.0, -0.2), Vector2(3.2, 1.0)]:
		var world := _make_world()
		var layer := _make_corridor(world, true)
		var npc := _make_npc(_world_position(layer, start_tile), 8.0)
		world.add_child(npc)
		var events := _navigation_events(npc)
		var target := _world_position(layer, Vector2(5, 1))
		_expect(npc.navigate_to(target), "a route from %s plans from its rounded cell" % start_tile)
		var cell := Vector2(floorf(start_tile.x + 0.5), floorf(start_tile.y + 0.5))
		var stepped_back := false
		for frame in range(300):
			await physics_frame
			if _tile_position(layer, npc.global_position).distance_to(cell) < 0.05:
				stepped_back = true
			if events.reached > 0 or events.failed > 0:
				break
		_expect(stepped_back, "the agent at %s steps back onto the centre of cell %s" % [start_tile, cell])
		_expect(events.reached == 1 and events.failed == 0, "the agent at %s walks on to its destination" % start_tile)
		_expect_vector(npc.global_position, target, "the agent at %s arrives" % start_tile)
		world.free()


# sub_418D20 marks the rounded cell of every other entity -- agents and the player -- as
# blocked before each search and restores it after. sub_41EE70 never tests the start, and the
# goal is reached by popping it, so an occupied goal or passage fails the route while an
# occupied start cell does not.
func _check_other_entities_block_routes() -> void:
	var world := _make_world()
	var layer := _make_corridor(world, true)
	var npc := _make_npc(_world_position(layer, Vector2(1, 1)), 8.0)
	world.add_child(npc)
	var goal := _world_position(layer, Vector2(5, 1))
	var agent := _entity(world, layer, Vector2(3, 4), false)
	_expect(not npc.navigate_to(goal), "an agent standing in the only gap closes it")
	agent.position = _world_position(layer, Vector2(5, 1))
	_expect(not npc.navigate_to(goal), "an agent standing on the goal cell refuses the route")
	agent.position = _world_position(layer, Vector2(5.3, 1.4))
	_expect(not npc.navigate_to(goal), "an agent anywhere inside the goal cell refuses it")
	agent.position = _world_position(layer, Vector2(1, 1))
	_expect(npc.navigate_to(goal), "an agent sharing the start cell does not")
	agent.position = _world_position(layer, Vector2(5, 2))
	_expect(npc.navigate_to(goal), "an agent beside the goal does not")
	agent.free()
	var player := _entity(world, layer, Vector2(3, 4), true)
	_expect(not npc.navigate_to(goal), "the player standing in the gap closes it too")
	var elsewhere := _make_world()
	player.reparent(elsewhere, false)
	_expect(npc.navigate_to(goal), "an entity in another world is ignored, and the cells come back after the search")
	npc.cancel_commands()
	elsewhere.free()

	# Off the centre of its cell, the start's footprint reaches into a neighbour someone
	# stands in; the search itself never looks at the start, so the route still goes.
	npc.global_position = _world_position(layer, Vector2(1.3, 1))
	var neighbour := _entity(world, layer, Vector2(2, 1), false)
	_expect(npc.navigate_to(goal), "a start whose footprint touches an occupied neighbour still routes")
	npc.cancel_commands()
	neighbour.free()

	# Walked for real: the route goes round a cell somebody stands in. The refusals above
	# report their failures deferred, so let them land first.
	await process_frame
	npc.global_position = _world_position(layer, Vector2(4, 1))
	var target := _world_position(layer, Vector2(6, 1))
	_entity(world, layer, Vector2(5, 1), false)
	var events := _navigation_events(npc)
	var entered := false
	_expect(npc.navigate_to(target), "a target past the occupied cell routes round it")
	for frame in range(240):
		await physics_frame
		var tile := _tile_position(layer, npc.global_position)
		if Vector2i(floori(tile.x + 0.5), floori(tile.y + 0.5)) == Vector2i(5, 1):
			entered = true
		if events.reached > 0 or events.failed > 0:
			break
	_expect(events.reached == 1, "the agent arrives past the occupied cell")
	_expect(not entered, "the agent never walks through the occupied cell")
	world.free()


# sub_4165D0 queues a failed goal again on the very next tick (0x416644), so an agent whose way
# is shut retries its search every tick. Until somebody whose cell refused the search moves,
# frees it or leaves, a retry searches nothing; somebody moving about out of its way changes
# nothing. And a start the search accepts is not searched a second time from its cell's centre.
func _check_retries_do_not_search_again() -> void:
	var world := _make_world()
	var layer := _make_corridor(world, true, CountingLayer.new()) as CountingLayer
	var npc := _make_npc(_world_position(layer, Vector2(1, 1)), 8.0)
	world.add_child(npc)
	var goal := _world_position(layer, Vector2(5, 1))
	var gap := _entity(world, layer, Vector2(3, 4), false)
	var passer_by := _entity(world, layer, Vector2(5, 5), false)
	layer.lookups = 0
	_expect(not npc.navigate_to(goal), "an agent in the only gap shuts the way")
	var searched := layer.lookups
	_expect(searched > 100, "the first attempt searches the whole near side, %d lookups" % searched)
	for tick in range(30):
		await physics_frame
		if tick == 10:
			passer_by.position = _world_position(layer, Vector2(6, 5))
		if tick == 20:
			_entity(world, layer, Vector2(6, 2), false)
		_expect(not npc.navigate_to(goal), "retry %d still finds the way shut" % tick)
	_expect(layer.lookups == searched, "thirty retries, one a tick, search nothing again, %d more lookups" % (layer.lookups - searched))
	gap.position = _world_position(layer, Vector2(4, 6))
	_expect(npc.navigate_to(goal), "the way opens the moment the agent in the gap steps out")
	_expect(layer.lookups > searched, "and that attempt searches again")
	npc.cancel_commands()
	gap.position = _world_position(layer, Vector2(3, 4))
	_expect(not npc.navigate_to(goal), "an agent back in the gap shuts it again")
	gap.free()
	_expect(npc.navigate_to(goal), "and it opens again when that agent is gone")
	npc.cancel_commands()

	var stranger := _entity(world, layer, Vector2(3, 4), false)
	layer.lookups = 0
	_expect(not npc.navigate_to(_world_position(layer, Vector2(5, 2))), "a start on its cell's centre floods once")
	var centred := layer.lookups
	npc.global_position = _world_position(layer, Vector2(1.3, 1))
	layer.lookups = 0
	_expect(not npc.navigate_to(_world_position(layer, Vector2(5, 3))), "so does a start off it")
	_expect(layer.lookups < centred * 3 / 2, "without a second flood from the cell's centre: %d lookups against %d" % [layer.lookups, centred])
	stranger.free()
	await process_frame
	world.free()


func _entity(world: Node2D, layer: TileMapLayer, tile: Vector2, player: bool) -> Node2D:
	var entity := Node2D.new()
	entity.position = _world_position(layer, tile)
	if player:
		var actions := Node.new()
		actions.add_to_group("player_actions")
		entity.add_child(actions)
	else:
		entity.add_to_group("npc_agents")
	world.add_child(entity)
	return entity


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


# sub_4187A0 moves agent+124 one step round the eight views (sub_41A3F0 masks it with 7), and
# sub_41A510 then shows the slot the agent was in, in the new view.
func _check_turning_the_view() -> void:
	var world := _make_world()
	var npc := _make_npc(Vector2(80, 80), 1.5)
	npc.profile = EMPLOYEE_PROFILE
	world.add_child(npc)
	await physics_frame
	var directions := IsoDirection.get_screen_directions()
	npc.last_direction = directions[0]
	npc.turn_view(-1)
	_expect(npc.view_index() == 7 and npc.last_direction == directions[7], "a step back from _000 wraps round to _315")
	_expect(String(npc.animation_controller.current_animation) == "male-employee-1/male-employee-1-idle1-atmen-up", "the idle slot is shown in the new view, got %s" % npc.animation_controller.current_animation)
	npc.turn_view(1)
	npc.turn_view(1)
	_expect(npc.view_index() == 1 and npc.last_direction == directions[1], "two steps on reach _045")
	_expect(npc.start_activity(&"pissed", 5.0, directions[1]), "an activity with a clip of its own starts")
	npc.turn_view(1)
	_expect(String(npc.animation_player.current_animation) == "male-employee-1-actions/male-employee-1-pissed-down-right", "a turn mid-activity keeps its slot in the new view, got %s" % npc.animation_player.current_animation)
	_expect(npc.current_activity == &"pissed", "and keeps the activity itself")
	world.free()


# IDLE#2 plays once (sub_419CE0 clears its loop flag at 0x419EA8) and slot 0 comes back when it
# has finished. The busy timer running out does not cut it short; a new command does.
func _check_fidgeting() -> void:
	var world := _make_world()
	var npc := _make_npc(Vector2(80, 80), 1.5)
	npc.profile = EMPLOYEE_PROFILE
	world.add_child(npc)
	await physics_frame
	npc.last_direction = IsoDirection.get_screen_directions()[1]
	var clip := "male-employee-1-actions/male-employee-1-idle-2-right"
	var start := Engine.get_physics_frames()
	_expect(npc.fidget() and npc.is_fidgeting(), "a coworker starts IDLE#2")
	_expect(String(npc.animation_player.current_animation) == clip, "in its current view, got %s" % npc.animation_player.current_animation)
	_expect(npc.animation_player.get_animation(clip).loop_mode == Animation.LOOP_NONE, "IDLE#2 is imported to play once")
	for frame in range(10):
		await physics_frame
	_expect(String(npc.animation_player.current_animation) == clip, "standing about does not replace IDLE#2 with the idle loop")
	await _wait_until(func(): return not npc.is_fidgeting(), 240, "IDLE#2 finishes")
	var elapsed := float(Engine.get_physics_frames() - start) / Engine.physics_ticks_per_second
	_expect(absf(elapsed - 1.3125) < 0.15, "IDLE#2 plays its 21 frames at 16 fps once, took %.2f s" % elapsed)
	_expect(String(npc.animation_controller.current_animation) == "male-employee-1/male-employee-1-idle1-atmen-right", "slot 0 comes back when it ends, got %s" % npc.animation_controller.current_animation)

	_expect(npc.start_activity(&"idle", 0.1, Vector2.ZERO) and npc.fidget(), "IDLE#2 can start during an idle activity")
	await _wait_until(func(): return npc.current_activity != &"idle" or npc._command == npc.Command.NONE, 30, "the idle activity's timer runs out")
	_expect(npc.is_fidgeting() and String(npc.animation_player.current_animation).ends_with("idle-2-right"), "the activity's end leaves IDLE#2 playing")
	npc.turn_view(1)
	_expect(String(npc.animation_player.current_animation) == "male-employee-1-actions/male-employee-1-idle-2-down-right", "a turn shows IDLE#2 in the new view")
	npc.cancel_commands()
	_expect(not npc.is_fidgeting() and String(npc.animation_controller.current_animation).ends_with("idle1-atmen-down-right"), "a new command ends IDLE#2")

	var boss := _make_npc(Vector2(200, 80), 1.5)
	world.add_child(boss)
	await physics_frame
	_expect(not boss.fidget() and not boss.is_fidgeting(), "the boss has no IDLE#2 to play")
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


func _make_corridor(world: Node2D, open_gap: bool, layer: TileMapLayer = null) -> TileMapLayer:
	if layer == null:
		layer = COLLISION_SCRIPT.new() as TileMapLayer
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
