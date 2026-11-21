class_name NPCStartup
extends RefCounted

# The level start's desk and chair search, for every agent nobody has assigned one yet: an
# agent dropped into a map finds a desk the way the original's agents do. The imported levels
# carry the importer's answer instead (tools/import_original_level.py build_npcs), and
# tests/check_npc_startup.gd holds this port to it on every one of them.
#
# sub_406AF0 creates the agents in ascending spawn type, once each for types 1-3, and
# sub_4185B0 searches for each in that order, so one claims a desk before the next looks:
#
# - a workstation, types 152-155: the first item inside radius 0.5, then 1.0, ... up to 10.0
#   tiles of the agent's spawn, kept only if its record's category is 5 (active);
# - then a chair, types 68-74, 86, 93, 94, 121 and 122: the first inside 1, 2 or 3 tiles of
#   that workstation (or of the spawn, without one), kept only if it is not active.
#
# "First" is item order, not nearest (sub_418230), and the boss and the janitor search for
# neither (sub_418790 zeroes both). See docs/npc-reference.md.

const WORKSTATION_TYPES := [152, 153, 154, 155]
const CHAIR_TYPES := [68, 69, 70, 71, 72, 73, 74, 86, 93, 94, 121, 122]
const WORKSTATION_RADII := [0.5, 1.0, 1.5, 2.0, 2.5, 3.0, 3.5, 4.0, 4.5, 5.0, 5.5, 6.0, 6.5, 7.0, 7.5, 8.0, 8.5, 9.0, 9.5, 10.0]
const CHAIR_RADII := [1.0, 2.0, 3.0]
# Spawn types 1 and 3, the boss and the janitor.
const NO_DESK_SPAWNS := [1, 3]
# The types sub_406AF0 creates at most once: the boss, the secretary and the janitor.
const UNIQUE_SPAWN_LIMIT := 3
# Set on a brain whose search has been run, here or by the importer.
const DONE_META := &"startup_assigned"


# Runs the search for every agent of the map `world` holds whose brain has not had it, and
# returns how many it searched for. Agents already assigned claim their desks first.
static func assign(world: Node) -> int:
	var objects := world.get_node_or_null("Objects")
	if objects == null:
		return 0
	var items: Array = []
	for object in objects.get_children():
		var point := object.get_node_or_null("InteractionPoint")
		if point != null and point.has_method("anchor_tile"):
			items.append([point, point.call("anchor_tile")])
	var claimed := {}
	var agents: Array = []
	for node in world.get_children():
		var brain := node.get_node_or_null("Brain") if node is Node2D else null
		if brain == null:
			continue
		if brain.has_meta(DONE_META) or not (brain.get("assigned_workstation") as NodePath).is_empty() or not (brain.get("assigned_chair") as NodePath).is_empty():
			for field in ["assigned_workstation", "assigned_chair"]:
				var path: NodePath = brain.get(field)
				var point := brain.get_node_or_null(path) if not path.is_empty() else null
				if point != null:
					claimed[point] = true
			continue
		agents.append([spawn_type(node), agents.size(), node])
	# Ascending spawn type; tree order breaks a tie, as file order does in sub_413320.
	agents.sort_custom(func(a, b): return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))

	var created := {}
	for entry in agents:
		var spawn: int = entry[0]
		var agent: Node2D = entry[2]
		var brain := agent.get_node("Brain")
		brain.set_meta(DONE_META, true)
		if spawn <= UNIQUE_SPAWN_LIMIT and created.has(spawn):
			continue
		created[spawn] = true
		if spawn in NO_DESK_SPAWNS:
			continue
		var origin := _agent_tile(agent, world)
		var workstation = _first_within(items, WORKSTATION_TYPES, claimed, origin, WORKSTATION_RADII)
		if workstation != null:
			if bool(workstation[0].get("active")):
				claimed[workstation[0]] = true
				origin = workstation[1]
				brain.set("assigned_workstation", brain.get_path_to(workstation[0]))
		var chair = _first_within(items, CHAIR_TYPES, claimed, origin, CHAIR_RADII)
		if chair != null and not bool(chair[0].get("active")):
			claimed[chair[0]] = true
			brain.set("assigned_chair", brain.get_path_to(chair[0]))
	return agents.size()


# The spawn type an agent's profile was imported from, from resources/original/npc_profiles.json.
static func spawn_type(agent: Node) -> int:
	var profile = agent.get("profile")
	var entry: Dictionary = NPCBrain.profiles().get(StringName(profile.get("id")) if profile != null else &"", {})
	return int(entry.get("spawn_id", 0))


# sub_418230: the first item, in item order, of a wanted type inside each radius in turn. The
# distance is worked in doubles from the float32 tiles, as the importer's search does it.
static func _first_within(items: Array, types: Array, claimed: Dictionary, origin: Vector2, radii: Array):
	for radius in radii:
		for item in items:
			var point: Node = item[0]
			if claimed.has(point) or not (int(point.get("item_type")) in types):
				continue
			var tile: Vector2 = item[1]
			var dx := float(tile.x) - float(origin.x)
			var dy := float(tile.y) - float(origin.y)
			if sqrt(dx * dx + dy * dy) < float(radius):
				return item
	return null


# Where the agent spawned, in tiles: an imported agent still standing where the importer put it
# answers its manifest tile exactly; one moved or dropped in answers where it stands.
static func _agent_tile(agent: Node2D, world: Node) -> Vector2:
	var layer := world.get_node_or_null("CollisionTileMapLayer") as TileMapLayer
	if layer == null:
		return Vector2.ZERO
	var origin := layer.map_to_local(Vector2i.ZERO)
	var axes := Transform2D(layer.map_to_local(Vector2i(1, 0)) - origin, layer.map_to_local(Vector2i(0, 1)) - origin, origin)
	if agent.has_meta("original_tile_position"):
		var tile: Vector2 = agent.get_meta("original_tile_position")
		if origin + axes.x * tile.x + axes.y * tile.y == agent.position:
			return tile
	return axes.affine_inverse() * agent.position
