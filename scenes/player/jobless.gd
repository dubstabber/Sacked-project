extends CharacterBody2D


@export var move_speed: float = 300.0

const IDLE_ANIMATION_PREFIX := "jobless-idle1-atmen-"
const WALK_ANIMATION_PREFIX := "jobless-walk-"
const FOOTSTEP_STREAM_PATH := "res://audio/sfx/footsteps.wav"
const FOOTSTEP_LOOP_END_SECONDS := 3.915147
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

var is_moving: bool = false
var last_direction: Vector2 = Vector2.RIGHT
var current_animation: String = ""
var clock_driven_animation_frames: Dictionary = {}
var footstep_stream: AudioStream
var footstep_loop_active: bool = false

@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var sprite: Sprite2D = $Sprite2D
@onready var movement_arrow: Sprite2D = $MovementArrow
@onready var footstep_player: AudioStreamPlayer = $FootstepPlayer


func _ready() -> void:
	cache_clock_driven_animation_frames()
	load_footstep_stream()
	hide_movement_arrow()
	play_idle_animation(last_direction)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("mouse-movement"):
		is_moving = true
	elif event.is_action_released("mouse-movement"):
		is_moving = false


func _process(_delta: float) -> void:
	update_clock_driven_animation_frame()


func _physics_process(_delta: float) -> void:
	if is_moving:
		var mouse_pos = get_global_mouse_position()
		var raw_movement_direction = (mouse_pos - global_position).normalized()
		var movement_direction = snap_to_8_directions(raw_movement_direction)
		last_direction = movement_direction
		velocity = movement_direction * move_speed
		play_walk_animation(movement_direction)
		update_movement_arrow(raw_movement_direction, movement_direction)
	else:
		velocity = Vector2.ZERO
		play_idle_animation(last_direction)
		hide_movement_arrow()

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

	if anim_name != "":
		stop_footsteps()
	play_animation(anim_name)


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

	play_animation(anim_name)
	if anim_name != "":
		start_footsteps()


func update_movement_arrow(raw_direction: Vector2, snapped_direction: Vector2) -> void:
	var cursor_angle := get_movement_arrow_angle(snapped_direction)
	var arrow_direction := raw_direction
	if arrow_direction == Vector2.ZERO:
		arrow_direction = snapped_direction
	movement_arrow.texture = MOVEMENT_ARROW_TEXTURES.get(cursor_angle)
	movement_arrow.position = arrow_direction * MOVEMENT_ARROW_DISTANCE
	movement_arrow.visible = movement_arrow.texture != null


func hide_movement_arrow() -> void:
	movement_arrow.visible = false


func get_movement_arrow_angle(direction: Vector2) -> int:
	var index = int(round(direction.angle() / (PI / 4)))

	match index:
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
		-1:
			return 0

	return 45


func play_animation(anim_name: String) -> void:
	if anim_name == "":
		return

	if is_clock_driven_animation(anim_name):
		current_animation = anim_name
		if animation_player.is_playing():
			animation_player.stop()
		update_clock_driven_animation_frame()
		return

	if anim_name != current_animation:
		current_animation = anim_name
		animation_player.play(anim_name)


func is_clock_driven_animation(anim_name: String) -> bool:
	return anim_name.begins_with(WALK_ANIMATION_PREFIX) or anim_name.begins_with(IDLE_ANIMATION_PREFIX)


func update_clock_driven_animation_frame() -> void:
	if not is_clock_driven_animation(current_animation):
		return

	var animation_frame_data: Dictionary = clock_driven_animation_frames.get(current_animation, {})
	var frames: Array = animation_frame_data.get("frames", [])
	var animation_length := float(animation_frame_data.get("length", 0.0))
	if frames.is_empty() or animation_length <= 0.0:
		return

	var animation_clock := get_global_animation_time()
	var animation_time := fposmod(animation_clock, animation_length)
	var frame_index := 0
	for index in range(frames.size()):
		if float(frames[index]["time"]) > animation_time:
			break
		frame_index = index

	var frame: Dictionary = frames[frame_index]
	sprite.texture = frame["texture"]
	sprite.offset = frame["offset"]


func load_footstep_stream() -> void:
	var stream := AudioStreamWAV.load_from_file(FOOTSTEP_STREAM_PATH)
	if stream == null:
		push_warning("Unable to load jobless footstep stream: %s" % FOOTSTEP_STREAM_PATH)
		return

	var loop_end_frame := int(round(FOOTSTEP_LOOP_END_SECONDS * stream.mix_rate))
	stream.loop_begin = 0
	stream.loop_end = clampi(loop_end_frame, 1, int(round(stream.get_length() * stream.mix_rate)))
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD

	footstep_stream = stream
	footstep_player.stream = footstep_stream


func start_footsteps() -> void:
	if footstep_player.stream == null:
		return
	if footstep_loop_active:
		return
	footstep_player.play()
	footstep_loop_active = true


func stop_footsteps() -> void:
	footstep_loop_active = false
	if footstep_player.playing:
		footstep_player.stop()


func cache_clock_driven_animation_frames() -> void:
	for animation_name in animation_player.get_animation_list():
		var anim_name := String(animation_name)
		if not is_clock_driven_animation(anim_name):
			continue

		var animation := animation_player.get_animation(anim_name)
		var texture_track := animation.find_track(NodePath("Sprite2D:texture"), Animation.TYPE_VALUE)
		var offset_track := animation.find_track(NodePath("Sprite2D:offset"), Animation.TYPE_VALUE)
		if texture_track < 0 or offset_track < 0:
			continue

		var frame_count = min(animation.track_get_key_count(texture_track), animation.track_get_key_count(offset_track))
		if frame_count <= 0:
			continue

		var frames: Array = []
		for frame_index in range(frame_count):
			frames.append({
				"time": animation.track_get_key_time(texture_track, frame_index),
				"texture": animation.track_get_key_value(texture_track, frame_index),
				"offset": animation.track_get_key_value(offset_track, frame_index),
			})

		clock_driven_animation_frames[anim_name] = {
			"length": animation.length,
			"frames": frames,
		}


func get_global_animation_time() -> float:
	return Time.get_ticks_usec() * 0.000001
