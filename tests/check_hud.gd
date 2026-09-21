extends SceneTree


const ConsoleScene := preload("res://scenes/hud/console.tscn")

# sub_405930 builds every element at these absolute screen positions; the frame is bottom
# docked, which puts its 200 pixels at y 400..600. See docs/hud-reference.md.
const ExpectedPositions := {
	"Frame": Vector2(0, 400),
	"Score": Vector2(85, 500),
	"Clock": Vector2(250, 500),
	"HoverText": Vector2(135, 556),
	"ActionIcon": Vector2(170, 477),
	"AggroBar": Vector2(410, 497),
	"ClockBar": Vector2(662, 536),
	"LampSmoke": Vector2(717, 461),
	"LampPiss": Vector2(756, 485),
	"LampMatrix": Vector2(754, 537),
}
# Each of these waits on something: an action running, an action highlighted, or an item
# held. At rest, with an empty inventory, none of them may be drawn over the frame.
const InertElements := ["ActionIcon", "AggroBar", "ClockBar", "LampSmoke", "LampPiss", "LampMatrix"]

var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var console := ConsoleScene.instantiate()
	root.add_child(console)
	await process_frame

	_check_positions(console)
	_check_frame_covers_the_console_band(console)
	_check_inert_elements(console)
	_check_lamps(console)
	_check_action_progress(console)
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
	var frame := console.get_node("Frame") as Sprite2D
	_expect(frame.texture != null, "the console frame has its texture")
	if frame.texture == null:
		return
	_expect(not frame.centered, "the console frame is drawn from its top left")
	_expect(frame.texture.get_size() == Vector2(800, 200), "the console frame is the original 800x200")
	_expect(frame.position.y + frame.texture.get_height() == 600, "the console frame reaches the bottom of the viewport")


func _check_inert_elements(console: Node) -> void:
	for element: String in InertElements:
		var node := console.get_node(element) as CanvasItem
		_expect(not node.visible, "%s stays hidden until something drives it" % element)


# The lamps read player+1008 directly: smoking needs both of its slots, the other two one
# each. See docs/hud-reference.md.
func _check_lamps(console: Node) -> void:
	var inventory := PackedInt32Array()
	inventory.resize(28)
	inventory[5] = 1
	console.set_inventory(inventory)
	_expect(not (console.get_node("LampSmoke") as CanvasItem).visible, "the smoking lamp needs both of its items")
	inventory[6] = 1
	console.set_inventory(inventory)
	_expect((console.get_node("LampSmoke") as CanvasItem).visible, "the smoking lamp lights once both are held")
	inventory[14] = 1
	inventory[26] = 1
	console.set_inventory(inventory)
	_expect((console.get_node("LampMatrix") as CanvasItem).visible, "the Matrix lamp reads slot 14")
	_expect((console.get_node("LampPiss") as CanvasItem).visible, "the urination lamp reads slot 26")
	console.set_inventory(PackedInt32Array())


# game+14724 is fed player+992 * 100 / player+1000: the bar is action progress.
func _check_action_progress(console: Node) -> void:
	var bar := console.get_node("AggroBar") as Sprite2D
	var full: float = bar.texture.get_size().x
	console.set_action_progress(0.0, 0.0)
	_expect(not bar.visible, "the progress bar is hidden while no action runs")
	console.set_action_progress(2.5, 5.0)
	_expect(bar.visible, "the progress bar shows while an action runs")
	_expect(is_equal_approx(bar.region_rect.size.x, full * 0.5), "the bar is clipped to how far the action has come")
	console.set_action_progress(9.0, 5.0)
	_expect(is_equal_approx(bar.region_rect.size.x, full), "the bar never clips past its own width")
	console.set_action_progress(0.0, 0.0)


func _check_score_field(console: Node) -> void:
	var score := console.get_node("Score") as Label
	console._on_score_changed(0)
	_expect(score.text == "00000", "an empty score reads 00000, got %s" % score.text)
	console._on_score_changed(4000)
	_expect(score.text == "04000", "the score is zero padded to five digits, got %s" % score.text)
	console._on_score_changed(123456)
	_expect(score.text == "99999", "the score stays inside the five digit field, got %s" % score.text)


func _check_clock_field(console: Node) -> void:
	var clock := console.get_node("Clock") as Label
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
	var hover := console.get_node("HoverText") as Label
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
		_expect((console.get_node("Score") as Label).text == "00250", "the console shows the session score")
		_expect((console.get_node("Clock") as Label).text == "01:05", "the console shows the session clock")
	root.remove_child(level)
	level.free()
