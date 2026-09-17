extends SceneTree


const NPCScene := preload("res://scenes/npc/npc.tscn")
const BossProfile := preload("res://scenes/npc/profiles/boss.tres")

var _npc


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_check_boss_animation_library()
	_npc = NPCScene.instantiate()
	_npc.profile = BossProfile
	_npc.global_position = Vector2(100.0, 100.0)
	_npc.move_speed = 240.0
	_npc.pause_seconds = 0.0
	var patrol_offsets: Array[Vector2] = [Vector2(96.0, 0.0), Vector2(144.0, 24.0)]
	_npc.patrol_offsets = patrol_offsets
	root.add_child(_npc)

	await process_frame

	var start_position: Vector2 = _npc.global_position
	for i in range(4):
		await physics_frame

	if _npc.global_position.distance_to(start_position) <= 0.1:
		_fail("Boss NPC did not move along its patrol")

	_assert_equal(String(_npc.animation_controller.current_animation), "boss/boss-walk-right", "Boss walk animation")
	_free_npc()
	quit(0)


func _check_boss_animation_library() -> void:
	var library := BossProfile.get("animation_library") as AnimationLibrary
	if library == null:
		_fail("Boss profile has no animation library")
		return

	for prefix in ["boss-walk-", "boss-stand-idle-"]:
		for direction in ["right", "down-right", "down", "down-left", "left", "up-left", "up", "up-right"]:
			var animation_name: String = String(prefix) + String(direction)
			if not library.has_animation(animation_name):
				_fail("Boss animation missing: %s" % animation_name)
				return
			var animation := library.get_animation(animation_name)
			var texture_track := animation.find_track(NodePath("Sprite2D:texture"), Animation.TYPE_VALUE)
			var offset_track := animation.find_track(NodePath("Sprite2D:offset"), Animation.TYPE_VALUE)
			if texture_track < 0 or offset_track < 0:
				_fail("Boss animation %s missing texture or offset track" % animation_name)
				return
			if animation.track_get_key_count(texture_track) <= 0 or animation.track_get_key_count(offset_track) <= 0:
				_fail("Boss animation %s has no frame keys" % animation_name)
				return
			var texture := animation.track_get_key_value(texture_track, 0) as Texture2D
			if texture == null or not texture.resource_path.begins_with("res://images/characters/boss/"):
				_fail("Boss animation %s uses an embedded or invalid texture" % animation_name)
				return


func _free_npc() -> void:
	if _npc == null:
		return
	if _npc.get_parent() != null:
		_npc.get_parent().remove_child(_npc)
	_npc.free()
	_npc = null


func _assert_equal(actual: String, expected: String, label: String) -> void:
	if actual != expected:
		_fail("%s expected %s, got %s" % [label, expected, actual])


func _fail(message: String) -> void:
	_free_npc()
	push_error(message)
	quit(1)
