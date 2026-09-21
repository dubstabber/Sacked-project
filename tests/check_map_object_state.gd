extends SceneTree


const MapObjectScript := preload("res://scenes/shared/map_object.gd")
# The server is the richest level-1 case: a real seven frame transition plus three
# single frame results.
const ServerScene := "res://scenes/objects/aktiv-server-000.tscn"
# The mirror ships no DESTROY_1 at all, so breaking it settles straight on DESTROYED_1.
const MirrorScene := "res://scenes/objects/aktiv-spiegel-000.tscn"

var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_check_state_names()
	await _check_single_frame_swap()
	await _check_transition_settles()
	await _check_missing_transition_settles_immediately()
	await _check_idle_restores()
	if _failures == 0:
		print("Map object states: transitions, settling and the missing-clip fallback passed")
	quit(1 if _failures else 0)


func _expect(condition: bool, label: String) -> void:
	if not condition:
		_failures += 1
		push_error(label)


func _instance(path: String) -> Node2D:
	var node := (load(path) as PackedScene).instantiate() as Node2D
	root.add_child(node)
	return node


func _release(node: Node) -> void:
	root.remove_child(node)
	node.free()


func _check_state_names() -> void:
	_expect(MapObjectScript.STATE_NAMES.size() == 16, "the engine clamps item states to sixteen")
	_expect(MapObjectScript.STATE_NAMES[0] == "IDLE", "state 0 is IDLE")
	_expect(MapObjectScript.STATE_NAMES[2] == "DESTROY_1", "state 2 is the first transition")
	_expect(MapObjectScript.STATE_NAMES[9] == "DESTROYED_1", "state 9 is the first settled state")
	_expect(
		MapObjectScript.STATE_NAMES[2 + MapObjectScript.DESTROYED_OFFSET] == "DESTROYED_1",
		"a transition advances to its own damaged state"
	)


func _check_single_frame_swap() -> void:
	var server := _instance(ServerScene)
	await process_frame
	var idle: Texture2D = server.color_texture
	# DESTROYED_1 is a single frame, so it applies at once and needs no animation.
	server.set_state(9)
	_expect(server.state == 9, "the object records the state it was put into")
	_expect(server.color_texture != idle, "a single frame state swaps the texture immediately")
	_expect(not server.is_processing(), "a single frame state does not animate")
	_expect(server.depth_texture != null, "the swapped frame brought its depth mask")
	_release(server)


func _check_transition_settles() -> void:
	var server := _instance(ServerScene)
	await process_frame
	var settled: Array = []
	server.state_changed.connect(func(state: int) -> void: settled.append(state))
	server.set_state(3)
	_expect(server.state == 3, "the transition state is entered")
	_expect(server.is_processing(), "a multi frame transition animates")
	var first: Texture2D = server.color_texture
	# Seven frames at 8 fps: run past the end and it must settle on DESTROYED_2.
	for i in range(12):
		server._process(0.125)
	_expect(server.state == 10, "a finished DESTROY_2 advances to DESTROYED_2, got %d" % server.state)
	_expect(not server.is_processing(), "the settled state stops animating")
	_expect(settled == [3, 10], "the object reported both states, got %s" % [settled])
	_expect(server.color_texture != first, "the settled state is not the transition's first frame")
	_release(server)


func _check_missing_transition_settles_immediately() -> void:
	var mirror := _instance(MirrorScene)
	await process_frame
	var idle: Texture2D = mirror.color_texture
	_expect(not mirror.has_state(2), "the mirror ships no DESTROY_1")
	mirror.set_state(2)
	_expect(mirror.state == 9, "a missing transition settles straight on DESTROYED_1, got %d" % mirror.state)
	_expect(mirror.color_texture != idle, "the mirror still shows its damaged art")
	_release(mirror)


func _check_idle_restores() -> void:
	var server := _instance(ServerScene)
	await process_frame
	var idle: Texture2D = server.color_texture
	server.set_state(9)
	server.set_state(0)
	_expect(server.state == 0, "the object can be put back to IDLE")
	_expect(server.color_texture == idle, "IDLE restores the texture the level was built with")
	_release(server)
