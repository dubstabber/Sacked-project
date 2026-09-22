extends SceneTree

# The original's screen 14: seven records a page over three reachable pages, and a toggle
# that moves the name column together with the value column. Text is pinned to Polish.
# See docs/shell-reference.md.

const HighscoresScene := preload("res://scenes/screens/highscores.tscn")
const HIGHSCORES_SCRIPT := preload("res://scenes/screens/highscores.gd")
const TEST_PATH := "user://check_highscores.cfg"

var _failures := 0
var _restore_path := ""
var _restore_language: StringName = &"pl"


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

	await _check_a_fresh_board_is_all_sentinels()
	await _check_each_page_lists_its_own_seven_levels()
	await _check_the_toggle_moves_the_name_with_the_value()

	store.path = _restore_path
	store.reload()
	DirAccess.remove_absolute(TEST_PATH)
	i18n.set_language(_restore_language)
	if _failures == 0:
		print("Highscores: three pages of seven, the two boards and their paired name column passed")
	quit(1 if _failures else 0)


func _expect(condition: bool, label: String) -> void:
	if not condition:
		_failures += 1
		push_error(label)


func _open() -> Control:
	var screen := HighscoresScene.instantiate() as Control
	root.add_child(screen)
	await process_frame
	return screen


func _cell(screen: Control, row: int, column: String) -> String:
	var label := screen.get_node_or_null("SafeFrame/Rows/Row%d/%s" % [row, column]) as Label
	return "" if label == null else label.text


func _check_a_fresh_board_is_all_sentinels() -> void:
	var screen := await _open()
	_expect(
		screen.get_node("SafeFrame/Rows").get_child_count() == HIGHSCORES_SCRIPT.ROWS_PER_PAGE,
		"the board builds seven rows"
	)
	# sub_420A20 never constructs the fourth page's button.
	_expect(
		screen.get_node_or_null("SafeFrame/Page3") == null,
		"the fourth page has no button, as in the original"
	)
	for row in HIGHSCORES_SCRIPT.ROWS_PER_PAGE:
		_expect(_cell(screen, row, "name") == "---", "row %d has no score holder yet" % row)
		_expect(_cell(screen, row, "value") == "---", "row %d has no score yet" % row)
	_expect(_cell(screen, 0, "number") == "(#1)", "the first row is level 1")
	_expect(_cell(screen, 0, "title") == "Pierwszy ostatni dzień", "the first row names level 1")
	screen.queue_free()
	await process_frame


func _check_each_page_lists_its_own_seven_levels() -> void:
	var screen := await _open()
	var expected := {0: [1, 7], 1: [8, 14], 2: [15, 21]}
	for page: int in expected:
		screen._on_page_pressed(page)
		var bounds: Array = expected[page]
		_expect(
			_cell(screen, 0, "number") == "(#%d)" % bounds[0],
			"page %d opens at level %d, got %s" % [page, bounds[0], _cell(screen, 0, "number")]
		)
		_expect(
			_cell(screen, 6, "number") == "(#%d)" % bounds[1],
			"page %d ends at level %d, got %s" % [page, bounds[1], _cell(screen, 6, "number")]
		)
	screen.queue_free()
	await process_frame


func _check_the_toggle_moves_the_name_with_the_value() -> void:
	# Two different people hold level 1's two records, which is exactly what the original's
	# separate name fields allow.
	var store := root.get_node("ProgressStore")
	store.record_result(1, &"points", true, 5200, 300.0, "Jo")
	store.record_result(1, &"time", true, 0, 174.0, "Anne")

	var screen := await _open()
	# The board opens on the score, so its button offers the time.
	_expect(
		(screen.get_node("SafeFrame/Column/Label") as Label).text == "highscore.time",
		"the score board's button offers the time board"
	)
	_expect(_cell(screen, 0, "value") == "5200", "the score board shows the score")
	_expect(_cell(screen, 0, "name") == "Jo", "the score board names whoever set the score")

	screen._on_column_pressed()
	_expect(
		(screen.get_node("SafeFrame/Column/Label") as Label).text == "highscore.score",
		"the time board's button offers the score board"
	)
	_expect(_cell(screen, 0, "value") == "02:54", "the time board shows 174 seconds as 02:54")
	_expect(
		_cell(screen, 0, "name") == "Anne",
		"the time board names whoever set the time, not the score"
	)

	# A level with neither record still shows both sentinels on both boards.
	_expect(_cell(screen, 1, "value") == "--:--", "an unplayed level shows --:-- on the time board")
	screen._on_column_pressed()
	_expect(_cell(screen, 1, "value") == "---", "an unplayed level shows --- on the score board")
	screen.queue_free()
	await process_frame
