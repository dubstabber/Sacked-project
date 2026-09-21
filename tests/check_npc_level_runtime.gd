extends SceneTree


const LEVEL_SCENE := preload("res://scenes/level_1.tscn")
const BRAIN_SCRIPT := preload("res://scenes/npc/npc_brain.gd")
const EXPECTED_PROFILES := ["boss", "male-employee-1", "female-employee-1"]
const SIMULATION_SECONDS := 120

var _failures := 0
var _stats: Dictionary = {}


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
		brain.random_seed = 1037
		actors.append(child)
		var profile_id := String(child.profile.id)
		_stats[profile_id] = {
			"destinations": 0, "finished": 0, "navigation_failures": 0,
			"walk_frames": 0, "idle_activity_frames": 0, "seated_frames": 0,
			"claims": 0, "releases": 0, "seat": null,
			"walk_distance": 0.0, "last_position": child.position,
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
	var activity_points := get_nodes_in_group("npc_activity_points")
	for frame in range(SIMULATION_SECONDS * Engine.physics_ticks_per_second):
		await physics_frame
		for actor in actors:
			_check_actor_frame(actor, collision_layer, activity_points)
		if _failures > 0:
			break
	for actor in actors:
		_check_actor_result(actor)
		actor.get_node("Brain").enabled = false
		_expect(_find_claim(actor, activity_points) == null, "%s releases its seat when its brain is stopped" % actor.profile.id)
	_check_a_tampered_workstation_is_reacted_to(level)
	level.free()
	if _failures == 0:
		print("Original level NPC runtime: %d simulated seconds, all three brains moved and completed activities with safe walking footprints and released seat claims" % SIMULATION_SECONDS)
	quit(1 if _failures else 0)


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
	if seated:
		stats.seated_frames += 1
		_expect(seat != null, "%s seated work holds an exclusive seat claim" % profile_id)
		_expect(actor.animation_player.is_playing(), "%s seated action plays an available animation" % profile_id)
	else:
		_expect_footprint_clear(layer, actor.global_position, profile_id)
		if actor.current_activity == &"walking":
			stats.walk_frames += 1
			stats.walk_distance += actor.global_position.distance_to(stats.last_position)
		if brain._state == BRAIN_SCRIPT.State.ACTING and actor.current_activity == &"idle":
			stats.idle_activity_frames += 1
	stats.last_position = actor.global_position


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
	print("%s: %d destinations, %d completed activities, %d seat claims, %d seat releases, %d navigation retries" % [profile_id, stats.destinations, stats.finished, stats.claims, stats.releases, stats.navigation_failures])


func _find_claim(actor: Node, activity_points: Array[Node]) -> Node:
	for point in activity_points:
		if point.occupant == actor:
			return point
	return null


func _expect_footprint_clear(layer: TileMapLayer, position: Vector2, profile_id: String) -> void:
	var relative := layer.to_local(position) - layer.map_to_local(Vector2i.ZERO)
	var tile_position := Vector2(relative.x / 96 + relative.y / 48, -relative.x / 96 + relative.y / 48)
	var center := Vector2i(floori(tile_position.x + 0.5), floori(tile_position.y + 0.5))
	for y in range(center.y - 1, center.y + 2):
		for x in range(center.x - 1, center.x + 2):
			var cell := Vector2i(x, y)
			var distance := (tile_position - Vector2(cell)).abs()
			if distance.x < 0.8499 and distance.y < 0.8499 and layer.get_cell_source_id(cell) >= 0:
				_expect(false, "%s walks inside blocked cell %s at %s" % [profile_id, cell, tile_position])
				return


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
