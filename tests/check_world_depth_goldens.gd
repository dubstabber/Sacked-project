extends SceneTree

# Holds the depth compositing to fixed sha256 hashes rather than to a second run of the same
# code, so an optimisation that changes every result the same way still fails. Covered:
#
# - the whole static bake of levels 1 and 19, color, scores and bounds;
# - the same buffers after each frame of one state clip has repainted in place;
# - one cluster composed from real character and object frames, against a score window,
#   which takes every branch of the per-pixel loop: depth-tested, untested, the object
#   layer and the environment test.
#
# Run with `-- --update` to rewrite the goldens after a change that is meant to alter them.

const GOLDENS := "res://tests/fixtures/world_depth_goldens.json"
const LEVELS := ["res://scenes/level_1.tscn", "res://scenes/level_19.tscn"]
const CompositorScript := preload("res://scenes/shared/character_depth_compositor.gd")
const CLUSTER_FRAMES := [
	["res://images/characters/jobless/jobless-walk-down/jobless-walk-down-000.png", Vector2(10.0, 20.0), 140.0, false, true],
	["res://images/characters/boss/boss-stand-idle-down/boss-stand-idle-down-002.png", Vector2(30.0, 8.0), 150.0, false, true],
	["res://images/objects/aktiv-colamat-000.png", Vector2(0.0, 0.0), 145.0, true, true],
	["res://images/characters/jobless/jobless-walk-down/jobless-walk-down-000.png", Vector2(55.0, 40.0), 120.0, false, false],
]

var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var update := OS.get_cmdline_user_args().has("--update")
	var actual := {}
	for path in LEVELS:
		actual[path] = await _hash_level(path)
	actual["cluster"] = _hash_cluster()

	if update:
		var file := FileAccess.open(GOLDENS, FileAccess.WRITE)
		file.store_string(JSON.stringify(actual, "\t", true) + "\n")
		file.close()
		print("World depth goldens: rewrote %s" % GOLDENS)
		quit(0)
		return

	var expected = JSON.parse_string(FileAccess.get_file_as_string(GOLDENS)) if FileAccess.file_exists(GOLDENS) else null
	if not (expected is Dictionary):
		_expect(false, "%s exists; run this check with -- --update once" % GOLDENS)
	else:
		_compare(expected, actual, "")
	if _failures == 0:
		print("World depth goldens: the level 1 and 19 bakes, one repainted clip on each and a composed cluster hash as recorded")
	quit(1 if _failures else 0)


func _compare(expected: Dictionary, actual: Dictionary, prefix: String) -> void:
	for key in expected:
		var label := prefix + String(key)
		if not actual.has(key):
			_expect(false, "%s was measured" % label)
		elif expected[key] is Dictionary:
			_compare(expected[key], actual[key] if actual[key] is Dictionary else {}, label + " / ")
		else:
			_expect(str(expected[key]) == str(actual[key]), "%s is %s, got %s" % [label, expected[key], actual[key]])


func _hash_level(path: String) -> Dictionary:
	var level := (load(path) as PackedScene).instantiate()
	var runtime := level.get_node_or_null("LevelRuntime")
	if runtime != null:
		runtime.enabled = false
	root.add_child(level)
	await process_frame
	var mask = level.get_node("World/WorldDepthCompositor")
	mask.set_process(false)
	mask.rebuild()
	var hashes := {"bake": _hash_buffers(mask)}

	var pick := _first_clip(level)
	if pick.is_empty():
		_expect(false, "%s places an object with a multi-frame one-shot clip" % path)
	else:
		var object: MapObject = pick["object"]
		object.set_state(int(pick["state"]))
		object.set_process(false)
		var step := 1.0 / maxf(float(pick["fps"]), 1.0)
		var partial_before: int = mask.partial_rebuilds
		for index in range(int(pick["frames"])):
			mask.rebuild()
			if index < int(pick["frames"]) - 1:
				object._process(step)
		_expect(mask.partial_rebuilds > partial_before, "%s repaints %s in place" % [path, object.name])
		hashes["swap"] = _hash_buffers(mask)
		hashes["swap_object"] = "%s:%d" % [object.name, int(pick["state"])]
	root.remove_child(level)
	level.free()
	return hashes


func _hash_buffers(mask: Node) -> Dictionary:
	var bounds: Rect2 = mask.depth_bounds
	return {
		"bounds": "%d,%d,%d,%d" % [bounds.position.x, bounds.position.y, bounds.size.x, bounds.size.y],
		"color": _sha256((mask._color_image as Image).get_data()),
		"scores": _sha256((mask._score_image as Image).get_data()),
	}


# The first object in tree order -- the ITEM order -- with a one-shot DESTROY_n of more than
# one frame.
func _first_clip(level: Node) -> Dictionary:
	for object in level.get_node("World/Objects").get_children():
		if not (object is MapObject) or object.color_texture == null:
			continue
		var manifest := "res://resources/objects/%s.json" % object.color_texture.resource_path.get_file().get_basename()
		if not FileAccess.file_exists(manifest):
			continue
		var states: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(manifest)).get("states", {})
		for target in range(MapObject.FIRST_TRANSITION_STATE, MapObject.LAST_TRANSITION_STATE + 1):
			var clip: Dictionary = states.get(MapObject.STATE_NAMES[target], {})
			var frames: Array = clip.get("frames", [])
			if frames.size() > 1:
				return {"object": object, "state": target, "frames": frames.size(), "fps": float(clip.get("fps", 8.0))}
	return {}


func _hash_cluster() -> Dictionary:
	var compositor = CompositorScript.new()
	var actors: Array = []
	for index in range(CLUSTER_FRAMES.size()):
		var entry: Array = CLUSTER_FRAMES[index]
		var color := _image(String(entry[0]))
		var depth: Image = _image(String(entry[0]).get_basename() + "-depth.png") if entry[4] else null
		var actor := {
			"index": index,
			"color": color,
			"depth": depth,
			"position": entry[1],
			"size": color.get_size(),
			"base_y": entry[2],
			"opaque_rect": color.get_used_rect(),
		}
		if entry[3]:
			actor["item"] = true
		actors.append(actor)
	var bounds: Rect2 = compositor.union_bounds(actors)
	# A window over the middle of the cluster only, so pixels both inside and outside it are
	# composed; its scores rise across it so the test passes some pixels and rejects others.
	var window := Rect2(bounds.position + Vector2(20, 30), Vector2(60, 70))
	var scores := PackedFloat32Array()
	scores.resize(int(window.size.x) * int(window.size.y))
	for y in range(int(window.size.y)):
		for x in range(int(window.size.x)):
			scores[y * int(window.size.x) + x] = 60.0 + float(x) * 1.5 - float(y)
	compositor.set_environment_for_test(scores, window)
	var result: Dictionary = compositor.compose_region(actors, bounds)
	var hashes := {
		"bounds": "%d,%d,%d,%d" % [bounds.position.x, bounds.position.y, bounds.size.x, bounds.size.y],
		"color": _sha256((result["image"] as Image).get_data()),
		"items": _sha256((result["item_image"] as Image).get_data()),
		"scores": _sha256((result["scores"] as PackedFloat32Array).to_byte_array()),
	}
	compositor.free()
	return hashes


func _image(path: String) -> Image:
	var image := (load(path) as Texture2D).get_image()
	if image.is_compressed():
		image.decompress()
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	return image


func _sha256(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()


func _expect(condition: bool, label: String) -> void:
	if not condition:
		_failures += 1
		push_error(label)
