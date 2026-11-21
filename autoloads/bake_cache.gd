extends Node

# Keeps the last level's static depth bake, and the images it was composed from, across the
# scene change a retry makes. A retry reloads the same scene from zero (sub_407370 case 9), so
# its world composes from exactly the same actors in the same order; when the new
# WorldDepthCompositor's signature matches, it adopts these buffers instead of composing
# them again. An autoload because nothing else outlives the level: a static on the
# compositor's script would be freed with it. See docs/map-rendering.md.
#
# The editor never uses it: a reimported texture keeps its path, so the signature would not
# notice the change.

# The level scene everything here belongs to; a compositor in any other scene starts it over.
var scene_path := ""
var _signature := ""
var _color: Image
var _scores: Image
var _bounds := Rect2()
# Texture key -> Image, and the derived caches keyed off those images, shared with whichever
# compositor is live so a retry reads nothing back from the GPU either.
var images: Dictionary = {}
var regions: Dictionary = {}
var opaque_rects: Dictionary = {}
var hits := 0


# Called by a compositor as it becomes ready in the level scene at path. Returns whether the
# cache now serves that scene: an unnamed scene, such as a test's hand-built world, has none.
func attach(path: String) -> bool:
	if path == "":
		return false
	if path != scene_path:
		clear()
		scene_path = path
	return true


# Copies, because the compositor repaints its own buffers in place as the level plays.
func store(signature: String, color: Image, scores: Image, bounds: Rect2) -> void:
	_signature = signature
	_color = color.duplicate() as Image
	_scores = scores.duplicate() as Image
	_bounds = bounds


# The stored bake as fresh copies, or an empty dictionary for any other signature.
func take(signature: String) -> Dictionary:
	if _signature == "" or signature != _signature:
		return {}
	hits += 1
	return {"color": _color.duplicate() as Image, "scores": _scores.duplicate() as Image, "bounds": _bounds}


func clear() -> void:
	scene_path = ""
	_signature = ""
	_color = null
	_scores = null
	_bounds = Rect2()
	images.clear()
	regions.clear()
	opaque_rects.clear()
