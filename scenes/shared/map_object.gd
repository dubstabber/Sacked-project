@tool
class_name MapObject
extends Node2D


signal changed
signal state_changed(state: int)

# sub_40FDA0 clamps an item state to 0..15 and picks its clip from a per-state slot.
# DESTROY_1..7 play once and then advance to the matching DESTROYED_n, which loops. A state
# the container ships no clip for plays the IDLE clip. See docs/prank-reference.md.
const STATE_NAMES := [
	"IDLE", "USE",
	"DESTROY_1", "DESTROY_2", "DESTROY_3", "DESTROY_4", "DESTROY_5", "DESTROY_6", "DESTROY_7",
	"DESTROYED_1", "DESTROYED_2", "DESTROYED_3", "DESTROYED_4", "DESTROYED_5", "DESTROYED_6", "DESTROYED_7",
]
const FIRST_TRANSITION_STATE := 2
const LAST_TRANSITION_STATE := 8
const DESTROYED_OFFSET := 7
const STATE_MANIFEST_DIR := "res://resources/objects/"

# An object normally bakes into the one static world composite. A clip that never stops
# would make that composite repaint at its frame rate forever, so a looping object leaves
# the bake and is drawn as a depth-tested actor instead, exactly as a character is: the
# shader still tests it against every other object, and a frame becomes a texture swap.
# See docs/map-rendering.md.
const WORLD_GROUP := &"depth_world_objects"
const ACTOR_GROUP := &"depth_composited_characters"
# How the object is drawn never takes it out of the pick: the original registers an item's
# click box every frame it draws the item (sub_411E20 at 0x411F88), and no state touches
# either flag that gates it. See docs/player-action-reference.md.
const PICK_GROUP := &"map_objects"

@export var color_texture: Texture2D:
	set(value):
		color_texture = value
		_refresh_sprite()
		if Engine.is_editor_hint():
			update_configuration_warnings()
@export var depth_texture: Texture2D:
	set(value):
		depth_texture = value
		# Like a new frame in _refresh_sprite: while drawn as an actor this object is not in
		# the bake, so its depth plane is nothing the world composite has to hear about.
		if not _drawn_as_actor:
			_announce_change()
		if Engine.is_editor_hint():
			update_configuration_warnings()
@export var pivot := Vector2.ZERO:
	set(value):
		pivot = value
		_refresh_sprite()


var state := 0
var _states: Dictionary = {}
var _states_loaded := false
var _idle_texture: Texture2D
var _idle_pivot := Vector2.ZERO
# The IDLE clip's fps and frame count, which an empty DESTROY_n plays once.
var _idle_clip: Dictionary = {}
var _clip: Array = []
# Path -> texture, held for the length of the clip.
var _clip_textures: Dictionary = {}
# The clip's later frames, asked of ThreadedLoads when the clip started and not taken yet.
var _clip_requested: Dictionary = {}
var _clip_fps := 0.0
var _clip_elapsed := 0.0
var _clip_frame := -1
var _clip_loops := false
# anim+556: a one-shot that has run out holds its last frame with this raised.
var _clip_finished := false
var _drawn_as_actor := false
# Counts every change this object announces, so the world compositor can keep what it
# prepared from the object until the object changes again.
var depth_revision := 0


func _enter_tree() -> void:
	add_to_group(PICK_GROUP)
	add_to_group(ACTOR_GROUP if _drawn_as_actor else WORLD_GROUP)
	set_notify_transform(true)


func _ready() -> void:
	_refresh_sprite()


# An object freed in the middle of a clip lets go of the frames it asked the worker threads for.
func _exit_tree() -> void:
	_release_clip_textures()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED or what == NOTIFICATION_VISIBILITY_CHANGED:
		_announce_change()


func _refresh_sprite() -> void:
	var sprite := get_node_or_null("Sprite2D") as Sprite2D
	if sprite != null:
		sprite.centered = false
		sprite.texture = color_texture
		sprite.offset = -pivot
	# While drawn as an actor this object is not in the bake, so a new frame is nothing the
	# world composite has to hear about.
	if not _drawn_as_actor:
		_announce_change()


func _announce_change() -> void:
	depth_revision += 1
	changed.emit()


func _set_drawn_as_actor(value: bool) -> void:
	if value == _drawn_as_actor:
		return
	_drawn_as_actor = value
	if is_inside_tree():
		remove_from_group(WORLD_GROUP if value else ACTOR_GROUP)
		add_to_group(ACTOR_GROUP if value else WORLD_GROUP)
	# Either way the bake changes: it loses this object, or it gains it back.
	_announce_change()


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
		_idle_clip = parsed.get("idle", {})


func has_state(target: int) -> bool:
	_load_states()
	return target == 0 or _states.has(STATE_NAMES[target]) if target >= 0 and target < STATE_NAMES.size() else false


func set_state(target: int) -> void:
	PerfProbe.begin(&"object.set_state")
	_set_state(target)
	PerfProbe.end(&"object.set_state")


func _set_state(target: int) -> void:
	_load_states()
	target = clampi(target, 0, STATE_NAMES.size() - 1)
	state = target
	if target == 0:
		_stop_clip()
		_apply_texture(_idle_texture, _idle_pivot)
		_set_drawn_as_actor(false)
		state_changed.emit(state)
		return
	var clip := _clip_for(target)
	var frames: Array = clip.get("frames", [])
	if frames.is_empty():
		# Only an object with no state manifest at all lands here; it never changes look.
		state_changed.emit(state)
		return

	_clip = frames
	_warm_clip_textures(frames)
	_clip_fps = maxf(float(clip.get("fps", 8.0)), 0.001)
	_clip_elapsed = 0.0
	_clip_frame = -1
	_clip_finished = false
	# sub_40FDA0 sets the loop flag by state, not by clip (0x40FE07): a DESTROY_n plays once
	# and settles, every other state runs for as long as it is held.
	_clip_loops = not (FIRST_TRANSITION_STATE <= target and target <= LAST_TRANSITION_STATE)
	# A looping single frame is a plain swap. A DESTROY_n runs on the clock even when it is
	# one frame: CObjectAnim_SelectFrameFromTime flags a one-shot finished once
	# int(t * fps) reaches its frame count (0x407F27), and sub_410290 then settles it.
	set_process(frames.size() > 1 or not _clip_loops)
	_set_drawn_as_actor(_clip_loops and frames.size() > 1)
	_show_frame(0)
	state_changed.emit(state)


# sub_410550 names the sixteen slots and gives every state the container ships no clip for
# the IDLE clip instead (0x41087C), so no state is without one: an empty DESTROY_n plays
# IDLE once and settles, an empty DESTROYED_n shows IDLE. See docs/prank-reference.md.
func _clip_for(target: int) -> Dictionary:
	var clip: Dictionary = _states.get(STATE_NAMES[target], {})
	if not (clip.get("frames", []) as Array).is_empty():
		return clip
	if _idle_texture == null or _idle_clip.is_empty():
		return {}
	var frame := {"texture": _idle_texture.resource_path, "pivot": [_idle_pivot.x, _idle_pivot.y]}
	var frames := []
	for index in range(maxi(int(_idle_clip.get("frame_count", 1)), 1)):
		frames.append(frame)
	return {"frames": frames, "fps": float(_idle_clip.get("fps", 0.0))}


# Frames are loaded by path as they are shown, and held for the length of the clip. The first
# is loaded on the spot; the rest load on worker threads while it shows, which used to cost
# 20-25 ms in the frame the state changed. Without worker threads (headless) they are all
# loaded now, as before.
func _warm_clip_textures(frames: Array) -> void:
	_release_clip_textures()
	if frames.size() < 2:
		return
	for index in range(frames.size()):
		var path := String(frames[index]["texture"])
		for each in [path, path.get_basename() + "-depth.png"]:
			if _clip_textures.has(each) or _clip_requested.has(each):
				continue
			if index > 0 and ThreadedLoads.available():
				ThreadedLoads.request(each)
				_clip_requested[each] = true
			elif ResourceLoader.exists(each):
				_clip_textures[each] = load(each)


func _clip_texture(path: String) -> Texture2D:
	if _clip_textures.has(path):
		return _clip_textures[path]
	_clip_requested.erase(path)
	var texture := ThreadedLoads.take(path) as Texture2D
	if texture != null and not _clip.is_empty():
		_clip_textures[path] = texture
	return texture


func _release_clip_textures() -> void:
	for path in _clip_requested:
		ThreadedLoads.release(path)
	_clip_requested.clear()
	_clip_textures.clear()


func _show_frame(index: int) -> void:
	if index == _clip_frame or index >= _clip.size():
		return
	_clip_frame = index
	var frame: Dictionary = _clip[index]
	var texture := _clip_texture(String(frame["texture"]))
	var frame_pivot := Vector2(float(frame["pivot"][0]), float(frame["pivot"][1]))
	_apply_texture(texture, frame_pivot)


func _apply_texture(texture: Texture2D, frame_pivot: Vector2) -> void:
	if texture == null:
		return
	var depth_path := texture.resource_path.get_basename() + "-depth.png"
	depth_texture = _clip_texture(depth_path) if ResourceLoader.exists(depth_path) else null
	pivot = frame_pivot
	color_texture = texture


func _stop_clip() -> void:
	set_process(false)
	_clip = []
	_release_clip_textures()
	_clip_frame = -1
	_clip_loops = false
	_clip_finished = false


func _process(delta: float) -> void:
	if _clip.is_empty() or _clip_finished or (_clip_loops and _clip.size() < 2):
		set_process(false)
		return
	_clip_elapsed += delta
	var index := int(_clip_elapsed * _clip_fps)
	if index < _clip.size():
		_show_frame(index)
		return
	if _clip_loops:
		_clip_elapsed = fmod(_clip_elapsed, float(_clip.size()) / _clip_fps)
		_show_frame(int(_clip_elapsed * _clip_fps))
		return
	_show_frame(_clip.size() - 1)
	_clip_finished = true
	_release_clip_textures()
	set_process(false)
	# sub_410290 (0x4102BC): a DESTROY_n whose clip has finished steps forward by seven.
	if FIRST_TRANSITION_STATE <= state and state <= LAST_TRANSITION_STATE:
		set_state(state + DESTROYED_OFFSET)


# The editor's warnings for an object in a map: what would make it draw wrongly or do nothing.
# See docs/map-authoring.md.
func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if color_texture == null:
		warnings.append("No Color Texture: the object draws nothing.")
	elif depth_texture == null:
		warnings.append("No Depth Texture (the -depth.png beside the image): the world compositor leaves the object out.")
	if not is_equal_approx(rotation, 0.0) or not scale.is_equal_approx(Vector2.ONE):
		warnings.append("Rotated or scaled: the depth masks support neither. For another direction, use the prefab with the other angle in its name.")
	if get_node_or_null("InteractionPoint") == null:
		warnings.append("No InteractionPoint: a decoration, with no pranks and no use by colleagues. Drag the object's prefab from scenes/objects/ to get one.")
	return warnings


# The object's anchor in tiles, offered in the editor beside its pixel position: the grid the
# original places items on. Not stored; it reads and moves the position through the level's
# own tile axes, and is absent where the object stands in no map.
func _get_property_list() -> Array[Dictionary]:
	if not Engine.is_editor_hint() or _tile_axes() == Transform2D():
		return []
	return [{"name": "tile_position", "type": TYPE_VECTOR2, "usage": PROPERTY_USAGE_EDITOR}]


func _get(property: StringName) -> Variant:
	if property == &"tile_position":
		var axes := _tile_axes()
		return axes.affine_inverse() * position if axes != Transform2D() else null
	return null


func _set(property: StringName, value: Variant) -> bool:
	if property == &"tile_position" and value is Vector2:
		var axes := _tile_axes()
		if axes != Transform2D():
			position = axes * (value as Vector2)
			return true
	return false


func _tile_axes() -> Transform2D:
	var node: Node = get_parent()
	while node != null:
		var layer := node.get_node_or_null("CollisionTileMapLayer") as TileMapLayer
		if layer != null:
			var origin := layer.map_to_local(Vector2i.ZERO)
			return Transform2D(layer.map_to_local(Vector2i(1, 0)) - origin, layer.map_to_local(Vector2i(0, 1)) - origin, origin)
		node = node.get_parent()
	return Transform2D()


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
