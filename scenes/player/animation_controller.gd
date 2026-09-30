extends Node


@export var idle_animation_prefix: String = ""
@export var walk_animation_prefix: String = ""
@export var sprite_path: NodePath
@export var animation_player_path: NodePath

var current_animation: String = ""
var clock_driven_animation_frames: Dictionary = {}
# Clips besides the idle and the walk whose start nothing ever moves off 0, so their frame
# follows the clock too.
var clock_driven_prefixes := PackedStringArray()
var _last_clock_animation := ""
var _last_clock_frame_index := -1
var _once: Dictionary = {}
var _once_frame_index := -1
# The clip speed +536, 1.0 by default (0x42E3C0). CObjectAnim_SelectFrameFromTime picks every
# frame from absolute time, (now - start) * fps * speed, so a clip at speed s shows what it would
# s times as far into its run, and a change of speed jumps the frame instead of easing it. A
# slowed agent's tick writes 0.2 (0x419D08-0x419D2E); the player's clips stay at 1. See
# docs/player-ability-reference.md, "What being slowed changes".
var speed_scale := 1.0
# How long the AnimationPlayer's clip has run, unscaled, on the clock the AnimationPlayer itself
# advances on, which stands still with the tree.
var _clip_elapsed := 0.0

@onready var sprite: Sprite2D = get_node(sprite_path)
@onready var animation_player: AnimationPlayer = get_node(animation_player_path)


func _ready() -> void:
	cache_clock_driven_animation_frames()


func _process(delta: float) -> void:
	_clip_elapsed += delta
	update_clock_driven_animation_frame()


func configure(idle_prefix: String, walk_prefix: String, other_clock_prefixes := PackedStringArray()) -> void:
	idle_animation_prefix = idle_prefix
	walk_animation_prefix = walk_prefix
	clock_driven_prefixes = other_clock_prefixes
	current_animation = ""
	_last_clock_animation = ""
	_last_clock_frame_index = -1
	cache_clock_driven_animation_frames()


func play_idle(direction: Vector2) -> void:
	play_animation(get_directional_animation_name(idle_animation_prefix, direction))


func play_walk(direction: Vector2) -> void:
	play_animation(get_directional_animation_name(walk_animation_prefix, direction))


func get_directional_animation_name(prefix: String, direction: Vector2) -> String:
	var angle = direction.angle()
	var index = int(round(angle / (PI / 4))) % 8

	match index:
		0:
			return prefix + "right"
		1:
			return prefix + "down-right"
		2:
			return prefix + "down"
		3:
			return prefix + "down-left"
		4, -4:
			return prefix + "left"
		-3:
			return prefix + "up-left"
		-2:
			return prefix + "up"
		-1:
			return prefix + "up-right"

	return ""


func play_animation(anim_name: String) -> void:
	if anim_name == "":
		return
	if anim_name != current_animation:
		_once = {}

	if is_clock_driven_animation(anim_name):
		if anim_name != current_animation:
			current_animation = anim_name
			_last_clock_animation = ""
			_last_clock_frame_index = -1
			if animation_player.is_playing():
				animation_player.stop()
			update_clock_driven_animation_frame()
			return
		if animation_player.is_playing():
			animation_player.stop()
		return

	if anim_name != current_animation:
		current_animation = anim_name
		animation_player.play(anim_name)
		_clip_elapsed = 0.0


# A clip played once on the caller's clock, the way CObjectAnim_SelectFrameFromTime runs a clip
# whose loop flag is cleared (0x407E10): frame trunc((now - start) * fps) until the count is
# reached, then the last frame held with the finished flag +556 raised (0x407F27). The
# AnimationPlayer would loop the clip as its ANIM says, so it is stopped and the frames are
# set from here. See docs/player-ability-reference.md.
func play_once(anim_name: String) -> bool:
	var data := _animation_frames(anim_name)
	if data.is_empty():
		return false
	if animation_player.is_playing():
		animation_player.stop()
	current_animation = anim_name
	_last_clock_animation = ""
	_last_clock_frame_index = -1
	_once = data
	_once_frame_index = -1
	show_once_frame(0.0)
	return true


# Shows the frame `elapsed` seconds into the clip play_once started, and answers whether it has
# run out.
func show_once_frame(elapsed: float) -> bool:
	if _once.is_empty():
		return true
	var frames: Array = _once["frames"]
	var frame_index := 0
	for index in range(frames.size()):
		if float(frames[index]["time"]) > elapsed:
			break
		frame_index = index
	if frame_index != _once_frame_index:
		_once_frame_index = frame_index
		sprite.texture = frames[frame_index]["texture"]
		sprite.offset = frames[frame_index]["offset"]
	return elapsed >= float(_once["length"])


# Every clip this controller plays runs at `value` from here on, the clock-driven ones and the
# AnimationPlayer's alike. The clip under way jumps to where the new speed puts it: a looping
# one to (elapsed * value) mod its length, a one-shot to elapsed * value, which may finish it.
# A one-shot that has already finished keeps its last frame.
func set_speed_scale(value: float) -> void:
	if value == speed_scale:
		return
	speed_scale = value
	animation_player.speed_scale = value
	if not is_clock_driven_animation(current_animation) and animation_player.is_playing() and String(animation_player.current_animation) == current_animation:
		var animation := animation_player.get_animation(current_animation)
		var position := _clip_elapsed * value
		if animation.loop_mode != Animation.LOOP_NONE:
			animation_player.seek(fposmod(position, animation.length), true)
		elif position < animation.length:
			animation_player.seek(position, true)
		else:
			# A seek onto the end stops the player on the last frame without the signal a clip
			# that runs out raises, so it is raised here: the finished flag +556 is up.
			animation_player.seek(animation.length, true)
			animation_player.animation_finished.emit(StringName(current_animation))
	_last_clock_frame_index = -1
	update_clock_driven_animation_frame()


func is_clock_driven_animation(anim_name: String) -> bool:
	var is_walk := walk_animation_prefix != "" and anim_name.begins_with(walk_animation_prefix)
	var is_idle := idle_animation_prefix != "" and anim_name.begins_with(idle_animation_prefix)
	if is_walk or is_idle:
		return true
	for prefix in clock_driven_prefixes:
		if prefix != "" and anim_name.begins_with(prefix):
			return true
	return false


# `clock` stands in for the global animation clock, so a check can pin the frame.
func update_clock_driven_animation_frame(clock := -1.0) -> void:
	var frame_index := clock_driven_frame_index(get_global_animation_time() if clock < 0.0 else clock)
	if frame_index < 0:
		return

	var frame: Dictionary = clock_driven_animation_frames[current_animation]["frames"][frame_index]
	if current_animation == _last_clock_animation and frame_index == _last_clock_frame_index:
		return

	sprite.texture = frame["texture"]
	sprite.offset = frame["offset"]
	_last_clock_animation = current_animation
	_last_clock_frame_index = frame_index


# The frame the current clock-driven clip shows at `clock`: a start of 0 and the clip's speed,
# so floor(((clock * speed) mod length) * fps). -1 when the clip is not clock-driven.
func clock_driven_frame_index(clock: float) -> int:
	if not is_clock_driven_animation(current_animation):
		return -1
	var animation_frame_data: Dictionary = clock_driven_animation_frames.get(current_animation, {})
	var frames: Array = animation_frame_data.get("frames", [])
	var animation_length := float(animation_frame_data.get("length", 0.0))
	if frames.is_empty() or animation_length <= 0.0:
		return -1
	var animation_time := fposmod(clock * speed_scale, animation_length)
	var frame_index := 0
	for index in range(frames.size()):
		if float(frames[index]["time"]) > animation_time:
			break
		frame_index = index
	return frame_index


func cache_clock_driven_animation_frames() -> void:
	clock_driven_animation_frames.clear()

	for animation_name in animation_player.get_animation_list():
		var anim_name := String(animation_name)
		if not is_clock_driven_animation(anim_name):
			continue
		var data := _animation_frames(anim_name)
		if not data.is_empty():
			clock_driven_animation_frames[anim_name] = data


func _animation_frames(anim_name: String) -> Dictionary:
	if not animation_player.has_animation(anim_name):
		return {}
	var animation := animation_player.get_animation(anim_name)
	var texture_track := animation.find_track(NodePath("Sprite2D:texture"), Animation.TYPE_VALUE)
	var offset_track := animation.find_track(NodePath("Sprite2D:offset"), Animation.TYPE_VALUE)
	if texture_track < 0 or offset_track < 0:
		return {}

	var frame_count = min(animation.track_get_key_count(texture_track), animation.track_get_key_count(offset_track))
	if frame_count <= 0:
		return {}

	var frames: Array = []
	for frame_index in range(frame_count):
		frames.append({
			"time": animation.track_get_key_time(texture_track, frame_index),
			"texture": animation.track_get_key_value(texture_track, frame_index),
			"offset": animation.track_get_key_value(offset_track, frame_index),
		})
	return {
		"length": animation.length,
		"frames": frames,
	}


func get_global_animation_time() -> float:
	return Time.get_ticks_usec() * 0.000001
