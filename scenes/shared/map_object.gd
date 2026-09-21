@tool
class_name MapObject
extends Node2D


signal changed
signal state_changed(state: int)

# sub_40FDA0 clamps an item state to 0..15 and picks its clip from a per-state slot.
# DESTROY_1..7 play once and then advance to the matching DESTROYED_n, which loops.
const STATE_NAMES := [
	"IDLE", "USE",
	"DESTROY_1", "DESTROY_2", "DESTROY_3", "DESTROY_4", "DESTROY_5", "DESTROY_6", "DESTROY_7",
	"DESTROYED_1", "DESTROYED_2", "DESTROYED_3", "DESTROYED_4", "DESTROYED_5", "DESTROYED_6", "DESTROYED_7",
]
const FIRST_TRANSITION_STATE := 2
const LAST_TRANSITION_STATE := 8
const DESTROYED_OFFSET := 7
const STATE_MANIFEST_DIR := "res://resources/objects/"

@export var color_texture: Texture2D:
	set(value):
		color_texture = value
		_refresh_sprite()
@export var depth_texture: Texture2D:
	set(value):
		depth_texture = value
		changed.emit()
@export var pivot := Vector2.ZERO:
	set(value):
		pivot = value
		_refresh_sprite()


var state := 0
var _states: Dictionary = {}
var _states_loaded := false
var _idle_texture: Texture2D
var _idle_pivot := Vector2.ZERO
var _clip: Array = []
var _clip_fps := 0.0
var _clip_elapsed := 0.0
var _clip_frame := -1
var _clip_advances_to := -1


func _enter_tree() -> void:
	add_to_group("depth_world_objects")
	set_notify_transform(true)


func _ready() -> void:
	_refresh_sprite()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED or what == NOTIFICATION_VISIBILITY_CHANGED:
		changed.emit()


func _refresh_sprite() -> void:
	var sprite := get_node_or_null("Sprite2D") as Sprite2D
	if sprite != null:
		sprite.centered = false
		sprite.texture = color_texture
		sprite.offset = -pivot
	changed.emit()


func _load_states() -> void:
	if _states_loaded:
		return
	_states_loaded = true
	_idle_texture = color_texture
	_idle_pivot = pivot
	if color_texture == null:
		return
	var path := STATE_MANIFEST_DIR + color_texture.resource_path.get_file().get_basename() + ".json"
	if not ResourceLoader.exists(path):
		return
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		_states = parsed.get("states", {})


func has_state(target: int) -> bool:
	_load_states()
	return target == 0 or _states.has(STATE_NAMES[target]) if target >= 0 and target < STATE_NAMES.size() else false


# The engine stores the requested state even when the object ships no art for it, and an
# unplayable DESTROY_n settles on its DESTROYED_n. See docs/prank-reference.md.
func set_state(target: int) -> void:
	_load_states()
	target = clampi(target, 0, STATE_NAMES.size() - 1)
	state = target
	var clip: Dictionary = _states.get(STATE_NAMES[target], {})
	if clip.is_empty():
		if FIRST_TRANSITION_STATE <= target and target <= LAST_TRANSITION_STATE:
			var settled := target + DESTROYED_OFFSET
			if _states.has(STATE_NAMES[settled]):
				set_state(settled)
				return
		if target == 0:
			_stop_clip()
			_apply_texture(_idle_texture, _idle_pivot)
		state_changed.emit(state)
		return

	var frames: Array = clip.get("frames", [])
	if frames.is_empty():
		state_changed.emit(state)
		return
	_clip = frames
	_clip_fps = maxf(float(clip.get("fps", 8.0)), 0.001)
	_clip_elapsed = 0.0
	_clip_frame = -1
	_clip_advances_to = int(clip.get("advances_to", -1)) if clip.get("advances_to") != null else -1
	# A single frame is a plain swap; a real transition animates and then settles.
	set_process(frames.size() > 1)
	_show_frame(0)
	state_changed.emit(state)


func _show_frame(index: int) -> void:
	if index == _clip_frame or index >= _clip.size():
		return
	_clip_frame = index
	var frame: Dictionary = _clip[index]
	var texture := load(String(frame["texture"])) as Texture2D
	var frame_pivot := Vector2(float(frame["pivot"][0]), float(frame["pivot"][1]))
	_apply_texture(texture, frame_pivot)


func _apply_texture(texture: Texture2D, frame_pivot: Vector2) -> void:
	if texture == null:
		return
	var depth_path := texture.resource_path.get_basename() + "-depth.png"
	depth_texture = load(depth_path) as Texture2D if ResourceLoader.exists(depth_path) else null
	pivot = frame_pivot
	color_texture = texture


func _stop_clip() -> void:
	set_process(false)
	_clip = []
	_clip_frame = -1
	_clip_advances_to = -1


func _process(delta: float) -> void:
	if _clip.size() < 2:
		set_process(false)
		return
	_clip_elapsed += delta
	var index := int(_clip_elapsed * _clip_fps)
	if index >= _clip.size():
		# sub_410290 advances a finished DESTROY_n to its DESTROYED_n.
		var settled := _clip_advances_to
		_stop_clip()
		if settled >= 0:
			set_state(settled)
		return
	_show_frame(index)


func get_depth_actor() -> Dictionary:
	var sprite := get_node_or_null("Sprite2D") as Sprite2D
	if sprite == null or color_texture == null:
		return {}
	return {
		"node": self,
		"sprite": sprite,
		"color": color_texture,
		"depth": depth_texture,
		"position": sprite.to_global(sprite.offset),
		"size": Vector2i(color_texture.get_size()),
		# Original entity depth is half projected Y, rounded up after integer projection.
		"base_y": ceilf(float(int(global_position.y)) * 0.5),
	}
