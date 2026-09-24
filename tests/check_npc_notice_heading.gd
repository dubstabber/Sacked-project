extends SceneTree

# sub_4179B0, which sub_402260 runs for every agent each frame: agent+1848 moves 1/8 of the
# short way round (sub_45E270) toward the sprite's view, 45 * agent+124, plus a sway of
# 10 * sin(agent+1844 + agent+72), and sub_418310 tests the player against it. At the port's
# nominal 60 Hz. See docs/npc-reference.md and docs/catch-reference.md.

const NPC_SCENE := preload("res://scenes/npc/npc.tscn")
const NPC_SCRIPT := preload("res://scenes/npc/npc.gd")
const BRAIN := preload("res://scenes/npc/npc_brain.gd")
const EMPLOYEE_PROFILE := preload("res://scenes/npc/profiles/male-employee-1.tres")
const LEVEL_SCENE := preload("res://scenes/level_2.tscn")
const FRAME := 1.0 / 60.0

var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_check_the_short_way_round()
	_check_easing()
	_check_sway()
	_check_a_turn_lags_the_cone()
	_check_a_seeded_phase()
	await _check_the_notice_test_reads_it()
	if _failures == 0:
		print("NPC notice heading: the short way round, 1/8 a frame, the ten-degree sway, the lag behind a turn, the seeded phase and the notice test passed")
	quit(1 if _failures else 0)


func _check_the_short_way_round() -> void:
	var cases := [[10.0, 350.0, 20.0], [350.0, 10.0, -20.0], [90.0, 90.0, 0.0], [180.0, 0.0, 180.0], [0.0, 180.0, -180.0], [45.0, 90.0, -45.0]]
	for case in cases:
		var got := NPC_SCRIPT.heading_difference(case[0], case[1])
		_expect(is_equal_approx(got, case[2]), "sub_45E270(%s, %s) is %s, got %s" % [case[0], case[1], case[2], got])


# The heading starts at 0 and takes 1/8 of the way each frame.
func _check_easing() -> void:
	var npc := _agent(3, 0.5)
	_expect(npc.notice_heading == 0.0, "a new agent's heading starts at 0 (0x415EC4)")
	_expect(absf(NPC_SCRIPT.heading_difference(_heading_of(npc.facing_screen), 0.0)) < 0.001, "so its cone starts on view _000")
	npc._ease_notice_heading(FRAME)
	var target := 135.0 + 10.0 * sin(0.5 + FRAME)
	_expect(absf(npc.notice_heading - target / 8.0) < 0.0001, "one frame covers 1/8 of the way, got %f for %f" % [npc.notice_heading, target / 8.0])
	_frames(npc, 119)
	var left := absf(NPC_SCRIPT.heading_difference(npc.notice_heading, 135.0 + _sway(npc)))
	_expect(left < 2.0, "two seconds later the heading sits on its target, %.2f degrees off" % left)
	_expect(absf(NPC_SCRIPT.heading_difference(_heading_of(npc.facing_screen), npc.notice_heading)) < 0.001, "facing_screen is the heading's own direction")

	# The short way round, through 0.
	npc.notice_heading = 350.0
	npc.last_direction = IsoDirection.get_screen_directions()[1]
	npc._ease_notice_heading(FRAME)
	_expect(npc.notice_heading > 350.0 or npc.notice_heading < 45.0, "from 350 toward 45 the heading climbs through 0, got %f" % npc.notice_heading)
	npc.free()


# 10 * sin(phase + clock) about the view: a period of 2 pi seconds, barely softened by the
# easing at 60 Hz.
func _check_sway() -> void:
	var npc := _agent(1, 0.0)
	_frames(npc, 240)
	var low := INF
	var high := -INF
	for frame in range(1200):
		npc._ease_notice_heading(FRAME)
		var offset := -NPC_SCRIPT.heading_difference(npc.notice_heading, 45.0)
		low = minf(low, offset)
		high = maxf(high, offset)
	_expect(high > 9.5 and high <= 10.0 and low < -9.5 and low >= -10.0, "the cone sways ten degrees either side of its view, got %.2f to %.2f" % [low, high])
	npc.free()


# sub_4187A0 turns the view at once, but the cone only follows at 1/8 a frame.
func _check_a_turn_lags_the_cone() -> void:
	var npc := _agent(1, 0.25)
	_frames(npc, 240)
	var before: float = npc.notice_heading
	var facing: Vector2 = npc.facing_screen
	npc.turn_view(1)
	_expect(npc.view_index() == 2, "the view turns at once")
	_expect(npc.notice_heading == before and npc.facing_screen == facing, "the cone does not jump with it")
	npc._ease_notice_heading(FRAME)
	var target := 90.0 + _sway(npc)
	var expected := before - 0.125 * NPC_SCRIPT.heading_difference(before, target)
	_expect(absf(npc.notice_heading - expected) < 0.0001, "one frame later it has come 1/8 of the way, got %f for %f" % [npc.notice_heading, expected])
	_frames(npc, 5)
	_expect(absf(NPC_SCRIPT.heading_difference(npc.notice_heading, 90.0 + _sway(npc))) > 15.0, "a tenth of a second on it still lags by more than fifteen degrees")
	_frames(npc, 54)
	_expect(absf(NPC_SCRIPT.heading_difference(npc.notice_heading, 90.0 + _sway(npc))) < 2.5, "a second on it has caught up")
	npc.free()


# rand() / 32767 in sub_415D50: a seeded brain draws the phase from its own stream.
func _check_a_seeded_phase() -> void:
	var phases: Array[float] = []
	for value in [1037, 1037, 7]:
		var world := Node2D.new()
		root.add_child(world)
		var npc := NPC_SCENE.instantiate() as CharacterBody2D
		npc.profile = EMPLOYEE_PROFILE
		var brain := BRAIN.new()
		brain.name = "Brain"
		brain.random_seed = value
		npc.add_child(brain)
		world.add_child(npc)
		brain._initialize()
		phases.append(npc.sway_phase)
		world.free()
	_expect(phases[0] == phases[1] and phases[0] != phases[2], "the same seed gives the same sway, got %s" % [phases])
	for phase in phases:
		_expect(phase >= 0.0 and phase <= 1.0, "the phase is 0 to 1 radian, got %f" % phase)


# sub_418310 on the real level-2 map: a player three tiles off along view _090 is outside a
# cone that still points along _045, and comes into it only as the heading catches up.
func _check_the_notice_test_reads_it() -> void:
	var level := LEVEL_SCENE.instantiate()
	var world := level.get_node("World")
	for child in world.get_children():
		if child is CharacterBody2D and child.has_node("Brain"):
			child.get_node("Brain").enabled = false
	root.add_child(level)
	await process_frame
	world.get_node("WorldDepthCompositor").set_process(false)
	world.get_node("CharacterDepthCompositor").set_process(false)
	var player := world.get_node("Player") as Node2D
	player.set_physics_process(false)
	player.get_node("FootstepPlayer").stop_footsteps()
	player.get_node("FootstepPlayer").stream = null
	var agent: CharacterBody2D = null
	for child in world.get_children():
		if child is CharacterBody2D and child.has_node("Brain") and String(child.profile.id) == "male-employee-1":
			agent = child
	var layer: Node = null
	for candidate in get_nodes_in_group("collision_maps"):
		if candidate.has_method("has_line_of_sight") and candidate.get_parent().is_ancestor_of(agent):
			layer = candidate
	if agent == null or layer == null:
		_expect(false, "level 2 carries male employee 1 and a collision layer")
		level.free()
		return
	var offset := IsoDirection.ground_to_screen(Vector2(3.0, 0.0))
	var spot := _open_ground(agent, layer, offset)
	if spot == Vector2.INF:
		_expect(false, "level 2 has open ground around male employee 1")
		level.free()
		return
	agent.set_physics_process(false)
	agent.global_position = spot
	player.global_position = spot + offset
	var brain = agent.get_node("Brain")
	agent.last_direction = IsoDirection.get_screen_directions()[1]
	_frames(agent, 240)
	_expect(not brain.notices(player, layer), "a player 45 degrees off a 60-degree cone is not seen")
	agent.turn_view(1)
	_expect(not brain.notices(player, layer), "nor straight after the agent turns toward them")
	_frames(agent, 60)
	_expect(brain.notices(player, layer), "but once the heading has caught up, they are")
	level.free()


# Somewhere the agent can stand with a clear sight line along the test offset.
func _open_ground(agent: Node2D, layer: Node, offset: Vector2) -> Vector2:
	for radius in range(0, 12):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				var here := agent.global_position + IsoDirection.ground_to_screen(Vector2(dx, dy))
				if layer.has_line_of_sight(here, here + offset):
					return here
	return Vector2.INF


func _agent(view: int, phase: float) -> CharacterBody2D:
	var npc := NPC_SCENE.instantiate() as CharacterBody2D
	npc.profile = EMPLOYEE_PROFILE
	root.add_child(npc)
	npc.set_physics_process(false)
	npc.last_direction = IsoDirection.get_screen_directions()[view]
	npc.sway_phase = phase
	return npc


func _frames(npc: Node, count: int) -> void:
	for frame in range(count):
		npc._ease_notice_heading(FRAME)


func _sway(npc: Node) -> float:
	return 10.0 * sin(npc.sway_phase + npc._sway_clock)


# The original's heading convention, as the brain reads it back out of facing_screen.
func _heading_of(screen: Vector2) -> float:
	var tiles := IsoDirection.screen_to_ground(screen)
	return fposmod(180.0 - rad_to_deg(atan2(tiles.x, tiles.y)), 360.0)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
