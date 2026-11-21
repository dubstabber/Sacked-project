extends SceneTree

# Which click box answers when several hold the cursor. sub_42BF20 walks buckets of
# depth >> 4 front to back and, inside a bucket, the box registered last first; items
# register in world order and the agents after them. See docs/player-action-reference.md,
# "Which box answers".

const LEVEL := preload("res://scenes/level_8.tscn")
const PRANK_CONTROLLER := preload("res://scenes/player/prank_controller.gd")

var _failures := 0
var _level: Node
var _controller: Node
var _player: Node2D


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_check_the_bucket_formula()
	_level = LEVEL.instantiate()
	var runtime := _level.get_node_or_null("LevelRuntime")
	if runtime != null:
		runtime.enabled = false
	root.add_child(_level)
	await process_frame
	_controller = get_first_node_in_group("player_actions")
	_player = _controller.get("_player") as Node2D
	_controller.set_process(false)
	await _check_the_soap_beats_its_sink()
	await _check_a_nearer_bucket_beats_a_later_box()
	root.remove_child(_level)
	_level.free()
	if _failures == 0:
		print("Pick order: depth buckets, the later box in a bucket, and level 8's soap over its sink passed")
	quit(1 if _failures else 0)


func _expect(condition: bool, label: String) -> void:
	if not condition:
		_failures += 1
		push_error(label)


func _check_the_bucket_formula() -> void:
	# 0.5 a row and 16 a bucket: buckets are 32 rows tall, edged at the camera's own row.
	_expect(PRANK_CONTROLLER.pick_bucket(0.0) == 3072, "the camera's own row is depth 49152, bucket 3072")
	_expect(PRANK_CONTROLLER.pick_bucket(1.0) == 3071, "one row down is depth 49151, the nearer bucket")
	_expect(PRANK_CONTROLLER.pick_bucket(32.9) == 3071, "sy truncates, so 32.9 rows down is still 3071")
	_expect(PRANK_CONTROLLER.pick_bucket(33.0) == 3070, "33 rows down is the next bucket")
	_expect(PRANK_CONTROLLER.pick_bucket(-0.9) == 3072, "sy truncates toward zero above the camera")
	_expect(PRANK_CONTROLLER.pick_bucket(-31.0) == 3072, "31 rows up is depth 49167, still bucket 3072")
	_expect(PRANK_CONTROLLER.pick_bucket(-32.0) == 3073, "32 rows up is one bucket farther")


func _object(node_name: String) -> Node2D:
	return _level.get_node("World/Objects/" + node_name) as Node2D


func _box(object: Node2D) -> Rect2:
	var sprite := object.get_node("Sprite2D") as Sprite2D
	return Rect2(sprite.to_global(sprite.offset), sprite.texture.get_size())


# Level 8's soap (ITEM46) sits on its sink (ITEM40) at the same x + z, so the two share a
# depth wherever the camera stands, and the soap, registered later, answers.
func _check_the_soap_beats_its_sink() -> void:
	var soap := _object("Object054Seife")
	var sink := _object("Object048Waschbecken")
	var centre := _box(soap).get_center()
	_expect(_box(sink).has_point(centre), "the soap's centre lies inside the sink's box too")
	for offset in [Vector2.ZERO, Vector2(37, 11), Vector2(-90, 140), Vector2(200, -75), Vector2(-13, -260)]:
		_player.global_position = soap.global_position + offset
		var front: Node2D = _controller._front_at(centre)
		_expect(front == soap, "with the camera at %s the soap answers, got %s" % [offset, front.name if front != null else "nothing"])


# Two boxes a whole bucket apart: the nearer one answers even though it registered first.
func _check_a_nearer_bucket_beats_a_later_box() -> void:
	var soap := _object("Object054Seife")
	var sink := _object("Object048Waschbecken")
	var centre := _box(soap).get_center()
	var home := sink.global_position
	sink.global_position = home + Vector2(0, 40)
	sink.get_node("Sprite2D").global_position -= Vector2(0, 40)
	_player.global_position = soap.global_position
	var front: Node2D = _controller._front_at(centre)
	_expect(front == sink, "a sink 40 rows nearer answers before the later soap, got %s" % [front.name if front != null else "nothing"])
	sink.get_node("Sprite2D").global_position += Vector2(0, 40)
	sink.global_position = home
