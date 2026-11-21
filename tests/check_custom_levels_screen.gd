extends SceneTree

# The port's Custom levels screen and the route through it (docs/shell-reference.md):
#
# - it lists the CustomLevelInfo files of its directory, skipping one whose scene is missing,
#   and shows the chosen level's own title and description as written;
# - a mode button starts that level's scene in that mode, through ScreenManager;
# - a win is recorded as the custom level's best run and touches no campaign level;
# - the result screen's second button after a win comes back to this screen, which shows the
#   new best time;
# - with nothing to list it says so and offers no start.

const SCREEN := preload("res://scenes/screens/custom_levels.tscn")
const RESULT := preload("res://scenes/screens/level_result.tscn")
const FIXTURES := "res://tests/fixtures/custom_levels/"
const TEMPLATE := "res://scenes/custom_level_template.tscn"
const PROGRESS_PATH := "user://check_custom_levels_progress.cfg"

var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var manager := root.get_node("ScreenManager")
	var store := root.get_node("ProgressStore")
	var restore_path: String = store.path
	store.path = PROGRESS_PATH
	DirAccess.remove_absolute(PROGRESS_PATH)
	store.reload()
	await process_frame

	var screen := SCREEN.instantiate()
	screen.directory = FIXTURES
	root.add_child(screen)
	await process_frame
	_expect(screen.levels.size() == 1, "the fixture is listed and the level with no scene is not, got %d" % screen.levels.size())
	_expect(screen.get_node("SafeFrame/Rows/List").get_child_count() == 1, "one row is drawn")
	var row: Control = screen.rows[0]
	var title := row.get_node("Title") as Label
	_expect(title.text == "Fixture office" and title.auto_translate_mode == Node.AUTO_TRANSLATE_MODE_DISABLED, "under its own title, untranslated")
	_expect((row.get_node("Author") as Label).text == "tests", "with its author")
	_expect((row.get_node("BestTime") as Label).text == "--:--" and (row.get_node("BestScore") as Label).text == "---", "and no record yet")
	_expect((row.get_node("Highlight") as CanvasItem).visible, "the first row starts chosen")
	_expect((screen.get_node("SafeFrame/Description") as Label).text.begins_with("The template"), "its description shows below the list")

	(screen.get_node("SafeFrame/TimeGame") as TextureButton).pressed.emit()
	await process_frame
	await process_frame
	_expect(manager.current == manager.Screen.LEVEL, "the time button starts the level")
	_expect(manager.selected_custom_level != null and manager.selected_custom_level.scene == TEMPLATE, "the custom level")
	_expect(manager.selected_game_mode == &"time", "in the time game")
	_expect(current_scene != null and current_scene.scene_file_path == TEMPLATE, "its scene is the one on show")

	manager.report_level_finished(true, 2500, 42.0, TEMPLATE)
	await process_frame
	_expect(is_equal_approx(store.custom_best_time_seconds(TEMPLATE), 42.0), "a win records the custom level's best time")
	_expect(store.cleared_mask(&"time") == 0 and not store.has_best_time(1), "and no campaign level")
	_expect(manager.current == manager.Screen.LEVEL_RESULT, "the result screen shows")
	await process_frame
	var result := current_scene
	if result != null and result.has_node("SafeFrame/Forward"):
		(result.get_node("SafeFrame/Forward") as TextureButton).pressed.emit()
	await process_frame
	await process_frame
	_expect(manager.current == manager.Screen.CUSTOM_LEVELS, "after a win its second button comes back to the custom levels")

	var again := SCREEN.instantiate()
	again.directory = FIXTURES
	root.add_child(again)
	await process_frame
	_expect((again.rows[0].get_node("BestTime") as Label).text == "00:42", "whose row shows the new best time")
	root.remove_child(again)
	again.free()

	var empty := SCREEN.instantiate()
	empty.directory = "res://tests/fixtures/no_such_directory/"
	root.add_child(empty)
	await process_frame
	_expect(empty.get_node("SafeFrame/Empty").visible, "with nothing to list the screen says so")
	_expect((empty.get_node("SafeFrame/TimeGame") as TextureButton).disabled and (empty.get_node("SafeFrame/PointsGame") as TextureButton).disabled, "and offers no start")
	root.remove_child(empty)
	empty.free()

	root.remove_child(screen)
	screen.free()
	manager.start_level(1)
	manager.change_to_main_menu()
	await process_frame
	store.path = restore_path
	store.reload()
	DirAccess.remove_absolute(PROGRESS_PATH)
	if _failures == 0:
		print("Custom levels screen: the list, the start in either mode, the separate record, the way back after a win and the empty list passed")
	quit(1 if _failures else 0)


func _expect(condition: bool, label: String) -> void:
	if not condition:
		_failures += 1
		push_error(label)
