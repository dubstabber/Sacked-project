extends Sprite2D


const BUSY_CURSOR_TEXTURE := preload("res://images/gui/cursors/clock-000.png")
const BUSY_CURSOR_HOTSPOT := Vector2(16, 16)
# project.godot sets this as the cursor image, which a custom one has to be swapped back to.
const POINTER_CURSOR_TEXTURE := preload("res://images/gui/cursors/pointer.png")

const MOVEMENT_ARROW_DISTANCE := 40.0
const MOVEMENT_ARROW_TEXTURES := {
	0: preload("res://images/gui/cursors/active/active-000.png"),
	45: preload("res://images/gui/cursors/active/active-045.png"),
	90: preload("res://images/gui/cursors/active/active-090.png"),
	135: preload("res://images/gui/cursors/active/active-135.png"),
	180: preload("res://images/gui/cursors/active/active-180.png"),
	225: preload("res://images/gui/cursors/active/active-225.png"),
	270: preload("res://images/gui/cursors/active/active-270.png"),
	315: preload("res://images/gui/cursors/active/active-315.png"),
}
const MOVEMENT_ARROW_OFFSETS := {
	0: Vector2(-10, -17),
	45: Vector2(-10, -9),
	90: Vector2(-10, -5),
	135: Vector2(-18, -5),
	180: Vector2(-36, -5),
	225: Vector2(-50, -9),
	270: Vector2(-36, -16),
	315: Vector2(-19, -22),
}

var _menu_capture := false
# Headless, Input.mouse_mode always reads back VISIBLE, so the checks read what was asked for.
var requested_mouse_mode: Input.MouseMode = Input.MOUSE_MODE_VISIBLE


func _notification(what: int) -> void:
	if not _menu_capture:
		return
	if what == NOTIFICATION_PAUSED or what == NOTIFICATION_UNPAUSED:
		_set_pointer_mode(menu_pointer_mode())


func is_menu_captured() -> bool:
	return _menu_capture


# sub_406510 zeroes game+15084 (0x4066B0), the flag sub_415500 tests (0x41551A) before it
# draws any cursor, while sub_415400 keeps integrating the raw deltas that turn the ring.
# CAPTURED is both: no pointer, and relative motion that does not stop at the window edge.
func capture_for_menu() -> void:
	_menu_capture = true
	_set_pointer_mode(menu_pointer_mode())


# sub_4066D0's closing branch sets the flag back (0x406854) and sub_4155F0 re-centres the
# cursor on the screen (0x40685A), which is where the camera keeps the player. A walk the
# right button started keeps the pointer hidden.
func release_from_menu(player_viewport_pos: Vector2, dragging: bool) -> void:
	if not _menu_capture:
		return
	_menu_capture = false
	if dragging:
		hide_main_cursor()
	else:
		show_main_cursor()
	# X11 ignores a warp while the pointer is captured, so it has to follow the release.
	get_viewport().warp_mouse(player_viewport_pos)


# The pause key and the quit prompt freeze the ring with the cursor still hidden. A frozen
# ring cannot be turned, so it gives the pointer back to the desktop without showing it.
func menu_pointer_mode() -> Input.MouseMode:
	if is_inside_tree() and get_tree().paused:
		return Input.MOUSE_MODE_HIDDEN
	return Input.MOUSE_MODE_CAPTURED


func show_arrow(raw_direction: Vector2, snapped_direction: Vector2) -> void:
	var arrow_direction := raw_direction
	if arrow_direction == Vector2.ZERO:
		arrow_direction = snapped_direction
	if arrow_direction == Vector2.ZERO:
		hide_arrow()
		return

	var cursor_phase := get_movement_arrow_phase(arrow_direction)
	var cursor_angle := get_movement_arrow_angle_for_direction(snapped_direction)
	texture = MOVEMENT_ARROW_TEXTURES.get(cursor_angle)
	offset = MOVEMENT_ARROW_OFFSETS.get(cursor_angle, Vector2.ZERO)
	position = get_movement_arrow_position(cursor_phase)
	visible = texture != null


func hide_arrow() -> void:
	visible = false


func start_drag() -> void:
	hide_main_cursor()


func stop_drag(player_viewport_pos: Vector2) -> void:
	hide_arrow()
	# A release that lands while the ring holds the pointer must not hand it back.
	if _menu_capture:
		return
	get_viewport().warp_mouse(player_viewport_pos)
	show_main_cursor()


# sub_4154B0 mode 1: the clock, shown for as long as an action is running.
func show_busy_cursor() -> void:
	Input.set_custom_mouse_cursor(BUSY_CURSOR_TEXTURE, Input.CURSOR_ARROW, BUSY_CURSOR_HOTSPOT)


func hide_main_cursor() -> void:
	_set_pointer_mode(Input.MOUSE_MODE_HIDDEN)


func show_main_cursor() -> void:
	Input.set_custom_mouse_cursor(POINTER_CURSOR_TEXTURE, Input.CURSOR_ARROW)
	_set_pointer_mode(Input.MOUSE_MODE_VISIBLE)


func _set_pointer_mode(mode: Input.MouseMode) -> void:
	requested_mouse_mode = mode
	Input.mouse_mode = mode


func get_movement_arrow_phase(direction: Vector2) -> float:
	return fposmod(direction.angle() / (PI / 4.0) + 1.5, 8.0)


func get_movement_arrow_angle_for_direction(direction: Vector2) -> int:
	var direction_index := int(round(direction.angle() / (PI / 4.0))) % 8

	match direction_index:
		-1:
			return 0
		0:
			return 45
		1:
			return 90
		2:
			return 135
		3:
			return 180
		4, -4:
			return 225
		-3:
			return 270
		-2:
			return 315

	return 0


func get_movement_arrow_position(cursor_phase: float) -> Vector2:
	var cursor_radians := cursor_phase * PI / 4.0
	return Vector2(sin(cursor_radians), -cos(cursor_radians)) * MOVEMENT_ARROW_DISTANCE
