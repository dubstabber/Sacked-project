extends SceneTree

# The face every Label, LineEdit and panel draws in, the size each recovered Arial becomes, the
# line pitch and the shadow each of the original's text draws puts under its glyphs. The
# original makes all of its fonts from Arial through sub_42B680, which rasterises code page
# 1250 with CreateFontA into an atlas. The port bundles Liberation Sans, which has Arial's
# metrics under a licence that lets it ship, and sets it as the project theme's default font.
# The rising score is a sprite strip and is not affected; tests/check_score_popup.gd owns it.
# Everything below is argued in "Fonts" in docs/hud-reference.md.
#
# How the face is rasterised. Every value is in the importer defaults in project.godot,
# because the .import sidecar is not committed:
#   - Grayscale antialiasing: ANTIALIASED_QUALITY is grey-level smoothing, not ClearType.
#   - Normal hinting, the face's own instructions, as GDI runs Arial's. Light and none were
#     measured too: no reference text changes width by a pixel between the three.
#   - Subpixel positioning disabled, so every glyph starts on a whole pixel as sub_42B9A0's do.
#   - Rounding remainders kept. GDI advances by Arial's own hinted widths, which Liberation
#     cannot reproduce; rounding each advance on its own draws the Arial 24 group 4.4 % wider
#     than the reference screenshots, carrying the remainder draws it 1.3 % wider.
#   - Kerning off: those per-character widths are all the original has.
#   - No system fallback: sub_42B680's atlas holds 0x20-0xFF of code page 1250 and nothing else,
#     so a character the face lacks must not be drawn in some other face of the machine's.
#   - No mipmaps and no MSDF: the text is drawn at its own size, as GDI's is.
#
# CreateFontA gets a positive height, which GDI matches against the cell (winAscent +
# winDescent), not the em. The em it builds is MulDiv(N, unitsPerEm, cell), rounded: that is
# the largest size whose rounded ascent and descent still fit the cell, it is what the
# reference screenshots measure (screen 16's and screen 12's Arial 42 titles are within 0.5 %
# of size 38 and 1.4 % to 2.7 % off 37), and it gives the line pitches they show (below).

const THEME_PATH := "res://resources/ui_theme.tres"
const FONT_PATH := "res://images/gui/fonts/liberation-sans-regular.ttf"
const LICENSE_PATH := "res://images/gui/fonts/LICENSE-liberation-sans.txt"
const STRINGS_PATH := "res://resources/original/strings.json"
const TRANSLATIONS_PATH := "res://resources/i18n/translations.json"
const NAMES_PATH := "res://resources/original/names.json"
const ScreenManagerScript := preload("res://autoloads/screen_manager.gd")
const LevelPromptsScript := preload("res://scenes/hud/level_prompts.gd")
const HighscoresScript := preload("res://scenes/screens/highscores.gd")
const CharacterSelectScript := preload("res://scenes/screens/character_select.gd")
const GdiTextWrap := preload("res://scenes/shared/gdi_text_wrap.gd")

# Arial's and Liberation Sans's shared vertical metrics, in font units.
const UNITS_PER_EM := 2048
const WIN_ASCENT := 1854
const WIN_DESCENT := 434

const POLISH := "ąćęłńóśźżĄĆĘŁŃÓŚŹŻ"
const GERMAN := "äöüÄÖÜß"

const TITLE := 42  # CMenuBase +1172, the title of every menu screen (sub_423C50)
const MENU_INPUT := 32  # CMenuBase +1168, the text in the CGUIInput boxes
const MENU_BUTTON := 22  # CMenuBase +1164, the button captions and the highscore rows
const LEVEL_TEXT := 24  # CLevelDesc's own font (sub_421570) and game+2008 (sub_405430)
const CONSOLE := 22  # the score, clock and hover text (sub_405930)
const CAPTION := 30  # the warning caption under THERMO_UP and AGGRO_UP (sub_405930)

# The line pitches the reference screenshots show, which sub_42B9A0 steps by the cell height:
# screen 16's Arial 24 body, nine pitches over 207 px, and screen 12's two-line Arial 22 name
# prompt, whose ascenders stand 22.2 px apart. The wrapped titles' Arial 42 is not in a shot;
# its cell is 42 by the same arithmetic.
const MEASURED_PITCH := {LEVEL_TEXT: 23, MENU_BUTTON: 22, TITLE: 42}

# The theme type variation standing for each of the original's text draws: the tint the copy
# it draws first is given and how far down and right it sits. The blitter (0x44D780) multiplies
# the white glyph by the tint and drops the low byte, so each copy lands one level below its
# tint. See docs/hud-reference.md.
const SHADOWS := {
	&"MenuTitle": [48, 3],  # sub_423F70, every CMenuBase title
	&"MenuButtonCaption": [48, 2],  # sub_422C80, every TGUIExtButton caption
	&"MenuPrompt": [48, 3],  # sub_424D50, the character-select name prompt
	&"MenuTableText": [32, 2],  # sub_421380, the highscore cells
	&"LevelDescText": [32, 2],  # sub_421BA0, screen 16's body and its four pairs
	&"ConsoleText": [30, 2],  # sub_45A730, CGUIText: score, clock, hover text
	&"ConsoleCaption": [30, 2],  # sub_45A730, the two warning captions
}

# scene -> {node path: the Arial cell height the original draws it in}
const RECOVERED_SIZES := {
	"res://scenes/screens/character_select.tscn": {
		"SafeFrame/Title": TITLE,
		"SafeFrame/NameLabel": MENU_BUTTON,
		"SafeFrame/NameEdit": MENU_INPUT,
		"SafeFrame/NameShadow": MENU_INPUT,
	},
	"res://scenes/screens/coworker_names.tscn": {
		"SafeFrame/Title": TITLE,
		"SafeFrame/NameBox0": MENU_INPUT,
		"SafeFrame/NameBox1": MENU_INPUT,
		"SafeFrame/NameBox2": MENU_INPUT,
		"SafeFrame/NameShadow0": MENU_INPUT,
		"SafeFrame/NameShadow1": MENU_INPUT,
		"SafeFrame/NameShadow2": MENU_INPUT,
	},
	"res://scenes/screens/highscores.tscn": {"SafeFrame/Title": TITLE},
	"res://scenes/screens/level_tree.tscn": {"SafeFrame/Title": TITLE},
	"res://scenes/screens/sound_setup.tscn": {
		"SafeFrame/Title": TITLE,
		"SafeFrame/EffectsBox/Value": MENU_INPUT,
		"SafeFrame/MusicBox/Value": MENU_INPUT,
	},
	"res://scenes/screens/level_description.tscn": {
		"SafeFrame/Title": TITLE,
		"SafeFrame/DescText": LEVEL_TEXT,
		"SafeFrame/Info/BestTimeLabel": LEVEL_TEXT,
		"SafeFrame/Info/BestTimeValue": LEVEL_TEXT,
		"SafeFrame/Info/BestScoreLabel": LEVEL_TEXT,
		"SafeFrame/Info/BestScoreValue": LEVEL_TEXT,
		"SafeFrame/Info/SizeLabel": LEVEL_TEXT,
		"SafeFrame/Info/SizeValue": LEVEL_TEXT,
		"SafeFrame/Info/DifficultyLabel": LEVEL_TEXT,
		"SafeFrame/Info/DifficultyValue": LEVEL_TEXT,
	},
	"res://scenes/hud/console.tscn": {
		"Band/Score": CONSOLE,
		"Band/Clock": CONSOLE,
		"Band/HoverText": CONSOLE,
		"Banners/ThermoUp/ThermoUpText": CAPTION,
		"Banners/AggroUp/AggroUpText": CAPTION,
	},
	"res://scenes/npc/npc.tscn": {"NameLabel": LEVEL_TEXT},
}

# scene -> {node path: the variation it must carry}. Every caption on a TextureButton in a
# screen is a TGUIExtButton's, and is found rather than listed.
const RECOVERED_DRAWS := {
	"res://scenes/screens/character_select.tscn": {"SafeFrame/Title": &"MenuTitle", "SafeFrame/NameLabel": &"MenuPrompt"},
	"res://scenes/screens/coworker_names.tscn": {"SafeFrame/Title": &"MenuTitle"},
	"res://scenes/screens/highscores.tscn": {"SafeFrame/Title": &"MenuTitle"},
	"res://scenes/screens/level_tree.tscn": {"SafeFrame/Title": &"MenuTitle"},
	"res://scenes/screens/sound_setup.tscn": {"SafeFrame/Title": &"MenuTitle"},
	"res://scenes/screens/level_description.tscn": {
		"SafeFrame/Title": &"MenuTitle",
		"SafeFrame/DescText": &"LevelDescText",
		"SafeFrame/Info/BestTimeLabel": &"LevelDescText",
		"SafeFrame/Info/BestTimeValue": &"LevelDescText",
		"SafeFrame/Info/BestScoreLabel": &"LevelDescText",
		"SafeFrame/Info/BestScoreValue": &"LevelDescText",
		"SafeFrame/Info/SizeLabel": &"LevelDescText",
		"SafeFrame/Info/SizeValue": &"LevelDescText",
		"SafeFrame/Info/DifficultyLabel": &"LevelDescText",
		"SafeFrame/Info/DifficultyValue": &"LevelDescText",
	},
	"res://scenes/hud/console.tscn": {
		"Band/Score": &"ConsoleText",
		"Band/Clock": &"ConsoleText",
		"Band/HoverText": &"ConsoleText",
		"Banners/ThermoUp/ThermoUpText": &"ConsoleCaption",
		"Banners/AggroUp/AggroUpText": &"ConsoleCaption",
	},
}
const SCREENS_DIR := "res://scenes/screens"

# Where the original starts the texts no other check places, from the rects in its data:
# scene -> {node path: {offset property: value}}.
const RECOVERED_PLACES := {
	"res://scenes/screens/character_select.tscn": {
		# sub_4245E0 hands sub_424520 the title rect (64, 16, 672, 64) at 0x470F48.
		"SafeFrame/Title": {&"offset_left": 64.0, &"offset_top": 16.0, &"offset_right": 736.0, &"offset_bottom": 80.0},
		# sub_424D50 starts slot 219 at (140, 463), 2 px into its clip at 0x470F98, and the
		# label is as wide as the clip's 208, the room of its second line.
		"SafeFrame/NameLabel": {&"offset_left": 140.0, &"offset_top": 463.0, &"offset_right": 348.0},
		# sub_422C80 with the portraits' alignment (0, 1): the caption's 22-pixel cell ends 7 px
		# above the button's bottom edge.
		"SafeFrame/JoblessButton/Label": {&"anchor_top": 1.0, &"anchor_bottom": 1.0, &"offset_top": -29.0, &"offset_bottom": -7.0},
		"SafeFrame/AnneButton/Label": {&"anchor_top": 1.0, &"anchor_bottom": 1.0, &"offset_top": -29.0, &"offset_bottom": -7.0},
		# Every CGUIInput (sub_45CE00) starts centred text at (w - text width) / 2 - 2 (0x45CEF0) and
		# its copy 2 px right and down (0x45CF57-0x45CF67). A LineEdit or Label centres exactly,
		# so the text's node sits 2 px left of the box, (336, 464, 352, 48) at 0x470F58, and the
		# copy's over it, 2 px down. See scenes/shared/gui_input.gd.
		"SafeFrame/NameEdit": {&"offset_left": 334.0, &"offset_top": 464.0, &"offset_right": 686.0, &"offset_bottom": 512.0},
		"SafeFrame/NameShadow": {&"offset_left": 336.0, &"offset_top": 466.0, &"offset_right": 688.0, &"offset_bottom": 514.0},
	},
	"res://scenes/screens/coworker_names.tscn": {
		# The boxes at 0x470538, each (232, y, 352, 44).
		"SafeFrame/NameBox0": {&"offset_left": 230.0, &"offset_right": 582.0},
		"SafeFrame/NameBox1": {&"offset_left": 230.0, &"offset_right": 582.0},
		"SafeFrame/NameBox2": {&"offset_left": 230.0, &"offset_right": 582.0},
		"SafeFrame/NameShadow0": {&"offset_left": 232.0, &"offset_top": 338.0, &"offset_right": 584.0},
		"SafeFrame/NameShadow1": {&"offset_left": 232.0, &"offset_top": 398.0, &"offset_right": 584.0},
		"SafeFrame/NameShadow2": {&"offset_left": 232.0, &"offset_top": 458.0, &"offset_right": 584.0},
	},
	"res://scenes/screens/sound_setup.tscn": {
		# The two volume boxes: the value fills its box, 2 px to the left, and draws its copy as
		# the Label's shadow, 2 px right and down.
		"SafeFrame/EffectsBox/Value": {&"offset_left": -2.0, &"offset_right": -2.0},
		"SafeFrame/MusicBox/Value": {&"offset_left": -2.0, &"offset_right": -2.0},
	},
}

# Anything that would give a node a face of its own instead of the theme's.
const FOREIGN_FACE := [
	"fallback_font", "get_fallback_font", "theme_override_fonts/", "add_theme_font_override",
	"SystemFont", "FontVariation", "FontFile.new", "label_settings",
]
const SCANNED_DIRS := ["res://scenes", "res://autoloads"]
const SCANNED_EXTENSIONS := ["gd", "tscn", "tres"]

var _failures := 0
var _font: Font
var _theme: Theme


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_check_the_project_theme()
	if _font != null:
		_check_how_the_face_is_rasterised()
		_check_the_metrics_are_arials()
		_check_every_glyph_the_game_draws()
		_check_the_recovered_sizes()
		_check_the_line_pitch()
		_check_the_shadows()
		_check_where_each_text_starts()
		await _check_every_control_resolves_to_it()
		_check_nothing_draws_in_another_face()
	if _failures == 0:
		print("UI font: the bundled face, its rasterisation, Arial's metrics, every glyph, the sizes, the line pitch and the shadows passed")
	quit(1 if _failures else 0)


func _expect(condition: bool, label: String) -> void:
	if not condition:
		_failures += 1
		push_error(label)


# MulDiv(N, 2048, 2288): the em GDI builds for a cell of N pixels, rounded half up.
static func em_size(arial_cell: int) -> int:
	var cell := WIN_ASCENT + WIN_DESCENT
	@warning_ignore("integer_division")
	return (arial_cell * UNITS_PER_EM + cell / 2) / cell


# GDI's tmHeight at that em: the rounded ascent plus the rounded descent.
static func gdi_cell_height(em: int) -> int:
	return roundi(WIN_ASCENT * em / float(UNITS_PER_EM)) + roundi(WIN_DESCENT * em / float(UNITS_PER_EM))


func _check_the_project_theme() -> void:
	_expect(
		String(ProjectSettings.get_setting("gui/theme/custom", "")) == THEME_PATH,
		"project.godot sets %s as the project theme" % THEME_PATH
	)
	_theme = ThemeDB.get_project_theme()
	_expect(_theme != null and _theme.resource_path == THEME_PATH, "the project theme is loaded from %s" % THEME_PATH)
	if _theme == null:
		return
	_font = _theme.default_font
	_expect(_font is FontFile, "the theme's default font is a FontFile, got %s" % _font)
	_expect(_font != null and _font.resource_path == FONT_PATH, "the default font is the bundled %s" % FONT_PATH)
	_expect(
		_theme.default_font_size == em_size(MENU_BUTTON),
		"an unsized label draws in the menu's Arial 22, size %d, got %d" % [em_size(MENU_BUTTON), _theme.default_font_size]
	)
	var licence := FileAccess.get_file_as_string(LICENSE_PATH)
	_expect(licence.contains("SIL OPEN FONT LICENSE Version 1.1"), "the OFL 1.1 ships beside the face")
	_expect(licence.contains("Reserved Font Name Liberation"), "the licence reserves the Liberation name")


func _check_how_the_face_is_rasterised() -> void:
	var file := _font as FontFile
	if file == null:
		return
	var kern := TextServerManager.get_primary_interface().name_to_tag("kern")
	_expect(file.antialiasing == TextServer.FONT_ANTIALIASING_GRAY, "grey-level antialiasing, as ANTIALIASED_QUALITY asks")
	_expect(file.hinting == TextServer.HINTING_NORMAL, "the face's own hinting at full strength")
	_expect(
		file.subpixel_positioning == TextServer.SUBPIXEL_POSITIONING_DISABLED,
		"every glyph starts on a whole pixel"
	)
	_expect(file.keep_rounding_remainders, "the advances carry their rounding remainders")
	_expect(not file.allow_system_fallback, "a character the face lacks is not drawn in a system face")
	_expect(int(file.opentype_feature_overrides.get(kern, 1)) == 0, "no pair is kerned")
	_expect(not file.multichannel_signed_distance_field and not file.generate_mipmaps, "no MSDF and no mipmaps")
	var defaults: Dictionary = ProjectSettings.get_setting("importer_defaults/font_data_dynamic", {})
	var features: Dictionary = defaults.get("opentype_features", {})
	_expect(
		int(defaults.get("antialiasing", -1)) == 1
			and int(defaults.get("hinting", -1)) == 2
			and int(defaults.get("subpixel_positioning", -1)) == 0
			and defaults.get("keep_rounding_remainders", false) == true
			and defaults.get("allow_system_fallback", true) == false,
		"project.godot's importer defaults carry the same settings to a fresh clone"
	)
	_expect(features.has(kern) and int(features[kern]) == 0, "project.godot's importer defaults switch kerning off")


# Liberation Sans is only a stand-in for Arial if the cell it builds from a size is Arial's.
func _check_the_metrics_are_arials() -> void:
	var file := _font as FontFile
	var ascent := _font.get_ascent(UNITS_PER_EM)
	var descent := _font.get_descent(UNITS_PER_EM)
	_expect(
		is_equal_approx(ascent, WIN_ASCENT) and is_equal_approx(descent, WIN_DESCENT),
		"the face has Arial's 1854 / 434 over 2048, got %f / %f" % [ascent, descent]
	)
	_expect(file == null or file.get_font_name() == "Liberation Sans", "the face is Liberation Sans")
	var sizes := {18: 16, 20: 18, 22: 20, 24: 21, 28: 25, 30: 27, 32: 29, 42: 38}
	for cell: int in sizes:
		_expect(em_size(cell) == sizes[cell], "Arial %d is drawn at %d, got %d" % [cell, sizes[cell], em_size(cell)])


func _check_every_glyph_the_game_draws() -> void:
	var texts: Array[String] = [POLISH, GERMAN]
	var strings: Dictionary = _read_json(STRINGS_PATH).get("strings", {})
	for key: String in strings:
		for language in ["pl", "en", "de"]:
			texts.append(String((strings[key] as Dictionary).get(language, "")))
	var authored := _read_json(TRANSLATIONS_PATH)
	for key: String in authored:
		if authored[key] is Dictionary:
			for language in ["pl", "en", "de"]:
				texts.append(String((authored[key] as Dictionary).get(language, "")))
	var names := _read_json(NAMES_PATH)
	texts.append(String(names.get("placeholder", "")))
	for record: Dictionary in names.get("records", []):
		texts.append(String(record.get("name", "")))
	for character_id: StringName in ScreenManagerScript.DEFAULT_PLAYER_NAMES:
		texts.append(String(ScreenManagerScript.DEFAULT_PLAYER_NAMES[character_id]))
	_expect(texts.size() > 700, "every string of every language was read, got %d" % texts.size())
	var missing := {}
	var seen := {}
	for text in texts:
		for index in text.length():
			var code := text.unicode_at(index)
			if code < 0x20 or seen.has(code):
				continue
			seen[code] = true
			if not _font.has_char(code):
				missing[text[index]] = text
	_expect(missing.is_empty(), "the bundled face cannot draw %s" % str(missing))
	for letter in POLISH + GERMAN:
		_expect(seen.has(letter.unicode_at(0)), "%s was among the letters checked" % letter)


# Read from the packed scenes rather than their instances, so no screen's _ready runs. A
# node's size is its own override, else its variation's, else the theme's default.
func _check_the_recovered_sizes() -> void:
	for path: String in RECOVERED_SIZES:
		var properties := _scene_properties(path)
		var expected: Dictionary = RECOVERED_SIZES[path]
		for node_path: String in expected:
			var cell: int = expected[node_path]
			var found := _size_of(properties.get(node_path, {}))
			_expect(
				found == em_size(cell),
				"%s:%s is Arial %d, so size %d, got %d" % [path.get_file(), node_path, cell, em_size(cell), found]
			)
	_expect(LevelPromptsScript.FONT_SIZE == em_size(LEVEL_TEXT), "the pause and quit panels are game+2008's Arial 24")
	_expect(
		_theme.get_font_size(&"font_size", HighscoresScript.CELL_VARIATION) == em_size(MENU_BUTTON),
		"the highscore rows are the menu's Arial 22"
	)


func _size_of(properties: Dictionary) -> int:
	if properties.has(&"theme_override_font_sizes/font_size"):
		return int(properties[&"theme_override_font_sizes/font_size"])
	var variation := StringName(properties.get(&"theme_type_variation", &""))
	if variation != &"" and _theme.has_font_size(&"font_size", variation):
		return _theme.get_font_size(&"font_size", variation)
	return _theme.default_font_size


# sub_42B9A0 moves each new line down by the font's tallest cell, GDI's tmHeight. Godot's
# FreeType ascent and descent each round up where GDI's round to nearest, one pixel more
# apiece at every size a multi-line text uses, so the theme takes the two back.
func _check_the_line_pitch() -> void:
	var spacing := _theme.get_constant(&"line_spacing", &"Label")
	for cell: int in MEASURED_PITCH:
		var em := em_size(cell)
		_expect(
			gdi_cell_height(em) == MEASURED_PITCH[cell],
			"GDI's cell for Arial %d is %d, the pitch the screenshot shows, got %d" % [cell, MEASURED_PITCH[cell], gdi_cell_height(em)]
		)
		_expect(
			int(_font.get_height(em)) + spacing == MEASURED_PITCH[cell],
			"a Label steps Arial %d's lines by %d, got %d + %d" % [cell, MEASURED_PITCH[cell], _font.get_height(em), spacing]
		)
		var one := Label.new()
		var two := Label.new()
		for label in [one, two]:
			label.add_theme_font_size_override(&"font_size", em)
		one.text = "Ag"
		two.text = "Ag\nAg"
		root.add_child(one)
		root.add_child(two)
		var pitch := two.get_minimum_size().y - one.get_minimum_size().y
		_expect(
			is_equal_approx(pitch, MEASURED_PITCH[cell]),
			"a two-line Label at size %d is %d px taller than one line, got %s" % [em, MEASURED_PITCH[cell], pitch]
		)
		one.free()
		two.free()


# Every variation draws an opaque copy in the original's tint, offset down and right, with no
# outline to thicken it; and every scene node that stands for one of those draws carries it.
# Every copy in the original is a plain second pass, so no Label's shadow has an outline.
func _check_the_shadows() -> void:
	_expect(
		_theme.has_constant(&"shadow_outline_size", &"Label") and _theme.get_constant(&"shadow_outline_size", &"Label") == 0,
		"a Label's shadow is a plain copy, with no outline"
	)
	for variation: StringName in SHADOWS:
		var spec: Array = SHADOWS[variation]
		var drawn: int = (int(spec[0]) * 255) >> 8
		var tint := Color8(drawn, drawn, drawn)
		_expect(_theme.get_type_variation_base(variation) == &"Label", "%s is a Label variation" % variation)
		var label := Label.new()
		label.theme_type_variation = variation
		root.add_child(label)
		var colour := label.get_theme_color(&"font_shadow_color")
		_expect(
			colour.is_equal_approx(tint),
			"%s's copy, tinted %d, draws (%d, %d, %d), got %s" % [variation, spec[0], drawn, drawn, drawn, colour]
		)
		for axis in [&"shadow_offset_x", &"shadow_offset_y"]:
			_expect(
				label.get_theme_constant(axis) == spec[1],
				"%s's copy sits %d px off on %s, got %d" % [variation, spec[1], axis, label.get_theme_constant(axis)]
			)
		_expect(label.get_theme_constant(&"shadow_outline_size") == 0, "%s's copy has no outline" % variation)
		_expect(label.get_theme_constant(&"line_spacing") == -2, "%s steps its lines by GDI's cell" % variation)
		label.free()
	for path: String in RECOVERED_DRAWS:
		var properties := _scene_properties(path)
		var expected: Dictionary = RECOVERED_DRAWS[path]
		for node_path: String in expected:
			var found := StringName((properties.get(node_path, {}) as Dictionary).get(&"theme_type_variation", &""))
			_expect(found == expected[node_path], "%s:%s draws as %s, got %s" % [path.get_file(), node_path, expected[node_path], found])
	var captions := 0
	for file in DirAccess.get_files_at(SCREENS_DIR):
		if not file.ends_with(".tscn"):
			continue
		var state := (load(SCREENS_DIR.path_join(file)) as PackedScene).get_state()
		var properties := _scene_properties(SCREENS_DIR.path_join(file))
		var types := {}
		for index in state.get_node_count():
			types[String(state.get_node_path(index)).trim_prefix("./")] = state.get_node_type(index)
		for node_path: String in types:
			var parent := node_path.get_base_dir()
			if types[node_path] != &"Label" or types.get(parent, &"") != &"TextureButton":
				continue
			captions += 1
			var found := StringName((properties.get(node_path, {}) as Dictionary).get(&"theme_type_variation", &""))
			_expect(found == &"MenuButtonCaption", "%s:%s is a TGUIExtButton caption, got %s" % [file, node_path, found])
	_expect(captions >= 20, "every screen's button captions were checked, got %d" % captions)


func _check_where_each_text_starts() -> void:
	for path: String in RECOVERED_PLACES:
		var properties := _scene_properties(path)
		var expected: Dictionary = RECOVERED_PLACES[path]
		for node_path: String in expected:
			var found: Dictionary = properties.get(node_path, {})
			var wanted: Dictionary = expected[node_path]
			for property: StringName in wanted:
				_expect(
					found.get(property) == wanted[property],
					"%s:%s has %s %s, got %s" % [path.get_file(), node_path, property, wanted[property], found.get(property)]
				)
	_expect(
		CharacterSelectScript.NAME_PROMPT_WIDTH == 208.0 and CharacterSelectScript.NAME_PROMPT_START == 2.0,
		"the name prompt breaks against the 208-pixel clip it starts 2 px into"
	)
	# The copy starts 5 px in (sub_424D50 passes 5, 12 for it and 2, 9 for the text), so its first
	# line has only 203 px; the port draws it from the text's own lines, which holds only while
	# no language breaks differently for it.
	var size := _theme.get_font_size(&"font_size", &"MenuPrompt")
	for language in ["pl", "de", "en"]:
		var prompt := _translation(&"highscore.name_prompt", language)
		_expect(prompt != "", "slot 219 has %s wording" % language)
		_expect(
			GdiTextWrap.break_lines(prompt, _font, size, 206.0, 208.0) == GdiTextWrap.break_lines(prompt, _font, size, 203.0, 208.0),
			"the %s name prompt's copy breaks where its text does" % language
		)


func _translation(key: StringName, language: String) -> String:
	var generated: Dictionary = _read_json(STRINGS_PATH).get("strings", {}).get(String(key), {})
	if generated.has(language):
		return String(generated[language])
	return String((_read_json(TRANSLATIONS_PATH).get(String(key), {}) as Dictionary).get(language, ""))


func _scene_properties(path: String) -> Dictionary:
	var state := (load(path) as PackedScene).get_state()
	var result := {}
	for index in state.get_node_count():
		var node_path := String(state.get_node_path(index)).trim_prefix("./")
		var properties := {}
		for property in state.get_node_property_count(index):
			properties[state.get_node_property_name(index, property)] = state.get_node_property_value(index, property)
		result[node_path] = properties
	return result


func _check_every_control_resolves_to_it() -> void:
	var scene := Node.new()
	root.add_child(scene)
	var controls: Array[Control] = [Label.new(), LineEdit.new(), Button.new()]
	for control in controls:
		scene.add_child(control)
	# The HUD lives on a CanvasLayer, and a colleague's name hangs off a Node2D.
	var layer := CanvasLayer.new()
	scene.add_child(layer)
	var hud_label := Label.new()
	layer.add_child(hud_label)
	controls.append(hud_label)
	var actor := Node2D.new()
	scene.add_child(actor)
	var name_label := Label.new()
	actor.add_child(name_label)
	controls.append(name_label)
	await process_frame
	for control in controls:
		_expect(control.get_theme_font(&"font") == _font, "a %s under %s draws in the bundled face" % [control.get_class(), control.get_parent().get_class()])
		_expect(
			control.get_theme_font_size(&"font_size") == em_size(MENU_BUTTON),
			"a %s under %s draws at the theme's size" % [control.get_class(), control.get_parent().get_class()]
		)
	var rich := RichTextLabel.new()
	scene.add_child(rich)
	_expect(rich.get_theme_font(&"normal_font") == _font, "a RichTextLabel draws in the bundled face")
	_expect(hud_label.get_theme_default_font() == _font, "a panel that draws its own text finds the face as the default")
	root.remove_child(scene)
	scene.free()


# ThemeDB.fallback_font is Godot's own face, which a project theme does not replace, and a
# font override, a FontVariation, a SystemFont or LabelSettings would each bring a face or a
# rasterisation of its own. The face and the theme live outside the scanned folders.
func _check_nothing_draws_in_another_face() -> void:
	var scanned := 0
	for directory: String in SCANNED_DIRS:
		for path in _files_under(directory):
			scanned += 1
			var source := FileAccess.get_file_as_string(path)
			for pattern: String in FOREIGN_FACE:
				_expect(not source.contains(pattern), "%s uses %s instead of the theme's face" % [path, pattern])
	_expect(scanned > 50, "the scripts and scenes were scanned, got %d" % scanned)


func _files_under(directory: String) -> PackedStringArray:
	var found := PackedStringArray()
	for file in DirAccess.get_files_at(directory):
		if SCANNED_EXTENSIONS.has(file.get_extension()):
			found.append(directory.path_join(file))
	for child in DirAccess.get_directories_at(directory):
		found.append_array(_files_under(directory.path_join(child)))
	return found


func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_expect(false, "%s is readable" % path)
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}
