extends SceneTree

# Every imported level except 1 and 2, which keep their own deeper fixtures
# (check_npc_level_runtime.gd and check_npc_level_2_runtime.gd). This one asserts only what
# has to hold on any map: each agent is configured, chooses goals, walks to them, finishes
# something, and never puts its footprint inside a blocked cell while walking. A points-mode
# variant is checked too, because that is the scene the points game actually loads.
#
# The simulation advances on the wall clock, so run it with --fixed-fps 10: the physics tick
# and therefore every decision is unchanged, but 120 simulated seconds take about five
# wall-clock seconds instead of two minutes. tools/run_checks.py passes that flag.

const LevelDir := "res://resources/levels"
const BRAIN_SCRIPT := preload("res://scenes/npc/npc_brain.gd")
const SIMULATION_SECONDS := 120
const RANDOM_SEED := 4091
# The grid pitch, and the clearance scenes/shared/grid_collision.gd requires.
const TILE := Vector2(96.0, 48.0)
const HALF_EXTENT := 0.8499

var _failures := 0
var _checked := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var seconds := SIMULATION_SECONDS
	var only := ""
	var args := OS.get_cmdline_user_args()
	for index in range(args.size() - 1):
		if args[index] == "--level":
			only = args[index + 1]
		elif args[index] == "--seconds":
			seconds = int(args[index + 1])

	for label in _labels():
		if only != "" and label != only:
			continue
		await _check_level(label, seconds)
		if _failures > 0:
			quit(1)
			return
	if _checked == 0:
		_expect(false, "no level beyond the two with their own fixtures is imported")
		quit(1)
		return
	print("Campaign NPC runtime: %d level scene(s), %d simulated seconds each, every agent chose goals, walked and finished an activity" % [_checked, seconds])
	quit(0)


# "5" is a level and "5s" the scene its points-mode file earns; both are enumerated so the
# points game's own layout is exercised.
func _labels() -> Array[String]:
	var numbers: Array[int] = []
	var variants := {}
	var dir := DirAccess.open(LevelDir)
	if dir == null:
		return []
	for file in dir.get_files():
		var name := file.trim_suffix(".remap")
		if not (name.begins_with("level_") and name.ends_with(".json")):
			continue
		var digits := name.trim_prefix("level_").trim_suffix(".json")
		if digits.is_valid_int():
			numbers.append(int(digits))
		elif digits.ends_with("s") and digits.trim_suffix("s").is_valid_int():
			variants[int(digits.trim_suffix("s"))] = true
	numbers.sort()
	var labels: Array[String] = []
	for number: int in numbers:
		if number <= 2:
			continue
		labels.append(str(number))
		if variants.has(number):
			labels.append("%ds" % number)
	return labels


func _check_level(label: String, seconds: int) -> void:
	var scene_path := "res://scenes/level_%s.tscn" % label
	if not ResourceLoader.exists(scene_path):
		_expect(false, "level %s has a scene" % label)
		return
	var level := (load(scene_path) as PackedScene).instantiate()
	var world := level.get_node("World")
	var actors: Array[CharacterBody2D] = []
	var stats := {}
	for child in world.get_children():
		if not child is CharacterBody2D or not child.has_node("Brain"):
			continue
		var brain := child.get_node("Brain")
		brain.random_seed = RANDOM_SEED
		actors.append(child)
		var key := child.name
		stats[key] = {"destinations": 0, "finished": 0, "walk_frames": 0, "goals": {}}
		var entry: Dictionary = stats[key]
		child.destination_reached.connect(func(): entry.destinations += 1)
		child.activity_finished.connect(func(): entry.finished += 1)
		brain.goal_changed.connect(func(goal: int): entry.goals[goal] = true)
		var profile_id := String(child.profile.id)
		_expect(brain.enabled, "level %s %s has its brain enabled" % [label, key])
		_expect(
			not brain.profiles().get(StringName(profile_id), {}).is_empty(),
			"level %s %s (%s) is configured in the exported profile table" % [label, key, profile_id]
		)
	_expect(not actors.is_empty(), "level %s spawns at least one agent" % label)
	if _failures > 0:
		level.free()
		return

	root.add_child(level)
	world.get_node("WorldDepthCompositor").set_process(false)
	world.get_node("CharacterDepthCompositor").set_process(false)
	var player := world.get_node("Player")
	player.set_physics_process(false)
	player.get_node("FootstepPlayer").stop_footsteps()
	player.get_node("FootstepPlayer").stream = null
	var collision_layer := world.get_node("CollisionTileMapLayer") as TileMapLayer

	for frame in range(seconds * Engine.physics_ticks_per_second):
		await physics_frame
		for actor in actors:
			var entry: Dictionary = stats[actor.name]
			_expect(actor.global_position.is_finite(), "level %s %s keeps a finite position" % [label, actor.name])
			if actor.get_node("Brain")._state != BRAIN_SCRIPT.State.ACTING:
				_footprint_clear(collision_layer, actor.global_position, label, actor.name)
				if actor.current_activity == &"walking":
					entry.walk_frames += 1
		if _failures > 0:
			break

	if _failures == 0:
		var moved := 0
		for actor in actors:
			var entry: Dictionary = stats[actor.name]
			var who := "level %s %s (%s)" % [label, actor.name, String(actor.profile.id)]
			_expect(entry.goals.size() > 0, "%s raises at least one goal" % who)
			_expect(entry.walk_frames > 0, "%s walks to a target of its own choosing" % who)
			_expect(entry.destinations > 0, "%s reaches a destination" % who)
			_expect(entry.finished > 0, "%s completes an activity" % who)
			moved += int(entry.destinations)
		print("  level %-3s %2d agents, %3d destinations reached" % [label, actors.size(), moved])
	root.remove_child(level)
	level.free()
	_checked += 1


func _footprint_clear(layer: TileMapLayer, position: Vector2, label: String, who: String) -> void:
	var relative := layer.to_local(position) - layer.map_to_local(Vector2i.ZERO)
	var tile_position := Vector2(relative.x / TILE.x + relative.y / TILE.y, -relative.x / TILE.x + relative.y / TILE.y)
	var center := Vector2i(floori(tile_position.x + 0.5), floori(tile_position.y + 0.5))
	for y in range(center.y - 1, center.y + 2):
		for x in range(center.x - 1, center.x + 2):
			var cell := Vector2i(x, y)
			var distance := (tile_position - Vector2(cell)).abs()
			if distance.x < HALF_EXTENT and distance.y < HALF_EXTENT and layer.get_cell_source_id(cell) >= 0:
				_expect(false, "level %s %s walks inside blocked cell %s at %s" % [label, who, cell, tile_position])
				return


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
