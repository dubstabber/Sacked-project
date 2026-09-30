extends CharacterBody2D


const MAP_COLLISION := preload("res://scenes/shared/collision_map_layer.gd")

@export_range(0.0, 20.0, 0.1, "suffix:tiles/s") var move_speed_tiles: float = 3.0
@export var profile: Resource

var is_mouse_movement_active: bool = false
# Set while a prank is running: the original plays an animation there and takes input away.
var input_locked: bool = false
# Set while the action ring is up: sub_41B240's state 1 only rewrites the hover text, so the
# player stands and the arrow keys belong to the ring.
var menu_open: bool = false
# Set while the pill holds the player: its states change no sound, so a footstep already
# sounding goes on until the player is free again.
var footsteps_held: bool = false
var last_direction: Vector2 = Vector2.RIGHT
# Logical units above the floor. sub_41A2D0 takes 24 px a unit off the projected y before it
# derives both the draw anchor and the depth base, and sub_41D500 draws the shadow from that
# same anchor. The node stays on the ground, so reach, sight, being noticed and the camera
# all still measure from x/z as the original does.
var height := 0.0:
	set(value):
		height = value
		var lift := Vector2(0.0, -24.0 * value)
		for child in [^"Sprite2D", ^"Shadow"]:
			var node := get_node_or_null(child) as Node2D
			if node != null:
				node.position = lift

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


# A paused player never sees the right button's press or release, but sub_403FB0 rebuilds the
# walk bit from the polled button every frame (0x403FE4, 0x4043CC), so a walk never outlives
# the button across the pause key, the quit prompt or the duel, and a button still held when
# they end walks the player. An open ring takes that same bit as its cancel (0x40450C) and
# the walk follows once it has shut, as a press on the ring does in _input.
func _notification(what: int) -> void:
	if what != NOTIFICATION_UNPAUSED:
		return
	resync_mouse_movement()


func resync_mouse_movement() -> void:
	var held := Input.is_action_pressed("mouse-movement")
	if is_mouse_movement_active and not held:
		stop_mouse_movement()
	elif held and not is_mouse_movement_active and not input_locked:
		start_mouse_movement()


# An ability stops the player where they stand, even mid-walk: only the free-mode tick moves
# them (sub_41B0C0 at 0x41B125), and the next frame's `and al, 0Fh` (0x403FC1) wipes a
# right-button walk. The arrow cannot show while the mode runs (0x4043B1-0x4043C2), and the
# pointer is not re-centred. Smoking and urinating stop the footstep; the pill's states touch
# no sound, and the first free tick stops it (0x41B189). See docs/player-ability-reference.md.
func hold_for_ability(stop_footsteps := true) -> void:
	input_locked = true
	is_mouse_movement_active = false
	velocity = Vector2.ZERO
	movement_cursor.hide_arrow()
	footsteps_held = not stop_footsteps
	if stop_footsteps:
		footstep_controller.stop_footsteps()


# A right button still held when the ability ends raises the walk again on the next mouse
# event, and the first mode-0 tick walks.
func release_from_ability() -> void:
	input_locked = false
	footsteps_held = false
	resync_mouse_movement()


func _input(event: InputEvent) -> void:
	if input_locked:
		# sub_403FB0 re-centres both cursors on every right release whatever the player is
		# doing (0x40447E-0x4044A3), so a release under a prank or an ability puts the pointer
		# back on the player without starting a walk.
		if event.is_action_released("mouse-movement"):
			movement_cursor.recentre(get_player_viewport_position())
		return
	if event.is_action_pressed("mouse-movement"):
		start_mouse_movement()
	elif event.is_action_released("mouse-movement"):
		stop_mouse_movement()


func _physics_process(delta: float) -> void:
	var movement_direction := Vector2.ZERO
	var raw_mouse_movement_direction := Vector2.ZERO

	if input_locked:
		# The prank or ability controller owns the animation while it holds the player.
		velocity = Vector2.ZERO
		if not footsteps_held:
			footstep_controller.stop_footsteps()
		movement_cursor.hide_arrow()
		return
	if is_mouse_movement_active:
		var mouse_pos = get_global_mouse_position()
		raw_mouse_movement_direction = (mouse_pos - global_position).normalized()
		movement_direction = snap_to_8_directions(raw_mouse_movement_direction)
	elif not menu_open:
		movement_direction = get_keyboard_movement_direction()

	if movement_direction != Vector2.ZERO:
		last_direction = movement_direction
		velocity = IsoDirection.screen_velocity(movement_direction, move_speed_tiles)
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

	var actions := profile.get("action_animation_library") as AnimationLibrary
	if actions != null:
		var action_library_name := StringName("%s-actions" % profile_id)
		if animation_player.has_animation_library(action_library_name):
			animation_player.remove_animation_library(action_library_name)
		animation_player.add_animation_library(action_library_name, actions)

	var library_prefix := ""
	if String(profile_id) != "":
		library_prefix = "%s/" % String(profile_id)

	# Urinating's PISS#1 keeps the start of 0 Animation_AllocRegister gives it (0x42E430): nothing
	# stores to it, so its frame is floor((now mod 0.375) * 16), locked to the clock like the idle
	# and the walk. See docs/player-ability-reference.md, "Mode 3: urinating".
	animation_controller.configure(
		library_prefix + String(profile.get("idle_animation_prefix")),
		library_prefix + String(profile.get("walk_animation_prefix")),
		PackedStringArray([action_animation_prefix("piss-1")])
	)
	footstep_controller.configure(
		String(profile.get("footstep_stream_path")),
		float(profile.get("footstep_loop_end_seconds"))
	)


# The prank controller drives these: the library is registered as "<id>-actions" and its
# clips are named "<id>-<action>-<direction>".
func play_action_animation(action: String, direction: Vector2) -> bool:
	var anim_name := action_animation_name(action, direction)
	if anim_name == "":
		return false
	animation_controller.play_animation(anim_name)
	return true


func action_animation_name(action: String, direction: Vector2) -> String:
	if profile == null:
		return ""
	var anim_name: String = animation_controller.get_directional_animation_name(action_animation_prefix(action), direction)
	return anim_name if animation_player.has_animation(anim_name) else ""


func action_animation_prefix(action: String) -> String:
	var id := String(profile.get("id")) if profile != null else ""
	return "%s-actions/%s-%s-" % [id, id, action]


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
