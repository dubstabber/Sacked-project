extends SceneTree


const DIRECTIONS := {
	"000": "up-right", "045": "right", "090": "down-right", "135": "down",
	"180": "down-left", "225": "left", "270": "up-left", "315": "up",
}
# The exporter, the library importer and this check all read one spec, so adding a
# character is a single edit and cannot leave the three out of step.
const SPEC_PATH := "res://tools/character_action_clips.json"

var _failures := 0
var _frames_checked := 0


func _init() -> void:
	call_deferred("_run")


# [character, source prefix, action name, angles, library], for both libraries -- the NPC
# action clips and the player's own, which share one exporter and one importer.
func _load_specs() -> Array:
	var file := FileAccess.open(SPEC_PATH, FileAccess.READ)
	if file == null:
		_expect(false, "cannot read clip spec %s" % SPEC_PATH)
		return []
	var parsed = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary):
		_expect(false, "clip spec is not readable")
		return []
	var specs := []
	for row in parsed.get("clips", []):
		specs.append([
			String(row["character"]), String(row["source"]), String(row["action"]),
			row["angles"], String(row.get("library", "npc")),
		])
	return specs


func _library_path(spec: Array) -> String:
	if String(spec[4]) == "player":
		return "res://scenes/player/profiles/%s_actions.res" % spec[0]
	return "res://scenes/npc/profiles/%s_actions.res" % spec[0]


func _run() -> void:
	var specs := _load_specs()
	_expect(not specs.is_empty(), "the spec lists action clips")
	var expected_clips := {}
	var total_clips := 0
	for spec in specs:
		expected_clips[spec[0]] = int(expected_clips.get(spec[0], 0)) + spec[3].size()
	for spec in specs:
		var library := load(_library_path(spec)) as AnimationLibrary
		if library == null:
			_expect(false, "action library exists for %s" % spec[0])
			continue
		_expect(library.get_animation_list().size() == int(expected_clips[spec[0]]), "%s action library holds only the requested clips" % spec[0])
		for angle in spec[3]:
			_check_clip(library, spec, angle)
			total_clips += 1
	if _failures == 0:
		print("Action assets: %d clips and %d frame textures, masks, durations and pivots match extracted source JSON" % [total_clips, _frames_checked])
	quit(1 if _failures else 0)


func _check_clip(library: AnimationLibrary, spec: Array, angle: String) -> void:
	var clip := "%s-%s-%s" % [spec[0], spec[2], DIRECTIONS[angle]]
	if not library.has_animation(clip):
		_expect(false, "missing action clip %s" % clip)
		return
	var source_path := "res://extract-sacked-assets/extracted/animations_godot/CO_CHARS_CO_CHARS_%s_%s_godot.json" % [spec[1], angle]
	var file := FileAccess.open(source_path, FileAccess.READ)
	if file == null:
		_expect(false, "cannot read extracted source %s" % source_path)
		return
	var source: Dictionary = JSON.parse_string(file.get_as_text())
	var animation := library.get_animation(clip)
	_expect(absf(animation.length - float(source["duration_seconds"])) < 0.000001, "%s preserves original clip duration" % clip)
	_expect(animation.loop_mode == (Animation.LOOP_LINEAR if source["loop"] else Animation.LOOP_NONE), "%s preserves its original loop flag" % clip)
	var texture_track := animation.find_track(NodePath("Sprite2D:texture"), Animation.TYPE_VALUE)
	var offset_track := animation.find_track(NodePath("Sprite2D:offset"), Animation.TYPE_VALUE)
	if texture_track < 0 or offset_track < 0:
		_expect(false, "%s requires texture and pivot tracks" % clip)
		return
	var frames: Array = source["frames"]
	for track in [texture_track, offset_track]:
		_expect(animation.track_get_key_count(track) == frames.size(), "%s frame count matches source" % clip)
		_expect(animation.value_track_get_update_mode(track) == Animation.UPDATE_DISCRETE, "%s updates image and pivot together without interpolation" % clip)
	var time := 0.0
	for index in range(frames.size()):
		var frame: Dictionary = frames[index]
		var texture := animation.track_get_key_value(texture_track, index) as Texture2D
		var offset: Vector2 = animation.track_get_key_value(offset_track, index)
		var expected_path := "res://images/characters/%s/%s/%s-%s.png" % [spec[0], clip, clip, String(frame["sprite_name"]).right(3)]
		_expect(texture != null and texture.resource_path == expected_path, "%s frame %d uses its extracted friendly-named texture" % [clip, index])
		_expect(offset == _expected_offset(frame), "%s frame %d preserves its original pivot" % [clip, index])
		_expect(absf(animation.track_get_key_time(texture_track, index) - time) < 0.000001, "%s frame %d keeps its duration" % [clip, index])
		_expect(absf(animation.track_get_key_time(offset_track, index) - time) < 0.000001, "%s frame %d changes its pivot with its texture" % [clip, index])
		if texture != null:
			_expect(texture.get_size() == Vector2(frame["w"], frame["h"]), "%s frame %d preserves its original image dimensions" % [clip, index])
		# A few original frames ship no Z plane; those must stay without a runtime mask.
		var mask_path := expected_path.get_basename() + "-depth.png"
		if FileAccess.file_exists("res://extract-sacked-assets/%s/SPRITEZB.bin" % String(frame["path"]).get_base_dir()):
			var mask := load(mask_path) as Texture2D
			_expect(mask != null and mask.get_size() == Vector2(frame["w"], frame["h"]), "%s frame %d has a matching depth mask" % [clip, index])
		else:
			_expect(not ResourceLoader.exists(mask_path), "%s frame %d has no depth mask because the original has no Z plane" % [clip, index])
		time += float(frame["duration_sec"])
		_frames_checked += 1


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)


# SPRITEHDR's pivot is a signed 16-bit pair that the extraction helper read unsigned, so the
# reference JSON carries ANNE_ASSCOPY_090's -5 as 65531. The importer sign-extends it, and
# this reproduces that rather than trusting the number in the file.
const PIVOT_WRAP := 65536
const PIVOT_SIGN_LIMIT := 32768


func _signed_pivot(value: float) -> float:
	return value - PIVOT_WRAP if value >= PIVOT_SIGN_LIMIT else value


func _expected_offset(frame: Dictionary) -> Vector2:
	return Vector2(-_signed_pivot(float(frame["pivot_x"])), -_signed_pivot(float(frame["pivot_y"])))
