extends SceneTree

# Every imported level except 1 and 2, which keep their own deeper fixtures
# (check_npc_level_runtime.gd and check_npc_level_2_runtime.gd). This one asserts only what
# has to hold on any map: each agent is configured, chooses goals, walks to them, finishes
# something, stands on free cells the way the original's routes do, and everyone whose desk a
# route can reach sits down at their own chair. A desk whose route ends on a blocked cell is
# never reached, in the original as here, and is listed rather than excused. A points-mode
# variant is checked too, because that is the scene the points game actually loads.
#
# The simulation advances on the wall clock, so run it with --fixed-fps 10: the physics tick
# and therefore every decision is unchanged, but 120 simulated seconds take about five
# wall-clock seconds instead of two minutes. tools/run_checks.py passes that flag.

const LevelDir := "res://resources/levels"
const BRAIN_SCRIPT := preload("res://scenes/npc/npc_brain.gd")
const SIMULATION_SECONDS := 120
const RANDOM_SEED := 4091
const WORK_GOAL := 3
# The grid pitch.
const TILE := Vector2(96.0, 48.0)

var _failures := 0
var _checked := 0
# IDLE#2 across every level: starts, and the idle frames of the ticks that can start it.
var _fidgets := 0
var _fidget_frames := 0


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
	_check_the_office_fidgets()
	if _failures > 0:
		quit(1)
		return
	print("Campaign NPC runtime: %d level scene(s), %d simulated seconds each, every agent chose goals, walked, finished an activity, stayed on free cells and worked at its own desk wherever a route reaches it, and the coworkers and the secretary played IDLE#2 at its rate" % [_checked, seconds])
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
		# One stream per agent: the per-frame rolls draw from a stream seeded by random_seed, and
		# a shared one would make every agent's IDLE#2 count the same draws.
		brain.random_seed = RANDOM_SEED + actors.size()
		actors.append(child)
		var key := child.name
		stats[key] = {
			"destinations": 0, "finished": 0, "walk_frames": 0, "goals": {}, "return_cell": null,
			"assigned_chair": brain.get_node_or_null(brain.assigned_chair) if not brain.assigned_chair.is_empty() else null,
			"sat_in_assigned_chair": false, "worked_at_desk": false, "fidgeting": false, "fidgets": 0,
		}
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
	# The loader puts an agent wherever its SPAWN record says, blocked cell or not, and
	# sub_41EE70 never tests the start cell, so a spawn cell is allowed the way a stand-back
	# point is until the agent steps off it. Level 16 spawns a coworker on blocked (9, 1).
	for actor in actors:
		var spawn_cell := _rounded_cell(collision_layer, actor.global_position)
		if collision_layer.get_cell_source_id(spawn_cell) >= 0:
			stats[actor.name].return_cell = spawn_cell
	var activity_points: Array[Node] = []
	for point in get_nodes_in_group("npc_activity_points"):
		if level.is_ancestor_of(point):
			activity_points.append(point)

	for frame in range(seconds * Engine.physics_ticks_per_second):
		await physics_frame
		for actor in actors:
			var entry: Dictionary = stats[actor.name]
			_expect(actor.global_position.is_finite(), "level %s %s keeps a finite position" % [label, actor.name])
			for point in activity_points:
				if point.occupant == actor:
					entry.return_cell = _rounded_cell(collision_layer, point.global_position)
					if point == entry.assigned_chair and String(actor.current_activity).begins_with("sit-"):
						entry.sat_in_assigned_chair = true
			var brain := actor.get_node("Brain")
			if brain._goal == WORK_GOAL and brain._state == BRAIN_SCRIPT.State.ACTING and entry.assigned_chair != null:
				if brain._target == entry.assigned_chair or brain._active == brain.get_node_or_null(brain.assigned_workstation):
					entry.worked_at_desk = true
			if actor.get_node("Brain")._state != BRAIN_SCRIPT.State.ACTING:
				_rounded_cell_free(collision_layer, actor.global_position, entry.return_cell, label, actor.name)
				if actor.current_activity == &"walking":
					entry.walk_frames += 1
			_count_fidgets(actor, entry, label)
		if _failures > 0:
			break

	if _failures == 0:
		var moved := 0
		var unreachable: Array[String] = []
		var starved: Array[String] = []
		var elsewhere: Array[String] = []
		for actor in actors:
			var entry: Dictionary = stats[actor.name]
			var who := "level %s %s (%s)" % [label, actor.name, String(actor.profile.id)]
			if entry.finished == 0:
				var goal := _starving_goal(actor)
				if goal >= 0:
					starved.append("%s (goal %d, every candidate out of reach)" % [actor.name, goal])
					continue
			_expect(entry.goals.size() > 0, "%s raises at least one goal" % who)
			_expect(entry.walk_frames > 0, "%s walks to a target of its own choosing" % who)
			_expect(entry.destinations > 0, "%s reaches a destination" % who)
			_expect(entry.finished > 0, "%s completes an activity" % who)
			# Seven coworkers' chairs on levels 4, 6 and 7 are flush against a wall, and only a
			# route that ends on the free cell, as sub_416D50's does, gets them seated. Where that
			# cell is itself blocked, sub_41E910 never enters it, so the colleague works only at
			# the 1-in-8 alternates and never sits at its own desk. Arriving, the monitor's seat
			# search (sub_418230) claims the first free seat within 1.8 tiles rather than the
			# assigned one, so two colleagues at neighbouring desks can work from each other's
			# seats, and one who finds none free works standing for the same 50 to 60 seconds.
			if entry.assigned_chair != null:
				var chair_name: String = entry.assigned_chair.get_parent().name
				var desk_cell := _rounded_cell(collision_layer, actor.get_node("Brain")._route_end(entry.assigned_chair.global_position))
				if collision_layer.get_cell_source_id(desk_cell) >= 0:
					_expect(not entry.sat_in_assigned_chair, "%s never reaches %s, whose cell %s is blocked" % [who, chair_name, desk_cell])
					unreachable.append("%s (%s at %s)" % [actor.name, chair_name, desk_cell])
				else:
					_expect(entry.worked_at_desk, "%s gets to its desk %s and works" % [who, chair_name])
					if entry.worked_at_desk and not entry.sat_in_assigned_chair:
						elsewhere.append("%s (not in %s)" % [actor.name, chair_name])
			moved += int(entry.destinations)
		var fidgets := 0
		for actor in actors:
			fidgets += int(stats[actor.name].fidgets)
		print("  level %-3s %2d agents, %3d destinations reached, %2d IDLE#2" % [label, actors.size(), moved, fidgets])
		for desk in unreachable:
			print("            desk out of reach: %s" % desk)
		for agent in starved:
			print("            stands still, starved: %s" % agent)
		for agent in elsewhere:
			print("            works standing or from another seat: %s" % agent)
	root.remove_child(level)
	level.free()
	_checked += 1


# sub_415FF0 keeps choosing the lowest need, a tie going to the lower goal, and a goal whose
# every candidate is out of reach pins its need at 0 and so beats every goal after it until a
# reaction resets the needs (docs/npc-reference.md, "When a goal can never succeed"). An agent
# left retrying such a goal from the start stands still for good, in the original as here.
# Returns that goal, or -1 when the agent is not in that state.
func _starving_goal(actor: CharacterBody2D) -> int:
	var brain := actor.get_node("Brain")
	var goal: int = brain._pending_goal if brain._pending_goal >= 0 else brain._goal
	if goal < 0 or goal == BRAIN_SCRIPT.SOCIAL_GOAL or float(brain._needs[goal]) > 0.0:
		return -1
	var points: Array = (brain._goal_candidates[goal] as Array).duplicate()
	if goal == 3:
		points.append_array(brain._alternate_candidates)
		for path: NodePath in [brain.assigned_chair, brain.assigned_workstation]:
			var node := brain.get_node_or_null(path) if not path.is_empty() else null
			if node != null:
				points.append(node)
	for point: Node2D in points:
		if not actor._find_navigation_path(brain._route_end(point.global_position)).is_empty():
			return -1
	return goal


# sub_419CE0 and sub_41E360 start IDLE#2 from their idle branch on 7/4096 of its frames at the
# port's nominal 60 Hz; the boss's and the janitor's ticks never do.
func _count_fidgets(actor: CharacterBody2D, entry: Dictionary, label: String) -> void:
	var brain := actor.get_node("Brain")
	var fidgeting: bool = actor.is_fidgeting()
	var reads_slot := StringName(actor.profile.id) in BRAIN_SCRIPT.SLOT_READING_PROFILES
	if fidgeting and not entry.fidgeting:
		entry.fidgets += 1
		_fidgets += 1
		_expect(reads_slot, "level %s %s (%s) has no IDLE#2 to play" % [label, actor.name, actor.profile.id])
		_expect(brain._in_idle_branch(), "level %s %s starts IDLE#2 only while it stands about" % [label, actor.name])
	elif reads_slot and not fidgeting and brain._in_idle_branch():
		_fidget_frames += 1
	entry.fidgeting = fidgeting


func _check_the_office_fidgets() -> void:
	var expected := _fidget_frames * 7.0 / 4096.0
	_expect(_fidgets > 0 and absf(_fidgets - expected) < 5.0 * sqrt(expected), "IDLE#2 starts on 7/4096 of the idle frames: %d in %d, expected %.0f" % [_fidgets, _fidget_frames, expected])
	print("  IDLE#2: %d starts in %d idle frames, expected %.0f" % [_fidgets, _fidget_frames, expected])


# sub_416D50 routes between cell centres and sub_41E910 never enters a blocked cell, so an
# agent stands on a free cell -- except on the exact interaction point sub_4161E0 or
# sub_416090 put it back on, and while it steps back off it.
func _rounded_cell_free(layer: TileMapLayer, position: Vector2, return_cell: Variant, label: String, who: String) -> void:
	var cell := _rounded_cell(layer, position)
	if cell != return_cell and layer.get_cell_source_id(cell) >= 0:
		_expect(false, "level %s %s stands in blocked cell %s at %s" % [label, who, cell, position])


func _rounded_cell(layer: TileMapLayer, position: Vector2) -> Vector2i:
	var relative := layer.to_local(position) - layer.map_to_local(Vector2i.ZERO)
	var tile_position := Vector2(relative.x / TILE.x + relative.y / TILE.y, -relative.x / TILE.x + relative.y / TILE.y)
	return Vector2i(floori(tile_position.x + 0.5), floori(tile_position.y + 0.5))


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
