extends SceneTree

# The main menu, screen 3, animates three things every frame (sub_423630, sub_423710,
# sub_423AE0): the swirl rotates by a fixed step, the six buttons sway on a sine, and the
# character orbits a small circle. The constants come from tools/export_menu_animation.py; this
# drives the scene's _process and checks each element against the recovered formula. See
# docs/shell-reference.md, "What every menu screen shares".

const MainMenuScene := preload("res://scenes/screens/main_menu.tscn")
const STEP := 1.0 / 60.0
const ANIM_PATH := "res://resources/original/menu_animation.json"

var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var anim: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ANIM_PATH))
	var rotation_step := float(anim["background_rotation_step"])
	var amplitude := float(anim["button_sway_amplitude"])
	var base_x := float(anim["button_base_x"])
	var phase_step := float(anim["button_phase_step"])
	var orbit_rate := float(anim["char_orbit_rate"])
	var orbit_amplitude := float(anim["char_orbit_amplitude"])

	_expect(is_equal_approx(rotation_step, 0.01), "the swirl's step is the recovered 0.01")
	_expect(amplitude == 32.0 and base_x == 380.0, "the buttons sway 32 px about x 380")

	var menu := MainMenuScene.instantiate()
	root.add_child(menu)
	# Freeze auto-processing so the only steps are the ones this test drives.
	menu.set_process(false)

	var background := menu.get_node("SafeFrame/Background") as Sprite2D
	var character := menu.get_node("SafeFrame/Char") as Sprite2D
	var frame := menu.get_node("SafeFrame") as Control
	var buttons: Array = []
	for i in range(7):
		buttons.append(menu.get_node("SafeFrame/Buttons/Button%d" % (i + 1)) as Control)
	# The port's Custom levels button is third, after the two games; the original's other four
	# follow it a row down each, Quit last after the original's wider gap, inside the frame.
	var keys := ["menu.time_game", "menu.points_game", "menu.custom_levels", "menu.highscores", "menu.names", "menu.sound", "menu.quit"]
	for i in range(7):
		_expect(String((buttons[i] as Control).get_node("Label").text) == keys[i], "button %d is %s" % [i, keys[i]])
	for i in range(1, 6):
		_expect(is_equal_approx(buttons[i].position.y, buttons[i - 1].position.y + 64.0), "button %d sits one row below the one before" % i)
	_expect(is_equal_approx(buttons[6].position.y, buttons[5].position.y + 80.0), "Quit keeps the original's wider gap")
	_expect(buttons[6].position.y + buttons[6].size.y <= 600.0, "inside the frame")

	# The structure the rotating swirl needs: a centred sprite, scaled to cover, in a frame that
	# clips the overhang off the black margin, exactly as the duel's swirl is set up.
	_expect(frame.clip_contents, "the SafeFrame clips the swirl's overhang")
	_expect(background is Sprite2D and background.centered, "the background is a centred sprite that can rotate")
	_expect(background.position == Vector2(400, 300), "it pivots on the frame's centre")
	_expect(background.scale.x >= 1.25, "and is scaled past the frame's half-diagonal so a turn never bares a corner")
	_expect(character is Sprite2D and not character.centered, "the character draws from its top-left, as the original anchors it")

	# At phase 0 the first button sits at its centre and the character at the top of its circle.
	_expect(is_equal_approx(background.rotation, 0.0), "the swirl starts unrotated")
	_expect(is_equal_approx(buttons[0].position.x, base_x), "button 0 starts at x 380")
	_expect(character.position.is_equal_approx(Vector2(64.0, 0.0)), "the character starts at (64, 0), the top of its orbit, got %s" % character.position)

	# Drive the menu's own _process the way the tree would, then check every element against the
	# formula at the accumulated angle and phase.
	var steps := 100
	for i in range(steps):
		menu._process(STEP)
	var phase := float(steps) * STEP

	_expect(is_equal_approx(background.rotation, float(steps) * rotation_step),
		"the swirl turned by the step every frame, got %f after %d" % [background.rotation, steps])
	_expect(background.rotation > 0.0, "so the swirl is actually turning")

	for i in range(7):
		var expected_x := sin(float(i) * phase_step + phase) * amplitude + base_x
		_expect(is_equal_approx(buttons[i].position.x, expected_x),
			"button %d sways to x %f, got %f" % [i, expected_x, buttons[i].position.x])
	_expect(absf(buttons[1].position.x - base_x) > 1.0, "a button has actually moved off its centre")

	var a := phase * orbit_rate
	var expected_char := Vector2(64.0 - sin(a) * orbit_amplitude, 32.0 - cos(a) * amplitude)
	_expect(character.position.is_equal_approx(expected_char),
		"the character orbits to %s, got %s" % [expected_char, character.position])

	root.remove_child(menu)
	menu.free()

	if _failures == 0:
		print("Main menu: the swirl rotates by 0.01 a frame, the six buttons sway on their sine and the character orbits its circle")
	quit(1 if _failures else 0)


func _expect(condition: bool, label: String) -> void:
	if not condition:
		_failures += 1
		push_error(label)
