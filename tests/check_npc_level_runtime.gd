extends SceneTree


const LEVEL_SCENE := preload("res://scenes/level_1.tscn")
const BRAIN_SCRIPT := preload("res://scenes/npc/npc_brain.gd")
const EXPECTED_PROFILES := ["boss", "male-employee-1", "female-employee-1"]
const SIMULATION_SECONDS := 120
const CUBICLE_TYPES := [173, 262]
# The long run checks what must hold whatever the agents choose; which goals come up in it
# depends on the seed, so the sofa and the toilet are driven directly instead.
const LONG_RUN_SEED := 1037
const SOFA := "Object060Sofa01"
const CUBICLE := "Object015Toikabine"
const COWORKER := "Npc079MaleEmployee1"
# sub_418D20 blocks the cell of every other entity before a route search, the player's
# included, and the player spawns on (12, 9): the interaction cell of the cardboard cutout,
# the only decoration any level-1 agent has. A player who never moved would pin every
# agent's goal 2 at 0 and starve every goal after it, the coworkers' work included, so the
# long runs park the frozen player off the map.
const CUTOUT := "Object031Pappaufsteller01"
const PARKED_PLAYER := Vector2(-100000, -100000)

var _failures := 0
var _stats: Dictionary = {}
# Put in front of every failure, so a failure in the long run names its seed.
var _context := ""


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var level := LEVEL_SCENE.instantiate()
	var world := level.get_node("World")
	var actors: Array[CharacterBody2D] = []
	for child in world.get_children():
		if not child is CharacterBody2D or not child.has_node("Brain"):
			continue
		var brain := child.get_node("Brain")
		brain.random_seed = LONG_RUN_SEED
		actors.append(child)
		var profile_id := String(child.profile.id)
		_stats[profile_id] = {
			"destinations": 0, "finished": 0, "navigation_failures": 0,
			"walk_frames": 0, "idle_activity_frames": 0, "seated_frames": 0,
			"claims": 0, "releases": 0, "seat": null, "return_cell": null,
			"walk_distance": 0.0, "last_position": child.position,
			"idle_frames": 0, "idle_turns": 0, "was_idle": false, "last_view": -1,
			"fidgets": 0, "was_fidgeting": false,
		}
		var stats: Dictionary = _stats[profile_id]
		child.destination_reached.connect(func(): stats.destinations += 1)
		child.activity_finished.connect(func(): stats.finished += 1)
		child.navigation_failed.connect(func(): stats.navigation_failures += 1)
		_expect(child.patrol_offsets.is_empty() and child.route_path.is_empty(), "%s uses its original brain rather than an authored substitute patrol" % profile_id)
		_expect(brain.enabled, "%s original brain is enabled" % profile_id)
	_expect(actors.size() == EXPECTED_PROFILES.size(), "reference map contains its three original NPCs")
	for profile_id in EXPECTED_PROFILES:
		_expect(_stats.has(profile_id), "reference map contains original profile %s" % profile_id)
	root.add_child(level)
	world.get_node("WorldDepthCompositor").set_process(false)
	world.get_node("CharacterDepthCompositor").set_process(false)
	var player := world.get_node("Player")
	player.set_physics_process(false)
	player.get_node("FootstepPlayer").stop_footsteps()
	player.get_node("FootstepPlayer").stream = null
	var collision_layer := world.get_node("CollisionTileMapLayer") as TileMapLayer
	_check_the_player_blocks_the_cutout(world, player, collision_layer)
	player.position = PARKED_PLAYER
	var activity_points := get_nodes_in_group("npc_activity_points")
	_context = "seed %d" % LONG_RUN_SEED
	for frame in range(SIMULATION_SECONDS * Engine.physics_ticks_per_second):
		await physics_frame
		for actor in actors:
			_check_actor_frame(actor, collision_layer, activity_points)
		if _failures > 0:
			break
	_check_the_office_looks_around()
	for actor in actors:
		_check_actor_result(actor)
		actor.get_node("Brain").enabled = false
		_expect(_find_claim(actor, activity_points) == null, "%s releases its seat when its brain is stopped" % actor.profile.id)
	_context = ""
	_check_a_tampered_workstation_is_reacted_to(level)
	level.free()
	await _check_driven_goals()
	if _failures == 0:
		print("Original level NPC runtime: %d simulated seconds, all three brains moved and completed activities, every agent stayed on free cells and released seat claims; driven directly, the boss sat on the sofa with SIT#IDLE and a coworker went into the toilet cubicle" % SIMULATION_SECONDS)
	quit(1 if _failures else 0)


# The sofa and the cubicle, each reached on the real map by driving the goal rather than
# waiting for a seed to choose it. The sofa's interaction point is 0.79 tiles from a blocked
# cell, so its footprint overlaps it, but the cell it rounds to is free: sub_416D50 walks there
# and the boss sits (goal 7, mask 72 covers its room), playing SIT#IDLE on any seat. The
# cubicle's point is flush against a wall; the original walks to its free cell, and before
# routes ended on cell centres the port refused it outright. See docs/npc-reference.md.
func _check_driven_goals() -> void:
	var level := LEVEL_SCENE.instantiate()
	var world := level.get_node("World")
	root.add_child(level)
	world.get_node("WorldDepthCompositor").set_process(false)
	world.get_node("CharacterDepthCompositor").set_process(false)
	var player := world.get_node("Player")
	player.set_physics_process(false)
	player.get_node("FootstepPlayer").stop_footsteps()
	player.get_node("FootstepPlayer").stream = null
	player.position = PARKED_PLAYER
	var layer := world.get_node("CollisionTileMapLayer") as TileMapLayer

	var boss := await _drive_goal(world, layer, "Npc080Boss", 7, SOFA)
	var sofa := world.get_node("Objects/%s/InteractionPoint" % SOFA)
	_expect(sofa.occupant == boss and boss.current_activity == &"sit-idle", "the boss sits on %s with SIT#IDLE, got %s" % [SOFA, boss.current_activity])

	var coworker := await _drive_goal(world, layer, COWORKER, 4, CUBICLE)
	var cubicle := world.get_node("Objects/%s/InteractionPoint" % CUBICLE)
	var anchor: Vector2 = (cubicle.get_parent() as Node2D).global_position
	_expect(cubicle.occupant == coworker and coworker.get_node("Brain")._inside_cubicle, "%s goes into %s" % [COWORKER, CUBICLE])
	_expect(coworker.global_position.is_equal_approx(anchor), "%s stands on the cubicle's anchor %s, got %s" % [COWORKER, anchor, coworker.global_position])
	level.free()


# Only the named agent's brain runs. Its goal's candidates must be the one object, and the
# agent must claim it within its route's walking time and a second.
func _drive_goal(world: Node, layer: TileMapLayer, agent_name: String, goal: int, object_name: String) -> CharacterBody2D:
	var point := world.get_node("Objects/%s/InteractionPoint" % object_name) as Node2D
	for child in world.get_children():
		if child is CharacterBody2D and child.has_node("Brain"):
			var agent_brain := child.get_node("Brain")
			agent_brain._initialize()
			agent_brain.enabled = child.name == agent_name
	var actor := world.get_node(agent_name) as CharacterBody2D
	var brain := actor.get_node("Brain")
	brain._stop()
	var names: Array[String] = []
	for candidate in brain._candidates(goal):
		names.append(String(candidate.get_parent().name))
	_expect(names == [object_name], "%s's only goal-%d candidate is %s, got %s" % [agent_name, goal, object_name, names])
	brain._attempt_goal(goal)
	_expect(brain._state == BRAIN_SCRIPT.State.NAVIGATING and brain._target == point, "%s sets off for %s" % [agent_name, object_name])
	var tiles := 0.0
	var from: Vector2 = layer.to_grid_position(actor.global_position)
	for step in actor._navigation_path:
		var to: Vector2 = layer.to_grid_position(step)
		tiles += from.distance_to(to)
		from = to
	var limit: float = tiles / actor.get_move_speed_tiles() + 1.0
	var frames := 0
	while point.occupant != actor and frames < ceili(limit * Engine.physics_ticks_per_second):
		await physics_frame
		frames += 1
	_expect(point.occupant == actor, "%s claims %s within %.1f s for a %.1f-tile route, got %s after %.1f s" % [agent_name, object_name, limit, tiles, point.occupant, float(frames) / Engine.physics_ticks_per_second])
	return actor


# The cutout's interaction point rounds to the player's spawn cell, so the boss cannot plan a
# route to it until the player steps off; an agent standing there would do the same.
func _check_the_player_blocks_the_cutout(world: Node, player: Node2D, layer: TileMapLayer) -> void:
	var boss := world.get_node("Npc080Boss") as CharacterBody2D
	var cutout := world.get_node("Objects/%s/InteractionPoint" % CUTOUT) as Node2D
	var cell := _rounded_cell(layer, cutout.global_position)
	var end := layer.to_global(layer.map_to_local(cell))
	_expect(cell == _rounded_cell(layer, player.global_position), "the player spawns on the cutout's interaction cell")
	_expect(not boss.navigate_to(end), "the boss cannot route to the cutout while the player stands on its cell")
	var spawn := player.position
	player.position = PARKED_PLAYER
	_expect(boss.navigate_to(end), "he can once the player has moved off it")
	boss.cancel_commands()
	player.position = spawn


# The same arrival the long run exercises, but against an object the player has finished an
# action on. Level 1's keyboard is an assigned workstation, so this is a goal the agent
# reaches in ordinary play rather than a contrived target. See docs/npc-reference.md.
func _check_a_tampered_workstation_is_reacted_to(level: Node) -> void:
	var actor := level.get_node_or_null("World/Npc079MaleEmployee1") as CharacterBody2D
	var session := level.get_node_or_null("LevelRuntime")
	if actor == null or session == null:
		_expect(false, "the reference map carries the male employee and its session")
		return
	var brain := actor.get_node("Brain")
	var workstation := brain.get_node_or_null(brain.assigned_workstation)
	if workstation == null:
		_expect(false, "the male employee has an assigned workstation to find tampered with")
		return

	brain.enabled = true
	workstation.tampered = true
	brain._target = workstation
	brain._active = workstation
	brain._passive = null
	brain._state = BRAIN_SCRIPT.State.NAVIGATING
	brain._goal = 3
	var score_before: int = session.score
	actor.destination_reached.emit()

	_expect(brain._goal == BRAIN_SCRIPT.REACTION_GOAL, "arriving at a tampered workstation raises the reaction goal")
	_expect(actor.current_activity == &"pissed", "the agent plays its reaction clip, got %s" % actor.current_activity)
	_expect(actor.animation_player.is_playing(), "the reaction clip is available on the real profile")
	_expect(session.score == score_before + BRAIN_SCRIPT.REACTION_SCORE, "the reaction pays the level session")
	_expect(workstation.occupant != actor, "reacting to a workstation does not claim it")
	brain.enabled = false


func _check_actor_frame(actor: CharacterBody2D, layer: TileMapLayer, activity_points: Array[Node]) -> void:
	var profile_id := String(actor.profile.id)
	var stats: Dictionary = _stats[profile_id]
	var brain := actor.get_node("Brain")
	_expect(actor.global_position.is_finite(), "%s position remains finite" % profile_id)
	var seated := String(actor.current_activity).begins_with("sit-")
	var seat := _find_claim(actor, activity_points)
	if seat != stats.seat:
		if stats.seat != null:
			stats.releases += 1
		if seat != null:
			stats.claims += 1
		stats.seat = seat
	if seat != null:
		stats.return_cell = _rounded_cell(layer, seat.global_position)
	if seated:
		stats.seated_frames += 1
		_expect(seat != null, "%s seated work holds an exclusive seat claim" % profile_id)
		_expect(actor.animation_player.is_playing(), "%s seated action plays an available animation" % profile_id)
		if profile_id == "boss":
			_expect(actor.current_activity == &"sit-idle", "the boss sits with SIT#IDLE on any seat, got %s" % actor.current_activity)
	else:
		# A claimed cubicle puts its occupant on the item's own anchor, inside the stall.
		if seat == null:
			_expect_rounded_cell_free(layer, actor.global_position, stats.return_cell, profile_id)
		if actor.current_activity == &"walking":
			stats.walk_frames += 1
			stats.walk_distance += actor.global_position.distance_to(stats.last_position)
		if brain._state == BRAIN_SCRIPT.State.ACTING and actor.current_activity == &"idle":
			stats.idle_activity_frames += 1
	_count_looking_around(actor, brain, stats)
	stats.last_position = actor.global_position


# Between two frames in the idle branch nothing but sub_4187A0 moves the view, and it moves it
# one step at a time. A cubicle's occupant and the copier's first user are in that branch too,
# but faced back every frame, and the port leaves their turn out.
func _count_looking_around(actor: CharacterBody2D, brain: Node, stats: Dictionary) -> void:
	var idle: bool = brain._in_idle_branch()
	var turning: bool = idle and not brain._copying and not brain._inside_cubicle
	var view: int = actor.view_index()
	if turning and stats.was_idle:
		stats.idle_frames += 1
		if view != stats.last_view:
			stats.idle_turns += 1
			_expect(posmod(view - int(stats.last_view), 8) in [1, 7], "%s turns one step at a time, from %d to %d" % [actor.profile.id, stats.last_view, view])
	stats.was_idle = turning
	stats.last_view = view
	var fidgeting: bool = actor.is_fidgeting()
	if fidgeting and not stats.was_fidgeting:
		stats.fidgets += 1
		_expect(idle, "%s starts IDLE#2 only while it stands about" % actor.profile.id)
		_expect(actor.profile.id != &"boss", "the boss has no IDLE#2")
	if fidgeting:
		_expect(String(actor.animation_player.current_animation).contains("-idle-2-"), "%s shows IDLE#2 while it plays, got %s" % [actor.profile.id, actor.animation_player.current_animation])
	stats.was_fidgeting = fidgeting


# sub_4187A0 at the port's nominal 60 Hz: 95/4096 of the frames an agent spends standing about.
func _check_the_office_looks_around() -> void:
	var frames := 0
	var turns := 0
	for profile_id in _stats:
		var stats: Dictionary = _stats[profile_id]
		# 300 idle frames without a turn is a 1-in-1000 chance.
		_expect(stats.idle_frames < 300 or stats.idle_turns > 0, "%s looks around while it stands about: %d frames, no turn" % [profile_id, stats.idle_frames])
		frames += int(stats.idle_frames)
		turns += int(stats.idle_turns)
	var rate := 95.0 / 4096.0
	var expected := frames * rate
	_expect(absf(turns - expected) < 5.0 * sqrt(expected), "idle agents turn on 95/4096 of their frames: %d turns in %d frames, expected %.0f" % [turns, frames, expected])
	print("Looking around: %d turns in %d idle frames (%.2f a second)" % [turns, frames, turns * Engine.physics_ticks_per_second / maxf(frames, 1.0)])
	var fidgets := 0
	var fidget_frames := 0
	for profile_id in _stats:
		if profile_id != "boss":
			fidgets += int(_stats[profile_id].fidgets)
			fidget_frames += int(_stats[profile_id].idle_frames)
	print("IDLE#2: %d in %d coworker idle frames" % [fidgets, fidget_frames])


func _check_actor_result(actor: CharacterBody2D) -> void:
	var profile_id := String(actor.profile.id)
	var stats: Dictionary = _stats[profile_id]
	_expect(stats.walk_frames > 0, "%s walks to a target of its own choosing" % profile_id)
	_expect(stats.destinations > 0 and stats.finished > 0, "%s reaches a destination and completes an activity" % profile_id)
	if profile_id == "boss":
		# Only an agent without an assigned workstation crosses the map often. A
		# coworker's work need decays several times faster than any other, so it can
		# spend the whole window at a desk one tile from its spawn.
		_expect(stats.walk_distance > 48.0, "boss roams the original map between goals")
		_expect(stats.idle_activity_frames > 0, "boss performs an ordinary idle activity")
	else:
		_expect(stats.seated_frames > 0 and stats.claims > 0, "%s eventually performs its seated work activity" % profile_id)
		_expect(stats.releases > 0, "%s releases a claimed seat after finishing work" % profile_id)
	print("%s: %d destinations, %d completed activities, %d seat claims, %d seat releases, %d navigation retries, %d idle frames, %d turns, %d IDLE#2" % [profile_id, stats.destinations, stats.finished, stats.claims, stats.releases, stats.navigation_failures, stats.idle_frames, stats.idle_turns, stats.fidgets])


func _find_claim(actor: Node, activity_points: Array[Node]) -> Node:
	for point in activity_points:
		if point.occupant == actor:
			return point
	return null


# The original's own invariant: sub_416D50 routes between cell centres and sub_41E910 never
# enters a blocked cell, so an agent stands on a free cell -- except on the exact
# interaction point sub_4161E0 or sub_416090 put it back on, and while it steps back off it.
# A footprint test cannot hold here, because that point can be flush against a wall.
func _expect_rounded_cell_free(layer: TileMapLayer, position: Vector2, return_cell: Variant, profile_id: String) -> void:
	var cell := _rounded_cell(layer, position)
	if cell != return_cell and layer.get_cell_source_id(cell) >= 0:
		_expect(false, "%s stands in blocked cell %s at %s" % [profile_id, cell, position])


func _rounded_cell(layer: TileMapLayer, position: Vector2) -> Vector2i:
	var relative := layer.to_local(position) - layer.map_to_local(Vector2i.ZERO)
	var tile_position := Vector2(relative.x / 96 + relative.y / 48, -relative.x / 96 + relative.y / 48)
	return Vector2i(floori(tile_position.x + 0.5), floori(tile_position.y + 0.5))


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message if _context.is_empty() else "%s: %s" % [_context, message])
