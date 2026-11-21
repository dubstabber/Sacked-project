extends SceneTree


const ConsoleScene := preload("res://scenes/hud/console.tscn")
const PrankControllerScript := preload("res://scenes/player/prank_controller.gd")

# sub_405930 builds every element at these absolute screen positions; the frame is bottom
# docked, which puts its 200 pixels at y 400..600 of its band. The port keeps those numbers
# as offsets inside two anchored 800x600 bands. See docs/hud-reference.md, docs/widescreen.md.
const ExpectedPositions := {
	"Band/Frame": Vector2(0, 400),
	"Band/Score": Vector2(85, 500),
	"Band/Clock": Vector2(250, 500),
	"Band/HoverText": Vector2(135, 556),
	"Band/ActionIcon": Vector2(170, 477),
	"Band/AggroBar": Vector2(410, 497),
	"Band/ClockBar": Vector2(662, 536),
	"Band/LampSmoke": Vector2(717, 461),
	"Band/LampPiss": Vector2(756, 485),
	"Band/LampMatrix": Vector2(754, 537),
	"Banners/ThermoUp": Vector2(5, 5),
}
# Each of these waits on something: an action running, an action highlighted, an item held,
# or the office souring. At rest, with an empty inventory, none may be drawn over the frame.
# The aggression bar is not among them: sub_405930 never hides it, it just starts short.
const InertElements := [
	"Band/ActionIcon", "Band/ClockBar", "Band/LampSmoke", "Band/LampPiss", "Band/LampMatrix",
	"Banners/ThermoUp",
]

var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var console := ConsoleScene.instantiate()
	root.add_child(console)
	await process_frame

	_check_positions(console)
	_check_frame_covers_the_console_band(console)
	_check_the_bands_are_anchored(console)
	_check_inert_elements(console)
	_check_lamps(console)
	_check_the_warning_captions_are_opaque(console)
	_check_action_progress(console)
	_check_the_stopwatch_sweeps_the_dial(console)
	_check_the_aggression_bar(console)
	_check_score_field(console)
	_check_clock_field(console)
	_check_hover_text(console)
	root.remove_child(console)
	console.free()

	await _check_the_level_console_follows_its_session()

	if _failures == 0:
		print("HUD console: original element positions, both digit fields and the hover bar passed")
	quit(1 if _failures else 0)


func _expect(condition: bool, label: String) -> void:
	if not condition:
		_failures += 1
		push_error(label)


func _position_of(console: Node, element: String) -> Vector2:
	var node := console.get_node(element)
	if node is Sprite2D:
		return (node as Sprite2D).position
	var label := node as Label
	return Vector2(label.offset_left, label.offset_top)


func _check_positions(console: Node) -> void:
	for element: String in ExpectedPositions:
		_expect(
			_position_of(console, element).is_equal_approx(ExpectedPositions[element]),
			"%s sits at %s, expected %s" % [element, _position_of(console, element), ExpectedPositions[element]]
		)


func _check_frame_covers_the_console_band(console: Node) -> void:
	var frame := console.get_node("Band/Frame") as Sprite2D
	_expect(frame.texture != null, "the console frame has its texture")
	if frame.texture == null:
		return
	_expect(not frame.centered, "the console frame is drawn from its top left")
	_expect(frame.texture.get_size() == Vector2(800, 200), "the console frame is the original 800x200")
	var band := console.get_node("Band") as Control
	_expect(
		frame.position.y + frame.texture.get_height() == band.size.y,
		"the console frame reaches the bottom of its band"
	)


# The bands are what carries the original's absolute coordinates onto a canvas that is only
# fixed in height. Band is bottom docked like the original's frame flag 8, Banners top
# aligned like its flag 0, and both must let clicks through to the world.
func _check_the_bands_are_anchored(console: Node) -> void:
	var band := console.get_node("Band") as Control
	_expect(
		Vector4(band.anchor_left, band.anchor_top, band.anchor_right, band.anchor_bottom)
			== Vector4(0.5, 1.0, 0.5, 1.0),
		"the console band is anchored to the bottom centre"
	)
	_expect(
		Vector4(band.offset_left, band.offset_top, band.offset_right, band.offset_bottom)
			== Vector4(-400.0, -600.0, 400.0, 0.0),
		"the console band is the original 800x600"
	)
	var banners := console.get_node("Banners") as Control
	_expect(
		Vector4(banners.anchor_left, banners.anchor_top, banners.anchor_right, banners.anchor_bottom)
			== Vector4(0.5, 0.0, 0.5, 0.0),
		"the banner band is anchored to the top centre"
	)
	_expect(
		Vector4(banners.offset_left, banners.offset_top, banners.offset_right, banners.offset_bottom)
			== Vector4(-400.0, 0.0, 400.0, 600.0),
		"the banner band is the original 800x600"
	)
	for name in ["Band", "Banners"]:
		var control := console.get_node(name) as Control
		_expect(
			control.mouse_filter == Control.MOUSE_FILTER_IGNORE,
			"%s lets the pointer through to the world" % name
		)


func _check_inert_elements(console: Node) -> void:
	for element: String in InertElements:
		var node := console.get_node(element) as CanvasItem
		_expect(not node.visible, "%s stays hidden until something drives it" % element)


# Both banners are built at alpha 220 (+1163), but each caption is a CGUIText of its own that
# sub_45A730 draws in mode 39, keyed and opaque, over an opaque (30, 30, 30) copy. So only the
# banner art is translucent; the caption must not inherit its alpha.
func _check_the_warning_captions_are_opaque(console: Node) -> void:
	for banner_path in ["Banners/ThermoUp", "Banners/AggroUp"]:
		var banner := console.get_node(banner_path) as Sprite2D
		var caption := banner.get_child(0) as Label
		_expect(is_equal_approx(banner.self_modulate.a, 220.0 / 255.0), "%s's art is drawn at alpha 220" % banner_path)
		var inherited := banner.modulate.a * caption.modulate.a * caption.self_modulate.a
		_expect(is_equal_approx(inherited, 1.0), "%s's caption draws opaque, got alpha %f" % [banner_path, inherited])


# The lamps read player+1008 directly: smoking needs both of its slots, the other two one
# each. See docs/hud-reference.md.
func _check_lamps(console: Node) -> void:
	var inventory := PackedInt32Array()
	inventory.resize(PrankControllerScript.INVENTORY_SLOTS)
	inventory[5] = 1
	console.set_inventory(inventory)
	_expect(not (console.get_node("Band/LampSmoke") as CanvasItem).visible, "the smoking lamp needs both of its items")
	inventory[6] = 1
	console.set_inventory(inventory)
	_expect((console.get_node("Band/LampSmoke") as CanvasItem).visible, "the smoking lamp lights once both are held")
	inventory[14] = 1
	inventory[26] = 1
	console.set_inventory(inventory)
	_expect((console.get_node("Band/LampMatrix") as CanvasItem).visible, "the Matrix lamp reads slot 14")
	_expect((console.get_node("Band/LampPiss") as CanvasItem).visible, "the urination lamp reads slot 26")
	console.set_inventory(PackedInt32Array())


# game+14724 sits at (662, 536), the stopwatch, and is fed player+992 * 100 / player+1000.
# A half and a whole sweep cover what the original's fan does at 0.5 and 1.0, 2178 and 4413
# pixels (tests/fixtures/round_bar_goldens.json).
func _check_action_progress(console: Node) -> void:
	var bar := console.get_node("Band/ClockBar") as Sprite2D
	console.set_action_progress(0.0, 0.0)
	_expect(not bar.visible, "the progress bar is hidden while no action runs")
	console.set_action_progress(2.5, 5.0)
	_expect(bar.visible, "the progress bar shows while an action runs")
	_expect(_drawn_pixels(console) == 2178, "half an action sweeps half the dial, got %d pixels" % _drawn_pixels(console))
	console.set_action_progress(9.0, 5.0)
	_expect(_drawn_pixels(console) == 4413, "the sweep never runs past a full turn, got %d pixels" % _drawn_pixels(console))
	console.set_action_progress(0.0, 0.0)


# The window the console last drew. The headless renderer keeps no texture data, so this reads
# the image the bar's texture is updated from.
func _drawn_pixels(console: Node) -> int:
	var image: Image = console.get("_clock_image")
	var count := 0
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			if image.get_pixel(x, y).a > 0.0:
				count += 1
	return count


# CGUIRoundBarTex fans out *from* (662, 536) with the radius, step and start angle
# sub_405930 gives it, so the console draws a window around that centre rather than the
# texture at its corner, and every pixel it draws is a texel of the dial art.
# See docs/hud-reference.md.
func _check_the_stopwatch_sweeps_the_dial(console: Node) -> void:
	var bar := console.get_node("Band/ClockBar") as Sprite2D
	_expect(not bar.centered, "the stopwatch window is placed from its top left")
	_expect(console.CLOCK_BAR_RADIUS == 38.0, "the fan keeps the original radius, got %f" % console.CLOCK_BAR_RADIUS)
	_expect(console.CLOCK_BAR_STEP == 15, "the fan keeps the original step, got %d" % console.CLOCK_BAR_STEP)
	_expect(console.CLOCK_BAR_START_ANGLE == 0.5, "the sweep starts at the original angle")
	var half := RoundBarFan.WINDOW / 2
	_expect(bar.position == Vector2(662, 536), "the stopwatch element sits at its centre, got %s" % bar.position)
	_expect(bar.offset == Vector2(-half, -half), "the window hangs half its size up and left, got %s" % bar.offset)
	var dial := (load("res://images/gui/hud/clock-full.png") as Texture2D).get_image()
	dial.convert(Image.FORMAT_RGBA8)
	var fan := RoundBarFan.new(console.CLOCK_BAR_CENTRE, console.CLOCK_BAR_RADIUS, console.CLOCK_BAR_STEP, console.CLOCK_BAR_START_ANGLE, dial.get_width())
	var texels: PackedInt32Array = fan.draw(1.0)[0]
	console.set_action_progress(1.0, 1.0)
	var image: Image = console.get("_clock_image")
	var wrong := 0
	for index in range(texels.size()):
		if texels[index] == RoundBarFan.NONE:
			continue
		var texel := texels[index]
		var expected := dial.get_pixel(texel % dial.get_width(), texel / dial.get_width())
		var shown := image.get_pixel(index % RoundBarFan.WINDOW, index / RoundBarFan.WINDOW)
		if not shown.is_equal_approx(Color(expected.r, expected.g, expected.b, 1.0)):
			wrong += 1
	_expect(wrong == 0, "every swept pixel shows the dial texel the fan maps to it, %d do not" % wrong)
	console.set_action_progress(0.0, 0.0)


# game+14732 is fed `188 - (aggro * 1.42 + 46)` as the width to crop off its right edge.
func _check_the_aggression_bar(console: Node) -> void:
	var bar := console.get_node("Band/AggroBar") as Sprite2D
	_expect(bar.visible, "the aggression bar is on screen from the first frame")
	_expect(bar.region_enabled, "the bar is cropped rather than scaled")
	_expect(bar.texture != null and bar.texture.get_size() == Vector2(188, 40), "the bar art is the original 188x40")

	console.set_aggression(0.0)
	_expect(bar.region_rect.size == Vector2(46, 40), "a calm office still shows 46 pixels, got %s" % bar.region_rect.size)
	console.set_aggression(100.0)
	_expect(bar.region_rect.size == Vector2(188, 40), "a furious office fills the bar, got %s" % bar.region_rect.size)
	console.set_aggression(50.0)
	_expect(bar.region_rect.size == Vector2(117, 40), "half an office is 117 pixels, got %s" % bar.region_rect.size)
	console.set_aggression(0.0)

	# sub_407960 raises the warning for two seconds and sub_403780 counts it back down.
	var thermo := console.get_node("Banners/ThermoUp") as Sprite2D
	_expect(not thermo.visible, "the warning is down until the office crosses a band")
	console.warn_of_aggravation()
	_expect(thermo.visible, "crossing a band raises the warning")
	console._process(1.9)
	_expect(thermo.visible, "the warning holds for two seconds")
	console._process(0.2)
	_expect(not thermo.visible, "and goes down again after them")


func _check_score_field(console: Node) -> void:
	var score := console.get_node("Band/Score") as Label
	console._on_score_changed(0)
	_expect(score.text == "00000", "an empty score reads 00000, got %s" % score.text)
	console._on_score_changed(4000)
	_expect(score.text == "04000", "the score is zero padded to five digits, got %s" % score.text)
	console._on_score_changed(123456)
	_expect(score.text == "99999", "the score stays inside the five digit field, got %s" % score.text)


func _check_clock_field(console: Node) -> void:
	var clock := console.get_node("Band/Clock") as Label
	console._on_time_changed(0)
	_expect(clock.text == "00:00", "the clock starts at 00:00, got %s" % clock.text)
	console._on_time_changed(11)
	_expect(clock.text == "00:11", "eleven seconds reads 00:11, got %s" % clock.text)
	console._on_time_changed(360)
	_expect(clock.text == "06:00", "level 1's limit reads 06:00, got %s" % clock.text)
	# sub_403780 gives up past 5940 seconds rather than printing a fourth digit.
	console._on_time_changed(5940)
	_expect(clock.text == "99:00", "5940 seconds still reads as a clock, got %s" % clock.text)
	console._on_time_changed(5941)
	_expect(clock.text == "XX:XX", "past 5940 seconds the clock reads XX:XX, got %s" % clock.text)


func _check_hover_text(console: Node) -> void:
	var hover := console.get_node("Band/HoverText") as Label
	_expect(hover.text == "...", "the hover bar idles on the original placeholder")
	console.set_hover_text("Zrestrukturyzuj pliki")
	_expect(hover.text == "Zrestrukturyzuj pliki", "the hover bar shows an action name")
	console.set_hover_text("")
	_expect(hover.text == "...", "an empty hover text falls back to the placeholder")


# The console finds its session by group, so a level has to satisfy that without wiring.
func _check_the_level_console_follows_its_session() -> void:
	var level := (load("res://scenes/level_1.tscn") as PackedScene).instantiate()
	var runtime: Node = level.get_node("LevelRuntime")
	runtime.enabled = false
	root.add_child(level)
	await process_frame
	var console := runtime.get_node_or_null("Console")
	_expect(console != null, "the level carries the console")
	if console != null:
		runtime.add_score(250)
		runtime.advance(65.0)
		_expect((console.get_node("Band/Score") as Label).text == "00250", "the console shows the session score")
		_expect((console.get_node("Band/Clock") as Label).text == "01:05", "the console shows the session clock")
	root.remove_child(level)
	level.free()
