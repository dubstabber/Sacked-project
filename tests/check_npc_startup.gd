extends SceneTree

# NPCStartup, the level start's desk search, ported from the importer's build_npcs so that an
# agent dropped into a map finds a desk. On every imported level, the s variants included, it
# has to hand each agent exactly the workstation and chair the importer did: every brain's
# baked answer is cleared, the port runs, and the answer has to come back. That covers the
# order (ascending spawn type), the first-in-item-order rule, the radii and their strict
# comparison, which 38 campaign distances tie exactly, and the active-category checks.
#
# Then a coworker dropped into level 1 where an agent stood, with nobody's desk assigned to it,
# finds one of its own that nobody else holds.

const DONE := &"startup_assigned"

var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var levels := 0
	var desks := 0
	for manifest in DirAccess.get_files_at("res://resources/levels"):
		if not (manifest.begins_with("level_") and manifest.ends_with(".json")):
			continue
		var scene := "res://scenes/%s.tscn" % manifest.get_basename()
		var level := (load(scene) as PackedScene).instantiate()
		desks += _check_level(level, manifest.get_basename())
		level.free()
		levels += 1
	_expect(levels == 27, "every imported level was searched, got %d" % levels)
	_expect(desks > 100, "and their agents hold desks, %d of them" % desks)
	_check_a_dropped_coworker()
	if _failures == 0:
		print("NPC startup: on all %d imported levels the port hands every agent the importer's %d desks and chairs, and a dropped coworker finds a free one" % [levels, desks])
	quit(1 if _failures else 0)


func _check_level(level: Node, label: String) -> int:
	var world := level.get_node("World")
	var expected := {}
	for node in world.get_children():
		var brain := node.get_node_or_null("Brain")
		if brain == null:
			continue
		_expect(brain.has_meta(DONE), "%s %s carries the importer's search" % [label, node.name])
		expected[node.name] = [brain.assigned_workstation, brain.assigned_chair]
		brain.assigned_workstation = NodePath()
		brain.assigned_chair = NodePath()
		brain.remove_meta(DONE)
	NPCStartup.assign(world)
	var held := 0
	for agent_name in expected:
		var brain := world.get_node("%s/Brain" % agent_name)
		var got := [brain.assigned_workstation, brain.assigned_chair]
		_expect(got == expected[agent_name], "%s %s gets %s, the importer gave %s" % [label, agent_name, got, expected[agent_name]])
		for path: NodePath in got:
			held += 0 if path.is_empty() else 1
	return held


func _check_a_dropped_coworker() -> void:
	var level := (load("res://scenes/level_1.tscn") as PackedScene).instantiate()
	var world := level.get_node("World")
	var leaving := world.get_node("Npc079MaleEmployee1") as Node2D
	var spot := leaving.position
	world.remove_child(leaving)
	leaving.free()
	var coworker := (load("res://scenes/npc/coworker.tscn") as PackedScene).instantiate() as Node2D
	coworker.position = spot
	world.add_child(coworker)
	NPCStartup.assign(world)
	var brain := coworker.get_node("Brain")
	_expect(brain.has_meta(DONE), "the dropped coworker has been searched for")
	var workstation := brain.get_node_or_null(brain.assigned_workstation) if not brain.assigned_workstation.is_empty() else null
	var chair := brain.get_node_or_null(brain.assigned_chair) if not brain.assigned_chair.is_empty() else null
	_expect(workstation != null and int(workstation.item_type) in NPCStartup.WORKSTATION_TYPES and workstation.active, "it takes a workstation")
	_expect(chair != null and int(chair.item_type) in NPCStartup.CHAIR_TYPES and not chair.active, "and a chair")
	for node in world.get_children():
		var other := node.get_node_or_null("Brain")
		if other == null or other == brain:
			continue
		for path: NodePath in [other.assigned_workstation, other.assigned_chair]:
			var held := other.get_node_or_null(path) if not path.is_empty() else null
			_expect(held == null or (held != workstation and held != chair), "that %s does not hold" % node.name)
	level.free()


func _expect(condition: bool, label: String) -> void:
	if not condition:
		_failures += 1
		push_error(label)
