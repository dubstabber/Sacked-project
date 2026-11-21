@tool
extends Node2D

# A character's idle frame, drawn in the editor only. Its sprite has no texture until the game
# sets one from its profile, so without this a player or a coworker placed in a map shows as a
# shadow. It reads the profile and initial direction off its parent as they are edited, and
# draws the idle clip's first frame with its pivot, where the game would show it. In play it
# frees itself; it never changes the sprite, so nothing of it is saved into a scene.

const PLAYER_DEFAULT_PROFILE := "res://scenes/player/profiles/jobless.tres"

var _shown := ""


func _ready() -> void:
	if not Engine.is_editor_hint():
		queue_free()
		return
	set_process(true)


# Profiles and directions are edited in the inspector, so the frame is looked up again only
# when the clip it names changes.
func _process(_delta: float) -> void:
	var clip := _clip_name()
	if clip != _shown:
		_shown = clip
		queue_redraw()


func _draw() -> void:
	var frame := _frame()
	if not frame.is_empty():
		draw_texture(frame["texture"], frame["offset"])


func _profile() -> Resource:
	var parent := get_parent()
	if parent == null:
		return null
	var profile = parent.get("profile")
	# A player with no profile of its own plays as the character chosen at character select,
	# which the editor shows as the default one.
	var script := parent.get_script() as Script
	if profile == null and script != null and script.resource_path == "res://scenes/player/player.gd":
		profile = load(PLAYER_DEFAULT_PROFILE)
	return profile


func _clip_name() -> String:
	var profile := _profile()
	if profile == null or String(profile.get("idle_animation_prefix")) == "":
		return ""
	var direction = get_parent().get("initial_direction")
	if not (direction is Vector2) or direction == Vector2.ZERO:
		direction = Vector2.DOWN
	return "%s|%s" % [profile.resource_path, _directional(String(profile.get("idle_animation_prefix")), direction)]


# AnimationController.get_directional_animation_name, which the game uses to pick the clip.
func _directional(prefix: String, direction: Vector2) -> String:
	var index := int(round(direction.angle() / (PI / 4))) % 8
	var names := {0: "right", 1: "down-right", 2: "down", 3: "down-left", 4: "left", -4: "left", -3: "up-left", -2: "up", -1: "up-right"}
	return prefix + String(names.get(index, "down"))


func _frame() -> Dictionary:
	var profile := _profile()
	if profile == null:
		return {}
	var library := profile.get("animation_library") as AnimationLibrary
	var clip := _clip_name().get_slice("|", 1)
	if library == null or clip == "" or not library.has_animation(clip):
		return {}
	var animation := library.get_animation(clip)
	var texture_track := animation.find_track(NodePath("Sprite2D:texture"), Animation.TYPE_VALUE)
	var offset_track := animation.find_track(NodePath("Sprite2D:offset"), Animation.TYPE_VALUE)
	if texture_track < 0 or animation.track_get_key_count(texture_track) == 0:
		return {}
	var texture := animation.track_get_key_value(texture_track, 0) as Texture2D
	var offset := Vector2.ZERO
	if offset_track >= 0 and animation.track_get_key_count(offset_track) > 0:
		offset = animation.track_get_key_value(offset_track, 0)
	return {"texture": texture, "offset": offset} if texture != null else {}
