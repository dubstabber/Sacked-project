extends SceneTree

# The player's prank and ability animations. Which clip each action uses comes from the
# animation slot table at 0x46EC04 by way of sub_41A510's selector map; the abilities play
# slots 7 (PISS#1) and 12 (SMOKE) directly; see docs/player-action-reference.md. The frames
# themselves must still match the extracted source they were exported from.

const CONTROLLER := preload("res://scenes/player/prank_controller.gd")
const SPEC_PATH := "res://tools/character_action_clips.json"
const SOURCE_DIR := "res://extract-sacked-assets/extracted/animations_godot/"
const PROFILES := {
	"jobless": "res://scenes/player/profiles/jobless.tres",
	"anne": "res://scenes/player/profiles/anne.tres",
}
const SOURCE_PREFIXES := {"jobless": "JOBLESS", "anne": "ANNE"}
const DIRECTIONS := {
	"000": "up-right", "045": "right", "090": "down-right", "135": "down",
	"180": "down-left", "225": "left", "270": "up-left", "315": "up",
}
# sub_41D630 hands both characters this one record by name (0x41D716), 11 frames at 8 fps.
const PUDDLE_RECORD := "CO_CHARS_JOBLESS_PISSPUDDLE_000"
const PUDDLE_FRAMES := 11
const PUDDLE_FRAME_SECONDS := 0.125
const PIVOT_WRAP := 65536
const PIVOT_SIGN_LIMIT := 32768

var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var spec := _spec()
	if spec.is_empty():
		quit(1)
		return
	_check_libraries(spec)
	_check_every_slot_has_exactly_its_recovered_views(spec)
	_check_every_reachable_selector_has_a_clip(spec)
	_check_the_two_view_clip_is_asked_for_a_view_it_has()
	_check_the_puddle_library(spec)
	if _failures == 0:
		print("Player action clips: both characters carry every slot clip in the views the original ships, matching their source, and the puddle's frames match its record")
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
# extracted original would show up as a frame-count or timing mismatch here.
func _check_frames_match_source(animation: Animation, source: String, angle: String, label: String) -> void:
	var path := "%sCO_CHARS_CO_CHARS_%s_%s_godot.json" % [SOURCE_DIR, source, angle]
	if not FileAccess.file_exists(path):
		_expect(false, "%s has its extracted source %s" % [label, path])
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	var frames: Array = parsed["frames"]
	var track: int = animation.find_track("Sprite2D:texture", Animation.TYPE_VALUE)
	_expect(track >= 0, "%s drives the sprite texture" % label)
	if track < 0:
		return
	_expect(
		animation.track_get_key_count(track) == frames.size(),
		"%s has the original's %d frames, found %d" % [label, frames.size(), animation.track_get_key_count(track)]
	)
	_expect(
		absf(animation.length - float(parsed["duration_seconds"])) < 0.000001,
		"%s lasts the original's %.4f s, found %.4f" % [label, float(parsed["duration_seconds"]), animation.length]
	)
	var time := 0.0
	for index in range(mini(frames.size(), animation.track_get_key_count(track))):
		_expect(
			absf(animation.track_get_key_time(track, index) - time) < 0.000001,
			"%s frame %d starts at %.4f s as the original's durations put it" % [label, index, time]
		)
		time += float(frames[index]["duration_sec"])


# Every slot the player's table names has its clip in both profiles, in exactly the views the
# original ships for it -- no view dropped, none invented. The abilities reach slots 7 and 12
# without a selector, so the reachable-selector check below cannot see them.
func _check_every_slot_has_exactly_its_recovered_views(spec: Dictionary) -> void:
	var slots: Dictionary = spec.get("player_slots", {})
	_expect(slots.has("7") and slots.has("12"), "the spec lists the ability slots 7 and 12")
	for character in PROFILES:
		var library: AnimationLibrary = (load(PROFILES[character]) as Resource).get("action_animation_library") as AnimationLibrary
		if library == null:
			continue
		var slot_sources := {}
		for slot in slots:
			var source := "%s_%s" % [SOURCE_PREFIXES[character], String(slots[slot])]
			slot_sources[source] = true
			var recovered: Array = []
			for angle in DIRECTIONS:
				if FileAccess.file_exists("%sCO_CHARS_CO_CHARS_%s_%s_godot.json" % [SOURCE_DIR, source, angle]):
					recovered.append(angle)
			_expect(not recovered.is_empty(), "slot %s (%s) has extracted views" % [slot, source])
			var rows: Array = spec["clips"].filter(func(clip: Dictionary) -> bool:
				return String(clip["character"]) == character and String(clip["source"]) == source)
			_expect(rows.size() == 1, "%s has one spec row for slot %s (%s), found %d" % [character, slot, source, rows.size()])
			if rows.size() != 1:
				continue
			var row: Dictionary = rows[0]
			if row.has("slot"):
				_expect(int(row["slot"]) == int(slot), "%s's %s row names slot %s" % [character, source, slot])
			var angles: Array = row["angles"].map(func(angle) -> String: return String(angle))
			angles.sort()
			_expect(angles == recovered, "%s's %s row asks for the views %s the original ships, found %s" % [character, source, recovered, angles])
			var prefix := "%s-%s-" % [character, String(row["action"])]
			var expected_names: Array = recovered.map(func(angle: String) -> String: return prefix + String(DIRECTIONS[angle]))
			expected_names.sort()
			var found_names: Array = []
			for name in library.get_animation_list():
				if String(name).begins_with(prefix) and DIRECTIONS.values().has(String(name).trim_prefix(prefix)):
					found_names.append(String(name))
			found_names.sort()
			_expect(found_names == expected_names, "%s plays slot %s in exactly %s, found %s" % [character, slot, expected_names, found_names])
			for name in found_names:
				var angle: String = DIRECTIONS.find_key(String(name).trim_prefix(prefix))
				_check_frames_match_source(library.get_animation(name), source, angle, name)
		for row in spec["clips"]:
			if String(row["character"]) == character:
				_expect(slot_sources.has(String(row["source"])), "%s's %s row is a slot of the player's table" % [character, row["source"]])


func _check_every_reachable_selector_has_a_clip(_unused_spec: Dictionary) -> void:
	var actions = JSON.parse_string(FileAccess.get_file_as_string("res://resources/original/actions.json"))
	var placed := {}
	var dir := DirAccess.open("res://resources/levels")
	if dir != null:
		for file in dir.get_files():
			var name := file.trim_suffix(".remap")
			if not (name.begins_with("level_") and name.ends_with(".json")):
				continue
			var manifest = JSON.parse_string(FileAccess.get_file_as_string("res://resources/levels/" + name))
			if manifest == null:
				continue
			for item in manifest["objects"]:
				for action_id in item["action_ids"]:
					if int(action_id) > 0:
						placed[int(actions["actions"][int(action_id)]["player_animation"])] = int(action_id)
	_expect(not placed.is_empty(), "the imported levels place actions")

	for selector in placed:
		# Every selector the imported levels place must resolve to a clip.
		_expect(
			CONTROLLER.SELECTOR_CLIPS.has(selector),
			"selector %d, placed by action %d, has no imported clip" % [selector, placed[selector]]
		)
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


# ASSCOPY is the one clip that does not ship eight views, so the controller snaps to the
# nearer of the two it has. Those two vectors have to name animations that exist: the clip
# name is resolved from a screen angle, and getting that wrong leaves the player standing
# still through the prank with nothing failing.
func _check_the_two_view_clip_is_asked_for_a_view_it_has() -> void:
	var controller_facings: Array = CONTROLLER.ASSCOPY_FACINGS
	_expect(controller_facings.size() == 2, "the two-view clip offers two facings")
	var scene := load("res://scenes/player/player.tscn") as PackedScene
	for character in PROFILES:
		var player := scene.instantiate()
		player.profile = load(PROFILES[character])
		root.add_child(player)
		for facing: Vector2 in controller_facings:
			_expect(
				player.play_action_animation("asscopy", facing),
				"%s has an asscopy view for the facing %s the controller snaps to" % [character, facing]
			)
		# Every other facing must land on one of those two rather than on a missing clip.
		for angle in range(8):
			var arbitrary := Vector2.RIGHT.rotated(float(angle) * PI / 4.0)
			var facing: Vector2 = CONTROLLER.new()._nearest_asscopy_facing(arbitrary)
			_expect(
				controller_facings.has(facing),
				"an arbitrary facing snaps onto a view the clip has, got %s" % facing
			)
		root.remove_child(player)
		player.free()


# The puddle the urinating ability leaves is one CO_CHARS record for both characters. Its
# library is built from the spec's effects row like the characters' clips: texture and pivot
# change together on each of the record's frames, at the record's own durations.
func _check_the_puddle_library(spec: Dictionary) -> void:
	var rows: Array = spec.get("effects", []).filter(func(row: Dictionary) -> bool: return String(row["name"]) == "puddle")
	_expect(rows.size() == 1, "the spec lists the puddle effect once")
	if rows.size() != 1:
		return
	_expect(String(rows[0]["record"]) == PUDDLE_RECORD, "the puddle is the record the executable names, %s" % PUDDLE_RECORD)
	var source_path := "%sCO_CHARS_%s_godot.json" % [SOURCE_DIR, PUDDLE_RECORD]
	var source = JSON.parse_string(FileAccess.get_file_as_string(source_path))
	if not (source is Dictionary):
		_expect(false, "the puddle's extracted source %s parses" % source_path)
		return
	var frames: Array = source["frames"]
	_expect(frames.size() == PUDDLE_FRAMES, "the puddle's record has %d frames, found %d" % [PUDDLE_FRAMES, frames.size()])
	var library := load("res://scenes/effects/puddle_animations.res") as AnimationLibrary
	_expect(library != null, "the puddle library exists")
	if library == null:
		return
	_expect(library.get_animation_list() == [&"puddle"], "the puddle library holds only the puddle, found %s" % [library.get_animation_list()])
	var animation := library.get_animation("puddle")
	if animation == null:
		return
	var loops: bool = rows[0].get("loop", source["loop"])
	_expect(animation.loop_mode == (Animation.LOOP_LINEAR if loops else Animation.LOOP_NONE), "the puddle keeps its record's loop flag")
	_expect(
		absf(animation.length - PUDDLE_FRAMES * PUDDLE_FRAME_SECONDS) < 0.000001 and absf(animation.length - float(source["duration_seconds"])) < 0.000001,
		"the puddle lasts %d frames at 8 fps, found %.4f s" % [PUDDLE_FRAMES, animation.length]
	)
	var texture_track := animation.find_track(NodePath("Sprite2D:texture"), Animation.TYPE_VALUE)
	var offset_track := animation.find_track(NodePath("Sprite2D:offset"), Animation.TYPE_VALUE)
	_expect(texture_track >= 0 and offset_track >= 0, "the puddle drives the sprite's texture and pivot")
	if texture_track < 0 or offset_track < 0:
		return
	for track in [texture_track, offset_track]:
		_expect(animation.track_get_key_count(track) == frames.size(), "the puddle keys every frame on track %d" % track)
		_expect(animation.value_track_get_update_mode(track) == Animation.UPDATE_DISCRETE, "the puddle swaps frames without interpolating")
	var time := 0.0
	for index in range(mini(frames.size(), animation.track_get_key_count(texture_track))):
		var frame: Dictionary = frames[index]
		_expect(absf(float(frame["duration_sec"]) - PUDDLE_FRAME_SECONDS) < 0.000001, "puddle frame %d lasts an eighth of a second" % index)
		for track in [texture_track, offset_track]:
			_expect(absf(animation.track_get_key_time(track, index) - time) < 0.000001, "puddle frame %d starts at %.3f s" % [index, time])
		var expected_path := "res://images/effects/puddle/puddle-%03d.png" % index
		var texture := animation.track_get_key_value(texture_track, index) as Texture2D
		_expect(texture != null and texture.resource_path == expected_path, "puddle frame %d is %s" % [index, expected_path])
		if texture != null:
			_expect(texture.get_size() == Vector2(frame["w"], frame["h"]), "puddle frame %d keeps its %dx%d size" % [index, frame["w"], frame["h"]])
		var pivot := Vector2(_signed_pivot(float(frame["pivot_x"])), _signed_pivot(float(frame["pivot_y"])))
		_expect(animation.track_get_key_value(offset_track, index) == -pivot, "puddle frame %d is placed by its pivot %s" % [index, pivot])
		var mask_path := expected_path.get_basename() + "-depth.png"
		if FileAccess.file_exists("res://extract-sacked-assets/%s/SPRITEZB.bin" % String(frame["path"]).get_base_dir()):
			var mask := load(mask_path) as Texture2D
			_expect(mask != null and mask.get_size() == Vector2(frame["w"], frame["h"]), "puddle frame %d has its depth mask" % index)
		else:
			_expect(not ResourceLoader.exists(mask_path), "puddle frame %d has no depth mask, as its record has no Z plane" % index)
		time += float(frame["duration_sec"])


# SPRITEHDR's pivot is a signed 16-bit pair the extraction read unsigned; the importer
# sign-extends it, and so does this.
func _signed_pivot(value: float) -> float:
	return value - PIVOT_WRAP if value >= PIVOT_SIGN_LIMIT else value
