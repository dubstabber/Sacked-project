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
	if _failures == 0:
		print("Round menu: the original pitch, radius ramp and rotation ease passed")
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
	_expect(menu.entry_position(0).is_equal_approx(MENU.CENTRE + MENU.ICON_OFFSET), "a ring of no radius stacks its entries on the centre")

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

	# The highlighted entry rotates to theta = PI, which is straight up from the centre.
	var drawn := MENU.RADIUS_LIMIT * MENU.RADIUS_SCALE
	_expect(is_equal_approx(drawn, 90.0), "the drawn radius is the original 90 pixels, got %f" % drawn)
	var first: Vector2 = menu.entry_position(0)
	_expect(
		first.is_equal_approx(MENU.CENTRE + MENU.ICON_OFFSET + Vector2(0.0, -drawn)),
		"the highlighted entry sits straight above the centre, got %s" % first
	)

	# Entries march clockwise from there at a fixed pitch, not a share of a full turn.
	for index in range(8):
		var angle := -MENU.ENTRY_PITCH * float(index) + PI
		var expected: Vector2 = MENU.CENTRE + MENU.ICON_OFFSET + Vector2(sin(angle), cos(angle)) * drawn
		_expect(menu.entry_position(index).is_equal_approx(expected), "entry %d follows the draw's own formula" % index)
	var pitch: float = menu.entry_position(0).angle_to_point(MENU.CENTRE + MENU.ICON_OFFSET) - menu.entry_position(1).angle_to_point(MENU.CENTRE + MENU.ICON_OFFSET)
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
	_expect(menu.is_settled(), "the ring reports itself settled once it arrives")
	_expect(
		menu.entry_position(3).is_equal_approx(MENU.CENTRE + MENU.ICON_OFFSET + Vector2(0.0, -drawn)),
		"the selected entry ends up straight above the centre"
	)
	_free(fixture)
