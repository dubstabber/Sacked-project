extends SceneTree

# The canvas is 600 pixels tall and grows sideways with the window, so every recovered
# 800x600 coordinate has to live inside something anchored. This drives the HUD, the ring,
# the prompts and the art screens at three canvas shapes and checks they stay put.
# See docs/widescreen.md.

const ConsoleScene := preload("res://scenes/hud/console.tscn")
const MenuScene := preload("res://scenes/hud/round_menu.tscn")
const PromptsScene := preload("res://scenes/hud/level_prompts.tscn")
const PROMPTS := preload("res://scenes/hud/level_prompts.gd")

const ORIGINAL := Vector2(800.0, 600.0)
const CONSOLE_HEIGHT := 200.0

# 4:3 is the original's own shape, 16:9 the one that widens it, 5:4 the one that grows the
# canvas vertically instead. All three keep 800x600 as the minimum.
const SIZES: Array[Vector2i] = [Vector2i(800, 600), Vector2i(1067, 600), Vector2i(800, 640)]

const SCREENS := [
	"res://scenes/screens/boot_loading.tscn",
	"res://scenes/screens/main_menu.tscn",
	"res://scenes/screens/character_select.tscn",
	"res://scenes/screens/level_tree.tscn",
	"res://scenes/screens/level_description.tscn",
	"res://scenes/screens/level_result.tscn",
	"res://scenes/screens/highscores.tscn",
	"res://scenes/screens/sound_setup.tscn",
]

var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	for size in SIZES:
		await _check_the_console_bands(size)
		await _check_the_ring_centre(size)
		await _check_the_prompt_panels(size)
		for path in SCREENS:
			await _check_a_safe_frame(path, size)

	if _failures == 0:
		print("Wide-screen: console bands, ring centre, prompt panels and safe frames hold at 4:3, 16:9 and 5:4")
	quit(1 if _failures else 0)


func _expect(condition: bool, label: String) -> void:
	if not condition:
		_failures += 1
		push_error(label)


# The headless root window reports no size, so each fixture gets a SubViewport of its own.
func _mount(node: Node, size: Vector2i) -> SubViewport:
	var viewport := SubViewport.new()
	viewport.size = size
	root.add_child(viewport)
	viewport.add_child(node)
	await process_frame
	await process_frame
	return viewport


func _drop(viewport: SubViewport) -> void:
	root.remove_child(viewport)
	viewport.free()


func _check_the_console_bands(size: Vector2i) -> void:
	var console := ConsoleScene.instantiate()
	var viewport := await _mount(console, size)
	var view := Vector2(size)
	var left := (view.x - ORIGINAL.x) * 0.5

	var band := console.get_node("Band") as Control
	_expect(
		band.get_global_rect().is_equal_approx(Rect2(left, view.y - ORIGINAL.y, ORIGINAL.x, ORIGINAL.y)),
		"%s: the console band is bottom centred, got %s" % [size, band.get_global_rect()]
	)
	var frame := console.get_node("Band/Frame") as Sprite2D
	_expect(
		is_equal_approx(frame.global_position.y + frame.texture.get_height(), view.y),
		"%s: the console frame still reaches the bottom of the canvas" % size
	)
	_expect(
		is_equal_approx(frame.global_position.x, left),
		"%s: the console frame is centred, got x %f" % [size, frame.global_position.x]
	)

	var banners := console.get_node("Banners") as Control
	_expect(
		banners.get_global_rect().is_equal_approx(Rect2(left, 0.0, ORIGINAL.x, ORIGINAL.y)),
		"%s: the banner band is top centred, got %s" % [size, banners.get_global_rect()]
	)
	# The banners are a starburst and a ribbon on a transparent plate, not a full-screen
	# tint, so stretching them would pull the ribbon off its caption.
	var thermo := console.get_node("Banners/ThermoUp") as Sprite2D
	_expect(thermo.scale.is_equal_approx(Vector2.ONE), "%s: the thermometer banner is never scaled" % size)
	_expect(
		thermo.global_position.is_equal_approx(Vector2(left + 5.0, 5.0)),
		"%s: the thermometer banner keeps its recovered corner, got %s" % [size, thermo.global_position]
	)
	_drop(viewport)


func _check_the_ring_centre(size: Vector2i) -> void:
	var menu := MenuScene.instantiate()
	var viewport := await _mount(menu, size)
	var view := Vector2(size)
	_expect(
		menu.centre().is_equal_approx(Vector2(view.x * 0.5, (view.y - CONSOLE_HEIGHT) * 0.5)),
		"%s: the ring centres on the band above the console, got %s" % [size, menu.centre()]
	)
	_drop(viewport)


func _check_the_prompt_panels(size: Vector2i) -> void:
	var prompts := PromptsScene.instantiate()
	var viewport := await _mount(prompts, size)
	var panels := prompts.get_node("Panels") as Control
	var left := (float(size.x) - ORIGINAL.x) * 0.5
	for panel: Rect2 in [PROMPTS.PAUSE_PANEL, PROMPTS.QUIT_PANEL]:
		var placed: Rect2 = panels.panel_rect(panel)
		_expect(
			is_equal_approx(placed.position.x, panel.position.x + left),
			"%s: a prompt panel recentres by half the added width, got x %f" % [size, placed.position.x]
		)
		_expect(placed.size.is_equal_approx(panel.size), "%s: a prompt panel keeps its recovered size" % size)
		_expect(is_equal_approx(placed.position.y, panel.position.y), "%s: a prompt panel keeps its recovered y" % size)
	_drop(viewport)


func _check_a_safe_frame(path: String, size: Vector2i) -> void:
	var scene := load(path) as PackedScene
	var screen := scene.instantiate()
	# Boot's timer would otherwise advance the screen out from under the check.
	var timer := screen.get_node_or_null("AdvanceTimer") as Timer
	if timer != null:
		timer.autostart = false
	var viewport := await _mount(screen, size)
	var view := Vector2(size)

	var frame := screen.get_node_or_null("SafeFrame") as Control
	_expect(frame != null, "%s: %s has a safe frame" % [size, path])
	if frame != null:
		_expect(
			frame.get_global_rect().is_equal_approx(
				Rect2((view.x - ORIGINAL.x) * 0.5, (view.y - ORIGINAL.y) * 0.5, ORIGINAL.x, ORIGINAL.y)
			),
			"%s: %s centres its 800x600 layout, got %s" % [size, path, frame.get_global_rect()]
		)
		_expect(frame.mouse_filter == Control.MOUSE_FILTER_IGNORE, "%s: %s's safe frame passes the pointer through" % [size, path])

	# The original pillarboxes in black on a widescreen display, so the margin around the
	# 4:3 art is black rather than a second copy of the art. See docs/widescreen.md.
	_expect(
		screen.get_node_or_null("Backdrop") == null,
		"%s does not repeat its own art in the margin" % path
	)
	var margin := screen.get_node_or_null("Margin") as ColorRect
	_expect(margin != null, "%s: %s has a margin behind its frame" % [size, path])
	if margin != null:
		_expect(margin.color == Color.BLACK, "%s's margin is the original's pillarbox black" % path)
		_expect(
			margin.get_global_rect().is_equal_approx(Rect2(0.0, 0.0, view.x, view.y)),
			"%s: %s's margin covers the canvas, got %s" % [size, path, margin.get_global_rect()]
		)
		_expect(margin.mouse_filter == Control.MOUSE_FILTER_IGNORE, "%s's margin passes the pointer through" % path)
		_expect(
			margin.get_index() < frame.get_index(),
			"%s's margin is drawn behind its safe frame" % path
		)

	_drop(viewport)
