extends SceneTree


const ISO_DIRECTION := preload("res://scenes/shared/iso_direction.gd")
const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const NPC_SCENE := preload("res://scenes/npc/npc.tscn")
const PROFILE_SCRIPT := preload("res://scenes/player/character_profile.gd")
const PLAYER_PROFILE := preload("res://scenes/player/profiles/jobless.tres")
const NPC_SPECS := [
	[preload("res://scenes/npc/profiles/boss.tres"), 1.8],
	[preload("res://scenes/npc/profiles/secretary.tres"), 1.8],
	[preload("res://scenes/npc/profiles/janitor.tres"), 1.2],
	[preload("res://scenes/npc/profiles/male-employee-1.tres"), 1.5],
	[preload("res://scenes/npc/profiles/male-employee-2.tres"), 1.6],
	[preload("res://scenes/npc/profiles/female-employee-1.tres"), 1.7],
	[preload("res://scenes/npc/profiles/female-employee-2.tres"), 1.5],
]
const INPUT_CASES := [
	[["move_right"], Vector2(1, -1)],
	[["move_right", "move_down"], Vector2(1, 0)],
	[["move_down"], Vector2(1, 1)],
	[["move_down", "move_left"], Vector2(0, 1)],
	[["move_left"], Vector2(-1, 1)],
	[["move_left", "move_up"], Vector2(-1, 0)],
	[["move_up"], Vector2(-1, -1)],
	[["move_up", "move_right"], Vector2(0, -1)],
]
const EPSILON := 0.001
const SAMPLE_FRAMES := 12

var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_check_projection_and_velocities()
	_check_speed_defaults()
	await _check_player_runtime()
	await _check_npc_runtime()
	_release_movement_actions()
	if _failures == 0:
		print("Movement speeds: projection, eight directions, original defaults, overrides and player/NPC physics distances passed")
	quit(1 if _failures else 0)


func _check_projection_and_velocities() -> void:
	_expect_vector(ISO_DIRECTION.ground_to_screen(Vector2(3, -2)), Vector2(240, 24), "logical displacement projects onto the 96x48 grid")
	_expect_vector(ISO_DIRECTION.screen_to_ground(Vector2(192, -36)), Vector2(1.25, -2.75), "screen displacement converts back to logical coordinates")
	_expect_vector(ISO_DIRECTION.screen_velocity(Vector2.ZERO, 3.0), Vector2.ZERO, "zero input produces a finite zero velocity")
	_expect_vector(ISO_DIRECTION.screen_velocity(Vector2.RIGHT, 0.0), Vector2.ZERO, "zero speed keeps the character stationary")
	_expect_vector(ISO_DIRECTION.screen_velocity(Vector2.RIGHT, 3.0), Vector2(144 * sqrt(2.0), 0), "horizontal screen velocity uses normalized logical diagonals")
	_expect_vector(ISO_DIRECTION.screen_velocity(Vector2.DOWN, 3.0), Vector2(0, 72 * sqrt(2.0)), "vertical screen velocity accounts for the isometric projection")
	_expect_vector(ISO_DIRECTION.screen_velocity(Vector2(48, 24), 3.0), Vector2(144, 72), "logical axis velocity projects directly")
	for direction in ISO_DIRECTION.get_screen_directions():
		var velocity: Vector2 = ISO_DIRECTION.screen_velocity(direction, 3.0)
		_expect_float(_ground_displacement(velocity).length(), 3.0, "all eight projected directions cover three logical tiles per second")
		_expect_vector(velocity.normalized(), direction, "logical normalization preserves the requested screen direction")
	_expect_float(_ground_displacement(ISO_DIRECTION.screen_velocity(Vector2(5, 2), 1.8)).length(), 1.8, "continuous NPC directions preserve their logical speed")


func _check_speed_defaults() -> void:
	var profile := PROFILE_SCRIPT.new()
	_expect_float(profile.walk_speed_tiles, 3.0, "base character profile uses the original player walking speed")
	var player := PLAYER_SCENE.instantiate()
	_expect_float(player.move_speed_tiles, 3.0, "player defaults to three logical tiles per second")
	player.free()
	var npc := NPC_SCENE.instantiate()
	_expect_float(npc.move_speed_tiles, 0.0, "NPC inherits its profile speed unless explicitly overridden")
	npc.free()
	for spec in NPC_SPECS:
		var npc_profile: Resource = spec[0]
		_expect_float(npc_profile.walk_speed_tiles, spec[1], "%s profile preserves its original walking speed" % npc_profile.id)


func _check_player_runtime() -> void:
	var world := Node2D.new()
	root.add_child(world)
	var player := PLAYER_SCENE.instantiate() as CharacterBody2D
	player.profile = PLAYER_PROFILE
	player.position = Vector2(300, 300)
	world.add_child(player)
	player.get_node("FootstepPlayer").stop_footsteps()
	player.get_node("FootstepPlayer").stream = null
	for input_case in INPUT_CASES:
		await _measure_player_motion(player, input_case[0], input_case[1], 3.0)
	player.move_speed_tiles = 4.5
	await _measure_player_motion(player, ["move_right"], Vector2(1, -1), 4.5)
	player.set_physics_process(false)
	world.free()


func _measure_player_motion(player: CharacterBody2D, actions: Array, ground_direction: Vector2, speed: float) -> void:
	_release_movement_actions()
	await physics_frame
	var start := player.global_position
	var start_frame := Engine.get_physics_frames()
	for action in actions:
		Input.action_press(action)
	for frame in range(SAMPLE_FRAMES):
		await physics_frame
	_release_movement_actions()
	var elapsed := float(Engine.get_physics_frames() - start_frame) / Engine.physics_ticks_per_second
	var travelled := _ground_displacement(player.global_position - start)
	_expect_vector(travelled, ground_direction.normalized() * speed * elapsed, "actual player physics distance for %s at %.1f tiles/s" % [actions, speed])


func _check_npc_runtime() -> void:
	var world := Node2D.new()
	root.add_child(world)
	var actors: Array[CharacterBody2D] = []
	var expected_speeds: Array[float] = []
	var target_offset := Vector2(1000, 173)
	for index in range(NPC_SPECS.size() + 1):
		var npc := NPC_SCENE.instantiate() as CharacterBody2D
		npc.profile = NPC_SPECS[index % NPC_SPECS.size()][0]
		npc.position = Vector2(index * 150, 0)
		npc.patrol_offsets = [target_offset] as Array[Vector2]
		npc.pause_seconds = 0.0
		if index == NPC_SPECS.size():
			npc.move_speed_tiles = 2.75
			expected_speeds.append(2.75)
		else:
			expected_speeds.append(NPC_SPECS[index][1])
		world.add_child(npc)
		actors.append(npc)
	await physics_frame
	var starts: Array[Vector2] = []
	for npc in actors:
		starts.append(npc.global_position)
	var start_frame := Engine.get_physics_frames()
	for frame in range(SAMPLE_FRAMES):
		await physics_frame
	var elapsed := float(Engine.get_physics_frames() - start_frame) / Engine.physics_ticks_per_second
	var ground_direction := _ground_displacement(target_offset).normalized()
	for index in range(actors.size()):
		var npc := actors[index]
		npc.set_physics_process(false)
		var travelled := _ground_displacement(npc.global_position - starts[index])
		_expect_vector(travelled, ground_direction * expected_speeds[index] * elapsed, "NPC %d follows its continuous target at the profile or override speed" % index)
	world.free()


func _ground_displacement(screen_displacement: Vector2) -> Vector2:
	return Vector2(screen_displacement.x / 96 + screen_displacement.y / 48, -screen_displacement.x / 96 + screen_displacement.y / 48)


func _release_movement_actions() -> void:
	for action in ["move_up", "move_down", "move_left", "move_right"]:
		Input.action_release(action)


func _expect_vector(actual: Vector2, expected: Vector2, label: String) -> void:
	_expect(actual.distance_to(expected) <= EPSILON, "%s: expected %s, got %s" % [label, expected, actual])


func _expect_float(actual: float, expected: float, label: String) -> void:
	_expect(absf(actual - expected) <= EPSILON, "%s: expected %s, got %s" % [label, expected, actual])


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
