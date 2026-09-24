extends SceneTree

# The original's sound index and what a level does with it; see docs/sound-reference.md.

const AUDIO := preload("res://scenes/level/level_audio.gd")
const MANIFEST := "res://resources/original/sounds.json"

var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_check_buses()
	_check_manifest()
	_check_every_level_action_sound_resolves()
	_check_the_duel_and_the_win_sounds_resolve()
	_check_one_shots_belong_to_the_sound_handler()
	await _check_the_warning_loops()
	if _failures == 0:
		print("Sound table: the buses, the index, every sound a level and its duel ask for, the one-shot handler and the warning loop passed")
	quit(1 if _failures else 0)


func _expect(condition: bool, label: String) -> void:
	if not condition:
		_failures += 1
		push_error(label)


# What a level plays through. The volumes themselves now come from the player's own
# settings file rather than the bus layout, so check_settings_store.gd pins the original's
# 75 and 65 against a temporary file instead of whatever this machine last chose.
func _check_buses() -> void:
	for bus in ["Master", "Music", "SFX"]:
		_expect(AudioServer.get_bus_index(bus) >= 0, "the %s bus exists" % bus)


func _check_manifest() -> void:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	_expect(parsed is Dictionary, "the sound index is exported")
	if not (parsed is Dictionary):
		return
	var effects: Array = parsed["effects"]
	_expect(effects.size() == 116, "the index lists all 116 effects, got %d" % effects.size())
	var without_file := 0
	for entry in effects:
		if String(entry["stream"]) == "":
			without_file += 1
		else:
			_expect(ResourceLoader.exists(String(entry["stream"])), "%s resolves to a file" % entry["id"])
	_expect(without_file == 22, "22 indexed effects ship no file, got %d" % without_file)
	# sub_42A2D0 keeps the number as the entry's already-loaded flag.
	var preloaded: Array = effects.filter(func(e): return bool(e["preloaded"])).map(func(e): return String(e["id"]))
	_expect(preloaded.size() == 12, "12 entries carry the preload flag, got %d" % preloaded.size())
	for name in ["S1000", "S1012", "S1100"]:
		_expect(preloaded.has(name), "%s carries the preload flag" % name)
	for track in ["Menu1", "Theme1", "Theme2", "Theme3"]:
		_expect(ResourceLoader.exists(String(parsed["music"][track])), "%s is in the project" % track)


func _check_every_level_action_sound_resolves() -> void:
	var actions = JSON.parse_string(FileAccess.get_file_as_string("res://resources/original/actions.json"))
	var ids := {}
	var levels := 0
	for manifest_path in _level_manifest_paths():
		var manifest = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
		if manifest == null:
			continue
		levels += 1
		for item in manifest["objects"]:
			for action_id in item["action_ids"]:
				if int(action_id) > 0:
					ids[String(actions["actions"][int(action_id)]["sound"])] = int(action_id)
	_expect(levels > 0, "at least one level manifest was read")
	_expect(ids.size() > 0, "the imported levels' actions name sounds")
	for sound_id in ids:
		if sound_id == "":
			continue
		_expect(AUDIO.effect_stream(sound_id) != null, "%s, used by action %d, resolves" % [sound_id, ids[sound_id]])


func _level_manifest_paths() -> Array[String]:
	var paths: Array[String] = []
	var dir := DirAccess.open("res://resources/levels")
	if dir == null:
		return paths
	for file in dir.get_files():
		var name := file.trim_suffix(".remap")
		if name.begins_with("level_") and name.ends_with(".json"):
			paths.append("res://resources/levels/" + name)
	paths.sort()
	return paths


# The seven casts and their answers are S1004 to S1010; the duel's own outcome is S1002 or
# S1001, and the win screen's is S1100. See docs/minigame-reference.md.
func _check_the_duel_and_the_win_sounds_resolve() -> void:
	var names := ["S1001", "S1002", "S1100"]
	for index in range(7):
		names.append("S%04d" % (1004 + index))
	for sound_id in names:
		_expect(AUDIO.effect_stream(sound_id) != null, "%s resolves" % sound_id)


# sub_42A6A0 plays every one-shot through the game's own handler, which no screen change
# flushes, so the port's copy lives on the ScreenManager autoload. Only the warning loops, and
# it stays with the level so the result screens can stop it.
func _check_one_shots_belong_to_the_sound_handler() -> void:
	var screens: Node = root.get_node_or_null("ScreenManager")
	_expect(screens != null, "the ScreenManager autoload is live")
	if screens == null:
		return
	_expect(screens.play_effect("S9999") == null, "an unknown sound plays nothing")
	var cue: AudioStreamPlayer = screens.play_effect("S1002")
	_expect(cue != null and cue.get_parent() == screens, "a one-shot belongs to the autoload")
	if cue != null:
		_expect(cue.bus == &"SFX", "on the effects bus")
		_expect(is_zero_approx(cue.volume_db), "at the full effects volume")
		_expect((cue.stream as AudioStreamWAV).loop_mode == AudioStreamWAV.LOOP_DISABLED, "and it does not loop")
		paused = true
		_expect(cue.can_process(), "it plays on under a pause")
		paused = false
		cue.free()
	var quiet: AudioStreamPlayer = screens.play_effect("S1002", true)
	_expect(
		quiet != null and is_equal_approx(quiet.volume_db, linear_to_db(AUDIO.QUIET_SCALE)),
		"the quiet flag starts it at a tenth of the effects volume"
	)
	if quiet != null:
		quiet.free()

	var audio: Node = AUDIO.new()
	root.add_child(audio)
	_expect(audio.is_in_group("level_audio"), "the level's audio joins the group the duel looks it up by")
	var shot: AudioStreamPlayer = audio.play_effect("S1004")
	_expect(shot != null and shot.get_parent() == screens, "the level hands its one-shots to the autoload")
	if shot != null:
		shot.free()
	var warning: AudioStreamPlayer = audio.play_effect("S1012", true)
	_expect(warning == audio._warning, "the looping warning stays with the level")
	audio._screens = null
	var fallback: AudioStreamPlayer = audio.play_effect("S1004")
	_expect(
		fallback != null and fallback.get_parent() == audio,
		"without the autoload the level plays its one-shots itself"
	)
	root.remove_child(audio)
	audio.free()


# sub_403780 starts S1012 with the loop flag, which sub_45F9B0 turns into DSBPLAY_LOOPING over
# the whole clip. The imported clip has no loop points of its own, and a forward loop that
# ends at sample 0 never starts at all.
func _check_the_warning_loops() -> void:
	var audio: Node = AUDIO.new()
	root.add_child(audio)
	var warning: AudioStreamPlayer = audio.play_effect("S1012", true)
	var wav := warning.stream as AudioStreamWAV if warning != null else null
	_expect(wav != null and wav.loop_mode == AudioStreamWAV.LOOP_FORWARD, "the warning loops")
	if wav != null:
		_expect(
			wav.loop_begin == 0 and wav.loop_end == roundi(wav.get_length() * wav.mix_rate),
			"over the whole clip, got %d to %d" % [wav.loop_begin, wav.loop_end]
		)
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < 300:
		await process_frame
	_expect(
		warning != null and warning.playing and warning.get_playback_position() > 0.0,
		"and it is actually heard: the playback has moved on"
	)
	root.remove_child(audio)
	audio.free()
