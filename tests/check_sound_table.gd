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
	if _failures == 0:
		print("Sound table: the buses, the index and every sound level 1 can ask for resolved")
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
