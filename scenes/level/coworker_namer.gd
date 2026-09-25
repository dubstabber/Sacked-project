extends Node

# sub_406AF0 sets a level up by freeing every name (sub_4156B0) and then creating its agents
# in ascending spawn type, SPAWN file order within a type. Each class's vtbl+28 copies
# sub_4156E0's first free name of its own pool into agent+1752 and marks it used, and an
# empty pool answers DEFAULT NAME. A freshly loaded level scene is that reset, so the port
# names the level's agents once, in that order. The level builder emits them in it already;
# the sort only holds a hand-built scene to it. See docs/names-reference.md.

const AGENT_GROUP := &"npc_agents"


func _ready() -> void:
	# The agents are ready by then, and a restart builds a new scene and a new namer.
	call_deferred("_bind")


func _bind() -> void:
	var level := get_parent().get_parent() if get_parent() != null else null
	var store: Node = get_node_or_null("/root/SettingsStore")
	name_agents(_level_agents(level), store)


# Returns each agent's name in the order they were dealt, for a check to read.
static func name_agents(agents: Array, store: Node) -> PackedStringArray:
	var ordered := []
	for index in agents.size():
		var agent := agents[index] as Node
		var profile = agent.get("profile")
		var type := CoworkerNames.type_for_profile(StringName(profile.get("id"))) if profile != null else 0
		if type > 0:
			ordered.append([type, index, agent])
	ordered.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))

	var dealt := {}
	var names := PackedStringArray()
	for entry: Array in ordered:
		var type: int = entry[0]
		if not dealt.has(type):
			var pool: PackedStringArray = store.names_for_type(type) if store != null else CoworkerNames.defaults_for(type)
			dealt[type] = {"pool": pool, "next": 0}
		var state: Dictionary = dealt[type]
		var pool: PackedStringArray = state["pool"]
		var next: int = state["next"]
		var dealt_name := pool[next] if next < pool.size() else CoworkerNames.placeholder()
		state["next"] = next + 1
		(entry[2] as Node).set("display_name", dealt_name)
		names.append(dealt_name)
	return names


func _level_agents(level: Node) -> Array:
	var agents := []
	for node in get_tree().get_nodes_in_group(AGENT_GROUP):
		if level == null or level.is_ancestor_of(node):
			agents.append(node)
	return agents
