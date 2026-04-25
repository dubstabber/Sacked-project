extends Node


@export var idle_animation_prefix: String = ""
@export var walk_animation_prefix: String = ""
@export var sprite_path: NodePath
@export var animation_player_path: NodePath

var current_animation: String = ""
var clock_driven_animation_frames: Dictionary = {}

@onready var sprite: Sprite2D = get_node(sprite_path)
@onready var animation_player: AnimationPlayer = get_node(animation_player_path)


func _ready() -> void:
	cache_clock_driven_animation_frames()


func _process(_delta: float) -> void:
	update_clock_driven_animation_frame()


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
	var is_walk := walk_animation_prefix != "" and anim_name.begins_with(walk_animation_prefix)
	var is_idle := idle_animation_prefix != "" and anim_name.begins_with(idle_animation_prefix)
	return is_walk or is_idle


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
