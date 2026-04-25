extends CharacterBody2D


@export var move_speed: float = 300.0

var is_moving: bool = false
var last_direction: Vector2 = Vector2.RIGHT

@onready var animation_controller = $AnimationController
@onready var movement_cursor = $MovementArrow
@onready var footstep_controller = $FootstepPlayer


func _ready() -> void:
	movement_cursor.show_main_cursor()
	movement_cursor.hide_arrow()
	animation_controller.play_idle(last_direction)


func _exit_tree() -> void:
	movement_cursor.show_main_cursor()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("mouse-movement"):
		start_mouse_movement()
	elif event.is_action_released("mouse-movement"):
		stop_mouse_movement()


func _physics_process(_delta: float) -> void:
	if is_moving:
		var mouse_pos = get_global_mouse_position()
		var raw_movement_direction = (mouse_pos - global_position).normalized()
		var movement_direction = snap_to_8_directions(raw_movement_direction)
		last_direction = movement_direction
		velocity = movement_direction * move_speed
		animation_controller.play_walk(movement_direction)
		footstep_controller.start_footsteps()
		movement_cursor.show_arrow(raw_movement_direction, movement_direction)
	else:
		velocity = Vector2.ZERO
		animation_controller.play_idle(last_direction)
		footstep_controller.stop_footsteps()
		movement_cursor.hide_arrow()

	move_and_slide()


func snap_to_8_directions(dir: Vector2) -> Vector2:
	var angle = dir.angle()
	var index = int(round(angle / (PI / 4))) % 8
	var snapped_angle = index * PI / 4
	return Vector2.RIGHT.rotated(snapped_angle)


func start_mouse_movement() -> void:
	is_moving = true
	movement_cursor.start_drag()


func stop_mouse_movement() -> void:
	is_moving = false
	movement_cursor.stop_drag(get_player_viewport_position())


func get_player_viewport_position() -> Vector2:
	return get_global_transform_with_canvas().origin
