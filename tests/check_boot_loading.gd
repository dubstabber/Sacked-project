extends SceneTree

# The boot screen, 2, as recovered in docs/shell-reference.md: a hundred steps of
# sub_403E20, the full pot revealed from the bottom by clipping _ftol(h - h * progress) rows
# off its top, stream frame _ftol(progress * 100) % 5, no key or click that skips it, Menu1
# from the first frame, and LOADING_EVIL on the 666th launch. The expected frames and clips
# below were computed from the executable's own float constants (0.01f at 0x465308, 100.0f at
# 0x465304), outside the port.

const SCREEN := preload("res://scenes/screens/boot_loading.tscn")
const BootLoading := preload("res://scenes/screens/boot_loading.gd")
const ScreenManagerScript := preload("res://autoloads/screen_manager.gd")
const STORE_SCRIPT := preload("res://autoloads/settings_store.gd")
const TEST_PATH := "user://check_boot_loading.cfg"

# step: [stream frame, rows of the pot still clipped]. The stored float lands most steps just
# under their hundredth, so the stream usually shows the frame before step % 5.
const EXPECTED := {
	0: [0, 51], 1: [0, 50], 2: [1, 49], 5: [4, 48], 7: [2, 47], 14: [4, 43],
	17: [2, 42], 25: [0, 38], 50: [0, 25], 99: [3, 0], 100: [0, 0],
}

var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var manager: Node = root.get_node_or_null("ScreenManager")
	var screen := SCREEN.instantiate()
	screen.advances = false
	root.add_child(screen)
	await process_frame

	_check_every_step_draws_the_recovered_frame_and_clip(screen)
	_check_the_clock_steps_at_the_nominal_rate(screen)
	_check_nothing_skips_it(screen)
	_check_the_666th_launch()
	_check_menu1_starts_with_the_screen(manager)

	screen.queue_free()
	await process_frame
	DirAccess.remove_absolute(TEST_PATH)
	if _failures == 0:
		print("Boot screen: a hundred recovered steps of pot and stream, the nominal clock, no skipping, Menu1, and the 666th launch passed")
	quit(1 if _failures else 0)


func _expect(condition: bool, label: String) -> void:
	if not condition:
		_failures += 1
		push_error(label)


func _check_every_step_draws_the_recovered_frame_and_clip(screen: Node) -> void:
	var pot := screen.get_node("SafeFrame/Pot") as Sprite2D
	var stream := screen.get_node("SafeFrame/Stream") as Sprite2D
	_expect(stream.position == Vector2(397, 343), "the stream is drawn at (400, 300) less its (3, -43) pivot")
	screen.step = 0
	screen.show_step(0)
	for step in range(0, 101):
		if step > 0:
			screen.advance()
		_expect(screen.step == step, "the tick counts one step at a time, got %d" % screen.step)
		if not EXPECTED.has(step):
			continue
		var frame: int = EXPECTED[step][0]
		var top: int = EXPECTED[step][1]
		_expect(
			stream.texture.resource_path.ends_with("piss-%03d.png" % frame),
			"step %d shows stream frame %d, got %s" % [step, frame, stream.texture.resource_path.get_file()]
		)
		_expect(
			pot.region_rect == Rect2(0, top, 55, 51 - top),
			"step %d clips %d rows off the pot's top, got %s" % [step, top, pot.region_rect]
		)
		_expect(pot.position == Vector2(375, 487 + top), "step %d keeps the pot's bottom where it stands" % step)
	screen.advance()
	_expect(screen.step == 100, "the tick stops counting at 100")


func _check_the_clock_steps_at_the_nominal_rate(screen: Node) -> void:
	screen.step = 0
	screen.show_step(0)
	screen._process(NPCBrain.ORIGINAL_FRAME_SECONDS * 3.0 + 0.0001)
	_expect(screen.step == 3, "three sixtieths of a second take three steps, got %d" % screen.step)
	screen._process(NPCBrain.ORIGINAL_FRAME_SECONDS * 0.5)
	_expect(screen.step == 3, "half a sixtieth takes none")


# Screen 2's input handler (0x4048B0) throws every event away.
func _check_nothing_skips_it(screen: Node) -> void:
	var handlers := []
	for method in (screen.get_script() as Script).get_script_method_list():
		if String(method["name"]) in ["_input", "_unhandled_input", "_unhandled_key_input", "_gui_input", "_shortcut_input"]:
			handlers.append(method["name"])
	_expect(handlers.is_empty(), "the boot screen reads no input, got %s" % [handlers])
	_expect(screen.get_node_or_null("AdvanceTimer") == null, "no timer cuts it short")


func _check_the_666th_launch() -> void:
	DirAccess.remove_absolute(TEST_PATH)
	var store: Node = STORE_SCRIPT.new()
	store.path = TEST_PATH
	store.reload()
	_expect(store.launch_count() == 0, "a fresh profile has not launched yet")
	_expect(store.count_launch() == 1, "the first launch counts as 1")
	store._config.set_value(STORE_SCRIPT.LAUNCH_SECTION, STORE_SCRIPT.LAUNCH_COUNT_KEY, 665)
	_expect(store.count_launch() == 666, "the count goes up before the screen is built")
	var reopened: Node = STORE_SCRIPT.new()
	reopened.path = TEST_PATH
	reopened.reload()
	_expect(reopened.launch_count() == 666, "the count survives a restart")
	reopened.free()
	store.free()
	for launch: int in [1, 665, 667, 1332]:
		_expect(
			BootLoading.background_for(launch).resource_path.ends_with("loading.png"),
			"launch %d shows the ordinary still" % launch
		)
	_expect(
		BootLoading.background_for(666).resource_path.ends_with("loading_evil.png"),
		"launch 666 shows LOADING_EVIL"
	)


func _check_menu1_starts_with_the_screen(manager: Node) -> void:
	var menu1 := load("res://audio/music/menu1.ogg")
	_expect(
		manager._menu_music_for(ScreenManagerScript.Screen.BOOT_LOADING) == menu1,
		"case 2 starts Menu1"
	)
	manager.enter_boot_screen()
	var player := manager.get_node("MenuMusic") as AudioStreamPlayer
	_expect(player.stream == menu1 and player.playing, "Menu1 plays from the boot screen on")
	player.stop()
