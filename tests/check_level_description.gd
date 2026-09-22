extends SceneTree

# The original's screen 16: the level's own text with its objective spliced in, and four
# label/value pairs read out of the saved record. Text is pinned to Polish, which is the
# language both the generated strings and the reference screenshot are in.
# See docs/shell-reference.md.

const DescriptionScene := preload("res://scenes/screens/level_description.tscn")
const TEST_PATH := "user://check_level_description.cfg"

var _failures := 0
var _restore_path := ""
var _restore_language: StringName = &"pl"
var _restore_level := 1


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var i18n := root.get_node("I18n")
	_restore_language = i18n.current_language()
	i18n.set_language(&"pl")

	var store := root.get_node("ProgressStore")
	_restore_path = store.path
	store.path = TEST_PATH
	DirAccess.remove_absolute(TEST_PATH)
	store.reload()

	var screens := root.get_node("ScreenManager")
	_restore_level = screens.selected_level

	await _check_level_one_reads_as_the_screenshot_does()
	await _check_the_objective_is_spliced_between_description_and_hint()
	await _check_a_recorded_run_replaces_the_two_sentinels()
	await _check_the_points_game_states_its_own_condition()
	await _check_a_level_with_no_scene_cannot_be_started()

	screens.selected_level = _restore_level
	screens.selected_game_mode = &"time"
	store.path = _restore_path
	store.reload()
	DirAccess.remove_absolute(TEST_PATH)
	i18n.set_language(_restore_language)
	if _failures == 0:
		print("Level description: the title, the four info pairs, the spliced objective and the unstartable level passed")
	quit(1 if _failures else 0)


func _expect(condition: bool, label: String) -> void:
	if not condition:
		_failures += 1
		push_error(label)


func _open(level: int, mode: StringName = &"time") -> Control:
	var screens := root.get_node("ScreenManager")
	screens.selected_level = level
	screens.selected_game_mode = mode
	var screen := DescriptionScene.instantiate() as Control
	root.add_child(screen)
	await process_frame
	return screen


func _text(screen: Control, path: String) -> String:
	var label := screen.get_node_or_null(path) as Label
	return "" if label == null else label.text


func _check_level_one_reads_as_the_screenshot_does() -> void:
	var screen := await _open(1)
	# The screenshot's own title, which is sub_421CD0's "%s (#%02d)".
	_expect(
		_text(screen, "SafeFrame/Title") == "Pierwszy ostatni dzień (#01)",
		"the title should read Pierwszy ostatni dzień (#01), got %s" % _text(screen, "SafeFrame/Title")
	)
	_expect(
		_text(screen, "SafeFrame/Info/SizeValue") == "16 x 16",
		"level 1's MAPINFO is 16 x 16, got %s" % _text(screen, "SafeFrame/Info/SizeValue")
	)
	_expect(
		_text(screen, "SafeFrame/Info/DifficultyValue") == "Początkujący",
		"level 1 sits in tree column 1, so its difficulty is Początkujący"
	)
	# HIGHSCORE.DAT's two empty markers, which sub_421CD0 writes as C literals.
	_expect(_text(screen, "SafeFrame/Info/BestTimeValue") == "--:--", "an unplayed level shows --:--")
	_expect(_text(screen, "SafeFrame/Info/BestScoreValue") == "---", "an unplayed level shows ---")
	# A Label auto-translates what it draws, so the key stays in `text` and the wording is
	# checked through the server, exactly as the screen will render it.
	_expect(
		_text(screen, "SafeFrame/Info/BestTimeLabel") == "description.best_time",
		"the best-time label carries slot 194's key"
	)
	_expect(
		TranslationServer.translate(&"description.best_time") == "Najlepszy czas",
		"slot 194 reads Najlepszy czas in Polish"
	)
	screen.queue_free()
	await process_frame


func _check_the_objective_is_spliced_between_description_and_hint() -> void:
	var screen := await _open(1)
	var body := _text(screen, "SafeFrame/DescText")
	var description := TranslationServer.translate(&"level.1.description")
	var hint := TranslationServer.translate(&"level.1.hint")
	var goal := GoalText.sentence(&"time", 360.0, 4000)
	_expect(body.begins_with(description), "the panel opens with the level's own description")
	_expect(body.ends_with(hint), "the panel closes with the level's own hint")
	_expect(body.contains(goal), "the objective is spliced into the %s, got %s" % ["%s", body])
	# Level 1 is 4000 points in 6 minutes, which is the sentence the pause panel also shows.
	_expect(goal.contains("4000"), "level 1's objective names its 4000 points")
	_expect(goal.contains("6"), "level 1's objective names its 6 minutes")
	screen.queue_free()
	await process_frame


func _check_a_recorded_run_replaces_the_two_sentinels() -> void:
	var store := root.get_node("ProgressStore")
	store.record_result(1, &"time", true, 0, 174.0, "Anne")
	store.record_result(1, &"points", true, 5200, 300.0, "Jo")
	var screen := await _open(1)
	_expect(
		_text(screen, "SafeFrame/Info/BestTimeValue") == "02:54",
		"174 seconds should read 02:54, got %s" % _text(screen, "SafeFrame/Info/BestTimeValue")
	)
	# sub_421CD0 pads the score to six digits.
	_expect(
		_text(screen, "SafeFrame/Info/BestScoreValue") == "005200",
		"5200 should read 005200, got %s" % _text(screen, "SafeFrame/Info/BestScoreValue")
	)
	screen.queue_free()
	await process_frame


func _check_the_points_game_states_its_own_condition() -> void:
	# sub_408D00 reads the S file for the points game, and level 1's differs: 3000 in 5.
	var timed := await _open(1, &"time")
	var timed_body := _text(timed, "SafeFrame/DescText")
	timed.queue_free()
	await process_frame

	var points := await _open(1, &"points")
	var points_body := _text(points, "SafeFrame/DescText")
	points.queue_free()
	await process_frame

	_expect(timed_body != points_body, "the two game modes state different objectives")
	_expect(points_body.contains("3000"), "the points game names the S file's 3000 points")
	_expect(timed_body.contains("4000"), "the time game names the plain file's 4000 points")


func _check_a_level_with_no_scene_cannot_be_started() -> void:
	var screens := root.get_node("ScreenManager")
	var missing := 0
	for level in range(1, 22):
		if not screens.is_level_available(level):
			missing = level
			break
	_expect(missing != 0, "some level has no imported scene yet, or this check has nothing to prove")
	if missing == 0:
		return

	var screen := await _open(missing)
	var start := screen.get_node("SafeFrame/Continue") as TextureButton
	# A port divergence: the original ships every level, so it never has to refuse one.
	_expect(start.disabled, "level %d has no scene, so it cannot be started" % missing)
	_expect(
		_text(screen, "SafeFrame/Title") != "",
		"level %d still shows its description" % missing
	)
	screen.queue_free()
	await process_frame

	var playable := await _open(1)
	_expect(
		not (playable.get_node("SafeFrame/Continue") as TextureButton).disabled,
		"level 1 is imported, so it can be started"
	)
	playable.queue_free()
	await process_frame
