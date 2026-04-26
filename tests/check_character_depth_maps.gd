extends SceneTree


const Profiles := [
	preload("res://scenes/player/profiles/jobless.tres"),
	preload("res://scenes/player/profiles/anne.tres"),
	preload("res://scenes/npc/profiles/boss.tres"),
]

var _failed := false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	for profile in Profiles:
		_check_profile(profile)
		if _failed:
			return
	quit(0)


func _check_profile(profile: Resource) -> void:
	var library := profile.get("animation_library") as AnimationLibrary
	if library == null:
		_fail("%s has no animation library" % profile.resource_path)
		return

	for animation_name in library.get_animation_list():
		var animation := library.get_animation(animation_name)
		var texture_track := animation.find_track(NodePath("Sprite2D:texture"), Animation.TYPE_VALUE)
		if texture_track < 0:
			_fail("%s has no texture track" % animation_name)
			return

		for key_index in range(animation.track_get_key_count(texture_track)):
			var texture := animation.track_get_key_value(texture_track, key_index) as Texture2D
			if texture == null:
				_fail("%s has a null texture at key %d" % [animation_name, key_index])
				return
			_check_depth_map(texture)
			if _failed:
				return


func _check_depth_map(texture: Texture2D) -> void:
	var texture_path := texture.resource_path
	if not texture_path.ends_with(".png"):
		_fail("Texture path is not a PNG: %s" % texture_path)
		return

	var depth_path := texture_path.substr(0, texture_path.length() - 4) + "-depth.png"
	if not FileAccess.file_exists(depth_path):
		_fail("Missing depth map: %s" % depth_path)
		return

	var depth_size := _read_png_size(depth_path)
	if depth_size == Vector2i.ZERO:
		_fail("Failed to read depth PNG: %s" % depth_path)
		return

	if texture.get_width() != depth_size.x or texture.get_height() != depth_size.y:
		_fail("Depth map size mismatch: %s" % depth_path)
		return


func _read_png_size(path: String) -> Vector2i:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return Vector2i.ZERO

	var header := file.get_buffer(24)
	if header.size() < 24:
		return Vector2i.ZERO
	if header[0] != 0x89 or header[1] != 0x50 or header[2] != 0x4E or header[3] != 0x47:
		return Vector2i.ZERO

	return Vector2i(
		_read_be_u32(header, 16),
		_read_be_u32(header, 20)
	)


func _read_be_u32(bytes: PackedByteArray, offset: int) -> int:
	return (
		(int(bytes[offset]) << 24)
		| (int(bytes[offset + 1]) << 16)
		| (int(bytes[offset + 2]) << 8)
		| int(bytes[offset + 3])
	)


func _fail(message: String) -> void:
	if _failed:
		return
	_failed = true
	push_error(message)
	quit(1)
