extends SceneTree

# CGUIRoundMenu: sub_406510 builds it, sub_4066D0 ticks it and sub_45BC90 lays it out.
# See docs/player-action-reference.md.

const MENU := preload("res://scenes/hud/round_menu.gd")

# A stand-in for the prank controller the ring reads its entries and selection from.
class ControllerStub extends Node:
	signal menu_opened(entries: Array)
	signal menu_closed()

	var entries: Array = []
	var highlighted := -1

	func _enter_tree() -> void:
		add_to_group("player_actions")

	func open(count: int) -> void:
		entries = []
		for index in range(count):
			entries.append({"slot": index, "action_id": index + 1, "name": "a%d" % index, "icon": null})
		highlighted = 0
		menu_opened.emit(entries)

	func close() -> void:
		highlighted = -1
		menu_closed.emit()

	func set_highlighted(index: int) -> void:
		if index < 0 or index >= entries.size():
			return
		highlighted = index

var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await _check_the_ring_opens_and_shuts()
	_check_entry_geometry()
	_check_stepping_through_the_entries()
	_check_the_arrow_keys_turn_the_ring()
	_check_the_selected_entry_is_tinted()
	if _failures == 0:
		print("Round menu: the original pitch, radius ramp, rotation ease, stepping, arrow keys and tint passed")
	quit(1 if _failures else 0)


func _expect(condition: bool, label: String) -> void:
	if not condition:
		_failures += 1
		push_error(label)


func _fixture() -> Dictionary:
	var controller := ControllerStub.new()
	root.add_child(controller)
	var menu := MENU.new()
	root.add_child(menu)
	return {"controller": controller, "menu": menu}


func _free(fixture: Dictionary) -> void:
	fixture["menu"].free()
	fixture["controller"].free()


# sub_45BC90 measures the gap before it moves, so the frame that lands on the target still
# reports the ring as turning and only the one after it reports it settled.
func _settle(menu: Node) -> void:
	for step in range(200):
		menu.advance(0.016)
		if menu.is_settled():
			return
	_expect(false, "the ring settles within a couple of seconds")


func _swipe(menu: Node, dx: float) -> void:
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(dx, 0.0)
	menu._unhandled_input(motion)


# sub_403FB0 sets the step bits from a mouse motion past eight pixels, and sub_4066D0 takes
# at most one step a frame and only once the ring has stopped turning.
func _check_stepping_through_the_entries() -> void:
	var fixture := _fixture()
	var menu = fixture["menu"]
	var controller = fixture["controller"]
	controller.open(4)
	menu.advance(1.0)
	_expect(controller.highlighted == 0, "a fresh menu starts on its first entry")

	_swipe(menu, MENU.STEP_THRESHOLD)
	menu.advance(0.016)
	_expect(controller.highlighted == 0, "a motion of exactly the threshold does not step")

	_swipe(menu, MENU.STEP_THRESHOLD + 1.0)
	menu.advance(0.016)
	_expect(controller.highlighted == 1, "moving right steps to the next entry, got %d" % controller.highlighted)

	# The ring is turning now, so further motion is dropped rather than queued.
	_expect(not menu.is_settled(), "stepping sets the ring turning")
	_swipe(menu, 40.0)
	menu.advance(0.016)
	_expect(controller.highlighted == 1, "a step is ignored while the ring is still turning")
	_settle(menu)
	_expect(controller.highlighted == 1, "the dropped step is not replayed once the ring settles")

	_swipe(menu, -40.0)
	menu.advance(0.016)
	_expect(controller.highlighted == 0, "moving left steps back, got %d" % controller.highlighted)
	_settle(menu)

	# Both bits in one frame: sub_4066D0 tests the down bit first, so the ring steps back.
	_swipe(menu, 40.0)
	_swipe(menu, -40.0)
	menu.advance(0.016)
	_expect(controller.highlighted == 0, "a step off the first entry is clamped, not wrapped")
	_settle(menu)

	for i in range(6):
		_swipe(menu, 40.0)
		menu.advance(0.016)
		_settle(menu)
	_expect(controller.highlighted == 3, "stepping stops on the last entry rather than wrapping, got %d" % controller.highlighted)

	# sub_4066D0 only reads the step bits while the menu is open.
	controller.close()
	var frozen: int = controller.highlighted
	_swipe(menu, 40.0)
	menu.advance(0.016)
	_expect(controller.highlighted == frozen, "a closing ring cannot be turned, got %d" % controller.highlighted)
	_free(fixture)


func _press(menu: Node, action: StringName) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	menu._unhandled_input(event)


# DIK_LEFT and DIK_RIGHT arrive in sub_403FB0 as codes 111 and 112 (the table at 0x4734CC)
# and set the same two step bits a swipe does, so they share the swipe's gating.
func _check_the_arrow_keys_turn_the_ring() -> void:
	var fixture := _fixture()
	var menu = fixture["menu"]
	var controller = fixture["controller"]
	controller.open(3)
	menu.advance(1.0)

	_press(menu, &"move_right")
	menu.advance(0.016)
	_expect(controller.highlighted == 1, "the right arrow steps to the next entry, got %d" % controller.highlighted)
	_press(menu, &"move_right")
	menu.advance(0.016)
	_expect(controller.highlighted == 1, "an arrow is dropped while the ring is still turning, got %d" % controller.highlighted)
	_settle(menu)

	_press(menu, &"move_left")
	menu.advance(0.016)
	_expect(controller.highlighted == 0, "the left arrow steps back, got %d" % controller.highlighted)
	_settle(menu)
	_press(menu, &"move_left")
	menu.advance(0.016)
	_expect(controller.highlighted == 0, "the left arrow stops on the first entry, got %d" % controller.highlighted)
	_settle(menu)

	# Up commits and down cancels in the prank controller; neither turns the ring.
	_press(menu, &"move_up")
	_press(menu, &"move_down")
	menu.advance(0.016)
	_expect(controller.highlighted == 0 and menu.is_settled(), "up and down do not turn the ring")

	controller.close()
	var frozen: int = controller.highlighted
	_press(menu, &"move_right")
	menu.advance(0.016)
	_expect(controller.highlighted == frozen, "a closing ring ignores the arrows, got %d" % controller.highlighted)
	_free(fixture)


# The tint rides on this+120 == 255, which only happens at the full radius.
func _check_the_selected_entry_is_tinted() -> void:
	var fixture := _fixture()
	var menu = fixture["menu"]
	var controller = fixture["controller"]
	controller.open(3)
	menu.advance(0.2)
	_expect(not menu.is_fully_open(), "a half-grown ring is not reported fully open")
	_expect(_tint(menu, 0) == Color.WHITE, "an opening ring leaves even the selected entry plain")

	menu.advance(1.0)
	_expect(menu.is_fully_open(), "a ring at the full radius is reported fully open")
	_expect(_tint(menu, 0) == MENU.SELECTED_TINT, "the selected entry takes the original tint, got %s" % _tint(menu, 0))
	_expect(_tint(menu, 1) == Color.WHITE, "the other entries stay white")
	_expect(_tint(menu, 2) == Color.WHITE, "the other entries stay white")

	controller.set_highlighted(2)
	_settle(menu)
	_expect(_tint(menu, 2) == MENU.SELECTED_TINT, "the tint follows the selection")
	_expect(_tint(menu, 0) == Color.WHITE, "the entry left behind goes back to white")
	_free(fixture)


func _tint(menu: Node, index: int) -> Color:
	var icons: Array = menu.get("_icons")
	if index < 0 or index >= icons.size():
		return Color.TRANSPARENT
	return (icons[index] as CanvasItem).modulate


# sub_4066D0 runs the radius from 0 to 60 at 150 a second on the way in and back down on the
# way out, and only hides the ring once it reaches zero.
func _check_the_ring_opens_and_shuts() -> void:
	var fixture := _fixture()
	await process_frame
	var menu = fixture["menu"]
	var controller = fixture["controller"]
	_expect(not menu.visible, "the ring is hidden until a menu opens")

	controller.open(3)
	_expect(menu.visible, "opening a menu shows the ring")
	_expect(is_equal_approx(menu.ring_radius(), 0.0), "the ring opens from nothing")
	_expect(menu.entry_position(0).is_equal_approx(menu.centre() + MENU.ICON_OFFSET), "a ring of no radius stacks its entries on the centre")

	menu.advance(0.1)
	_expect(is_equal_approx(menu.ring_radius(), 15.0), "the radius grows at 150 a second, got %f" % menu.ring_radius())
	menu.advance(1.0)
	_expect(is_equal_approx(menu.ring_radius(), MENU.RADIUS_LIMIT), "the radius stops at the original 60, got %f" % menu.ring_radius())

	controller.close()
	_expect(menu.visible, "closing does not cut the ring off mid-shrink")
	menu.advance(0.1)
	_expect(is_equal_approx(menu.ring_radius(), 45.0), "the radius shrinks at the same rate, got %f" % menu.ring_radius())
	menu.advance(0.3)
	_expect(is_equal_approx(menu.ring_radius(), 0.0), "the ring shrinks away in 0.4 seconds, got %f" % menu.ring_radius())
	menu.advance(0.016)
	_expect(not menu.visible, "the ring hides once it has shrunk to nothing")

	# sub_406510 rebuilds the menu from scratch, so catching it mid-shrink starts it over.
	controller.open(2)
	menu.advance(0.1)
	controller.close()
	menu.advance(0.1)
	controller.open(2)
	_expect(menu.visible, "reopening mid-shrink shows the ring again")
	_expect(is_equal_approx(menu.ring_radius(), 0.0), "reopening mid-shrink starts the radius over")
	menu.advance(0.1)
	_expect(is_equal_approx(menu.ring_radius(), 15.0), "a reopened ring grows rather than carrying on shrinking")
	_free(fixture)


# The draw's own formula, checked against a ring that has finished opening.
func _check_entry_geometry() -> void:
	var fixture := _fixture()
	var menu = fixture["menu"]
	var controller = fixture["controller"]
	controller.open(8)
	menu.advance(1.0)
	_expect(is_equal_approx(menu.ring_radius(), MENU.RADIUS_LIMIT), "the ring is fully open")
	_expect(menu.is_settled(), "a ring on its first entry has nothing to turn toward")

	# sub_406510's (400, 200) is the centre of the band above the console, so the port derives
	# it from the live viewport instead of pinning it. See docs/widescreen.md.
	var view: Vector2 = menu.get_viewport().get_visible_rect().size
	_expect(
		menu.centre().is_equal_approx(Vector2(view.x * 0.5, (view.y - MENU.CONSOLE_HEIGHT) * 0.5)),
		"the ring centres on the band the console leaves free, got %s in a %s viewport" % [menu.centre(), view]
	)

	# The highlighted entry rotates to theta = PI, which is straight up from the centre.
	var drawn := MENU.RADIUS_LIMIT * MENU.RADIUS_SCALE
	_expect(is_equal_approx(drawn, 90.0), "the drawn radius is the original 90 pixels, got %f" % drawn)
	var first: Vector2 = menu.entry_position(0)
	_expect(
		first.is_equal_approx(menu.centre() + MENU.ICON_OFFSET + Vector2(0.0, -drawn)),
		"the highlighted entry sits straight above the centre, got %s" % first
	)

	# Entries march clockwise from there at a fixed pitch, not a share of a full turn.
	for index in range(8):
		var angle := -MENU.ENTRY_PITCH * float(index) + PI
		var expected: Vector2 = menu.centre() + MENU.ICON_OFFSET + Vector2(sin(angle), cos(angle)) * drawn
		_expect(menu.entry_position(index).is_equal_approx(expected), "entry %d follows the draw's own formula" % index)
	var pitch: float = menu.entry_position(0).angle_to_point(menu.centre() + MENU.ICON_OFFSET) - menu.entry_position(1).angle_to_point(menu.centre() + MENU.ICON_OFFSET)
	_expect(is_equal_approx(absf(pitch), MENU.ENTRY_PITCH), "neighbouring entries are 0.6 radians apart, got %f" % absf(pitch))
	# Eight entries therefore cover 4.2 radians, not a full circle.
	_expect(menu.entry_position(7).distance_to(menu.entry_position(0)) > 1.0, "a full menu does not wrap back onto its first entry")

	# The ring turns to bring the selected entry to the top, at 5.0 radians a second.
	controller.set_highlighted(3)
	menu.advance(0.1)
	_expect(not menu.is_settled(), "the ring reports itself turning while it catches up")
	_expect(is_equal_approx(menu.rotation_angle(), 0.5), "the rotation eases at the original 5.0 a second, got %f" % menu.rotation_angle())
	menu.advance(1.0)
	_expect(is_equal_approx(menu.rotation_angle(), MENU.ENTRY_PITCH * 3.0), "the rotation stops on the selected entry, got %f" % menu.rotation_angle())
	menu.advance(0.016)
	_expect(menu.is_settled(), "the ring reports itself settled the frame after it arrives")
	_expect(
		menu.entry_position(3).is_equal_approx(menu.centre() + MENU.ICON_OFFSET + Vector2(0.0, -drawn)),
		"the selected entry ends up straight above the centre"
	)
	_free(fixture)
