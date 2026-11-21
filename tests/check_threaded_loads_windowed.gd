extends SceneTree

# A clip's later frames, an object's and a character's, load on worker threads (ThreadedLoads)
# only where the renderer can create a texture off the main thread, so this runs in a window
# rather than headless. It plays level 1 and holds every frame the loads served to the one
# the clip names:
#
# - each frame of the Colamat's DESTROY_2 shows its own color and depth texture, though all
#   but the first were asked of the worker threads when the state changed;
# - for three seconds of the office going about its day, every character's shader holds the
#   depth plane of the frame its sprite shows;
# - once the level is gone, every request a clip never took has been released and collected.

const LEVEL := "res://scenes/level_1.tscn"
const SECONDS := 3.0

var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if not ThreadedLoads.available():
		_expect(false, "worker threads can load textures here; run this in a window, not headless")
		quit(1)
		return
	var level := (load(LEVEL) as PackedScene).instantiate()
	root.add_child(level)
	for frame in range(3):
		await process_frame

	await _check_an_object_clip(level)
	await _check_the_characters_depth_planes(level)

	# A character mid-clip still holds the requests for the frames it has not shown yet, so
	# the count only has to reach zero once the level, and every clip in it, has gone.
	root.remove_child(level)
	level.free()
	for frame in range(600):
		if ThreadedLoads.pending_count() == 0:
			break
		await process_frame
	_expect(ThreadedLoads.pending_count() == 0, "every request is taken or collected (%d left)" % ThreadedLoads.pending_count())
	if _failures == 0:
		print("Threaded loads: an object clip and the characters' depth planes show the frames their clips name, and nothing is left loading")
	quit(1 if _failures else 0)


func _check_an_object_clip(level: Node) -> void:
	var object: MapObject = level.get_node("World/Objects/Object036Colamat")
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://resources/objects/aktiv-colamat-000.json"))
	var clip: Dictionary = manifest["states"]["DESTROY_2"]
	var frames: Array = clip["frames"]
	var before := ThreadedLoads.pending_count()
	object.set_state(int(clip["state"]))
	object.set_process(false)
	_expect(ThreadedLoads.pending_count() > before, "a multi-frame clip asks the worker threads for its later frames")
	var step := 1.0 / maxf(float(clip["fps"]), 1.0)
	for index in range(frames.size()):
		var path := String(frames[index]["texture"])
		_expect(object.color_texture != null and object.color_texture.resource_path == path, "the Colamat's frame %d shows %s" % [index, path.get_file()])
		var depth_path := path.get_basename() + "-depth.png"
		if ResourceLoader.exists(depth_path):
			_expect(object.depth_texture != null and object.depth_texture.resource_path == depth_path, "with its own depth plane")
		if index < frames.size() - 1:
			await process_frame
			object._process(step)
	object.set_state(0)
	await process_frame


func _check_the_characters_depth_planes(level: Node) -> void:
	var compositor: Node = level.get_node("World/CharacterDepthCompositor")
	var checked := 0
	var wrong := 0
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < SECONDS * 1000.0:
		await RenderingServer.frame_post_draw
		for node in get_nodes_in_group("depth_composited_characters"):
			var sprite := node.get_node_or_null("Sprite2D") as Sprite2D
			if sprite == null or sprite.texture == null or not (sprite.material is ShaderMaterial):
				continue
			var depth = (sprite.material as ShaderMaterial).get_shader_parameter("depth_map")
			var expected: String = compositor._depth_path_for_texture(sprite.texture.resource_path)
			if not ResourceLoader.exists(expected):
				continue
			checked += 1
			if not (depth is Texture2D) or (depth as Texture2D).resource_path != expected:
				wrong += 1
	_expect(checked > 0, "the characters were checked at all")
	_expect(wrong == 0, "every character shader holds its frame's depth plane (%d of %d frames did not)" % [wrong, checked])


func _expect(condition: bool, label: String) -> void:
	if not condition:
		_failures += 1
		push_error(label)
