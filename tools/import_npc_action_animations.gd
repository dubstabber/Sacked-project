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
# Seated clips only exist for the four diagonal views; standing ones have all eight.
const SEATED_ANGLES := ["000", "090", "180", "270"]
const STANDING_ANGLES := ["000", "045", "090", "135", "180", "225", "270", "315"]
const ACTIONS := {
	"boss": [
		["CHEF_SIT#IDLE", "sit-idle", SEATED_ANGLES],
		["CHEF_SIT#EASY", "sit-easy", SEATED_ANGLES],
	],
	"male-employee-1": [
		["ANGESTELLTER#1_SIT#IDLE", "sit-idle", SEATED_ANGLES],
		["ANGESTELLTER#1_SIT#USE", "sit-use", SEATED_ANGLES],
		["ANGESTELLTER#1_SIT#EASY", "sit-easy", SEATED_ANGLES],
		["ANGESTELLTER#1_SPECIAL#1", "special-1", STANDING_ANGLES],
	],
	"female-employee-1": [
		["ANGESTELLTE#1_SIT#IDLE", "sit-idle", SEATED_ANGLES],
		["ANGESTELLTE#1_SIT#USE", "sit-use", SEATED_ANGLES],
		["ANGESTELLTE#1_SIT#EASY", "sit-easy", SEATED_ANGLES],
		["ANGESTELLTE#1_SPECIAL#1", "special-1", STANDING_ANGLES],
	],
}

var _failed := false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	for character in ACTIONS:
		var library := AnimationLibrary.new()
		for action in ACTIONS[character]:
			for angle in action[2]:
				var animation := _build_animation(character, action[0], action[1], angle)
				if _failed:
					quit(1)
					return
				library.add_animation("%s-%s-%s" % [character, action[1], DIRECTIONS[angle]], animation)
		var path := "res://scenes/npc/profiles/%s_actions.res" % character
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
		var offset: Dictionary = frame["offset"]
		animation.track_insert_key(texture_track, time, texture)
		animation.track_insert_key(offset_track, time, Vector2(float(offset["x"]), float(offset["y"])))
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
