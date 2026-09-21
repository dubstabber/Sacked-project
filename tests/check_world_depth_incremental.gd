extends SceneTree

# Every object state change used to recompose the whole static world, which measured about
# 600 ms on level 1 and made an animated prank impossible. This drives the real level's
# transitions and removals and holds the incremental result against a full recomposite.

const LEVEL := preload("res://scenes/level_1.tscn")
# Level 1's transitions measure about 16 ms per swap, with the Colamat's large frames
# peaking near 26. The bar that matters is the clip's own frame interval -- the fastest
# state clip runs at 16 fps, or 62 ms a frame -- so this catches a slide back toward the
# 600 ms full recomposite without failing on the spread between runs.
const BUDGET_MS := 40.0

# Every multi-frame clip level 1 can reach, with the object carrying it.
const TRANSITIONS := [
	["Object036Colamat", "aktiv-colamat-000", "DESTROY_2"],
	["Object036Colamat", "aktiv-colamat-000", "DESTROY_6"],
	["Object029Server", "aktiv-server-000", "DESTROY_2"],
	["Object031Pappaufsteller01", "aktiv-pappaufsteller01-000", "DESTROY_1"],
	["Object033Papierkorb01", "aktiv-papierkorb01-000", "DESTROY_1"],
	["Object044Wasserkocher", "aktiv-wasserkocher-000", "DESTROY_1"],
	["Object027Wasserspender", "aktiv-wasserspender-090", "DESTROY_1"],
	["Object048Kaffeemaschi", "aktiv-kaffeemaschi-270", "DESTROY_2"],
]

var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var level := LEVEL.instantiate()
	var runtime := level.get_node_or_null("LevelRuntime")
	if runtime != null:
		runtime.enabled = false
	root.add_child(level)
	await process_frame

	var mask = level.get_node_or_null("World/WorldDepthCompositor")
	if mask == null:
		_expect(false, "level 1 carries a world depth compositor")
		quit(1)
		return
	mask.set_process(false)
	mask.rebuild()
	_expect(mask.full_rebuilds >= 1, "the level composes its static world once on load")

	var worst := 0.0
	var worst_label := ""
	for entry in TRANSITIONS:
		var result := _check_transition(level, mask, entry[0], entry[1], entry[2])
		if result > worst:
			worst = result
			worst_label = "%s %s" % [entry[0], entry[2]]
	_check_removal(level, mask)

	print("Worst state swap: %.1f ms (%s); a full recomposite is about 600 ms" % [worst, worst_label])
	_expect(worst <= BUDGET_MS, "the slowest state swap stays inside %.0f ms, measured %.1f" % [BUDGET_MS, worst])
	level.free()
	if _failures == 0:
		print("World depth incremental: every level-1 transition repaints in place and matches a full recomposite")
	quit(1 if _failures else 0)


# Steps one clip frame by frame, timing each repaint. Returns the worst frame in ms.
func _check_transition(level: Node, mask: Node, object_name: String, key: String, clip_name: String) -> float:
	var object: MapObject = level.get_node_or_null("World/Objects/%s" % object_name)
	if object == null:
		_expect(false, "level 1 places %s" % object_name)
		return 0.0
	var clip := _clip(key, clip_name)
	if clip.is_empty():
		_expect(false, "%s ships a %s clip" % [key, clip_name])
		return 0.0

	var frame_count: int = (clip["frames"] as Array).size()
	var step := 1.0 / maxf(float(clip["fps"]), 1.0)
	var full_before: int = mask.full_rebuilds
	var partial_before: int = mask.partial_rebuilds
	var worst := 0.0

	object.set_state(int(clip["state"]))
	# Driven here rather than by the engine so every frame is measured exactly once. The
	# last frame is left showing, so the comparison below sees what the buffer was painted
	# from rather than a scene that has already moved on.
	object.set_process(false)
	for index in range(frame_count):
		var started := Time.get_ticks_usec()
		mask.rebuild()
		worst = maxf(worst, float(Time.get_ticks_usec() - started) / 1000.0)
		if index < frame_count - 1:
			object._process(step)

	var label := "%s %s" % [object_name, clip_name]
	var repaints: int = mask.partial_rebuilds - partial_before
	var recomposites: int = mask.full_rebuilds - full_before
	_expect(
		recomposites == 0,
		"%s never recomposes the whole world (%d of %d frames did)" % [label, recomposites, frame_count]
	)
	_expect(
		repaints + recomposites == frame_count,
		"%s redraws once per frame (%d repaints, %d recomposites, %d frames)"
			% [label, repaints, recomposites, frame_count]
	)
	_expect_matches_reference(mask, label)

	object.set_state(0)
	mask.rebuild()
	return worst


func _check_removal(level: Node, mask: Node) -> void:
	# A pickup takes its object out of the world; that has to repaint in place too.
	var object := level.get_node_or_null("World/Objects/Object039Feuerzeug")
	if object == null:
		_expect(false, "level 1 places Object039Feuerzeug")
		return
	var full_before: int = mask.full_rebuilds
	var partial_before: int = mask.partial_rebuilds
	object.get_parent().remove_child(object)
	object.free()
	mask.rebuild()
	_expect(mask.partial_rebuilds == partial_before + 1, "removing a picked-up object repaints in place")
	_expect(mask.full_rebuilds == full_before, "removing a picked-up object does not recompose the world")
	_expect_matches_reference(mask, "a removed object")


func _expect_matches_reference(mask: Node, label: String) -> void:
	var reference: Dictionary = mask.compose_reference_for_test()
	_expect(
		mask._color_image.get_data() == (reference.image as Image).get_data(),
		"%s leaves the world pixel for pixel identical to a full recomposite" % label
	)
	_expect(
		mask.depth_scores == reference.scores,
		"%s leaves the depth scores identical to a full recomposite" % label
	)


func _clip(key: String, clip_name: String) -> Dictionary:
	var path := "res://resources/objects/%s.json" % key
	if not FileAccess.file_exists(path):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary):
		return {}
	return (parsed as Dictionary).get("states", {}).get(clip_name, {})


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
