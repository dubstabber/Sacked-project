extends SceneTree


const CursorScript := preload("res://scenes/player/movement_cursor.gd")
const EPSILON := 0.001


func _init() -> void:
	var cursor := Sprite2D.new()
	cursor.set_script(CursorScript)

	_assert_vector_close(cursor.get_movement_arrow_position(0.0), Vector2(0.0, -40.0), "phase 0")
	_assert_vector_close(cursor.get_movement_arrow_position(2.0), Vector2(40.0, 0.0), "phase 2")
	_assert_vector_close(cursor.get_movement_arrow_position(4.0), Vector2(0.0, 40.0), "phase 4")
	_assert_vector_close(cursor.get_movement_arrow_position(6.0), Vector2(-40.0, 0.0), "phase 6")

	_assert_equal(cursor.get_movement_arrow_angle_for_direction(Vector2(47.0, -24.0).normalized()), 0, "iso N cursor")
	_assert_equal(cursor.get_movement_arrow_angle_for_direction(Vector2(94.0, 0.0).normalized()), 45, "iso NE cursor")
	_assert_equal(cursor.get_movement_arrow_angle_for_direction(Vector2(47.0, 24.0).normalized()), 90, "iso E cursor")
	_assert_equal(cursor.get_movement_arrow_angle_for_direction(Vector2(0.0, 48.0).normalized()), 135, "iso SE cursor")
	_assert_equal(cursor.get_movement_arrow_angle_for_direction(Vector2(-47.0, 24.0).normalized()), 180, "iso S cursor")
	_assert_equal(cursor.get_movement_arrow_angle_for_direction(Vector2(-94.0, 0.0).normalized()), 225, "iso SW cursor")
	_assert_equal(cursor.get_movement_arrow_angle_for_direction(Vector2(-47.0, -24.0).normalized()), 270, "iso W cursor")
	_assert_equal(cursor.get_movement_arrow_angle_for_direction(Vector2(0.0, -48.0).normalized()), 315, "iso NW cursor")

	var first_position: Vector2 = cursor.get_movement_arrow_position(1.10)
	var second_position: Vector2 = cursor.get_movement_arrow_position(1.25)
	if first_position.distance_to(second_position) <= 1.0:
		_fail("nearby phases should still move the arrow smoothly")

	cursor.free()
	quit(0)


func _assert_vector_close(actual: Vector2, expected: Vector2, label: String) -> void:
	if actual.distance_to(expected) > EPSILON:
		_fail("%s expected %s, got %s" % [label, expected, actual])


func _assert_equal(actual: int, expected: int, label: String) -> void:
	if actual != expected:
		_fail("%s expected %d, got %d" % [label, expected, actual])


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
