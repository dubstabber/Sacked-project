extends SceneTree


const ProfileSpecs := [
	{
		"profile": preload("res://scenes/npc/profiles/boss.tres"),
		"image_root": "res://images/characters/boss/",
	},
	{
		"profile": preload("res://scenes/npc/profiles/secretary.tres"),
		"image_root": "res://images/characters/secretary/",
	},
	{
		"profile": preload("res://scenes/npc/profiles/janitor.tres"),
		"image_root": "res://images/characters/janitor/",
	},
	{
		"profile": preload("res://scenes/npc/profiles/male-employee-1.tres"),
		"image_root": "res://images/characters/male-employee-1/",
	},
	{
		"profile": preload("res://scenes/npc/profiles/male-employee-2.tres"),
		"image_root": "res://images/characters/male-employee-2/",
	},
	{
		"profile": preload("res://scenes/npc/profiles/female-employee-1.tres"),
		"image_root": "res://images/characters/female-employee-1/",
	},
	{
		"profile": preload("res://scenes/npc/profiles/female-employee-2.tres"),
		"image_root": "res://images/characters/female-employee-2/",
	},
]

const Directions := ["right", "down-right", "down", "down-left", "left", "up-left", "up", "up-right"]

var _failed := false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	for spec in ProfileSpecs:
		_check_profile(spec)
		if _failed:
			return
	quit(0)


func _check_profile(spec: Dictionary) -> void:
	var profile: Resource = spec["profile"]
	var profile_id := String(profile.get("id"))
	var library := profile.get("animation_library") as AnimationLibrary
	if profile_id == "":
		_fail("%s has no id" % profile.resource_path)
		return
	if library == null:
		_fail("%s has no animation library" % profile.resource_path)
		return

	_check_directional_prefix(profile, library, "idle_animation_prefix", spec["image_root"])
	_check_directional_prefix(profile, library, "walk_animation_prefix", spec["image_root"])


func _check_directional_prefix(
	profile: Resource,
	library: AnimationLibrary,
	prefix_property: String,
	image_root: String
) -> void:
	var prefix := String(profile.get(prefix_property))
	if prefix == "":
		_fail("%s has no %s" % [profile.resource_path, prefix_property])
		return

	for direction in Directions:
		var animation_name: String = prefix + direction
		if not library.has_animation(animation_name):
			_fail("%s missing %s" % [profile.resource_path, animation_name])
			return

		var animation := library.get_animation(animation_name)
		var texture_track := animation.find_track(NodePath("Sprite2D:texture"), Animation.TYPE_VALUE)
		var offset_track := animation.find_track(NodePath("Sprite2D:offset"), Animation.TYPE_VALUE)
		if texture_track < 0 or offset_track < 0:
			_fail("%s missing texture or offset track" % animation_name)
			return
		if animation.track_get_key_count(texture_track) <= 0:
			_fail("%s has no texture keys" % animation_name)
			return

		var texture := animation.track_get_key_value(texture_track, 0) as Texture2D
		if texture == null or not texture.resource_path.begins_with(image_root):
			_fail("%s uses an invalid texture path" % animation_name)
			return


func _fail(message: String) -> void:
	if _failed:
		return
	_failed = true
	push_error(message)
	quit(1)
