extends SceneTree

# The Matrix pill's slowed office on level 2, which has the boss, the secretary, the janitor and
# three coworkers: the pill slowing every one of them and never the player; the walk step at a
# fifth of the current, banded speed and the boss's unbanded one; every clip at a fifth of its
# rate, the clock-driven walk and IDLE#2 included, jumping rather than easing when the speed
# changes; the three green copies, their jitter, their depth test and their place in the draw,
# alone and inside a character cluster; the release after forty seconds; and a new level
# starting clean. See docs/player-ability-reference.md, "Mode 5: the Matrix pill".

const LEVEL_SCENE := preload("res://scenes/level_2.tscn")
const AbilityController := preload("res://scenes/player/ability_controller.gd")
const SlowedCopies := preload("res://scenes/npc/slowed_copies.gd")
const Slowdown := preload("res://scenes/npc/slowdown.gd")
const PROGRESS_PATH := "user://check_slowed_agents_progress.cfg"
const SETTINGS_PATH := "user://check_slowed_agents_settings.cfg"
const STEP := 0.0625
const ITEM_PILL := 14
const BAND := 2

var _failures := 0
var _level: Node
var _world: Node
var _player: Node2D
var _prank: Node
var _abilities: Node
var _layer: Node
var _restore_progress := ""
var _restore_settings := ""


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_redirect_stores()
	await _load_level()
	var slowed := Slowdown.params()
	var factor := float(slowed["slowed_factor"])
	_expect(factor == PackedFloat32Array([0.2])[0], "the slowed factor is the float32 0.2 the four ticks load, got %.17f" % factor)

	_check_the_pill_slows_every_agent()
	await _check_the_walk_step(_agent("MaleEmployee1"), true)
	await _check_the_walk_step(_agent("Secretary"), true)
	await _check_the_walk_step(_agent("Janitor"), true)
	await _check_the_walk_step(_agent("Boss"), false)
	_check_the_clock_driven_walk(_agent("MaleEmployee2"))
	_check_idle_2_lasts_five_times_longer(_agent("FemaleEmployee1"))
	_check_a_looping_clip_jumps(_agent("MaleEmployee1"))
	_check_the_copies(_agent("Secretary"))
	await _check_the_copies_roll_on_while_paused(_agent("Secretary"))
	_check_the_copies_in_a_cluster(_agent("MaleEmployee1"), _agent("MaleEmployee2"))
	_check_the_release()

	_level.free()
	await _load_level()
	_check_a_new_level_starts_clean()
	_level.free()
	_restore_stores()
	if _failures == 0:
		print("Slowed agents: the pill slows all six and never the player; the walk step at a fifth of the banded speed and the boss's unbanded one; the walk, IDLE#2 and a looping clip at 0.2, jumping; the three copies, their jitter, depth and draw place, alone and clustered; the release; and a clean start passed")
	quit(1 if _failures else 0)


func _expect(condition: bool, label: String) -> void:
	if not condition:
		_failures += 1
		push_error(label)


func _redirect_stores() -> void:
	var progress := root.get_node("ProgressStore")
	_restore_progress = progress.path
	progress.path = PROGRESS_PATH
	DirAccess.remove_absolute(PROGRESS_PATH)
	progress.reload()
	var settings := root.get_node("SettingsStore")
	_restore_settings = settings.path
	settings.path = SETTINGS_PATH
	DirAccess.remove_absolute(SETTINGS_PATH)
	settings.reload()


func _restore_stores() -> void:
	var progress := root.get_node("ProgressStore")
	progress.path = _restore_progress
	progress.reload()
	DirAccess.remove_absolute(PROGRESS_PATH)
	var settings := root.get_node("SettingsStore")
	settings.path = _restore_settings
	settings.reload()
	DirAccess.remove_absolute(SETTINGS_PATH)


func _load_level() -> void:
	_level = LEVEL_SCENE.instantiate()
	_world = _level.get_node("World")
	for child in _world.get_children():
		if child is CharacterBody2D and child.has_node("Brain"):
			child.get_node("Brain").enabled = false
	root.add_child(_level)
	await process_frame
	await process_frame
	_player = _world.get_node("Player")
	_player.set_physics_process(false)
	_player.get_node("FootstepPlayer").stop_footsteps()
	_player.get_node("FootstepPlayer").stream = null
	_prank = _player.get_node("PrankController")
	_prank.set_process(false)
	_abilities = _player.get_node("AbilityController")
	_abilities.set_process(false)
	_abilities.now = 0.0
	_layer = _world.get_node("CollisionTileMapLayer")
	var session := _level.get_node("LevelRuntime")
	session.set_process(false)
	session.set_physics_process(false)
	_level.get_node("LevelRuntime/CatchWatch").set_process(false)


func _agent(role: String) -> Node2D:
	for node in get_nodes_in_group("npc_agents"):
		if _world.is_ancestor_of(node) and String(node.name).ends_with(role):
			return node
	_expect(false, "level 2 has a %s" % role)
	return null


func _level_agents() -> Array:
	var agents := []
	for node in get_nodes_in_group("npc_agents"):
		if _world.is_ancestor_of(node):
			agents.append(node)
	return agents


func _set_all(value: bool) -> void:
	for agent in _level_agents():
		agent.slowed = value


func _absolute_z(item: CanvasItem) -> int:
	var z := 0
	var node: Node = item
	while node is CanvasItem:
		z += (node as CanvasItem).z_index
		if not (node as CanvasItem).z_as_relative:
			break
		node = node.get_parent()
	return z


# Item 14, a press on the Matrix lamp and 2.0 s: state 43 slows every agent, the player never.
func _check_the_pill_slows_every_agent() -> void:
	_prank.grant_item(ITEM_PILL)
	_abilities.request(AbilityController.REQUEST_PILL)
	var ticks := 0
	while (ticks == 0 or _abilities.mode != AbilityController.Mode.FREE) and ticks < 100:
		for agent in _level_agents():
			_expect(not agent.slowed, "no agent is slowed before state 43")
		_abilities.advance(STEP)
		ticks += 1
	_expect(ticks == 35, "40, 41, 32 ticks of 42 and 43, got %d" % ticks)
	var agents := _level_agents()
	_expect(agents.size() == 6, "level 2 has six agents, got %d" % agents.size())
	var factor := float(Slowdown.params()["slowed_factor"])
	for agent in agents:
		_expect(agent.slowed, "%s is slowed" % agent.name)
		_expect(agent.animation_controller.speed_scale == factor, "%s's clips run at 0.2" % agent.name)
		_expect((agent.get_node("SlowedCopies") as CanvasItem).visible, "%s shows its copies" % agent.name)
	_expect(_player.get("slowed") == null and _player.animation_controller.speed_scale == 1.0, "the player is not slowed")
	_expect(not _player.is_in_group("npc_agents"), "and is not one of the agents")


# Three clear cells in a row on the map with a clear cell at either end and nobody within three
# tiles. The 0.35-tile footprint walking along the cell centres never reaches a wall beside them.
func _free_cell_line() -> Array:
	var used: Rect2i = _layer.get_used_rect()
	var others: Array[Vector2] = []
	for body in _level_agents() + [_player]:
		others.append(_layer.to_grid_position(body.global_position))
	for y in range(used.position.y + 1, used.end.y - 1):
		for x in range(used.position.x + 1, used.end.x - 1):
			var start := Vector2i(x, y)
			for step in [Vector2i(1, 0), Vector2i(0, 1)]:
				if _clear_line(start, step, used, others):
					return [start, start + step * 3]
	return []


func _clear_line(start: Vector2i, step: Vector2i, used: Rect2i, others: Array[Vector2]) -> bool:
	for distance in range(-1, 5):
		var cell: Vector2i = start + step * distance
		if not used.has_point(cell) or _layer.is_blocked(cell):
			return false
		for other in others:
			if other.distance_to(Vector2(cell)) < 3.0:
				return false
	return true


# sub_417730: step = speed * +76 * dt, the speed being the current one, with the band in it for
# every archetype but the boss. The same band, slowed and not, from the same spot.
func _check_the_walk_step(agent: Node2D, banded: bool) -> void:
	var line := _free_cell_line()
	_expect(not line.is_empty(), "level 2 has a clear line of cells")
	if line.is_empty() or agent == null:
		return
	agent.aggression_band = BAND
	var base: float = agent.profile.walk_speed_tiles
	var expected_speed := base + (0.15 * BAND if banded else 0.0)
	var speeds := {}
	for slowed in [false, true]:
		agent.slowed = slowed
		agent.cancel_commands()
		agent.global_position = _layer.from_grid_position(Vector2(line[0]))
		_expect(agent.navigate_to(_layer.from_grid_position(Vector2(line[1]))), "%s finds the way along the line" % agent.name)
		var step := 0.0
		for _frame in range(6):
			await physics_frame
			var before := _layer.to_grid_position(agent.global_position) as Vector2
			await physics_frame
			var moved: float = (_layer.to_grid_position(agent.global_position) - before).length()
			if moved > 0.0:
				step = moved
				break
		speeds[slowed] = step * Engine.physics_ticks_per_second
		_expect(is_equal_approx(agent.get_move_speed_tiles(), expected_speed), "%s's current speed is %.2f either way, got %f" % [agent.name, expected_speed, agent.get_move_speed_tiles()])
	agent.cancel_commands()
	var factor := float(Slowdown.params()["slowed_factor"])
	_expect(absf(float(speeds[false]) - expected_speed) < 0.001, "%s walks %.2f tiles a second unslowed, got %f" % [agent.name, expected_speed, speeds[false]])
	_expect(absf(float(speeds[true]) - expected_speed * factor) < 0.001, "and a fifth of it slowed, got %f" % speeds[true])
	_expect(absf(float(speeds[true]) / float(speeds[false]) - factor) < 0.0005, "%s's slowed step is 0.2 of the unslowed one at band %d, got %f" % [agent.name, BAND, float(speeds[true]) / float(speeds[false])])
	agent.slowed = true


# The walk is clock-driven: floor(((clock * speed) mod length) * fps), so at speed 0.2 every
# slowed walker shows the frame the clock times 0.2 picks, and the change of speed jumps it.
func _check_the_clock_driven_walk(agent: Node2D) -> void:
	var controller = agent.animation_controller
	agent.slowed = false
	controller.play_walk(IsoDirection.get_screen_directions()[3])
	var data: Dictionary = controller.clock_driven_animation_frames[controller.current_animation]
	var frames: Array = data["frames"]
	var length := float(data["length"])
	var clock := 1234.5678
	var index_at := func(time: float) -> int:
		var at := fposmod(time, length)
		var found := 0
		for index in range(frames.size()):
			if float(frames[index]["time"]) <= at:
				found = index
		return found
	_expect(controller.clock_driven_frame_index(clock) == index_at.call(clock), "unslowed, the walk shows the clock's frame")
	agent.slowed = true
	var factor := float(Slowdown.params()["slowed_factor"])
	var slowed_index: int = index_at.call(clock * factor)
	_expect(controller.clock_driven_frame_index(clock) == slowed_index, "slowed, the frame of clock * 0.2, %d" % slowed_index)
	controller.update_clock_driven_animation_frame(clock)
	_expect(agent.get_node("Sprite2D").texture == frames[slowed_index]["texture"], "and the sprite shows it")
	var jumped := false
	for probe in [clock, clock + 0.37, clock + 1.11, clock + 2.9]:
		if index_at.call(probe) != index_at.call(probe * factor):
			jumped = true
	_expect(jumped, "the speed change jumps the frame rather than easing it")
	_expect(frames.size() > 1 and length > 0.0, "the walk has frames to jump between")


# IDLE#2 plays once, so at 0.2 it lasts five times its length, and the coworker's tick waits.
func _check_idle_2_lasts_five_times_longer(agent: Node2D) -> void:
	agent.slowed = true
	agent.cancel_commands()
	_expect(agent.fidget(), "%s starts IDLE#2" % agent.name)
	var player: AnimationPlayer = agent.animation_player
	var length: float = player.get_animation(player.current_animation).length
	_expect(is_equal_approx(player.speed_scale, float(Slowdown.params()["slowed_factor"])), "IDLE#2 runs at 0.2")
	player.advance(length * 1.01)
	_expect(agent.is_fidgeting() and absf(player.current_animation_position - length * 1.01 * player.speed_scale) < 0.001, "past its own length it is a fifth of the way through, at %f" % player.current_animation_position)
	player.advance(length * 3.9)
	_expect(agent.is_fidgeting(), "still playing at 4.9 lengths")
	player.advance(length * 0.2)
	_expect(not agent.is_fidgeting(), "and done after 5.1")
	_expect(String(agent.animation_controller.current_animation).begins_with(agent.animation_controller.idle_animation_prefix), "back to the idle, got %s" % agent.animation_controller.current_animation)

	# Released 1.5 lengths in, it is a whole length past its end at once, and finishes.
	_expect(agent.fidget(), "%s starts IDLE#2 again" % agent.name)
	agent.animation_controller._process(length * 1.5)
	player.advance(length * 1.5)
	_expect(agent.is_fidgeting(), "slowed, 1.5 lengths in it still plays")
	agent.slowed = false
	_expect(not agent.is_fidgeting(), "the release puts it past its end, and it is done")
	_expect(String(agent.animation_controller.current_animation).begins_with(agent.animation_controller.idle_animation_prefix), "back to the idle")
	agent.slowed = true


# A looping clip the AnimationPlayer runs picks its frame from the time since it started, so a
# change of speed puts it at (elapsed * speed) mod length at once, down and back up.
func _check_a_looping_clip_jumps(agent: Node2D) -> void:
	agent.slowed = false
	agent.cancel_commands()
	var player: AnimationPlayer = agent.animation_player
	var clip := ""
	for name in player.get_animation_list():
		var animation := player.get_animation(name)
		if String(name).contains("-actions/") and animation.loop_mode != Animation.LOOP_NONE and animation.length > 1.0:
			clip = String(name)
			break
	_expect(clip != "", "%s has a looping action clip" % agent.name)
	if clip == "":
		return
	var controller = agent.animation_controller
	controller.play_animation(clip)
	var length: float = player.get_animation(clip).length
	var elapsed := length * 0.75
	controller._process(elapsed)
	player.advance(elapsed)
	_expect(absf(player.current_animation_position - elapsed) < 0.001, "the clip is %f s in" % elapsed)
	var factor := float(Slowdown.params()["slowed_factor"])
	agent.slowed = true
	_expect(absf(player.current_animation_position - fposmod(elapsed * factor, length)) < 0.001, "slowing puts it at elapsed * 0.2 at once, got %f" % player.current_animation_position)
	controller._process(STEP)
	player.advance(STEP)
	_expect(absf(player.current_animation_position - fposmod((elapsed + STEP) * factor, length)) < 0.001, "and it runs at 0.2 from there")
	agent.slowed = false
	_expect(absf(player.current_animation_position - fposmod(elapsed + STEP, length)) < 0.001, "the release jumps it back, got %f" % player.current_animation_position)
	agent.slowed = true
	agent.cancel_commands()


# sub_417460 0x41762D-0x41772F: three copies, y = rand() % 4 - 2 then x = rand() % 6 - 3 each,
# 2 depth units nearer than the agent, tested and never written, in mode 54 with tint
# (40, 255, 40), brightness 60 and weight 120; after the bubble and the name.
func _check_the_copies(agent: Node2D) -> void:
	agent.slowed = true
	var copies := agent.get_node("SlowedCopies") as Node2D
	var sprite := agent.get_node("Sprite2D") as Sprite2D
	var rolls := [7, 13, 2, 5, 32767, 0]
	var saved: Callable = SlowedCopies.random
	SlowedCopies.random = func() -> int: return rolls.pop_front()
	copies.refresh()
	SlowedCopies.random = saved
	_expect(copies.offsets == [Vector2i(-2, 1), Vector2i(2, 0), Vector2i(-3, 1)], "y from the first roll, x from the second, three times, got %s" % [copies.offsets])
	var anchor := (sprite.global_position + sprite.offset).round()
	_expect(copies.anchor == anchor and copies.frame == sprite.texture, "each copy is the agent's current frame at its drawn spot")
	var size := sprite.texture.get_size()
	var bounds := Rect2(anchor + Vector2(-3, 0), size + Vector2(5, 1))
	_expect(copies.drawn_bounds == bounds, "the copies cover %s, got %s" % [bounds, copies.drawn_bounds])
	var base := ceilf(float(int(sprite.global_position.y)) * 0.5)
	_expect(copies.depth_base == base + 2.0, "two units nearer than the agent's base %.0f, got %f" % [base, copies.depth_base])

	var jitter := {}
	for _i in range(400):
		copies.refresh()
		for offset: Vector2i in copies.offsets:
			jitter[offset] = true
	var xs := {}
	var ys := {}
	for offset: Vector2i in jitter:
		xs[offset.x] = true
		ys[offset.y] = true
	var sorted_x := xs.keys()
	sorted_x.sort()
	var sorted_y := ys.keys()
	sorted_y.sort()
	_expect(sorted_x == [-3, -2, -1, 0, 1, 2] and sorted_y == [-2, -1, 0, 1], "x runs -3..2 and y -2..1, got %s and %s" % [sorted_x, sorted_y])

	var material := copies.material as ShaderMaterial
	var params := Slowdown.params()
	_expect(material.get_shader_parameter("tint") == Vector3(40, 255, 40), "tinted (40, 255, 40)")
	_expect(material.get_shader_parameter("brightness") == 60.0 and material.get_shader_parameter("weight") == 120.0 and material.get_shader_parameter("full_weight") == 255.0, "brightened by 60 and blended at 120 over (255 - 120)")
	_expect(int(params["copy_blend_mode"]) == 54, "mode 54")
	var compositor := _world.get_node("CharacterDepthCompositor")
	var mask := _world.get_node("WorldDepthCompositor")
	_expect(material.get_shader_parameter("depth_plane") == compositor.depth_texture_for(sprite) and material.get_shader_parameter("depth_plane_enabled") == true, "tested through the frame's own Z plane")
	_expect(material.get_shader_parameter("depth_base") == copies.depth_base, "at the copies' base")
	_expect(material.get_shader_parameter("world_depth_enabled") == true and material.get_shader_parameter("world_depth") == mask.depth_texture, "against the world composite")
	var count := int(material.get_shader_parameter("actor_count"))
	var rects = material.get_shader_parameter("actor_rect")
	var own := Rect2(anchor, size)
	var found := false
	for index in range(count):
		var rect: Vector4 = rects[index]
		if Rect2(rect.x, rect.y, rect.z, rect.w) == own:
			found = material.get_shader_parameter("actor_depth_%d" % index) == compositor.depth_texture_for(sprite)
	_expect(found, "and against the characters, the agent's own frame among them")
	_expect(_absolute_z(copies) == 3, "drawn at z 3, got %d" % _absolute_z(copies))
	var bubble := agent.get_node_or_null("ThoughtBubble") as CanvasItem
	_expect(bubble == null or _absolute_z(bubble) < 3, "after the bubble")
	var name_label := agent.get_node("NameLabel") as CanvasItem
	_expect(_absolute_z(name_label) == 3 and name_label.get_index() < copies.get_index(), "and after the name")
	_expect(_absolute_z(sprite) < 3 and _absolute_z(agent.get_node("Shadow")) < 3, "and the sprite and the shadow")

	agent.slowed = false
	copies.refresh()
	_expect(not copies.visible and copies.offsets.is_empty(), "an unslowed agent draws none")
	agent.slowed = true


# Main_RenderUpdate draws on under the pause panel, the quit prompt and the caught banner, where
# only the world tick stops, and sub_417460 rolls rand() for every copy it draws: the copies go on
# jittering over the frozen office.
func _check_the_copies_roll_on_while_paused(agent: Node2D) -> void:
	agent.slowed = true
	var copies := agent.get_node("SlowedCopies") as Node2D
	var generator := RandomNumberGenerator.new()
	generator.seed = 1792
	var saved: Callable = SlowedCopies.random
	SlowedCopies.random = func() -> int: return generator.randi() & 0x7FFF
	paused = true
	var sets := {}
	var runs := true
	for _frame in range(4):
		await process_frame
		runs = runs and copies.can_process()
		sets[str(copies.offsets)] = true
	paused = false
	SlowedCopies.random = saved
	_expect(runs, "the copies run while the tree is paused")
	_expect(sets.size() == 4, "fresh offsets on each of four paused frames, got %d sets" % sets.size())


# CharacterDepthCompositor draws overlapping characters on a surface of their own and hides
# their sprites; the copies still come from each agent's frame and depth plane, and each other's
# frames stay in the test.
func _check_the_copies_in_a_cluster(agent: Node2D, other: Node2D) -> void:
	agent.slowed = true
	other.slowed = true
	other.global_position = agent.global_position + Vector2(12, 6)
	var compositor := _world.get_node("CharacterDepthCompositor")
	compositor.update_composition()
	var sprite := agent.get_node("Sprite2D") as Sprite2D
	_expect(not sprite.visible, "the two agents are drawn as a cluster, their sprites hidden")
	var copies := agent.get_node("SlowedCopies") as Node2D
	copies.refresh()
	_expect(copies.frame == sprite.texture and copies.offsets.size() == 3, "the copies still draw the agent's frame")
	var material := copies.material as ShaderMaterial
	_expect(material.get_shader_parameter("depth_plane") == compositor.depth_texture_for(sprite), "through its own Z plane")
	var other_sprite := other.get_node("Sprite2D") as Sprite2D
	var other_rect := Rect2((other_sprite.global_position + other_sprite.offset).round(), other_sprite.texture.get_size())
	var count := int(material.get_shader_parameter("actor_count"))
	var rects = material.get_shader_parameter("actor_rect")
	var found := false
	for index in range(count):
		var rect: Vector4 = rects[index]
		found = found or Rect2(rect.x, rect.y, rect.z, rect.w) == other_rect
	_expect(found, "and the other agent of the cluster is in its test")
	other.global_position += Vector2(600, 0)
	compositor.update_composition()


# The tick past 40.0 s clears every agent: the walk and the clips back to 1, the copies gone.
func _check_the_release() -> void:
	_set_all(true)
	_abilities.slow_total = 4000.0
	_abilities.slow_elapsed = 40.0 - STEP
	_abilities.advance(STEP)
	_expect(_level_agents().all(func(agent) -> bool: return agent.slowed), "at exactly 40.0 s everyone is still slowed")
	_abilities.advance(STEP)
	for agent in _level_agents():
		_expect(not agent.slowed and agent.animation_controller.speed_scale == 1.0 and agent.walk_multiplier() == 1.0, "%s is released" % agent.name)
		_expect(not (agent.get_node("SlowedCopies") as CanvasItem).visible, "%s's copies are gone" % agent.name)


# A level start builds new agents and a new player: nothing slowed, no slow-down, no overlay.
func _check_a_new_level_starts_clean() -> void:
	for agent in _level_agents():
		_expect(not agent.slowed and agent.animation_controller.speed_scale == 1.0, "%s starts unslowed" % agent.name)
		_expect(not (agent.get_node("SlowedCopies") as CanvasItem).visible, "with no copies")
	_expect(_abilities.slow_total == 0.0 and _abilities.slow_elapsed == 0.0 and not _abilities.slowdown_shown, "the slow-down starts at zero")
	_expect(_abilities.overlay == null and _player.get_node_or_null("SlowdownOverlay") == null, "and there is no overlay")
