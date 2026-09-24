extends SceneTree

# A state whose clip loops takes an object out of the static bake and draws it as a depth
# actor (docs/map-rendering.md), but the original registers an item's click box every frame
# it draws the item, whatever its state (sub_411E20 at 0x411F88). So a looping object must
# stay pickable, focusable and lit. Level 3 holds the three that loop after a prank: the
# copier after ASSCOPY (126 -> DESTROY_1, which it ships no art for, so DESTROYED_1's 25-frame
# loop), the radio after 38 and the stove after 21. See docs/player-action-reference.md.

const LEVEL := "res://scenes/level_3.tscn"
const ASSCOPY := 126
const RADIO_OFF := 38
const STOVE_ON := 21

var _failures := 0
var _level: Node
var _world: Node2D
var _player: Node2D
var _controller: Node
var _compositor: CharacterDepthCompositor


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_level = (load(LEVEL) as PackedScene).instantiate()
	_level.get_node("LevelRuntime").enabled = false
	root.add_child(_level)
	await process_frame
	await process_frame
	# A colleague walking in or a catch aborting the prank would make every case below
	# depend on where the cast happened to be.
	for agent in get_nodes_in_group("npc_agents"):
		agent.process_mode = Node.PROCESS_MODE_DISABLED
	var watch := _level.get_node_or_null("LevelRuntime/CatchWatch")
	if watch != null:
		watch.process_mode = Node.PROCESS_MODE_DISABLED
	_world = _level.get_node("World") as Node2D
	_player = _world.get_node("Player") as Node2D
	_player.set_physics_process(false)
	_controller = _player.get_node("PrankController")
	_controller.set_process(false)
	_compositor = _world.get_node("CharacterDepthCompositor") as CharacterDepthCompositor

	await _check_copier_after_asscopy()
	await _check_copier_while_it_is_used()
	await _check_copier_overlapping_the_player()
	await _check_nothing_left_still_tints_red(_object("Object036Radio"), RADIO_OFF, null)
	await _check_nothing_left_still_tints_red(_object("Object069Herd"), STOVE_ON, _object("Object014Spuelmaschine"))

	root.remove_child(_level)
	_level.free()
	if _failures == 0:
		print("Looping object focus: the copier, the radio and the stove stay picked, focused and lit through their loops, and the pulse is handed the scores of the surface it shares with the player")
	quit(1 if _failures else 0)


func _expect(condition: bool, label: String) -> void:
	if not condition:
		_failures += 1
		push_error(label)


func _object(object_name: String) -> MapObject:
	return _world.get_node("Objects/" + object_name) as MapObject


func _ids(entries: Array) -> Array:
	return entries.map(func(entry: Dictionary) -> int: return int(entry["action_id"]))


func _box(object: Node2D) -> Rect2:
	var sprite := object.get_node("Sprite2D") as Sprite2D
	return Rect2(sprite.to_global(sprite.offset), sprite.texture.get_size())


func _pick_depth(object: Node2D) -> float:
	return ceilf(float(int(object.global_position.y)) * 0.5)


# An opaque pixel of the object's current frame that no nearer pickable box covers, so the
# pick has only this object to find there. With `behind`, the pixel must also fall inside
# that object's box: where a pick that misses this object would land instead.
func _winning_point(object: Node2D, behind: Node2D = null) -> Vector2:
	var box := _box(object)
	var image := (object.get_node("Sprite2D") as Sprite2D).texture.get_image()
	if image.is_compressed():
		image.decompress()
	for y in range(0, int(box.size.y), 2):
		for x in range(0, int(box.size.x), 2):
			if image.get_pixel(x, y).a < 0.9:
				continue
			var point := box.position + Vector2(x, y) + Vector2(0.5, 0.5)
			if behind != null and not _box(behind).has_point(point):
				continue
			if not _covered_by_a_nearer_box(object, point):
				return point
	return Vector2.INF


func _covered_by_a_nearer_box(object: Node2D, point: Vector2) -> bool:
	for node in get_nodes_in_group(MapObject.PICK_GROUP):
		var other := node as Node2D
		if other == object or not other.is_visible_in_tree():
			continue
		var interaction := other.get_node_or_null("InteractionPoint")
		if interaction == null or (interaction.get("action_ids") as PackedInt32Array).is_empty():
			continue
		if _box(other).has_point(point) and _pick_depth(other) >= _pick_depth(object):
			return true
	return false


# Every free half-tile stand from which the player may act on the object.
func _stands(object: Node2D) -> Array[Vector2]:
	var point := object.get_node("InteractionPoint") as Node2D
	var layer := _world.get_node("CollisionTileMapLayer")
	var origin := IsoDirection.screen_to_ground(point.global_position)
	var saved := _player.global_position
	var found: Array[Vector2] = []
	for dy in range(-6, 7):
		for dx in range(-6, 7):
			var stand := IsoDirection.ground_to_screen(origin + Vector2(dx, dy) * 0.5)
			if layer.is_blocked(Vector2i((layer.to_grid_position(stand) as Vector2).floor())):
				continue
			_player.global_position = stand
			if _controller._is_within_reach(point):
				found.append(stand)
	_player.global_position = saved
	return found


func _overlaps_player(object: Node2D) -> bool:
	return _box(_player).intersects(_box(object))


func _place_player(stand: Vector2) -> void:
	_player.global_position = stand
	# The camera follows and the compositor re-clusters on the frames after a move.
	await process_frame
	await process_frame


func _hover(point: Vector2) -> void:
	var viewport := _player.get_viewport()
	var motion := InputEventMouseMotion.new()
	motion.position = viewport.get_canvas_transform() * point
	motion.global_position = viewport.get_screen_transform() * motion.position
	Input.parse_input_event(motion)
	await process_frame
	_controller._update_hover()


func _run_action(object: Node2D, action_id: int) -> void:
	var point := object.get_node("InteractionPoint")
	_controller.focus_point = point
	_controller.entries = _controller.build_entries(point)
	var index := _ids(_controller.entries).find(action_id)
	_expect(index >= 0, "%s offers action %d" % [object.name, action_id])
	if index < 0:
		return
	_controller.open_menu()
	_controller.set_highlighted(index)
	_controller.confirm()
	_controller._advance_action(_controller._duration)
	_expect(_controller.state == 0, "action %d on %s ran to the end" % [action_id, object.name])


func _highlight() -> Sprite2D:
	var highlight = _controller.get("_highlight")
	return highlight if is_instance_valid(highlight) else null


func _highlight_parameter(parameter: String) -> Variant:
	var highlight := _highlight()
	return (highlight.material as ShaderMaterial).get_shader_parameter(parameter) if highlight != null else null


# The pass sits one z above the layer the object is drawn on and before every ordinary child
# of the world, so on that z it follows the character surfaces and precedes the bubbles.
func _expect_lit_over(object: Node2D, label: String) -> void:
	var highlight := _highlight()
	_expect(highlight != null and highlight.visible, "%s: the highlight is drawn" % label)
	if highlight == null:
		return
	var sprite := object.get_node("Sprite2D") as Sprite2D
	_expect(highlight.texture == object.get("color_texture"), "%s: the highlight copies the current frame" % label)
	_expect(highlight.z_index == sprite.z_index + 1, "%s: the highlight sits one z above the object, got %d over %d" % [label, highlight.z_index, sprite.z_index])
	_expect(
		highlight.get_parent() == _world and highlight.get_index(true) < _world.get_child(0).get_index(true),
		"%s: the highlight comes first on its z" % label
	)


func _check_copier_after_asscopy() -> void:
	var copier := _object("Object122Kopierer")
	var sprite := copier.get_node("Sprite2D") as Sprite2D
	var clean := Vector2.INF
	for stand in _stands(copier):
		_player.global_position = stand
		if not _overlaps_player(copier):
			clean = stand
			break
	_expect(clean.is_finite(), "the copier can be reached from a stand clear of its box")
	if not clean.is_finite():
		return
	await _place_player(clean)

	var target := _winning_point(copier)
	_expect(target.is_finite(), "the idle copier has a pixel only it is picked at")
	await _hover(target)
	_expect(_controller._hovered == copier, "the idle copier is hovered")
	_expect(_controller.focus_point == copier.get_node("InteractionPoint"), "the idle copier is focused")
	_expect(_ids(_controller.entries) == [28, 29, ASSCOPY], "the idle copier offers 28, 29 and ASSCOPY, got %s" % [_ids(_controller.entries)])
	_expect_lit_over(copier, "idle copier")

	await _run_action(copier, ASSCOPY)
	_expect(copier.state == 9, "ASSCOPY leaves the copier on DESTROYED_1, got %d" % copier.state)
	_expect(copier.is_in_group(MapObject.ACTOR_GROUP), "the looping copier is drawn as a depth actor")
	await _place_player(clean)
	_expect(sprite.visible and sprite.z_index == 1, "the looping copier draws its own sprite on the actor layer here")

	target = _winning_point(copier)
	_expect(target.is_finite(), "the looping copier has a pixel only it is picked at")
	await _hover(target)
	_expect(_controller._object_under_cursor() == copier, "the pick still finds the looping copier")
	_expect(_controller._hovered == copier, "the looping copier is hovered")
	_expect(_controller.focus_point == copier.get_node("InteractionPoint"), "the looping copier is focused")
	# sub_41D820 has no state rule; 82 stays locked behind 28's unlock list (sub_4100B0).
	_expect(_ids(_controller.entries) == [28, 29], "after ASSCOPY the copier offers 28 and 29, got %s" % [_ids(_controller.entries)])
	_expect_lit_over(copier, "looping copier")
	_expect(_highlight_parameter("cluster_depth_enabled") == false, "the copier overlaps no character, so no cluster test runs")


# The copier's first NPC user puts it into the same loop with no prank done to it.
func _check_copier_while_it_is_used() -> void:
	var copier := _object("Object122Kopierer")
	var point := copier.get_node("InteractionPoint")
	point.reset_actions()
	copier.set_state(0)
	copier.set_state(9)
	await process_frame
	await _hover(_winning_point(copier))
	_expect(_controller.focus_point == point, "a copier looping for a colleague is focused")
	_expect(_ids(_controller.entries) == [28, 29, ASSCOPY], "and offers its full menu, got %s" % [_ids(_controller.entries)])
	_expect_lit_over(copier, "copier in use")


# Most stands the copier can be used from put the player's box over it, and then the two are
# drawn together on one of the character compositor's surfaces with the copier's own sprite
# hidden. The pulse must still show, but only where the copier is in front.
func _check_copier_overlapping_the_player() -> void:
	var copier := _object("Object122Kopierer")
	var sprite := copier.get_node("Sprite2D") as Sprite2D
	var clustered := Vector2.INF
	for stand in _stands(copier):
		await _place_player(stand)
		if not sprite.visible:
			clustered = stand
			break
	_expect(clustered.is_finite(), "some stand draws the player and the looping copier on one surface")
	if not clustered.is_finite():
		return
	await _hover(_winning_point(copier))
	_expect(_controller._hovered == copier and _controller.focus_point != null, "the clustered copier is focused")
	_expect_lit_over(copier, "clustered copier")
	var cluster := _compositor.cluster_depth_for(sprite)
	_expect(not cluster.is_empty(), "the compositor publishes the copier's surface scores")
	_expect(_highlight_parameter("cluster_depth_enabled") == true, "the highlight tests the surface the copier is drawn on")
	if cluster.is_empty():
		return
	var bounds: Rect2 = cluster["bounds"]
	var texture := cluster["texture"] as Texture2D
	_expect(_highlight_parameter("cluster_depth") == texture, "the highlight samples that surface's scores")
	_expect(texture != null and Vector2(texture.get_size()) == bounds.size, "the scores cover the surface")
	_expect(texture is ImageTexture and (texture as ImageTexture).get_format() == Image.FORMAT_RF, "the scores are R32F, like the world buffer")
	_expect(_highlight_parameter("cluster_depth_origin") == bounds.position, "the test is aligned to the surface")

	# The compositor runs after the controller every frame and hands the new surface over
	# once it has composed it, so the test never lags the surface that is drawn. Moving the
	# player recomposes the surface; its scores are only rebuilt when asked for, so fresh
	# scores after the frame mean the highlight took them up without being redrawn.
	var surfaces: Dictionary = _compositor.get("_sprite_surfaces")
	var index: int = surfaces.get(sprite.get_instance_id(), -1)
	_player.global_position += Vector2(2, 1)
	await process_frame
	var stale: Array = _compositor.get("_surface_scores_stale")
	_expect(index >= 0 and index < stale.size() and not stale[index], "the highlight takes up the recomposed surface the same frame")
	cluster = _compositor.cluster_depth_for(sprite)
	_expect(not cluster.is_empty() and _highlight_parameter("cluster_depth_origin") == (cluster["bounds"] as Rect2).position, "the cluster test follows the surface")

	for stand in _stands(copier):
		_player.global_position = stand
		if not _overlaps_player(copier):
			await _place_player(stand)
			break
	await _hover(_winning_point(copier))
	_expect(sprite.visible and _highlight_parameter("cluster_depth_enabled") == false, "stepping clear of the copier drops the cluster test")


# An object with nothing left to offer is still focused and dropped with the red tint
# (0x4033A8-0x4033B7), and the pick does not fall through it to the object behind.
func _check_nothing_left_still_tints_red(object: MapObject, action_id: int, behind: Node2D) -> void:
	var stands := _stands(object)
	_expect(not stands.is_empty(), "%s can be reached" % object.name)
	if stands.is_empty():
		return
	await _place_player(stands[0])
	await _run_action(object, action_id)
	# A DESTROY_n plays out before its loop starts.
	for step in range(64):
		if object.state >= MapObject.FIRST_TRANSITION_STATE + MapObject.DESTROYED_OFFSET:
			break
		object._process(0.125)
	_expect(object.state == 9, "%s settles on DESTROYED_1, got %d" % [object.name, object.state])
	_expect(object.is_in_group(MapObject.ACTOR_GROUP), "%s loops as a depth actor" % object.name)
	await process_frame

	var target := _winning_point(object, behind)
	_expect(target.is_finite(), "%s has a pixel only it is picked at%s" % [object.name, "" if behind == null else ", inside %s" % behind.name])
	await _hover(target)
	_expect(_controller._hovered == object, "%s is hovered, not %s" % [object.name, _controller._hovered.name if _controller._hovered != null else "nothing"])
	_expect(_controller.focus_point == null and _controller.entries.is_empty(), "%s has nothing left, so the focus is dropped" % object.name)
	_expect_lit_over(object, String(object.name))
	var highlight := _highlight()
	if highlight != null:
		var tint: Color = highlight.modulate
		_expect(is_equal_approx(tint.r, 1.0) and is_equal_approx(tint.g, 50.0 / 255.0) and is_equal_approx(tint.b, 50.0 / 255.0), "%s pulses red, got %s" % [object.name, tint])
