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

const NPC_SPECS := [
	{
		"id": &"secretary",
		"walk_speed_tiles": 1.8,
		"resource_name": "secretary",
		"idle_source": "SEKRETAERIN_IDLE#1#ATMEN",
		"walk_source": "SEKRETAERIN_WALK",
		"idle_prefix": "secretary-idle1-atmen-",
		"walk_prefix": "secretary-walk-",
	},
	{
		"id": &"janitor",
		"walk_speed_tiles": 1.2,
		"resource_name": "janitor",
		"idle_source": "HOUSEMEISTER_IDLE#1#ATMEN",
		"walk_source": "HOUSEMEISTER_WALK",
		"idle_prefix": "janitor-idle1-atmen-",
		"walk_prefix": "janitor-walk-",
	},
	{
		"id": &"male-employee-1",
		"walk_speed_tiles": 1.5,
		"resource_name": "male-employee-1",
		"idle_source": "ANGESTELLTER#1_IDLE#1#ATMEN",
		"walk_source": "ANGESTELLTER#1_WALK",
		"idle_prefix": "male-employee-1-idle1-atmen-",
		"walk_prefix": "male-employee-1-walk-",
	},
	{
		"id": &"male-employee-2",
		"walk_speed_tiles": 1.6,
		"resource_name": "male-employee-2",
		"idle_source": "ANGESTELLTER#2_IDLE#1#ATMEN",
		"walk_source": "ANGESTELLTER#2_WALK",
		"idle_prefix": "male-employee-2-idle1-atmen-",
		"walk_prefix": "male-employee-2-walk-",
	},
	{
		"id": &"female-employee-1",
		"walk_speed_tiles": 1.7,
		"resource_name": "female-employee-1",
		"idle_source": "ANGESTELLTE#1_IDLE#1#ATMEN",
		"walk_source": "ANGESTELLTE#1_WALK",
		"idle_prefix": "female-employee-1-idle1-atmen-",
		"walk_prefix": "female-employee-1-walk-",
	},
	{
		"id": &"female-employee-2",
		"walk_speed_tiles": 1.5,
		"resource_name": "female-employee-2",
		"idle_source": "ANGESTELLTE#2_IDLE#1#ATMEN",
		"walk_source": "ANGESTELLTE#2_WALK",
		"idle_prefix": "female-employee-2-idle1-atmen-",
		"walk_prefix": "female-employee-2-walk-",
	},
]

const PROFILE_SCRIPT := preload("res://scenes/player/character_profile.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	for spec in NPC_SPECS:
		var library := _build_library(spec)
		var resource_name: String = spec["resource_name"]
		var library_path := "res://scenes/npc/profiles/%s_animations.res" % resource_name
		var save_error := ResourceSaver.save(library, library_path)
		if save_error != OK:
			push_error("Failed to save %s: %s" % [library_path, error_string(save_error)])
			quit(1)
			return

		var profile := PROFILE_SCRIPT.new()
		profile.id = spec["id"]
		profile.walk_speed_tiles = spec["walk_speed_tiles"]
		profile.animation_library = load(library_path)
		profile.idle_animation_prefix = spec["idle_prefix"]
		profile.walk_animation_prefix = spec["walk_prefix"]
		profile.initial_texture = _load_initial_texture(resource_name, spec["idle_prefix"])
		var profile_path := "res://scenes/npc/profiles/%s.tres" % resource_name
		save_error = ResourceSaver.save(profile, profile_path)
		if save_error != OK:
			push_error("Failed to save %s: %s" % [profile_path, error_string(save_error)])
			quit(1)
			return

	quit(0)


func _build_library(spec: Dictionary) -> AnimationLibrary:
	var library := AnimationLibrary.new()
	_add_directional_animations(library, spec["idle_source"], spec["resource_name"], spec["idle_prefix"])
	_add_directional_animations(library, spec["walk_source"], spec["resource_name"], spec["walk_prefix"])
	return library


func _add_directional_animations(
	library: AnimationLibrary,
	source_prefix: String,
	resource_name: String,
	runtime_prefix: String
) -> void:
	for angle in DIRECTIONS:
		var direction_name: String = DIRECTIONS[angle]
		var animation_data := _read_json(
			"res://extract-sacked-assets/extracted/animations_godot/CO_CHARS_CO_CHARS_%s_%s_godot.json"
			% [source_prefix, angle]
		)
		var animation := Animation.new()
		animation.length = float(animation_data.get("duration_seconds", 0.0))
		animation.loop_mode = Animation.LOOP_LINEAR

		var texture_track := animation.add_track(Animation.TYPE_VALUE)
		animation.track_set_path(texture_track, NodePath("Sprite2D:texture"))
		var offset_track := animation.add_track(Animation.TYPE_VALUE)
		animation.track_set_path(offset_track, NodePath("Sprite2D:offset"))

		var key_time := 0.0
		for frame in animation_data["frames"]:
			var texture := load(_runtime_frame_path(resource_name, runtime_prefix, direction_name, frame))
			if texture == null:
				push_error("Missing runtime texture for %s %s" % [runtime_prefix, direction_name])
				quit(1)
				return
			animation.track_insert_key(texture_track, key_time, texture)
			var offset: Dictionary = frame["offset"]
			animation.track_insert_key(offset_track, key_time, Vector2(float(offset["x"]), float(offset["y"])))
			key_time += float(frame["duration_sec"])

		if animation.length <= 0.0:
			animation.length = maxf(key_time, 0.001)

		library.add_animation(runtime_prefix + direction_name, animation)


func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Failed to open %s" % path)
		quit(1)
		return {}

	var parsed = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		return parsed

	push_error("Failed to parse %s" % path)
	quit(1)
	return {}


func _runtime_frame_path(
	resource_name: String,
	runtime_prefix: String,
	direction_name: String,
	frame: Dictionary
) -> String:
	var suffix := String(frame["sprite_name"]).right(3)
	var clip_name := runtime_prefix + direction_name
	return "res://images/characters/%s/%s/%s-%s.png" % [
		resource_name,
		clip_name,
		clip_name,
		suffix,
	]


func _load_initial_texture(resource_name: String, idle_prefix: String) -> Texture2D:
	var clip_name := idle_prefix + "right"
	return load("res://images/characters/%s/%s/%s-000.png" % [
		resource_name,
		clip_name,
		clip_name,
	])
