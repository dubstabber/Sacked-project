extends SceneTree

# Level 2 is the first map that spawns the secretary, the janitor and the second coworker
# variant, all of which stood inert until their profiles and clips were imported. This runs
# the whole cast on the real map and asserts each one chooses its own goals, walks to them
# and finishes an activity, with a footprint that never enters a blocked cell.
#
# check_npc_level_runtime.gd keeps the deeper level-1 assertions; the helpers here are
# copied rather than shared, following the convention for the generated level fixtures.

const LEVEL_SCENE := preload("res://scenes/level_2.tscn")
const BRAIN_SCRIPT := preload("res://scenes/npc/npc_brain.gd")
const EXPECTED_PROFILES := [
	"boss", "secretary", "janitor",
	"male-employee-1", "male-employee-2", "female-employee-1",
]
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
		brain.random_seed = 4091
		actors.append(child)
		var profile_id := String(child.profile.id)
		_stats[profile_id] = {
			"destinations": 0, "finished": 0, "navigation_failures": 0,
			"walk_frames": 0, "activity_frames": 0, "goals": {},
			"last_position": child.position,
		}
		var stats: Dictionary = _stats[profile_id]
		child.destination_reached.connect(func(): stats.destinations += 1)
		child.activity_finished.connect(func(): stats.finished += 1)
		child.navigation_failed.connect(func(): stats.navigation_failures += 1)
		brain.goal_changed.connect(func(goal: int): stats.goals[goal] = true)
		_expect(brain.enabled, "%s original brain is enabled" % profile_id)
		_expect(
			not brain.profiles().get(StringName(profile_id), {}).is_empty(),
			"%s is configured in the exported profile table" % profile_id
		)

	_expect(actors.size() == EXPECTED_PROFILES.size(), "level 2 spawns its six original agents, got %d" % actors.size())
	for profile_id in EXPECTED_PROFILES:
		_expect(_stats.has(profile_id), "level 2 spawns original profile %s" % profile_id)
	if _failures > 0:
		level.free()
		quit(1)
		return

	# Goal 9 needs something broken to repair, so this asserts level 2 actually places the
	# item types sub_4180F0 answers yes for and breaks them. Whether the janitor reaches one
	# inside the simulated window is down to its own needs and is not asserted here: the
	# goal itself is covered, with a negative control, by check_npc_brain.gd.
	var repairable := BRAIN_SCRIPT.repairable_types()
	var broken := 0
	for point in world.find_children("*", "Marker2D", true, false):
		if not point.has_method("reset_actions") or not repairable.has(int(point.item_type)):
			continue
		point.tampered = true
		broken += 1
	_expect(broken > 0, "level 2 places at least one item type a janitor will repair")

	root.add_child(level)
	world.get_node("WorldDepthCompositor").set_process(false)
	world.get_node("CharacterDepthCompositor").set_process(false)
	var player := world.get_node("Player")
	player.set_physics_process(false)
	player.get_node("FootstepPlayer").stop_footsteps()
	player.get_node("FootstepPlayer").stream = null
	var collision_layer := world.get_node("CollisionTileMapLayer") as TileMapLayer

	for frame in range(SIMULATION_SECONDS * Engine.physics_ticks_per_second):
		await physics_frame
		for actor in actors:
			_check_actor_frame(actor, collision_layer)
		if _failures > 0:
			break

	for actor in actors:
		_check_actor_result(actor)
	level.free()
	if _failures == 0:
		print("Level 2 NPC runtime: %d simulated seconds, all six brains chose goals, walked and completed activities" % SIMULATION_SECONDS)
	quit(1 if _failures else 0)


func _check_actor_frame(actor: CharacterBody2D, layer: TileMapLayer) -> void:
	var profile_id := String(actor.profile.id)
	var stats: Dictionary = _stats[profile_id]
	var brain := actor.get_node("Brain")
	_expect(actor.global_position.is_finite(), "%s position remains finite" % profile_id)
	if brain._state == BRAIN_SCRIPT.State.ACTING:
		# An activity places the agent on the item's own anchor, which is deliberately not a
		# cell it could have walked to: sub_4161E0 seats it on the furniture and sub_416090
		# puts it inside the cubicle. Only walking has to keep its footprint clear.
		stats.activity_frames += 1
		if String(actor.current_activity).begins_with("sit-"):
			_expect(actor.animation_player.is_playing(), "%s seated action plays an available animation" % profile_id)
	else:
		_expect_footprint_clear(layer, actor.global_position, profile_id)
		if actor.current_activity == &"walking":
			stats.walk_frames += 1
	stats.last_position = actor.global_position


func _check_actor_result(actor: CharacterBody2D) -> void:
	var profile_id := String(actor.profile.id)
	var stats: Dictionary = _stats[profile_id]
	_expect(stats.walk_frames > 0, "%s walks to a target of its own choosing" % profile_id)
	_expect(stats.destinations > 0, "%s reaches a destination" % profile_id)
	_expect(stats.finished > 0, "%s completes an activity" % profile_id)
	_expect(stats.goals.size() > 0, "%s raises at least one goal" % profile_id)
	print("%s: %d destinations, %d completed activities, %d distinct goals, %d navigation retries" % [
		profile_id, stats.destinations, stats.finished, stats.goals.size(), stats.navigation_failures,
	])


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
