extends CharacterBody2D


const MAP_COLLISION := preload("res://scenes/shared/collision_map_layer.gd")

@export var move_speed: float = 200.0
@export var profile: Resource

var is_mouse_movement_active: bool = false
var last_direction: Vector2 = Vector2.RIGHT

@onready var sprite: Sprite2D = $Sprite2D
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var animation_controller = $AnimationController
@onready var movement_cursor = $MovementArrow
@onready var footstep_controller = $FootstepPlayer


func _ready() -> void:
	add_to_group("depth_composited_characters")
	apply_profile(resolve_profile())
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


func _physics_process(delta: float) -> void:
	var movement_direction := Vector2.ZERO
	var raw_mouse_movement_direction := Vector2.ZERO

	if is_mouse_movement_active:
		var mouse_pos = get_global_mouse_position()
		raw_mouse_movement_direction = (mouse_pos - global_position).normalized()
		movement_direction = snap_to_8_directions(raw_mouse_movement_direction)
	else:
		movement_direction = get_keyboard_movement_direction()

	if movement_direction != Vector2.ZERO:
		last_direction = movement_direction
		velocity = movement_direction * move_speed
		animation_controller.play_walk(movement_direction)
		footstep_controller.start_footsteps()
		if is_mouse_movement_active:
			movement_cursor.show_arrow(raw_mouse_movement_direction, movement_direction)
		else:
			movement_cursor.hide_arrow()
	else:
		velocity = Vector2.ZERO
		animation_controller.play_idle(last_direction)
		footstep_controller.stop_footsteps()
		movement_cursor.hide_arrow()

	velocity = MAP_COLLISION.constrain_body_motion(self, velocity * delta) / delta
	move_and_slide()


func resolve_profile() -> Resource:
	if profile != null:
		return profile
	var screen_manager := get_node_or_null("/root/ScreenManager")
	if screen_manager != null and screen_manager.has_method("get_selected_profile"):
		return screen_manager.get_selected_profile()
	return null


func apply_profile(selected_profile: Resource) -> void:
	if selected_profile == null:
		push_warning("Player has no CharacterProfile")
		return

	profile = selected_profile
	var initial_texture := profile.get("initial_texture") as Texture2D
	if initial_texture != null:
		sprite.texture = initial_texture

	var animation_library := profile.get("animation_library") as AnimationLibrary
	var profile_id := StringName(profile.get("id"))
	if animation_library != null:
		var library_name: StringName = profile_id
		if animation_player.has_animation_library(library_name):
			animation_player.remove_animation_library(library_name)
		animation_player.add_animation_library(library_name, animation_library)

	var library_prefix := ""
	if String(profile_id) != "":
		library_prefix = "%s/" % String(profile_id)

	animation_controller.configure(
		library_prefix + String(profile.get("idle_animation_prefix")),
		library_prefix + String(profile.get("walk_animation_prefix"))
	)
	footstep_controller.configure(
		String(profile.get("footstep_stream_path")),
		float(profile.get("footstep_loop_end_seconds"))
	)


func snap_to_8_directions(dir: Vector2) -> Vector2:
	return IsoDirection.snap_to_8_directions(dir)


func get_keyboard_movement_direction() -> Vector2:
	var input_direction := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if input_direction == Vector2.ZERO:
		return Vector2.ZERO
	return snap_to_8_directions(input_direction)


func start_mouse_movement() -> void:
	is_mouse_movement_active = true
	movement_cursor.start_drag()


func stop_mouse_movement() -> void:
	is_mouse_movement_active = false
	movement_cursor.stop_drag(get_player_viewport_position())


func get_player_viewport_position() -> Vector2:
	return get_global_transform_with_canvas().origin
