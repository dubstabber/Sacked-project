extends SceneTree

# sub_418310 and sub_402470, on the real level-2 map: an agent notices the player only
# mid-prank, inside its own radius, inside its cone unless the player is within two tiles,
# and only with a clear sight ray. See docs/catch-reference.md.

const LEVEL_SCENE := preload("res://scenes/level_2.tscn")
const PrankController := preload("res://scenes/player/prank_controller.gd")
const LevelAudioScript := preload("res://scenes/level/level_audio.gd")

var _failures := 0
var _level: Node


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_level = LEVEL_SCENE.instantiate()
	var world := _level.get_node("World")
	for child in world.get_children():
		if child is CharacterBody2D and child.has_node("Brain"):
			child.get_node("Brain").enabled = false
	root.add_child(_level)
	await process_frame
	world.get_node("WorldDepthCompositor").set_process(false)
	world.get_node("CharacterDepthCompositor").set_process(false)

	var player := world.get_node("Player") as Node2D
	player.set_physics_process(false)
	player.get_node("FootstepPlayer").stop_footsteps()
	player.get_node("FootstepPlayer").stream = null

	var agent := _first_agent(world)
	var brain = agent.get_node("Brain")
	var layer := _collision_layer(player)
	if agent == null or layer == null:
		_expect(false, "level 2 carries an agent and a collision layer")
		_finish()
		return

	_check_constants(brain)
	await _check_notice_geometry(agent, brain, player, layer)
	await _check_only_mid_prank(world, player)
	_check_a_catch_cuts_the_start_sound(world, player)
	_check_the_duel_gets_the_pointer(world, player)
	_check_the_duel_holds_only_the_theme()
	_check_a_won_duel_keeps_the_count()
	_finish()


func _finish() -> void:
	if is_instance_valid(_level):
		_level.free()
	if _failures == 0:
		print("Catch trigger: notice radius, cone, the two-tile bypass, sight, the mid-prank gate, the duel's pointer, its sound and its length passed")
	quit(1 if _failures else 0)


func _first_agent(world: Node) -> CharacterBody2D:
	for child in world.get_children():
		if child is CharacterBody2D and child.has_node("Brain") and String(child.profile.id) == "male-employee-1":
			return child
	return null


func _collision_layer(player: Node2D) -> Node:
	for layer in get_nodes_in_group("collision_maps"):
		if layer.has_method("has_line_of_sight") and layer.get_parent().is_ancestor_of(player):
			return layer
	return null


func _check_constants(brain) -> void:
	# The exported table, not a transcription: male employee 1 is 5.2 tiles and 60 degrees.
	_expect(is_equal_approx(brain.notice_radius_tiles(), 5.2), "the notice radius comes from the profile table, got %f" % brain.notice_radius_tiles())
	_expect(is_equal_approx(brain.notice_cone_degrees(), 60.0), "the notice cone comes from the profile table, got %f" % brain.notice_cone_degrees())

	# Three of the four ticks widen both with the aggression band; the boss applies neither.
	brain._actor.aggression_band = 3
	_expect(is_equal_approx(brain.notice_radius_tiles(), 5.2 + 0.6), "band 3 adds 0.6 tiles of reach, got %f" % brain.notice_radius_tiles())
	_expect(is_equal_approx(brain.notice_cone_degrees(), 75.0), "band 3 adds 15 degrees of cone, got %f" % brain.notice_cone_degrees())
	brain._actor.aggression_band = 0


# Place the player at a known offset in logical tiles and ask whether the agent sees them.
func _place(player: Node2D, agent: Node2D, layer: Node, offset: Vector2) -> void:
	var origin: Vector2 = layer.to_grid_position(agent.global_position)
	player.global_position = layer.from_grid_position(origin + offset) \
		if layer.has_method("from_grid_position") else agent.global_position + _to_screen(offset)


func _to_screen(tiles: Vector2) -> Vector2:
	return Vector2(48.0 * (tiles.x - tiles.y), 24.0 * (tiles.x + tiles.y))


func _check_notice_geometry(agent: CharacterBody2D, brain, player: Node2D, layer: Node) -> void:
	# An open stretch of floor, so the sight ray never decides these cases for us.
	var spot := _open_ground(agent, layer)
	if spot == Vector2.INF:
		_expect(false, "level 2 has an agent with open ground around it")
		return
	agent.global_position = spot
	await process_frame

	agent.facing_screen = _to_screen(Vector2(1, 0)).normalized()
	_place(player, agent, layer, Vector2(1.0, 0.0))
	_expect(brain.notices(player, layer), "an agent sees the player straight ahead")

	_place(player, agent, layer, Vector2(7.0, 0.0))
	_expect(not brain.notices(player, layer), "the player beyond the notice radius is not seen")

	# Facing away: outside the cone, but inside the two-tile bypass the level hint promises.
	agent.facing_screen = _to_screen(Vector2(-1, 0)).normalized()
	_place(player, agent, layer, Vector2(1.5, 0.0))
	_expect(brain.notices(player, layer), "a prank within two tiles is noticed with the agent's back turned")

	_place(player, agent, layer, Vector2(3.0, 0.0))
	_expect(not brain.notices(player, layer), "past two tiles an agent facing away notices nothing")

	agent.facing_screen = _to_screen(Vector2(1, 0)).normalized()
	_expect(brain.notices(player, layer), "turning back around brings the same spot into the cone")

	# A cubicle blinds its occupant for as long as it holds them.
	brain._inside_cubicle = true
	_expect(brain.is_blind(), "an agent inside a cubicle reports itself blind")
	brain._inside_cubicle = false
	_expect(not brain.is_blind(), "stepping back out restores it")


# Somewhere the agent can stand with eight tiles of clear sight in the test directions.
func _open_ground(agent: CharacterBody2D, layer: Node) -> Vector2:
	var start: Vector2 = layer.to_grid_position(agent.global_position)
	for radius in range(0, 12):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				var tile := start + Vector2(dx, dy)
				var here := _from_tiles(agent, layer, tile)
				var clear := true
				for step in [Vector2(7.5, 0.0), Vector2(-7.5, 0.0), Vector2(3.0, 0.0), Vector2(1.5, 0.0)]:
					if not layer.has_line_of_sight(here, _from_tiles(agent, layer, tile + step)):
						clear = false
						break
				if clear:
					return here
	return Vector2.INF


func _from_tiles(agent: Node2D, layer: Node, tile: Vector2) -> Vector2:
	var origin: Vector2 = layer.to_grid_position(agent.global_position)
	return agent.global_position + _to_screen(tile - origin)


func _check_only_mid_prank(world: Node, player: Node2D) -> void:
	var watch := _level.get_node_or_null("LevelRuntime/CatchWatch")
	var prank = get_first_node_in_group("player_actions")
	if watch == null or prank == null:
		_expect(false, "the level runtime carries the catch watch and the player's actions")
		return
	# The duel exists now, so a catch leads somewhere. The flag survives only so a check can
	# drive the trigger without the screen opening over it.
	_expect(watch.hands_off_to_minigame, "a catch hands off to the duel")
	_expect(is_equal_approx(watch.BANNER_SECONDS, 2.0), "the banner gets its two seconds first")
	_expect(watch.caught_by == null, "nothing is caught before a prank starts")

	# Standing next to a colleague is safe; only performing an action is not.
	prank.state = PrankController.State.FREE
	_expect(not watch._is_mid_prank(), "walking about is not a prank")
	prank.state = PrankController.State.MENU
	_expect(not watch._is_mid_prank(), "an open ring menu is not a prank either")
	prank.state = PrankController.State.ACTING
	_expect(watch._is_mid_prank(), "performing an action is what can be caught")
	prank.state = PrankController.State.FREE

	_expect(watch.EXCLAMATIONS.size() == 4, "sub_407990 picks one of four exclamations")


# sub_402470 only catches in the acting states (2-3, 11-12, 21-22), so the ring is never open
# at the catch itself,
# but the caught pause still reads input and the ring can be opened under the banner.
# sub_407370 case 5 then shows and re-centres the cursor (0x40757C, 0x407582) whatever the
# ring is doing, and a duel played with the mouse must not inherit the ring's capture.
func _check_the_duel_gets_the_pointer(world: Node, player: Node2D) -> void:
	var watch := _level.get_node_or_null("LevelRuntime/CatchWatch")
	var minigame := _level.get_node_or_null("LevelRuntime/CatchMinigame")
	var prank = get_first_node_in_group("player_actions")
	var cursor := player.get_node_or_null("MovementArrow")
	var point := _prankable_point(world, prank, player)
	if watch == null or minigame == null or cursor == null or point == null:
		_expect(false, "level 2 carries the duel, the cursor and something to prank")
		return

	prank.focus_point = point
	prank.entries = prank.build_entries(point)
	prank.open_menu()
	_expect(prank.menu_open and cursor.is_menu_captured(), "the ring holds the pointer before the duel")

	watch._open_duel()
	_expect(paused, "the duel pauses the level")
	_expect(not cursor.is_menu_captured(), "the duel opens with the pointer handed back")
	_expect(prank.menu_open, "and leaves the ring itself alone, as screen 5 does")

	minigame.set_process(false)
	minigame.visible = false
	watch._on_duel_finished(true)
	_expect(not paused, "a won duel resumes the level")
	_expect(not cursor.is_menu_captured(), "nothing takes the pointer back after the duel")
	prank.close_menu()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


# The duel finds the level's audio by group. sub_407370 case 5 pauses the music stream and
# nothing else (0x407571), so a warning that has started loops on through the duel.
func _check_the_duel_holds_only_the_theme() -> void:
	var watch := _level.get_node_or_null("LevelRuntime/CatchWatch")
	var minigame := _level.get_node_or_null("LevelRuntime/CatchMinigame")
	var audio := _level.get_node_or_null("LevelRuntime/LevelAudio")
	if watch == null or minigame == null or audio == null:
		_expect(false, "level 2 carries the duel and the level's audio")
		return
	_expect(audio.is_in_group("level_audio"), "the level's audio is in the group the duel looks in")
	audio.play_effect("S1012", true)
	var screens := root.get_node("ScreenManager")
	var restore: int = screens.duels_fought

	watch._open_duel()
	minigame.set_process(false)
	_expect(minigame._audio == audio, "the duel plays through the level's audio")
	_expect(audio._theme.stream_paused, "the duel holds the theme")
	_expect(not audio._warning.stream_paused, "and leaves the warning looping")
	var cast: AudioStreamPlayer = audio.play_effect("S1004")
	_expect(audio._theme.stream_paused, "a sound played in the duel leaves the theme held")
	if cast != null:
		cast.free()

	minigame.visible = false
	watch._on_duel_finished(true)
	_expect(not audio._theme.stream_paused, "a won duel lets the theme go")
	audio._warning.stop()
	screens.duels_fought = restore


# A won duel goes back into the level still in memory (sub_4027B0, 0x402832), with no reload and
# no teardown to zero game+19052. So the count survives it, and the next catch in the same
# attempt is a cast longer. check_screen_flow.gd covers the resets.
func _check_a_won_duel_keeps_the_count() -> void:
	var watch := _level.get_node_or_null("LevelRuntime/CatchWatch")
	var minigame := _level.get_node_or_null("LevelRuntime/CatchMinigame")
	if watch == null or minigame == null:
		_expect(false, "level 2 carries the duel")
		return
	var screens := root.get_node("ScreenManager")
	var restore: int = screens.duels_fought
	screens.duels_fought = 0
	watch._open_duel()
	minigame.set_process(false)
	_expect(minigame.cast_count == 2 and screens.duels_fought == 1, "the first catch of an attempt is a two-cast duel")
	minigame.visible = false
	watch._on_duel_finished(true)
	_expect(screens.duels_fought == 1, "winning it keeps the count")
	watch._open_duel()
	minigame.set_process(false)
	_expect(minigame.cast_count == 3, "so the next catch in the same attempt is three casts")
	minigame.visible = false
	watch._on_duel_finished(true)
	screens.duels_fought = restore


# A catch pushes the prank to its abort state (sub_402470, 0x402534), and the abort stops the
# prank's own start sound in player+1112 (0x41BB61): the whole chain, not just abort_action.
func _check_a_catch_cuts_the_start_sound(world: Node, player: Node2D) -> void:
	var watch := _level.get_node_or_null("LevelRuntime/CatchWatch")
	var audio := _level.get_node_or_null("LevelRuntime/LevelAudio")
	var prank = get_first_node_in_group("player_actions")
	var found := _start_sound_prank(world, prank, player)
	if watch == null or audio == null or found.is_empty() or not ("_action_sound" in audio):
		_expect(false, "level 2 carries the catch watch, the audio and a prank that sounds as it starts")
		return
	prank.focus_point = found["point"]
	prank.entries = [found["entry"]]
	prank.open_menu()
	prank.confirm()
	var held: AudioStreamPlayer = audio._action_sound
	_expect(held != null and held.playing, "the prank's start sound plays")
	var hands_off: bool = watch.hands_off_to_minigame
	watch.hands_off_to_minigame = false
	watch._catch(_first_agent(world))
	watch.hands_off_to_minigame = hands_off
	_expect(prank.state == PrankController.State.FREE, "the catch aborts the prank")
	_expect(audio._action_sound == null, "the catch lets go of the start sound")
	_expect(held == null or not is_instance_valid(held) or not held.playing, "and stops it")
	watch.reset()


func _start_sound_prank(world: Node, prank: Node, player: Node2D) -> Dictionary:
	for node in world.get_node("Objects").get_children():
		var point := node.get_node_or_null("InteractionPoint") as Node2D
		if point == null or (point.get("action_ids") as PackedInt32Array).is_empty():
			continue
		player.global_position = point.global_position
		for entry in prank.build_entries(point):
			var action := ActionTable.get_action(int(entry["action_id"]))
			if bool(action.get("sound_at_start", false)) and LevelAudioScript.effect_stream(String(action.get("sound", ""))) != null:
				return {"point": point, "entry": entry}
	return {}


func _prankable_point(world: Node, prank: Node, player: Node2D) -> Node2D:
	for node in world.get_node("Objects").get_children():
		var point := node.get_node_or_null("InteractionPoint") as Node2D
		if point == null or (point.get("action_ids") as PackedInt32Array).is_empty():
			continue
		player.global_position = point.global_position
		if not prank.build_entries(point).is_empty():
			return point
	return null


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
