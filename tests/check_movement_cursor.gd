extends SceneTree


const CursorScript := preload("res://scenes/player/movement_cursor.gd")
const EPSILON := 0.001

var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var cursor := Sprite2D.new()
	cursor.set_script(CursorScript)

	_assert_vector_close(cursor.get_movement_arrow_position(0.0), Vector2(0.0, -40.0), "phase 0")
	_assert_vector_close(cursor.get_movement_arrow_position(2.0), Vector2(40.0, 0.0), "phase 2")
	_assert_vector_close(cursor.get_movement_arrow_position(4.0), Vector2(0.0, 40.0), "phase 4")
	_assert_vector_close(cursor.get_movement_arrow_position(6.0), Vector2(-40.0, 0.0), "phase 6")

	_assert_equal(cursor.get_movement_arrow_angle_for_direction(Vector2(48.0, -24.0).normalized()), 0, "iso N cursor")
	_assert_equal(cursor.get_movement_arrow_angle_for_direction(Vector2(96.0, 0.0).normalized()), 45, "iso NE cursor")
	_assert_equal(cursor.get_movement_arrow_angle_for_direction(Vector2(48.0, 24.0).normalized()), 90, "iso E cursor")
	_assert_equal(cursor.get_movement_arrow_angle_for_direction(Vector2(0.0, 48.0).normalized()), 135, "iso SE cursor")
	_assert_equal(cursor.get_movement_arrow_angle_for_direction(Vector2(-48.0, 24.0).normalized()), 180, "iso S cursor")
	_assert_equal(cursor.get_movement_arrow_angle_for_direction(Vector2(-96.0, 0.0).normalized()), 225, "iso SW cursor")
	_assert_equal(cursor.get_movement_arrow_angle_for_direction(Vector2(-48.0, -24.0).normalized()), 270, "iso W cursor")
	_assert_equal(cursor.get_movement_arrow_angle_for_direction(Vector2(0.0, -48.0).normalized()), 315, "iso NW cursor")

	var first_position: Vector2 = cursor.get_movement_arrow_position(1.10)
	var second_position: Vector2 = cursor.get_movement_arrow_position(1.25)
	if first_position.distance_to(second_position) <= 1.0:
		_fail("nearby phases should still move the arrow smoothly")

	root.add_child(cursor)
	await _check_the_ring_holds_the_pointer(cursor)

	cursor.queue_free()
	await process_frame
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	quit(1 if _failures else 0)


# sub_406510 hides the cursor for as long as the ring is up (game+15084 = 0 at 0x4066B0) and
# sub_4066D0's close shows and re-centres it. Headless, Input.mouse_mode always reads back as
# visible, so these read the cursor's own bookkeeping instead.
func _check_the_ring_holds_the_pointer(cursor: Sprite2D) -> void:
	_assert_false(cursor.is_menu_captured(), "the pointer starts free")

	cursor.capture_for_menu()
	_assert_true(cursor.is_menu_captured(), "opening the ring captures the pointer")
	_assert_equal(cursor.menu_pointer_mode(), Input.MOUSE_MODE_CAPTURED, "a running ring takes relative motion")
	_assert_equal(cursor.requested_mouse_mode, Input.MOUSE_MODE_CAPTURED, "opening the ring asks for a captured pointer")

	# P and the quit prompt freeze the ring with the cursor still hidden.
	paused = true
	await process_frame
	_assert_true(cursor.is_menu_captured(), "a pause does not close the ring")
	_assert_equal(cursor.menu_pointer_mode(), Input.MOUSE_MODE_HIDDEN, "a paused ring hands the pointer back, hidden")
	_assert_equal(cursor.requested_mouse_mode, Input.MOUSE_MODE_HIDDEN, "the pause itself hides the pointer")
	paused = false
	await process_frame
	_assert_equal(cursor.menu_pointer_mode(), Input.MOUSE_MODE_CAPTURED, "unpausing captures it again")
	_assert_equal(cursor.requested_mouse_mode, Input.MOUSE_MODE_CAPTURED, "the unpause itself captures it again")

	# A stray right-button release must not show the pointer over an open ring.
	cursor.stop_drag(Vector2(400.0, 300.0))
	_assert_true(cursor.is_menu_captured(), "a release while the ring is up leaves the pointer captured")
	_assert_false(cursor.visible, "and still hides the walk arrow")

	cursor.release_from_menu(Vector2(400.0, 300.0), false)
	_assert_false(cursor.is_menu_captured(), "closing the ring releases the pointer")
	_assert_equal(cursor.requested_mouse_mode, Input.MOUSE_MODE_VISIBLE, "closing the ring shows the pointer")
	cursor.release_from_menu(Vector2(400.0, 300.0), false)
	_assert_false(cursor.is_menu_captured(), "releasing twice is harmless")

	# A right press closes the ring and starts a walk, which keeps the pointer hidden.
	cursor.capture_for_menu()
	cursor.release_from_menu(Vector2(400.0, 300.0), true)
	_assert_equal(cursor.requested_mouse_mode, Input.MOUSE_MODE_HIDDEN, "a ring closed by a walk leaves the pointer hidden")
	cursor.show_main_cursor()


func _assert_vector_close(actual: Vector2, expected: Vector2, label: String) -> void:
	if actual.distance_to(expected) > EPSILON:
		_fail("%s expected %s, got %s" % [label, expected, actual])


func _assert_equal(actual: int, expected: int, label: String) -> void:
	if actual != expected:
		_fail("%s expected %d, got %d" % [label, expected, actual])


func _assert_true(value: bool, label: String) -> void:
	if not value:
		_fail("%s expected true" % label)


func _assert_false(value: bool, label: String) -> void:
	if value:
		_fail("%s expected false" % label)


func _fail(message: String) -> void:
	_failures += 1
	push_error(message)
