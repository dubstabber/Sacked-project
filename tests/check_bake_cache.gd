extends SceneTree

# A retry reloads the level from zero, and the BakeCache autoload hands its new world
# compositor the bake the last attempt started from instead of composing it again. Checked
# against the sha256 goldens, not against the cache itself:
#
# - a second instance of a scene adopts the first one's bake and hashes the same;
# - it still repaints a state swap in place exactly as a full recomposite would;
# - an instance whose objects differ before its first bake misses and composes its own;
# - another level starts the cache over.

const LEVEL_1 := "res://scenes/level_1.tscn"
const LEVEL_2 := "res://scenes/level_2.tscn"
const GOLDENS := "res://tests/fixtures/world_depth_goldens.json"

var _failures := 0
var _cache: Node


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_cache = root.get_node_or_null("BakeCache")
	if _cache == null:
		push_error("the BakeCache autoload is missing")
		quit(1)
		return
	_cache.clear()
	var goldens: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(GOLDENS))
	var golden: Dictionary = goldens[LEVEL_1]["bake"]

	var first := await _add(LEVEL_1)
	var first_mask: Node = first.get_node("World/WorldDepthCompositor")
	_expect(first_mask.cache_hits == 0, "the first attempt composes its own bake")
	_expect(_cache.scene_path == LEVEL_1, "and the cache now serves its scene")
	_expect(_hashes(first_mask) == golden, "the first bake hashes as recorded")
	_remove(first)

	var hits_before: int = _cache.hits
	var retry := await _add(LEVEL_1)
	var mask: Node = retry.get_node("World/WorldDepthCompositor")
	_expect(mask.cache_hits == 1 and _cache.hits == hits_before + 1, "a retry adopts the cached bake")
	_expect(_hashes(mask) == golden, "and it hashes the same as a composed one")
	_expect(mask.depth_texture != null and mask._composite.texture != null, "and publishes both textures")
	_expect_swap_matches_reference(retry, mask)
	_remove(retry)

	var moved := (load(LEVEL_1) as PackedScene).instantiate()
	(moved.get_node("World/Objects/Object036Colamat") as Node2D).position += Vector2(48, 24)
	moved = await _add_instance(moved)
	mask = moved.get_node("World/WorldDepthCompositor")
	_expect(mask.cache_hits == 0, "a scene whose objects differ composes its own bake")
	_expect(mask._color_image.get_data() == (mask.compose_reference_for_test().image as Image).get_data(), "and it is the right one")
	_remove(moved)

	var other := await _add(LEVEL_2)
	_expect(_cache.scene_path == LEVEL_2, "another level starts the cache over")
	_expect((other.get_node("World/WorldDepthCompositor") as Node).cache_hits == 0, "and composes its own bake")
	_remove(other)
	_cache.clear()

	if _failures == 0:
		print("Bake cache: a retry adopts the first attempt's bake and still repaints exactly; a changed scene and another level compose their own")
	quit(1 if _failures else 0)


func _add(path: String) -> Node:
	return await _add_instance((load(path) as PackedScene).instantiate())


func _add_instance(level: Node) -> Node:
	var runtime := level.get_node_or_null("LevelRuntime")
	if runtime != null:
		runtime.enabled = false
	root.add_child(level)
	await process_frame
	await process_frame
	return level


func _remove(level: Node) -> void:
	root.remove_child(level)
	level.free()


func _expect_swap_matches_reference(level: Node, mask: Node) -> void:
	var object: MapObject = level.get_node("World/Objects/Object036Colamat")
	var partial_before: int = mask.partial_rebuilds
	object.set_process(false)
	object.set_state(MapObject.STATE_NAMES.find("DESTROY_2"))
	mask.rebuild()
	_expect(mask.partial_rebuilds == partial_before + 1, "the adopted bake repaints a swap in place")
	var reference: Dictionary = mask.compose_reference_for_test()
	_expect(mask._color_image.get_data() == (reference.image as Image).get_data(), "exactly as a full recomposite would, pixel for pixel")
	_expect(mask.depth_scores == reference.scores, "and score for score")
	object.set_state(0)
	mask.rebuild()


func _hashes(mask: Node) -> Dictionary:
	var bounds: Rect2 = mask.depth_bounds
	return {
		"bounds": "%d,%d,%d,%d" % [bounds.position.x, bounds.position.y, bounds.size.x, bounds.size.y],
		"color": _sha256((mask._color_image as Image).get_data()),
		"scores": _sha256((mask._score_image as Image).get_data()),
	}


func _sha256(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()


func _expect(condition: bool, label: String) -> void:
	if not condition:
		_failures += 1
		push_error(label)
