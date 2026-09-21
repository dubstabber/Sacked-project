extends SceneTree

# The player's prank animations. Which clip each action uses comes from the animation slot
# table at 0x46EC04 by way of sub_41A510's selector map; see docs/player-action-reference.md.
# The frames themselves must still match the extracted source they were exported from.

const CONTROLLER := preload("res://scenes/player/prank_controller.gd")
const SPEC_PATH := "res://tools/character_action_clips.json"
const SOURCE_DIR := "res://extract-sacked-assets/extracted/animations_godot/"
const PROFILES := {
	"jobless": "res://scenes/player/profiles/jobless.tres",
	"anne": "res://scenes/player/profiles/anne.tres",
}
const DIRECTIONS := {
	"000": "up-right", "045": "right", "090": "down-right", "135": "down",
	"180": "down-left", "225": "left", "270": "up-left", "315": "up",
}

var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var spec := _spec()
	if spec.is_empty():
		quit(1)
		return
	_check_libraries(spec)
	_check_every_reachable_selector_has_a_clip(spec)
	if _failures == 0:
		print("Player action clips: both characters carry every clip level 1 can reach, matching their source")
	quit(1 if _failures else 0)


func _expect(condition: bool, label: String) -> void:
	if not condition:
		_failures += 1
		push_error(label)


func _spec() -> Dictionary:
	var file := FileAccess.open(SPEC_PATH, FileAccess.READ)
	if file == null:
		_expect(false, "the shared clip spec is present")
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary):
		_expect(false, "the shared clip spec parses")
		return {}
	return parsed


func _check_libraries(spec: Dictionary) -> void:
	for character in PROFILES:
		var profile: Resource = load(PROFILES[character]) as Resource
		var library: AnimationLibrary = profile.get("action_animation_library") as AnimationLibrary
		_expect(library != null, "%s carries an action animation library" % character)
		if library == null:
			continue
		var rows := 0
		for row in spec["clips"]:
			if String(row["character"]) != character:
				continue
			rows += 1
			for angle in row["angles"]:
				var name: String = "%s-%s-%s" % [character, String(row["action"]), DIRECTIONS[String(angle)]]
				if not library.has_animation(name):
					_expect(false, "%s has the clip %s" % [character, name])
					continue
				_check_frames_match_source(library.get_animation(name), String(row["source"]), String(angle), name)
		_expect(rows > 0, "%s has rows in the shared spec" % character)


# The exporter and the importer read the same spec, so a clip that drifted from the
# extracted original would show up as a frame-count mismatch here.
func _check_frames_match_source(animation: Animation, source: String, angle: String, label: String) -> void:
	var path := "%sCO_CHARS_CO_CHARS_%s_%s_godot.json" % [SOURCE_DIR, source, angle]
	if not FileAccess.file_exists(path):
		_expect(false, "%s has its extracted source %s" % [label, path])
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	var expected: int = (parsed["frames"] as Array).size()
	var track: int = animation.find_track("Sprite2D:texture", Animation.TYPE_VALUE)
	_expect(track >= 0, "%s drives the sprite texture" % label)
	if track < 0:
		return
	_expect(
		animation.track_get_key_count(track) == expected,
		"%s has the original's %d frames, found %d" % [label, expected, animation.track_get_key_count(track)]
	)


func _check_every_reachable_selector_has_a_clip(spec: Dictionary) -> void:
	var actions = JSON.parse_string(FileAccess.get_file_as_string("res://resources/original/actions.json"))
	var manifest = JSON.parse_string(FileAccess.get_file_as_string("res://resources/levels/level_1.json"))
	var placed := {}
	for item in manifest["objects"]:
		for action_id in item["action_ids"]:
			if int(action_id) > 0:
				placed[int(actions["actions"][int(action_id)]["player_animation"])] = int(action_id)

	for selector in placed:
		# Rows needing an item nothing on this level grants stay unreachable, and their
		# selectors are deliberately not imported.
		if not CONTROLLER.SELECTOR_CLIPS.has(selector):
			continue
		var clip: String = String(CONTROLLER.SELECTOR_CLIPS[selector])
		for character in PROFILES:
			var library: AnimationLibrary = (load(PROFILES[character]) as Resource).get("action_animation_library") as AnimationLibrary
			if library == null:
				continue
			var found := false
			for name in library.get_animation_list():
				if String(name).begins_with("%s-%s-" % [character, clip]):
					found = true
					break
			_expect(found, "%s can play selector %d (%s), used by action %d" % [character, selector, clip, placed[selector]])
