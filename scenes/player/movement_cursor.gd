extends Sprite2D


const MOVEMENT_ARROW_DISTANCE := 40.0
const MOVEMENT_ARROW_TEXTURES := {
	0: preload("res://images/gui/cursors/active/CO_GUI_Cursor_Active_000#000.png"),
	45: preload("res://images/gui/cursors/active/CO_GUI_Cursor_Active_045#000.png"),
	90: preload("res://images/gui/cursors/active/CO_GUI_Cursor_Active_090#000.png"),
	135: preload("res://images/gui/cursors/active/CO_GUI_Cursor_Active_135#000.png"),
	180: preload("res://images/gui/cursors/active/CO_GUI_Cursor_Active_180#000.png"),
	225: preload("res://images/gui/cursors/active/CO_GUI_Cursor_Active_225#000.png"),
	270: preload("res://images/gui/cursors/active/CO_GUI_Cursor_Active_270#000.png"),
	315: preload("res://images/gui/cursors/active/CO_GUI_Cursor_Active_315#000.png"),
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


func show_arrow(raw_direction: Vector2, snapped_direction: Vector2) -> void:
	var arrow_direction := raw_direction
	if arrow_direction == Vector2.ZERO:
		arrow_direction = snapped_direction

	var cursor_phase := get_movement_arrow_phase(arrow_direction)
	var cursor_angle := get_movement_arrow_angle_from_phase(cursor_phase)
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
	get_viewport().warp_mouse(player_viewport_pos)
	show_main_cursor()


func hide_main_cursor() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN


func show_main_cursor() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func get_movement_arrow_phase(direction: Vector2) -> float:
	return fposmod(direction.angle() / (PI / 4.0) + 1.5, 8.0)


func get_movement_arrow_angle_from_phase(cursor_phase: float) -> int:
	return int(floor(cursor_phase)) * 45


func get_movement_arrow_position(cursor_phase: float) -> Vector2:
	var cursor_radians := cursor_phase * PI / 4.0
	return Vector2(sin(cursor_radians), -cos(cursor_radians)) * MOVEMENT_ARROW_DISTANCE
