extends SceneTree


const MapObjectScript := preload("res://scenes/shared/map_object.gd")
# The server is the richest level-1 case: a real seven frame transition plus three
# single frame results.
const ServerScene := "res://scenes/objects/aktiv-server-000.tscn"
# The mirror ships DESTROYED_1 but no DESTROY_1, so breaking it plays the IDLE clip the
# factory put in that slot, once, and then settles on its broken art.
const MirrorScene := "res://scenes/objects/aktiv-spiegel-000.tscn"
# The phone's one-frame DESTROY_1 finishes into a DESTROYED_1 it does not ship, which shows
# IDLE again.
const PhoneScene := "res://scenes/objects/aktiv-telefon01-000.tscn"
# The copier is level 2's looping case: DESTROYED_1 runs 25 frames at 16 fps and never
# settles, and the first NPC to use the copier puts it there in ordinary play.
const CopierScene := "res://scenes/objects/aktiv-kopierer-000.tscn"
# The janitor's case (level 8, action 51) ships a one-frame DESTROY_1 at 16 fps that is a
# 16x16 square of its own colour key: invisible in the original, then DESTROYED_1.
const CaseScene := "res://scenes/objects/aktiv-hmkoffer-000.tscn"

var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_check_state_names()
	await _check_single_frame_swap()
	await _check_transition_settles()
	await _check_single_frame_transition_settles()
	await _check_missing_transition_plays_idle_once()
	await _check_missing_settled_state_shows_idle()
	await _check_new_state_replaces_a_running_clip()
	await _check_idle_restores()
	await _check_looping_state_runs_and_leaves_the_bake()
	if _failures == 0:
		print("Map object states: transitions, settling, looping and the missing-clip fallback passed")
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


func _check_single_frame_transition_settles() -> void:
	var case_node := _instance(CaseScene)
	await process_frame
	var settled: Array = []
	case_node.state_changed.connect(func(state: int) -> void: settled.append(state))
	case_node.set_state(2)
	_expect(case_node.state == 2, "the case enters its one-frame DESTROY_1")
	_expect(case_node.is_processing(), "a one-frame transition still runs on the clock")
	var image := (case_node.color_texture as Texture2D).get_image()
	image.convert(Image.FORMAT_RGBA8)
	var opaque := 0
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			if image.get_pixel(x, y).a8 > 0:
				opaque += 1
	_expect(opaque == 0, "the case's DESTROY_1 is all colour key and draws nothing, %d pixels show" % opaque)
	# One frame at 16 fps lasts a sixteenth of a second.
	case_node._process(0.05)
	_expect(case_node.state == 2, "the frame holds for its own duration, got %d" % case_node.state)
	case_node._process(0.02)
	_expect(case_node.state == 9, "a finished one-frame DESTROY_1 advances to DESTROYED_1, got %d" % case_node.state)
	_expect(not case_node.is_processing(), "the settled single frame stops the clock")
	_expect(settled == [2, 9], "the case reported both states, got %s" % [settled])
	_release(case_node)


func _check_missing_transition_plays_idle_once() -> void:
	var mirror := _instance(MirrorScene)
	await process_frame
	var idle: Texture2D = mirror.color_texture
	_expect(not mirror.has_state(2), "the mirror ships no DESTROY_1")
	_expect(mirror.has_state(9), "the mirror does ship DESTROYED_1")
	mirror.set_state(2)
	_expect(mirror.state == 2, "the missing DESTROY_1 is entered, got %d" % mirror.state)
	_expect(mirror.color_texture == idle, "and plays the IDLE clip in its place")
	_expect(mirror.is_processing(), "once, on the clock")
	# The mirror's IDLE is one frame at 16 fps.
	mirror._process(0.05)
	_expect(mirror.state == 2, "IDLE holds for its own length, got %d" % mirror.state)
	mirror._process(0.02)
	_expect(mirror.state == 9, "and then settles on DESTROYED_1, got %d" % mirror.state)
	_expect(mirror.color_texture != idle, "the mirror shows its broken art")
	_release(mirror)


func _check_missing_settled_state_shows_idle() -> void:
	var phone := _instance(PhoneScene)
	await process_frame
	var idle: Texture2D = phone.color_texture
	_expect(not phone.has_state(9), "the phone ships no DESTROYED_1")
	phone.set_state(2)
	_expect(phone.color_texture != idle, "its DESTROY_1 shows a frame of its own")
	phone._process(0.1)
	_expect(phone.state == 9, "the phone's DESTROY_1 settles on DESTROYED_1, got %d" % phone.state)
	_expect(phone.color_texture == idle, "which shows IDLE again")
	_expect(not phone.is_processing(), "and runs no clock")
	_release(phone)


# Every state has a clip, so every set_state replaces the one playing and a clip only ever
# settles its own state.
func _check_new_state_replaces_a_running_clip() -> void:
	var server := _instance(ServerScene)
	await process_frame
	var idle: Texture2D = server.color_texture
	server.set_state(3)
	server._process(0.25)
	server.set_state(2)
	_expect(server.state == 2 and server.color_texture == idle, "a missing DESTROY_1 mid-transition shows IDLE at once")
	server._process(0.07)
	_expect(server.state == 9, "and settles on DESTROYED_1 after IDLE's length, got %d" % server.state)
	_release(server)


func _check_idle_restores() -> void:
	var server := _instance(ServerScene)
	await process_frame
	var idle: Texture2D = server.color_texture
	server.set_state(9)
	server.set_state(0)
	_expect(server.state == 0, "the object can be put back to IDLE")
	_expect(server.color_texture == idle, "IDLE restores the texture the level was built with")
	_release(server)


# A DESTROYED_n with real frames runs for as long as the object is held in it, and while it
# does the object is drawn as a depth-tested actor rather than baked into the static world
# composite. Leaving it in the bake costs a full repaint per frame, forever: measured on
# level 2 that is 53 fps against 120. See docs/map-rendering.md.
func _check_looping_state_runs_and_leaves_the_bake() -> void:
	var copier := _instance(CopierScene)
	await process_frame
	_expect(copier.is_in_group(MapObjectScript.WORLD_GROUP), "an idle object bakes into the world composite")
	_expect(not copier.is_in_group(MapObjectScript.ACTOR_GROUP), "an idle object is not a depth actor")
	_expect(copier.is_in_group(MapObjectScript.PICK_GROUP), "an idle object can be picked")

	copier.set_state(9)
	_expect(copier.state == 9, "the copier reaches DESTROYED_1")
	var frames: Array = copier.get("_clip")
	_expect(frames.size() == 25, "the copier's DESTROYED_1 ships 25 frames, got %d" % frames.size())
	_expect(bool(copier.get("_clip_loops")), "DESTROYED_1 carries the container's loop flag")
	_expect(copier.is_in_group(MapObjectScript.ACTOR_GROUP), "a looping object is drawn as a depth actor")
	_expect(not copier.is_in_group(MapObjectScript.WORLD_GROUP), "a looping object leaves the static bake")
	# sub_411E20 registers the click box whatever the state, so leaving the bake never
	# leaves the pick. See docs/player-action-reference.md.
	_expect(copier.is_in_group(MapObjectScript.PICK_GROUP), "a looping object can still be picked")

	var idle_texture: Texture2D = copier.get("_idle_texture")
	# 25 frames at 16 fps is 1.5625 s, so 40 steps of a sixteenth run past the end and wrap.
	var seen := {}
	for step in range(40):
		copier._process(0.0625)
		seen[copier.color_texture.resource_path] = true
	_expect(seen.size() == 25, "a looping clip shows every frame and wraps, saw %d" % seen.size())
	_expect(copier.state == 9, "a looping clip does not settle onto another state")
	_expect(copier.is_processing(), "a looping clip keeps animating past its last frame")
	_expect(copier.get("_clip").size() == 25, "the clip is still loaded after wrapping")

	copier.set_state(0)
	_expect(copier.state == 0, "the object can be put back to IDLE")
	_expect(copier.color_texture == idle_texture, "IDLE restores the texture the level was built with")
	_expect(not copier.is_processing(), "IDLE ends the loop")
	_expect(copier.is_in_group(MapObjectScript.WORLD_GROUP), "the object returns to the static bake")
	_expect(not copier.is_in_group(MapObjectScript.ACTOR_GROUP), "the object stops being a depth actor")
	_expect(copier.is_in_group(MapObjectScript.PICK_GROUP), "the object back in the bake can be picked")
	_release(copier)
