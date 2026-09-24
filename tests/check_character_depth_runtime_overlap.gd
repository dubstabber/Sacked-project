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
	_check_a_lifted_body_takes_its_depth_from_the_lift()
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


# ASSCOPY on level 3: the player's node stays on the floor at y 849.6 while his height of 1.8
# draws him 43.2 px up. sub_41A2D0 derives the depth base from that lifted anchor, so it is
# ceil(806 / 2) = 403, not the 425 the node's own y would give -- on the GPU path and in the
# CPU composite alike.
func _check_a_lifted_body_takes_its_depth_from_the_lift() -> void:
	_npc.global_position = Vector2(2000.0, 2000.0)
	_player.global_position = Vector2(584.4, 849.6)
	_compositor.update_composition()
	_assert_equal(_shader_base(), 425.0, "a player on the floor bases his depth on his own y")

	_player.height = 1.8
	_compositor.update_composition()
	_assert_equal(_shader_base(), 403.0, "a lifted player bases his depth on the lifted sprite")

	_npc.global_position = _player.global_position + Vector2(6.0, -40.0)
	_compositor.update_composition()
	_assert_false(_player.sprite.visible, "the lifted player overlaps the npc and is composited")
	var texture_path: String = _player.sprite.texture.resource_path
	var composited := -1.0
	for part in String(_compositor._surface_signatures[0]).split(";"):
		if part.begins_with(texture_path + "|"):
			composited = float(part.get_slice("|", 5))
	_assert_equal(composited, 403.0, "the CPU composite uses the same lifted base")

	_player.height = 0.0
	_npc.global_position = Vector2(2000.0, 2000.0)
	_compositor.update_composition()


func _shader_base() -> float:
	var material := _player.sprite.material as ShaderMaterial
	if material == null:
		return -1.0
	return float(material.get_shader_parameter("base_y"))


func _assert_equal(actual: float, expected: float, label: String) -> void:
	if not is_equal_approx(actual, expected):
		_fail("%s: expected %s, got %s" % [label, expected, actual])


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
