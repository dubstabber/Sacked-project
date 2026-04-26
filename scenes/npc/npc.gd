extends CharacterBody2D


@export var profile: Resource
@export var move_speed: float = 110.0
@export var patrol_offsets: Array[Vector2] = []
@export var arrival_distance: float = 6.0
@export var pause_seconds: float = 0.4
@export var initial_direction: Vector2 = Vector2.RIGHT

var last_direction: Vector2 = Vector2.RIGHT
var _patrol_origin := Vector2.ZERO
var _patrol_targets: Array[Vector2] = []
var _target_index := 0
var _pause_remaining := 0.0

@onready var sprite: Sprite2D = $Sprite2D
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var animation_controller = $AnimationController


func _ready() -> void:
	add_to_group("depth_composited_characters")
	last_direction = IsoDirection.snap_to_8_directions(initial_direction)
	_patrol_origin = global_position
	_build_patrol_targets()
	apply_profile(profile)
	animation_controller.play_idle(last_direction)


func _physics_process(delta: float) -> void:
	if _patrol_targets.is_empty():
		velocity = Vector2.ZERO
		animation_controller.play_idle(last_direction)
		return

	if _pause_remaining > 0.0:
		_pause_remaining = maxf(_pause_remaining - delta, 0.0)
		velocity = Vector2.ZERO
		animation_controller.play_idle(last_direction)
		return

	var target := _patrol_targets[_target_index]
	var to_target := target - global_position
	if to_target.length_squared() <= arrival_distance * arrival_distance:
		global_position = target
		_advance_target()
		return

	var snapped_direction := IsoDirection.snap_to_8_directions(to_target.normalized())
	last_direction = snapped_direction
	velocity = snapped_direction * move_speed
	animation_controller.play_walk(snapped_direction)
	move_and_slide()


func apply_profile(selected_profile: Resource) -> void:
	if selected_profile == null:
		push_warning("NPC has no CharacterProfile")
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


func _build_patrol_targets() -> void:
	_patrol_targets.clear()
	for offset in patrol_offsets:
		_patrol_targets.append(_patrol_origin + offset)


func _advance_target() -> void:
	velocity = Vector2.ZERO
	animation_controller.play_idle(last_direction)
	_target_index = (_target_index + 1) % _patrol_targets.size()
	_pause_remaining = pause_seconds
