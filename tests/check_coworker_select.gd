extends SceneTree

# The name over a clicked colleague, as recovered in docs/names-reference.md. sub_417460 draws
# agent+1752 centred 135 px above the agent in (250, 180, 40) over a (40, 10, 0) copy, only
# while agent+1788 is set, and the level tick sets that flag on the colleague under the cursor
# when the act input comes, clearing it on everyone else. The pick shares one list of boxes
# with the items, so whichever box is in front answers, and a hovered colleague gets the same
# white pulse a hovered item does. The live store is pointed at a file of the check's own, so
# the player's own renames cannot change the names read here.

const LEVEL := preload("res://scenes/level_1.tscn")
const TEST_PATH := "user://check_coworker_select.cfg"
const NAME_COLOUR := Color8(250, 180, 40)
const SHADOW_COLOUR := Color8(40, 10, 0)

var _failures := 0
var _level: Node
var _world: Node2D
var _controller: Node


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var store: Node = root.get_node_or_null("SettingsStore")
	var restore_path := ""
	if store != null:
		restore_path = store.path
		store.path = TEST_PATH
		DirAccess.remove_absolute(TEST_PATH)
		store.reload()

	_level = LEVEL.instantiate()
	_level.get_node("LevelRuntime").enabled = false
	root.add_child(_level)
	await process_frame
	await process_frame
	for agent in get_nodes_in_group("npc_agents"):
		agent.process_mode = Node.PROCESS_MODE_DISABLED
	var watch := _level.get_node_or_null("LevelRuntime/CatchWatch")
	if watch != null:
		watch.process_mode = Node.PROCESS_MODE_DISABLED
	_world = _level.get_node("World") as Node2D
	var player := _world.get_node("Player") as Node2D
	player.set_physics_process(false)
	_controller = player.get_node("PrankController")
	_controller.set_process(false)

	var boss := _world.get_node("Npc080Boss") as Node2D
	var coworker := _world.get_node("Npc079MaleEmployee1") as Node2D
	_check_the_level_named_its_agents(boss, coworker)
	_check_the_name_shows_only_while_selected(boss)
	_check_a_click_selects_one_colleague(boss, coworker)
	_check_the_player_is_never_picked(player)
	await _check_one_box_answers_both_picks(boss)
	await _check_a_hovered_colleague_pulses_white(boss)

	root.remove_child(_level)
	_level.free()
	if store != null:
		store.path = restore_path
		store.reload()
	DirAccess.remove_absolute(TEST_PATH)
	if _failures == 0:
		print("Coworker selection: the dealt names, the label over a clicked colleague, one pick for items and colleagues, and the white pulse passed")
	quit(1 if _failures else 0)


func _expect(condition: bool, label: String) -> void:
	if not condition:
		_failures += 1
		push_error(label)


func _box(node: Node2D) -> Rect2:
	var sprite := node.get_node("Sprite2D") as Sprite2D
	return Rect2(sprite.to_global(sprite.offset), sprite.texture.get_size())


# A point in the node's box where the shared pick answers with that node.
func _winning_point(node: Node2D) -> Vector2:
	var box := _box(node)
	for y in range(int(box.position.y) + 2, int(box.end.y) - 1, 3):
		for x in range(int(box.position.x) + 2, int(box.end.x) - 1, 3):
			if _controller._front_at(Vector2(x, y)) == node:
				return Vector2(x, y)
	return Vector2.INF


func _check_the_level_named_its_agents(boss: Node2D, coworker: Node2D) -> void:
	_expect(boss.get("display_name") == "Roy Behr", "the level named its boss Roy Behr, got %s" % boss.get("display_name"))
	_expect(coworker.get("display_name") == "Tim Buktu", "the first male coworker drew Tim Buktu, got %s" % coworker.get("display_name"))
	_expect(not boss.get("selected"), "nobody is selected when a level starts")


func _check_the_name_shows_only_while_selected(boss: Node2D) -> void:
	var label := boss.get_node("NameLabel") as Label
	var bubble := boss.get_node("ThoughtBubble") as Sprite2D
	_expect(not label.visible, "the name is hidden until the colleague is clicked")
	boss.set("selected", true)
	_expect(label.visible and label.text == "Roy Behr", "a selected colleague shows the name")
	_expect(is_equal_approx(label.position.y, -135.0), "the name sits 135 px above the anchor, got %f" % label.position.y)
	_expect(
		is_equal_approx(label.position.x, -label.size.x * 0.5) and label.size.x > 0.0,
		"the name is centred over the anchor, got x %f for width %f" % [label.position.x, label.size.x]
	)
	_expect(label.get_theme_color(&"font_color").is_equal_approx(NAME_COLOUR), "the name is drawn in (250, 180, 40)")
	_expect(label.get_theme_color(&"font_shadow_color").is_equal_approx(SHADOW_COLOUR), "over a (40, 10, 0) copy")
	_expect(
		label.get_theme_constant(&"shadow_offset_x") == 2 and label.get_theme_constant(&"shadow_offset_y") == 2,
		"two pixels down and right"
	)
	_expect(label.get_theme_font_size(&"font_size") == 24, "at the size of the Arial 24 it was drawn in")
	_expect(label.z_index > bubble.z_index, "the name is drawn after the bubble, above every wall")
	_expect(label.material == null, "the name is never depth tested")
	boss.set("display_name", "")
	_expect(not label.visible, "an empty name is never drawn")
	boss.set("display_name", "Roy Behr")
	boss.set("selected", false)
	_expect(not label.visible, "a colleague no longer selected hides the name")


func _check_a_click_selects_one_colleague(boss: Node2D, coworker: Node2D) -> void:
	var click := InputEventAction.new()
	click.action = &"interact"
	click.pressed = true
	_controller.hovered_agent = boss
	_controller._unhandled_input(click)
	_expect(boss.get("selected") and not coworker.get("selected"), "clicking the boss selects him")
	_controller.hovered_agent = coworker
	_controller._unhandled_input(click)
	_expect(coworker.get("selected") and not boss.get("selected"), "clicking another colleague moves the selection")
	_controller.hovered_agent = null
	_controller._unhandled_input(click)
	_expect(coworker.get("selected"), "a click on nothing leaves the selection standing")
	_controller.select_agent(null)
	_expect(not coworker.get("selected") and not boss.get("selected"), "selecting nobody clears everyone")


func _check_the_player_is_never_picked(player: Node2D) -> void:
	var box := _box(player)
	var centre := box.get_center()
	_expect(_controller._front_at(centre) != player, "the player registers no box, so the pick never answers with it")


func _check_one_box_answers_both_picks(boss: Node2D) -> void:
	var object := _world.get_node("Objects/Object036Colamat") as Node2D
	var home := boss.global_position
	# In front of the machine the colleague's box answers; behind it, the machine's.
	for offset: Vector2 in [Vector2(0, 40), Vector2(0, -40)]:
		boss.global_position = object.global_position + offset
		await process_frame
		var overlap := _box(boss).intersection(_box(object))
		_expect(overlap.has_area(), "the boss's box overlaps the machine's at %s" % offset)
		if not overlap.has_area():
			continue
		var point := overlap.get_center()
		var front: Node2D = _controller._front_at(point)
		if offset.y > 0.0:
			_expect(front == boss, "a colleague in front of an object takes the pick from it, got %s" % front)
		else:
			_expect(front == object, "an object in front of a colleague keeps the pick, got %s" % front)
	boss.global_position = home
	await process_frame


func _hover(point: Vector2) -> void:
	var viewport := _world.get_viewport()
	var motion := InputEventMouseMotion.new()
	motion.position = viewport.get_canvas_transform() * point
	motion.global_position = viewport.get_screen_transform() * motion.position
	Input.parse_input_event(motion)
	await process_frame
	_controller._update_hover()


func _check_a_hovered_colleague_pulses_white(boss: Node2D) -> void:
	var sprite := boss.get_node("Sprite2D") as Sprite2D
	var point := _winning_point(boss)
	_expect(point.is_finite(), "some point of the boss's box answers with the boss")
	if not point.is_finite():
		return
	await _hover(point)
	_expect(_controller.hovered_agent == boss, "the pointer over the boss hovers him")
	_expect(_controller.focus_point == null, "and focuses no object, since his box is the one in front")
	var pulse := _controller.get("_agent_highlight") as Sprite2D
	_expect(pulse != null and pulse.visible, "the hovered colleague gets a pulse pass")
	if pulse == null:
		return
	_expect(pulse.texture == sprite.texture, "the pass redraws the colleague's own frame")
	_expect(
		Color(pulse.modulate.r, pulse.modulate.g, pulse.modulate.b).is_equal_approx(Color.WHITE),
		"in white, as game+14696's tint is"
	)
	_expect(pulse.modulate.a >= 40.0 / 255.0 - 0.001 and pulse.modulate.a <= 200.0 / 255.0 + 0.001, "pulsing between 40 and 200")
	_expect(pulse.z_index == sprite.z_index + 1, "one z above the colleague it lights")
	var material := pulse.material as ShaderMaterial
	var compositor := _world.get_node("CharacterDepthCompositor") as CharacterDepthCompositor
	_expect(
		material.get_shader_parameter("depth_map") == compositor.depth_texture_for(sprite),
		"the pass tests the colleague's own depth plane, so walls in front still hide it"
	)
	var item_pulse := _controller.get("_highlight") as Sprite2D
	_expect(item_pulse == null or not item_pulse.visible, "no object pulses while a colleague is in front")
	_controller._set_hovered_agent(null)
	_expect(not pulse.visible, "the pulse goes when the cursor leaves")
