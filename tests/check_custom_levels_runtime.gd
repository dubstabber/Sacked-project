extends SceneTree

# Every custom level, and the template they start from, is a level the game can play. For each
# CustomLevelInfo in res://custom_levels/ (and the fixture beside this check):
#
# - its scene loads, and every resource it depends on exists;
# - it has what a level needs: World with the floor, the movement cells, the painted rooms and
#   sight blockers, the objects, both depth compositors and the player, and a LevelRuntime;
# - every object carries an InteractionPoint, and every agent a profile the brains know;
# - played for twenty seconds with its office awake, nothing errors and every agent's brain
#   has started; the template's coworker has found a desk.
#
# A designer checks a new map with:  python3 tools/run_checks.py --filter custom

const DIRECTORIES := ["res://custom_levels/", "res://tests/fixtures/custom_levels/"]
const TEMPLATE := "res://scenes/custom_level_template.tscn"
const PLAY_SECONDS := 20.0
const REQUIRED := [
	"World/FloorTileMapLayer", "World/WallTileMapLayer", "World/Objects", "World/CollisionTileMapLayer",
	"World/RoomTileMapLayer", "World/SightTileMapLayer", "World/WorldDepthCompositor",
	"World/CharacterDepthCompositor", "World/Player", "LevelRuntime",
]

var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var levels := 0
	for directory: String in DIRECTORIES:
		for info in CustomLevelInfo.all_in(directory):
			await _check_level(info)
			levels += 1
	_expect(levels >= 2, "the sample and the fixture are listed, got %d" % levels)
	var fixtures := CustomLevelInfo.all_in("res://tests/fixtures/custom_levels/")
	_expect(fixtures.size() == 1, "a level whose scene is missing is not listed")
	_expect(not CustomLevelInfo.all_in("res://custom_levels/").is_empty() and CustomLevelInfo.all_in("res://custom_levels/")[0].title != "", "the sample office is listed under its title")
	if _failures == 0:
		print("Custom levels: %d levels load, carry everything a level needs and play for %d s with nothing failing" % [levels, int(PLAY_SECONDS)])
	quit(1 if _failures else 0)


func _check_level(info: CustomLevelInfo) -> void:
	var label := "%s (%s)" % [info.title, info.scene]
	_expect(info.title != "", "%s has a title" % info.scene)
	for dependency in ResourceLoader.get_dependencies(info.scene):
		var path := String(dependency).get_slice("::", 2) if String(dependency).contains("::") else String(dependency)
		_expect(ResourceLoader.exists(path), "%s depends on %s, which is missing" % [label, path])
	var packed := load(info.scene) as PackedScene
	if packed == null:
		_expect(false, "%s loads" % label)
		return
	var level := packed.instantiate()
	for path: String in REQUIRED:
		_expect(level.get_node_or_null(path) != null, "%s has %s" % [label, path])
	var world := level.get_node_or_null("World")
	if world == null:
		level.free()
		return
	for object in world.get_node("Objects").get_children():
		_expect(object.get_node_or_null("InteractionPoint") != null, "%s %s carries its InteractionPoint" % [label, object.name])
	var agents: Array[Node] = []
	for node in world.get_children():
		if node.get_node_or_null("Brain") == null:
			continue
		agents.append(node)
		var profile = node.get("profile")
		_expect(profile != null and NPCBrain.profiles().has(StringName(profile.get("id"))), "%s %s has a profile the brains know" % [label, node.name])

	root.add_child(level)
	var frames := 0
	# Run with --fixed-fps 10 (run_checks.py does), so twenty simulated seconds pass quickly.
	while frames < int(PLAY_SECONDS * 10.0):
		await process_frame
		frames += 1
	for agent in agents:
		var brain := agent.get_node("Brain")
		_expect(brain.is_initialized(), "%s %s's brain has started" % [label, agent.name])
	if info.scene == TEMPLATE:
		var coworker := world.get_node_or_null("Npc079MaleEmployee1/Brain")
		_expect(coworker != null and not (coworker.assigned_workstation as NodePath).is_empty(), "the template's coworker has found a desk")
	root.remove_child(level)
	level.free()


func _expect(condition: bool, label: String) -> void:
	if not condition:
		_failures += 1
		push_error(label)
