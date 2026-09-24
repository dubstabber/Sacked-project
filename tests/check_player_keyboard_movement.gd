extends SceneTree


const PlayerScene := preload("res://scenes/player/player.tscn")
const JoblessProfile := preload("res://scenes/player/profiles/jobless.tres")
const EPSILON := 0.001

var _player
var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_player = PlayerScene.instantiate()
	_player.profile = JoblessProfile
	_player.global_position = Vector2(100.0, 100.0)
	root.add_child(_player)

	await process_frame
	_player.set_physics_process(false)
	_player.footstep_controller.stop_footsteps()
	_player.footstep_controller.stream = null
	_release_movement_actions()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	_check_keyboard_movement_leaves_cursor_alone()
	_check_mouse_movement_wins_over_keyboard()
	_check_keyboard_resumes_after_mouse_release()
	_check_idle_without_movement_input()
	_check_open_ring_holds_the_player()

	_free_player()
	_release_movement_actions()
	quit(1 if _failures else 0)


func _check_keyboard_movement_leaves_cursor_alone() -> void:
	Input.action_press("move_right")
	_player._physics_process(0.016)

	var expected_direction: Vector2 = _player.snap_to_8_directions(Vector2.RIGHT)
	_assert_vector_close(_player.last_direction, expected_direction, "keyboard movement direction")
	_assert_vector_close(_player.velocity.normalized(), expected_direction, "keyboard velocity")
	_assert_equal(Input.mouse_mode, Input.MOUSE_MODE_VISIBLE, "keyboard movement mouse mode")
	_assert_false(_player.movement_cursor.visible, "keyboard movement arrow hidden")

	Input.action_release("move_right")


func _check_mouse_movement_wins_over_keyboard() -> void:
	_player.global_position = Vector2(100.0, 100.0)
	_player.get_viewport().warp_mouse(Vector2(220.0, 100.0))
	Input.action_press("move_left")
	_player.start_mouse_movement()

	var raw_mouse_direction: Vector2 = (_player.get_global_mouse_position() - _player.global_position).normalized()
	var expected_direction: Vector2 = _player.snap_to_8_directions(raw_mouse_direction)
	_player._physics_process(0.016)

	_assert_vector_close(_player.last_direction, expected_direction, "mouse movement wins over keyboard")
	_assert_true(_player.movement_cursor.visible, "mouse movement arrow visible")


func _check_keyboard_resumes_after_mouse_release() -> void:
	_player.stop_mouse_movement()
	_player._physics_process(0.016)

	var expected_direction: Vector2 = _player.snap_to_8_directions(Vector2.LEFT)
	_assert_vector_close(_player.last_direction, expected_direction, "keyboard resumes after mouse release")
	_assert_vector_close(_player.velocity.normalized(), expected_direction, "keyboard resumed velocity")
	_assert_false(_player.movement_cursor.visible, "keyboard resumed arrow hidden")

	Input.action_release("move_left")


func _check_idle_without_movement_input() -> void:
	_player._physics_process(0.016)

	_assert_vector_close(_player.velocity, Vector2.ZERO, "idle velocity")
	_assert_false(_player.movement_cursor.visible, "idle arrow hidden")


# sub_41B240's state 1 only rewrites the hover text: with the ring up the arrows belong to it
# and the player stands, facing wherever state 0 turned him.
func _check_open_ring_holds_the_player() -> void:
	var facing: Vector2 = _player.snap_to_8_directions(Vector2.UP)
	_player.last_direction = facing
	_player.menu_open = true
	Input.action_press("move_right")
	_player._physics_process(0.016)

	_assert_vector_close(_player.velocity, Vector2.ZERO, "an open ring holds the player still")
	_assert_vector_close(_player.last_direction, facing, "an open ring keeps the facing")
	_assert_false(_player.movement_cursor.visible, "an open ring shows no walk arrow")
	_assert_true(
		String(_player.animation_controller.current_animation).ends_with("-up"),
		"an open ring leaves the player idling, got %s" % _player.animation_controller.current_animation
	)

	_player.menu_open = false
	_player._physics_process(0.016)
	var expected_direction: Vector2 = _player.snap_to_8_directions(Vector2.RIGHT)
	_assert_vector_close(_player.velocity.normalized(), expected_direction, "the arrows walk again once the ring shuts")
	Input.action_release("move_right")


func _release_movement_actions() -> void:
	for action in ["move_up", "move_down", "move_left", "move_right"]:
		Input.action_release(action)


func _free_player() -> void:
	if _player == null:
		return
	if _player.footstep_controller != null:
		_player.footstep_controller.stop_footsteps()
		_player.footstep_controller.stream = null
	if _player.get_parent() != null:
		_player.get_parent().remove_child(_player)
	_player.free()
	_player = null


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
