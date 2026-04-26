extends SceneTree


const PlayerScene := preload("res://scenes/player/player.tscn")
const NPCScene := preload("res://scenes/npc/npc.tscn")
const JoblessProfile := preload("res://scenes/player/profiles/jobless.tres")
const BossProfile := preload("res://scenes/npc/profiles/boss.tres")
const CharacterDepthCompositorScript := preload("res://scenes/shared/character_depth_compositor.gd")

var _world: Node2D
var _player
var _npc
var _compositor
var _failed := false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_world = Node2D.new()
	root.add_child(_world)

	_player = PlayerScene.instantiate()
	_player.profile = JoblessProfile
	_player.global_position = Vector2(120.0, 120.0)
	_world.add_child(_player)

	_npc = NPCScene.instantiate()
	_npc.profile = BossProfile
	_npc.global_position = Vector2(126.0, 124.0)
	_world.add_child(_npc)

	_compositor = CharacterDepthCompositorScript.new()
	_world.add_child(_compositor)

	await process_frame
	_player.set_physics_process(false)
	_npc.set_physics_process(false)
	_player.footstep_controller.stop_footsteps()
	_player.footstep_controller.stream = null

	_check_overlap_composites_bodies()
	if _failed:
		return
	_check_separation_restores_bodies()
	if _failed:
		return

	_cleanup()
	quit(0)


func _check_overlap_composites_bodies() -> void:
	_compositor.update_composition()
	_assert_true(_compositor.visible, "overlap compositor visible")
	_assert_true(_compositor.texture != null, "overlap compositor texture")
	_assert_false(_player.sprite.visible, "overlap player body hidden")
	_assert_false(_npc.sprite.visible, "overlap npc body hidden")
	_assert_true(_player.get_node("Shadow").visible, "overlap player shadow remains visible")
	_assert_true(_npc.get_node("Shadow").visible, "overlap npc shadow remains visible")


func _check_separation_restores_bodies() -> void:
	_npc.global_position = Vector2(500.0, 500.0)
	_compositor.update_composition()
	_assert_false(_compositor.visible, "separated compositor hidden")
	_assert_true(_player.sprite.visible, "separated player body visible")
	_assert_true(_npc.sprite.visible, "separated npc body visible")


func _cleanup() -> void:
	if _player != null:
		_player.footstep_controller.stop_footsteps()
		_player.footstep_controller.stream = null
	if _world != null:
		root.remove_child(_world)
		_world.free()
	_world = null
	_player = null
	_npc = null
	_compositor = null


func _assert_true(value: bool, label: String) -> void:
	if not value:
		_fail("%s expected true" % label)


func _assert_false(value: bool, label: String) -> void:
	if value:
		_fail("%s expected false" % label)


func _fail(message: String) -> void:
	if _failed:
		return
	_failed = true
	_cleanup()
	push_error(message)
	quit(1)
