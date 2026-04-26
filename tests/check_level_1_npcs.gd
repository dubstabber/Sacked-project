extends SceneTree


const Level1Scene := preload("res://scenes/level_1.tscn")

const NpcNames := [
	"Boss",
	"Secretary",
	"Janitor",
	"MaleEmployee1",
	"MaleEmployee2",
	"FemaleEmployee1",
	"FemaleEmployee2",
]

var _level
var _failed := false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_level = Level1Scene.instantiate()
	root.add_child(_level)
	await process_frame

	var world: Node = _level.get_node_or_null("World")
	if world == null:
		_fail("Level 1 has no World node")
		return

	for npc_name in NpcNames:
		_check_npc(world, npc_name)
		if _failed:
			return

	_free_level()
	quit(0)


func _check_npc(world: Node, npc_name: String) -> void:
	var npc: Node = world.get_node_or_null(npc_name)
	if npc == null:
		_fail("Level 1 missing NPC: %s" % npc_name)
		return
	if npc.get("profile") == null:
		_fail("%s has no profile" % npc_name)
		return
	var animation_controller: Node = npc.get_node_or_null("AnimationController")
	if animation_controller == null:
		_fail("%s has no AnimationController" % npc_name)
		return
	if String(animation_controller.get("idle_animation_prefix")) == "":
		_fail("%s has no idle animation prefix" % npc_name)
		return
	if String(animation_controller.get("walk_animation_prefix")) == "":
		_fail("%s has no walk animation prefix" % npc_name)
		return


func _free_level() -> void:
	if _level == null:
		return
	if _level.get_parent() != null:
		_level.get_parent().remove_child(_level)
	_level.free()
	_level = null


func _fail(message: String) -> void:
	if _failed:
		return
	_failed = true
	_free_level()
	push_error(message)
	quit(1)
