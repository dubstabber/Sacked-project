extends SceneTree


const DIRECTIONS := {
	"000": "up-right",
	"045": "right",
	"090": "down-right",
	"135": "down",
	"180": "down-left",
	"225": "left",
	"270": "up-left",
	"315": "up",
}
# Which clips to build is shared with tools/export_npc_action_assets.py so the frames on
# disk and the libraries built from them cannot drift apart.
const SPEC_PATH := "res://tools/character_action_clips.json"

var _failed := false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var file := FileAccess.open(SPEC_PATH, FileAccess.READ)
	if file == null:
		push_error("Missing clip spec: %s" % SPEC_PATH)
		quit(1)
		return
	var spec: Dictionary = JSON.parse_string(file.get_as_text())
	var by_character: Dictionary = {}
	for row in spec["clips"]:
		var character: String = row["character"]
		if not by_character.has(character):
			by_character[character] = {"library": String(row["library"]), "clips": []}
		by_character[character]["clips"].append(row)

	for character in by_character:
		var library := AnimationLibrary.new()
		for action in by_character[character]["clips"]:
			for angle in action["angles"]:
				var animation := _build_animation(character, String(action["source"]), String(action["action"]), String(angle))
				if _failed:
					quit(1)
					return
				library.add_animation("%s-%s-%s" % [character, String(action["action"]), DIRECTIONS[angle]], animation)
		var folder := "npc" if String(by_character[character]["library"]) == "npc" else "player"
		var path := "res://scenes/%s/profiles/%s_actions.res" % [folder, character]
		var error := ResourceSaver.save(library, path)
		if error != OK:
			push_error("Failed to save %s: %s" % [path, error_string(error)])
			quit(1)
			return
		print("Saved %s (%d clips)" % [path, library.get_animation_list().size()])
	quit(0)


func _build_animation(character: String, source_prefix: String, action: String, angle: String) -> Animation:
	var source_path := "res://extract-sacked-assets/extracted/animations_godot/CO_CHARS_CO_CHARS_%s_%s_godot.json" % [source_prefix, angle]
	var source := _read_source(source_path)
	if source.is_empty():
		return null
	var frames: Array = source.get("frames", [])
	if frames.is_empty() or frames.size() != int(source.get("frame_count", 0)):
		_fail("Invalid frame count in %s" % source_path)
		return null
	var animation := Animation.new()
	animation.length = float(source["duration_seconds"])
	animation.loop_mode = Animation.LOOP_LINEAR if source.get("loop", false) else Animation.LOOP_NONE
	var texture_track := animation.add_track(Animation.TYPE_VALUE)
	var offset_track := animation.add_track(Animation.TYPE_VALUE)
	animation.track_set_path(texture_track, NodePath("Sprite2D:texture"))
	animation.track_set_path(offset_track, NodePath("Sprite2D:offset"))
	for track in [texture_track, offset_track]:
		animation.value_track_set_update_mode(track, Animation.UPDATE_DISCRETE)
		animation.track_set_interpolation_type(track, Animation.INTERPOLATION_NEAREST)
	var clip := "%s-%s-%s" % [character, action, DIRECTIONS[angle]]
	var time := 0.0
	for frame in frames:
		var path := "res://images/characters/%s/%s/%s-%s.png" % [character, clip, clip, String(frame["sprite_name"]).right(3)]
		var texture := load(path) as Texture2D
		if texture == null:
			_fail("Missing NPC action frame: %s" % path)
			return null
		animation.track_insert_key(texture_track, time, texture)
		animation.track_insert_key(offset_track, time, _frame_offset(frame))
		time += float(frame["duration_sec"])
	if absf(time - animation.length) > 0.00001:
		_fail("Frame durations do not match clip length in %s" % source_path)
		return null
	return animation


func _read_source(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_fail("Cannot read %s" % path)
		return {}
	var source = JSON.parse_string(file.get_as_text())
	if source is Dictionary:
		return source
	_fail("Invalid animation JSON: %s" % path)
	return {}


func _fail(message: String) -> void:
	_failed = true
	push_error(message)


# SPRITEHDR stores the pivot as a signed 16-bit pair, but the extraction helper read it
# unsigned, so a pivot just left of the sprite comes through as a number near 65536 --
# ANNE_ASSCOPY_090 has pivot_x 65531, which is -5. Sign-extending here rather than in the
# reference data keeps the extraction untouched. Anything still absurd afterwards is a
# decode this has not seen, so it fails rather than placing a sprite a screen away.
const PIVOT_WRAP := 65536
const PIVOT_SIGN_LIMIT := 32768
const PIVOT_SANITY_LIMIT := 4096


func _signed_pivot(value: float) -> float:
	return value - PIVOT_WRAP if value >= PIVOT_SIGN_LIMIT else value


func _frame_offset(frame: Dictionary) -> Vector2:
	var offset := Vector2(
		-_signed_pivot(float(frame["pivot_x"])),
		-_signed_pivot(float(frame["pivot_y"]))
	)
	if absf(offset.x) > PIVOT_SANITY_LIMIT or absf(offset.y) > PIVOT_SANITY_LIMIT:
		_fail("Frame %s has an implausible pivot offset %s" % [frame.get("sprite_name", "?"), offset])
	return offset
