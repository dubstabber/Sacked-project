extends SceneTree


const PlayerScene := preload("res://scenes/player/player.tscn")
const NPCScene := preload("res://scenes/npc/npc.tscn")
const JoblessProfile := preload("res://scenes/player/profiles/jobless.tres")
const BossProfile := preload("res://scenes/npc/profiles/boss.tres")
const WORLD_LAYER := 1
const CHARACTER_LAYER := 2

var _world: Node2D
var _player
var _npc
var _failed := false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_world = Node2D.new()
	root.add_child(_world)

	_player = PlayerScene.instantiate()
	_player.profile = JoblessProfile
	_player.global_position = Vector2.ZERO
	_world.add_child(_player)

	_npc = NPCScene.instantiate()
	_npc.profile = BossProfile
	_npc.global_position = Vector2(8.0, 0.0)
	_world.add_child(_npc)

	await process_frame
	_player.set_physics_process(false)
	_npc.set_physics_process(false)
	_player.footstep_controller.stop_footsteps()
	_player.footstep_controller.stream = null

	_check_character_layer_setup()
	if _failed:
		return
	_check_characters_do_not_collide()
	if _failed:
		return
	await _check_world_objects_still_collide()
	if _failed:
		return

	_cleanup()
	quit(0)


func _check_character_layer_setup() -> void:
	_assert_equal(_player.collision_layer, CHARACTER_LAYER, "player collision layer")
	_assert_equal(_npc.collision_layer, CHARACTER_LAYER, "npc collision layer")
	_assert_equal(_player.collision_mask, WORLD_LAYER, "player collision mask")
	_assert_equal(_npc.collision_mask, WORLD_LAYER, "npc collision mask")


func _check_characters_do_not_collide() -> void:
	_player.global_position = Vector2.ZERO
	_npc.global_position = Vector2(8.0, 0.0)
	var collision: KinematicCollision2D = _player.move_and_collide(Vector2(24.0, 0.0), true)
	if collision != null:
		_fail("Player unexpectedly collided with overlapping NPC")


func _check_world_objects_still_collide() -> void:
	var wall := StaticBody2D.new()
	wall.collision_layer = WORLD_LAYER
	wall.collision_mask = 0
	wall.global_position = Vector2(44.0, -17.0)

	var shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(10.0, 80.0)
	shape.shape = rectangle
	wall.add_child(shape)
	_world.add_child(wall)

	await physics_frame

	_player.global_position = Vector2.ZERO
	var collision: KinematicCollision2D = _player.move_and_collide(Vector2(80.0, 0.0), true)
	if collision == null:
		_fail("Player did not collide with a world-layer object")

	_world.remove_child(wall)
	wall.free()


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


func _assert_equal(actual: int, expected: int, label: String) -> void:
	if actual != expected:
		_fail("%s expected %d, got %d" % [label, expected, actual])


func _fail(message: String) -> void:
	if _failed:
		return
	_failed = true
	_cleanup()
	push_error(message)
	quit(1)
