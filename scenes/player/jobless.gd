extends CharacterBody2D


@export var move_speed: float = 300.0

var is_moving: bool = false
var last_direction: Vector2 = Vector2.RIGHT
var current_animation: String = ""

@onready var animation_player: AnimationPlayer = $AnimationPlayer


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("mouse-movement"):
		is_moving = true
	elif event.is_action_released("mouse-movement"):
		is_moving = false


func _physics_process(delta: float) -> void:
	if is_moving:
		var mouse_pos = get_global_mouse_position()
		var direction = (mouse_pos - global_position).normalized()
		direction = snap_to_8_directions(direction)
		last_direction = direction
		velocity = direction * move_speed
		play_walk_animation(direction)
	else:
		velocity = Vector2.ZERO
		play_idle_animation(last_direction)
	
	move_and_slide()


func snap_to_8_directions(dir: Vector2) -> Vector2:
	var angle = dir.angle()
	var index = int(round(angle / (PI / 4))) % 8
	var snapped_angle = index * PI / 4
	return Vector2.RIGHT.rotated(snapped_angle)


func play_idle_animation(direction: Vector2) -> void:
	var angle = direction.angle()
	var index = int(round(angle / (PI / 4))) % 8
	var anim_name: String = ""
	
	match index:
		0:  # Right
			anim_name = "jobless-idle1-atmen-right"
		1:  # Down-Right
			anim_name = "jobless-idle1-atmen-down-right"
		2:  # Down
			anim_name = "jobless-idle1-atmen-down"
		3:  # Down-Left
			anim_name = "jobless-idle1-atmen-down-left"
		4, -4:  # Left
			anim_name = "jobless-idle1-atmen-left"
		-3:  # Up-Left
			anim_name = "jobless-idle1-atmen-up-left"
		-2:  # Up
			anim_name = "jobless-idle1-atmen-up"
		-1:  # Up-Right
			anim_name = "jobless-idle1-atmen-up-right"
	
	if anim_name != current_animation:
		current_animation = anim_name
		animation_player.play(anim_name)


func play_walk_animation(direction: Vector2) -> void:
	var angle = direction.angle()
	var index = int(round(angle / (PI / 4))) % 8
	var anim_name: String = ""
	
	match index:
		0:  # Right
			anim_name = "jobless-walk-right"
		1:  # Down-Right
			anim_name = "jobless-walk-down-right"
		2:  # Down
			anim_name = "jobless-walk-down"
		3:  # Down-Left
			anim_name = "jobless-walk-down-left"
		4, -4:  # Left
			anim_name = "jobless-walk-left"
		-3:  # Up-Left
			anim_name = "jobless-walk-up-left"
		-2:  # Up
			anim_name = "jobless-walk-up"
		-1:  # Up-Right
			anim_name = "jobless-walk-up-right"
		
	
	if anim_name != current_animation:
		current_animation = anim_name
		animation_player.play(anim_name)
