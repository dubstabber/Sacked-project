extends Node

# The port's own profiling, off unless the command line asks for it after `--`:
#
#   --perf-log            print every frame longer than SPIKE_MS with what ran in it
#   --perf-bench=N        load level N through ScreenManager, time the load, run it for
#                         --perf-seconds (default 8), print one PERF_RESULT line and quit
#   --perf-storm          during the bench, swap one object's state every STORM_INTERVAL s
#   --perf-restart        after the bench, restart the level once and time that load too
#   --perf-mode=points    bench the points game instead of the time game
#
# tools/benchmark_levels.py drives the bench. Frames are timed between consecutive
# frame_post_draw signals, so a frame's time includes everything the engine did for it.
# See docs/map-rendering.md, "Measured cost".

const SPIKE_MS := 20.0
const STORM_INTERVAL := 1.0
const DEFAULT_SECONDS := 8.0

var _args := {}
var _last_frame_usec := 0
var _last_resources := 0
var _frames_ms: PackedFloat32Array = PackedFloat32Array()
var _spikes: Array = []
var _recording := false
var _log := false
# The sections of the frame _on_frame_post_draw closed last, for a bench awaiting that frame.
var _last_sections := {}


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if not arg.begins_with("--perf-"):
			continue
		var parts := arg.trim_prefix("--").split("=", true, 1)
		_args[parts[0]] = parts[1] if parts.size() > 1 else "1"
	if _args.is_empty():
		set_process(false)
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
	PerfProbe.enabled = true
	_log = _args.has("perf-log")
	RenderingServer.frame_post_draw.connect(_on_frame_post_draw)
	_last_frame_usec = Time.get_ticks_usec()
	_last_resources = int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT))
	if _args.has("perf-bench"):
		_run_bench.call_deferred()


func _on_frame_post_draw() -> void:
	var now := Time.get_ticks_usec()
	var frame_ms := float(now - _last_frame_usec) / 1000.0
	_last_frame_usec = now
	var resources := int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT))
	var loaded := resources - _last_resources
	_last_resources = resources
	var sections := PerfProbe.take_frame()
	_last_sections = sections
	if _recording:
		_frames_ms.append(frame_ms)
	if frame_ms < SPIKE_MS:
		return
	var spike := {
		"ms": snappedf(frame_ms, 0.01),
		"resources": loaded,
		"process_ms": snappedf(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, 0.01),
		"physics_ms": snappedf(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, 0.01),
		"sections": _section_summary(sections),
	}
	if _recording:
		_spikes.append(spike)
	if _log:
		print("PERF_SPIKE ", JSON.stringify(spike))


func _section_summary(sections: Dictionary) -> Dictionary:
	var summary := {}
	for section in sections:
		var entry: Array = sections[section]
		summary[String(section)] = [snappedf(float(entry[0]) / 1000.0, 0.01), entry[1]]
	return summary


func _screens() -> Node:
	return get_node_or_null("/root/ScreenManager")


func _run_bench() -> void:
	var screens := _screens()
	if screens == null:
		push_error("PerfMonitor needs the ScreenManager autoload")
		get_tree().quit(1)
		return
	var level := int(_args.get("perf-bench", "1"))
	var seconds := float(_args.get("perf-seconds", str(DEFAULT_SECONDS)))
	var result := {"level": level, "mode": String(_args.get("perf-mode", "time"))}
	# Two frames on the starting screen, so its own load is not counted against the level's.
	await get_tree().process_frame
	await get_tree().process_frame
	screens.set("selected_game_mode", StringName(result["mode"]))
	result["load"] = await _timed_load(func() -> void: screens.call("start_level", level))
	if result["load"].is_empty():
		get_tree().quit(1)
		return

	_frames_ms = PackedFloat32Array()
	_spikes = []
	_recording = true
	var storm := _args.has("perf-storm")
	var storm_objects := _storm_objects() if storm else []
	var swaps := 0
	var started := Time.get_ticks_msec()
	var next_storm := STORM_INTERVAL
	while float(Time.get_ticks_msec() - started) / 1000.0 < seconds:
		await RenderingServer.frame_post_draw
		var elapsed := float(Time.get_ticks_msec() - started) / 1000.0
		if storm and elapsed >= next_storm and swaps < storm_objects.size():
			next_storm += STORM_INTERVAL
			var entry: Array = storm_objects[swaps]
			if is_instance_valid(entry[0]):
				(entry[0] as MapObject).set_state(int(entry[1]))
			swaps += 1
	_recording = false
	result["frames"] = _frame_stats(_frames_ms)
	result["storm_swaps"] = swaps
	_spikes.sort_custom(func(a, b): return a["ms"] > b["ms"])
	result["spikes"] = _spikes.slice(0, 12)
	result["spike_count"] = _spikes.size()

	if _args.has("perf-restart"):
		result["restart"] = await _timed_load(func() -> void: screens.call("restart_level"))

	print("PERF_RESULT ", JSON.stringify(result))
	get_tree().quit(0)


# Times a scene change into a level up to the end of the first frame drawn after the world
# composite exists, and sums the sections that ran on the way.
func _timed_load(start: Callable) -> Dictionary:
	var totals := {}
	var started := Time.get_ticks_usec()
	start.call()
	var deadline := Time.get_ticks_msec() + 60000
	while Time.get_ticks_msec() < deadline:
		await RenderingServer.frame_post_draw
		_accumulate(totals, _last_sections)
		var scene := get_tree().current_scene
		if scene == null or scene.get_node_or_null("LevelRuntime") == null:
			continue
		var mask := scene.get_node_or_null("World/WorldDepthCompositor")
		if mask != null and int(mask.get("full_rebuilds")) >= 1:
			break
	var total_ms := float(Time.get_ticks_usec() - started) / 1000.0
	if Time.get_ticks_msec() >= deadline:
		push_error("the level never finished loading")
		return {}
	return {"total_ms": snappedf(total_ms, 0.1), "sections": _section_summary(totals)}


func _accumulate(totals: Dictionary, frame: Dictionary) -> void:
	for section in frame:
		var entry: Array = frame[section]
		var total: Array = totals.get(section, [0, 0])
		totals[section] = [int(total[0]) + int(entry[0]), int(total[1]) + int(entry[1])]


# Each object with a one-shot DESTROY_n clip of more than one frame, in tree order, paired
# with the first such state, so every bench of a level swaps the same objects in turn.
func _storm_objects() -> Array:
	var picks: Array = []
	for node in get_tree().get_nodes_in_group(MapObject.PICK_GROUP):
		var object := node as MapObject
		if object == null:
			continue
		for target in range(MapObject.FIRST_TRANSITION_STATE, MapObject.LAST_TRANSITION_STATE + 1):
			if object.has_state(target):
				picks.append([object, target])
				break
	return picks


func _frame_stats(frames: PackedFloat32Array) -> Dictionary:
	if frames.is_empty():
		return {}
	var sorted := Array(frames)
	sorted.sort()
	var total := 0.0
	for value in sorted:
		total += value
	return {
		"count": sorted.size(),
		"mean_ms": snappedf(total / sorted.size(), 0.01),
		"p50_ms": snappedf(sorted[int(sorted.size() * 0.5)], 0.01),
		"p95_ms": snappedf(sorted[mini(int(sorted.size() * 0.95), sorted.size() - 1)], 0.01),
		"p99_ms": snappedf(sorted[mini(int(sorted.size() * 0.99), sorted.size() - 1)], 0.01),
		"max_ms": snappedf(sorted.back(), 0.01),
		"over_20ms": sorted.filter(func(v): return v >= 20.0).size(),
	}
