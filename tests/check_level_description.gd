extends SceneTree

# The original's screen 16: the level's own text with its objective spliced in, and four
# label/value pairs read out of the saved record. Text is pinned to Polish, which is the
# language both the generated strings and the reference screenshot are in.
# See docs/shell-reference.md.

const DescriptionScene := preload("res://scenes/screens/level_description.tscn")
const DescriptionScript := preload("res://scenes/screens/level_description.gd")
const GdiTextWrap := preload("res://scenes/shared/gdi_text_wrap.gd")
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
	await _check_each_build_keeps_its_own_line_breaks()
	await _check_the_body_breaks_where_the_screenshot_does()
	_check_later_lines_get_the_whole_clip_width()
	_check_each_text_starts_where_sub_421ba0_draws_it()
	await _check_a_recorded_run_replaces_the_two_sentinels()
	await _check_the_points_game_states_its_own_condition()
	await _check_every_level_can_be_started()
	await _check_a_long_title_stays_centred_above_the_panels()

	screens.selected_level = _restore_level
	screens.selected_game_mode = &"time"
	store.path = _restore_path
	store.reload()
	DirAccess.remove_absolute(TEST_PATH)
	i18n.set_language(_restore_language)
	if _failures == 0:
		print("Level description: the title, the four info pairs, the spliced objective and every level starting passed")
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


# The words of a text with every run of blanks and line breaks as one space, so a check can
# find a sentence whatever line breaks the body gave it.
func _flat(text: String) -> String:
	return " ".join(text.replace("\n", " ").split(" ", false))


# The body as sub_42B9A0 breaks it: 460 px of room on the first line, 464 on every later one.
func _broken(screen: Control, text: String) -> String:
	var body := screen.get_node("SafeFrame/DescText") as Label
	return GdiTextWrap.break_lines(
		text, body.get_theme_font(&"font"), body.get_theme_font_size(&"font_size"), 460.0, 464.0, true
	)


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
	_expect(_flat(body).begins_with(_flat(description)), "the panel opens with the level's own description")
	_expect(_flat(body).ends_with(_flat(hint)), "the panel closes with the level's own hint")
	_expect(_flat(body).contains(_flat(goal)), "the objective is spliced into the %s, got %s" % ["%s", body])
	# Level 1 is 4000 points in 6 minutes, which is the sentence the pause panel also shows.
	_expect(goal.contains("4000"), "level 1's objective names its 4000 points")
	_expect(goal.contains("6"), "level 1's objective names its 6 minutes")
	screen.queue_free()
	await process_frame


# sub_42B9A0 draws every CRLF of Level_XX.txt as a line break: one blank line before the
# objective and two after it in the Polish files, three after it in the German ones. The
# screenshot shows the Polish shape: three line pitches from the objective to the hint.
func _check_each_build_keeps_its_own_line_breaks() -> void:
	var i18n := root.get_node("I18n")
	var shapes := {&"pl": ["\n\n", "\n\n\n"], &"de": ["\n\n", "\n\n\n\n"], &"en": ["\n\n", "\n\n\n"]}
	for language: StringName in shapes:
		i18n.set_language(language)
		var screen := await _open(1)
		var breaks: Array = shapes[language]
		var expected := _broken(screen, "%s%s%s%s%s" % [
			TranslationServer.translate(&"level.1.description"), breaks[0],
			GoalText.sentence(&"time", 360.0, 4000), breaks[1], TranslationServer.translate(&"level.1.hint"),
		])
		_expect(
			_text(screen, "SafeFrame/DescText") == expected,
			"%s level 1 reads in its build's own shape, got %s" % [language, _text(screen, "SafeFrame/DescText").c_escape()]
		)
		screen.queue_free()
		await process_frame
	# Level 20's German description is two lines in its file, and stays two lines.
	i18n.set_language(&"de")
	var two_lines := await _open(20)
	_expect(
		_text(two_lines, "SafeFrame/DescText").begins_with("Schnell, flexibel, dynamisch...\nmanche"),
		"de level 20 keeps the line break inside its description"
	)
	two_lines.queue_free()
	await process_frame
	i18n.set_language(&"pl")


# ds5bnh36ens.png, level 1 in Polish, line for line. A Label wrapping at one width breaks the
# hint after "Cię" instead, because it counts the blank after "zauważą," and gives the third
# line of text no more room than the first.
func _check_the_body_breaks_where_the_screenshot_does() -> void:
	var screen := await _open(1)
	var lines := _text(screen, "SafeFrame/DescText").split("\n")
	var expected := [
		"Niewielkie biuro, w którym pracują nadal dwie",
		"osoby. Wyczucie czasu jest niezbędne.",
		"",
		"Aby ukończyć ten poziom, musisz zdobyć 4000",
		"punktów w ciągu 6 minut.",
		"",
		"",
		"Czy wiesz, że Twoi koledzy zawsze Cię zauważą,",
		"jeśli siejesz zniszczenie blisko nich? Nawet jeśli",
		"są odwróceni plecami.",
	]
	_expect(lines.size() == expected.size(), "level 1's body is %d lines, got %d" % [expected.size(), lines.size()])
	for index in mini(lines.size(), expected.size()):
		# A word that does not fit keeps the blank before it on the line above, drawn and unseen.
		_expect(
			lines[index].strip_edges(false, true) == expected[index],
			"line %d reads %s, got %s" % [index, expected[index], lines[index]]
		)
	var font := (screen.get_node("SafeFrame/DescText") as Label).get_theme_font(&"font")
	_expect(
		font.get_string_size(lines[7], HORIZONTAL_ALIGNMENT_LEFT, -1, 21).x > 460.0,
		"the hint's first line is wider than the first line's room, so only a later line holds it"
	)
	screen.queue_free()
	await process_frame


# 0x42BAB6 gives the first line the clip width less the start, 0x42BB08 and 0x42BBAD give every
# later line the whole clip width. A word wraps only once the line reaches the room, and the
# blank after it is a run of its own that wraps the line and is dropped.
func _check_later_lines_get_the_whole_clip_width() -> void:
	var theme := ThemeDB.get_project_theme()
	var font := theme.default_font
	var size := theme.get_font_size(&"font_size", &"LevelDescText")
	var line := "Czy wiesz, że Twoi koledzy zawsze Cię zauważą,"
	var width := font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	_expect(width > 460.0 and width < 464.0, "the probe line fits 464 but not 460, got %s" % width)
	var text := line + " jeśli"
	_expect(
		GdiTextWrap.break_lines(text, font, size, 460.0, 464.0) == "Czy wiesz, że Twoi koledzy zawsze Cię \nzauważą, jeśli",
		"on the first line it wraps before its last word, which leaves the blank before it behind"
	)
	_expect(
		GdiTextWrap.break_lines("x\n" + text, font, size, 460.0, 464.0) == "x\n" + line + "\njeśli",
		"on a later line it fits, and the blank that reaches the room goes with the wrap"
	)
	_expect(
		GdiTextWrap.break_lines("x x", font, size, 1.0, 464.0) == "\nx x",
		"a run as wide as the room already wraps"
	)
	# The CR of a CRLF is a 1-pixel glyph that belongs to the word before it.
	var crlf_room := font.get_string_size("ab", HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + 1.0
	_expect(
		GdiTextWrap.break_lines("ab\nc", font, size, crlf_room, crlf_room, true) == "\nab\nc",
		"a word before a CRLF is one pixel wider"
	)
	_expect(
		GdiTextWrap.break_lines("ab\nc", font, size, crlf_room, crlf_room) == "ab\nc",
		"a bare line feed adds nothing"
	)


# sub_421AC0's rects at 0x470A40: the body (24, 128, 464, 360), then each label (536, y, 240,
# 32) with its value 40 px below. sub_421BA0 starts align 0 at +4 +4 and ends align 1 7 px
# short of the right edge, 4 px down.
func _check_each_text_starts_where_sub_421ba0_draws_it() -> void:
	_expect(
		DescriptionScript.BODY_WIDTH == 464.0 and DescriptionScript.BODY_START == 4.0,
		"the body has the 464-pixel clip and starts 4 px in"
	)
	var state := DescriptionScene.get_state()
	var offsets := {}
	for index in state.get_node_count():
		var values := {}
		for property in state.get_node_property_count(index):
			values[state.get_node_property_name(index, property)] = state.get_node_property_value(index, property)
		offsets[String(state.get_node_path(index)).trim_prefix("./")] = values
	var body: Dictionary = offsets.get("SafeFrame/DescText", {})
	_expect(
		body.get(&"offset_left") == 28.0 and body.get(&"offset_top") == 132.0,
		"the body starts at (28, 132), got (%s, %s)" % [body.get(&"offset_left"), body.get(&"offset_top")]
	)
	_expect(
		body.get(&"offset_right") == 492.0,
		"the body's label is as wide as the room of its later lines, got right %s" % body.get(&"offset_right")
	)
	var tops := {"BestTime": 128.0, "BestScore": 224.0, "Size": 320.0, "Difficulty": 416.0}
	for pair: String in tops:
		var y: float = tops[pair]
		var label: Dictionary = offsets.get("SafeFrame/Info/%sLabel" % pair, {})
		var value: Dictionary = offsets.get("SafeFrame/Info/%sValue" % pair, {})
		_expect(
			label.get(&"offset_left") == 540.0 and label.get(&"offset_top") == y + 4.0,
			"%sLabel starts at (540, %d), got (%s, %s)" % [pair, y + 4.0, label.get(&"offset_left"), label.get(&"offset_top")]
		)
		_expect(
			value.get(&"offset_right") == 769.0 and value.get(&"offset_top") == y + 44.0,
			"%sValue ends at x 769, from y %d, got (%s, %s)" % [pair, y + 44.0, value.get(&"offset_right"), value.get(&"offset_top")]
		)
		_expect(value.get(&"horizontal_alignment") == HORIZONTAL_ALIGNMENT_RIGHT, "%sValue is right-aligned" % pair)


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


func _check_every_level_can_be_started() -> void:
	var screens := root.get_node("ScreenManager")
	var missing := []
	for level in range(1, 22):
		if not screens.is_level_available(level):
			missing.append(level)
	_expect(missing.is_empty(), "every level of the campaign is imported, missing %s" % [missing])
	# The screen still refuses a level with no scene, a guard for a checkout without the
	# generated levels; with all 21 imported, every description offers Kontynuuj.
	for level in range(1, 22):
		var screen := await _open(level)
		_expect(
			not (screen.get_node("SafeFrame/Continue") as TextureButton).disabled,
			"level %d can be started from its description" % level
		)
		screen.queue_free()
		await process_frame


# A title wider than the 800 px rect wraps onto a second line. The rect grows both ways, so the
# block stays centred in the rect sub_423F70 centres every title in, (0, 16, 800, 64), and
# clear of the two panels below it.
func _check_a_long_title_stays_centred_above_the_panels() -> void:
	var i18n := root.get_node("I18n")
	var wrapped := 0
	for language: StringName in [&"pl", &"de", &"en"]:
		i18n.set_language(language)
		for level in range(1, 22):
			var screen := await _open(level)
			await process_frame
			var title := screen.get_node("SafeFrame/Title") as Label
			var panel_top := (screen.get_node("SafeFrame/DescPanel") as Control).position.y
			var rect := title.get_rect()
			if title.get_line_count() > 1:
				wrapped += 1
			_expect(
				is_equal_approx(rect.get_center().y, 48.0),
				"%s level %d's title is centred on y 48, got %s" % [language, level, rect]
			)
			_expect(rect.end.y <= panel_top, "%s level %d's title ends above the panels at %d, got %s" % [language, level, panel_top, rect])
			_expect(title.get_line_count() <= 2, "%s level %d's title takes at most two lines" % [language, level])
			screen.queue_free()
			await process_frame
	_expect(wrapped > 0, "at least one title is long enough to wrap, so the check above means something")
	i18n.set_language(&"pl")
