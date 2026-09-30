extends SceneTree

# The console lamps are buttons: sub_459AE0 clicks a visible lamp on the first left-button
# event with the cursor strictly inside its sprite and the latch clear, any release edge
# clears the latch, and the urination lamp, registered first, wins where it overlaps the
# smoking one. The port takes the press in the HUD, so the world never sees it.
# See docs/player-ability-reference.md, "The lamps are buttons".

const ConsoleScene := preload("res://scenes/hud/console.tscn")
const AbilityController := preload("res://scenes/player/ability_controller.gd")


class AbilitiesStub extends Node:
	var requests: Array = []

	func _enter_tree() -> void:
		add_to_group("player_abilities")

	func request(bit: int) -> void:
		requests.append(bit)


class WorldStub extends Node:
	var presses := 0

	func _unhandled_input(event: InputEvent) -> void:
		var button := event as InputEventMouseButton
		if button != null and button.pressed and button.button_index == MOUSE_BUTTON_LEFT:
			presses += 1


var _failures := 0
var _console: CanvasLayer
var _abilities: AbilitiesStub
var _world: WorldStub
var _ring: CanvasLayer


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_abilities = AbilitiesStub.new()
	root.add_child(_abilities)
	_world = WorldStub.new()
	root.add_child(_world)
	# The console asks its own parent for the ring, as it does inside LevelRuntime.
	_ring = CanvasLayer.new()
	_ring.name = "RoundMenu"
	_ring.visible = false
	root.add_child(_ring)
	_console = ConsoleScene.instantiate()
	root.add_child(_console)
	await process_frame

	_check_the_rects_are_strictly_inside()
	_check_the_press_is_the_hud_s()
	_check_a_press_fires_once()
	_check_a_drag_onto_a_lit_lamp_fires()
	_check_any_release_re_arms()
	_check_urination_wins_the_overlap()
	_check_a_hidden_lamp_takes_nothing()
	_check_only_the_left_button()
	_check_not_while_the_ring_is_up()
	_check_each_lamp_asks_for_its_mode()

	if _failures == 0:
		print("Console lamps: strict rects, the HUD's press, one fire per press, the drag, the re-arm, the overlap, hidden lamps, the left button only, the ring and each lamp's mode passed")
	quit(1 if _failures else 0)


func _expect(condition: bool, label: String) -> void:
	if not condition:
		_failures += 1
		push_error(label)


func _light(smoke: bool, piss: bool, matrix: bool) -> void:
	var inventory := PackedInt32Array()
	inventory.resize(31)
	inventory[5] = 1 if smoke else 0
	inventory[6] = 99 if smoke else 0
	inventory[26] = 1 if piss else 0
	inventory[14] = 1 if matrix else 0
	_console.set_inventory(inventory)


# A console-band position in the viewport, the band being anchored bottom centre.
func _at(band_position: Vector2) -> Vector2:
	var band := _console.get_node("Band") as Control
	return band.get_global_transform_with_canvas() * (band_position + Vector2(0.5, 0.5))


func _button(band_position: Vector2, pressed: bool, index := MOUSE_BUTTON_LEFT) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = index
	event.pressed = pressed
	event.position = _at(band_position)
	event.global_position = event.position
	root.push_input(event, true)


func _move(band_position: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = _at(band_position)
	event.global_position = event.position
	root.push_input(event, true)


func _reset() -> void:
	_button(Vector2(10, 10), false, MOUSE_BUTTON_LEFT)
	_abilities.requests.clear()
	_world.presses = 0


func _click(band_position: Vector2, index := MOUSE_BUTTON_LEFT) -> void:
	_button(band_position, true, index)
	_button(band_position, false, index)


# Smoking's sprite is 47 x 45 at (717, 461), so a press counts on x 718-763, y 462-505.
func _check_the_rects_are_strictly_inside() -> void:
	_light(true, false, false)
	_reset()
	for outside in [Vector2(717, 480), Vector2(740, 461), Vector2(764, 480), Vector2(740, 506)]:
		_click(outside)
	_expect(_abilities.requests.is_empty(), "the lamp's own edge and the pixels past it do not count, got %s" % [_abilities.requests])
	for inside in [Vector2(718, 462), Vector2(763, 505)]:
		_click(inside)
	_expect(_abilities.requests.size() == 2, "the first and last pixels inside do, got %s" % [_abilities.requests])


func _check_the_press_is_the_hud_s() -> void:
	_light(true, false, false)
	_reset()
	_click(Vector2(740, 480))
	_expect(_world.presses == 0, "a press on a lit lamp never reaches the world")
	_click(Vector2(400, 200))
	_expect(_world.presses == 1, "a press elsewhere still does")


func _check_a_press_fires_once() -> void:
	_light(true, false, false)
	_reset()
	_button(Vector2(740, 480), true)
	_move(Vector2(741, 481))
	_move(Vector2(742, 482))
	_console._process(0.0)
	_console._process(0.0)
	_expect(_abilities.requests.size() == 1, "a held press fires once, got %d" % _abilities.requests.size())
	_button(Vector2(742, 482), false)


# The click needs the button down, the cursor inside and the latch clear, on any button
# event, so a press that starts elsewhere fires as it is dragged onto the lamp.
func _check_a_drag_onto_a_lit_lamp_fires() -> void:
	_light(true, false, false)
	_reset()
	_button(Vector2(600, 480), true)
	_expect(_abilities.requests.is_empty() and _world.presses == 1, "the press starts on the world")
	_move(Vector2(740, 480))
	_expect(_abilities.requests.size() == 1, "dragging onto the lamp fires it")
	_button(Vector2(740, 480), false)
	_reset()
	_move(Vector2(740, 480))
	_console._process(0.0)
	_expect(_abilities.requests.is_empty(), "hovering without the button does nothing")


# Only a release edge clears the latch, and any button's does: a left hold that spans a right
# release fires again.
func _check_any_release_re_arms() -> void:
	_light(true, false, false)
	_reset()
	_button(Vector2(740, 480), true)
	_button(Vector2(740, 480), true, MOUSE_BUTTON_RIGHT)
	_button(Vector2(740, 480), false, MOUSE_BUTTON_RIGHT)
	_console._process(0.0)
	_expect(_abilities.requests.size() == 2, "a right release under a left hold re-arms the lamp, got %d" % _abilities.requests.size())
	_button(Vector2(740, 480), false)


func _check_urination_wins_the_overlap() -> void:
	_light(true, true, false)
	_reset()
	_click(Vector2(760, 490))
	_expect(
		_abilities.requests == [AbilityController.REQUEST_PISS],
		"urination is registered first, so it takes the shared pixels, got %s" % [_abilities.requests]
	)
	_light(true, false, false)
	_reset()
	_click(Vector2(760, 490))
	_expect(_abilities.requests == [AbilityController.REQUEST_SMOKE], "with urination dark, smoking takes them")


func _check_a_hidden_lamp_takes_nothing() -> void:
	_light(false, false, false)
	_reset()
	_click(Vector2(740, 480))
	_click(Vector2(775, 560))
	_expect(_abilities.requests.is_empty(), "a dark lamp is never clicked")
	_expect(_world.presses == 2, "and does not keep the press from the world")
	# Cigarettes without the lighter leave the smoking lamp dark.
	var inventory := PackedInt32Array()
	inventory.resize(31)
	inventory[5] = 1
	_console.set_inventory(inventory)
	_reset()
	_click(Vector2(740, 480))
	_expect(_abilities.requests.is_empty(), "smoking needs both items to light")


func _check_only_the_left_button() -> void:
	_light(true, true, true)
	_reset()
	_click(Vector2(740, 480), MOUSE_BUTTON_RIGHT)
	_click(Vector2(740, 480), MOUSE_BUTTON_MIDDLE)
	_expect(_abilities.requests.is_empty(), "the right and middle buttons never click a lamp")


# sub_4066D0 re-centres the cursor on every tick of the ring's close, so no lamp is reached
# until it has shut.
func _check_not_while_the_ring_is_up() -> void:
	_light(true, false, false)
	_reset()
	_ring.visible = true
	_click(Vector2(740, 480))
	_expect(_abilities.requests.is_empty(), "no lamp is pressed while the ring is up")
	_ring.visible = false
	_click(Vector2(740, 480))
	_expect(_abilities.requests.size() == 1, "once it has shut the lamp works again")

	# The port opens the ring on the press, so a press that starts on a focused item and is
	# dragged onto a lit lamp opens the ring and loses the lamp. The original raises the act
	# bit only on the release (0x40445F-0x404478), after the drag has started the ability.
	_reset()
	_button(Vector2(600, 480), true)
	_ring.visible = true
	_move(Vector2(740, 480))
	_console._process(0.0)
	_expect(_abilities.requests.is_empty(), "a drag from a focused item onto a lamp is the ring's, not the lamp's")
	_button(Vector2(740, 480), false)
	_ring.visible = false


func _check_each_lamp_asks_for_its_mode() -> void:
	_light(true, true, true)
	_reset()
	_click(Vector2(740, 470))
	_click(Vector2(780, 520))
	_click(Vector2(775, 560))
	_expect(
		_abilities.requests == [
			AbilityController.REQUEST_SMOKE, AbilityController.REQUEST_PISS, AbilityController.REQUEST_PILL,
		],
		"smoking, urination and Matrix raise 0x800, 0x1000 and 0x4000, got %s" % [_abilities.requests]
	)
