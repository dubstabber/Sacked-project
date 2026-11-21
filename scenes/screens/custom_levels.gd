extends Control

# The port's own screen: the levels designers have made, opened by the main menu's Custom
# levels button. The original has no custom levels. It lists each CustomLevelInfo in
# res://custom_levels/ (CustomLevelInfo.all_in), one row each with the level's title, its
# author and its best time and score in the description screen's formats, and shows the chosen
# row's description in a strip below. A button for each game mode, captioned as the main
# menu's, starts it. A level's title, description and author are the designer's and show as
# written. See docs/shell-reference.md and docs/map-authoring.md.

# The description screen's own formats for a record (sub_421CD0's C literals).
const NO_TIME_TEXT := "--:--"
const NO_SCORE_TEXT := "---"
const SCORE_FORMAT := "%06d"
const TIME_FORMAT := "%02d:%02d"
const ROW_HEIGHT := 30.0
# Each column's left edge and width inside a row, which spans the list's 744 px; the two
# records line up under their headings, right-aligned.
const COLUMNS := {
	"Title": [0.0, 332.0, HORIZONTAL_ALIGNMENT_LEFT],
	"Author": [340.0, 180.0, HORIZONTAL_ALIGNMENT_LEFT],
	"BestTime": [520.0, 72.0, HORIZONTAL_ALIGNMENT_RIGHT],
	"BestScore": [600.0, 144.0, HORIZONTAL_ALIGNMENT_RIGHT],
}
const SELECTED_TINT := Color(1.0, 0.85, 0.35)
const HIGHLIGHT := Color(1.0, 1.0, 1.0, 0.35)

# Where the levels are listed from; the checks point it at their fixtures.
@export var directory := CustomLevelInfo.DIRECTORY

var levels: Array[CustomLevelInfo] = []
var selected := -1
var rows: Array[Control] = []

@onready var _screens: Node = get_node_or_null("/root/ScreenManager")
@onready var _progress: Node = get_node_or_null("/root/ProgressStore")


func _ready() -> void:
	($SafeFrame/Back as TextureButton).pressed.connect(_on_back_pressed)
	($SafeFrame/TimeGame as TextureButton).pressed.connect(start.bind(&"time"))
	($SafeFrame/PointsGame as TextureButton).pressed.connect(start.bind(&"points"))
	levels = CustomLevelInfo.all_in(directory)
	for index in range(levels.size()):
		var row := _row(levels[index], index)
		$SafeFrame/Rows/List.add_child(row)
		rows.append(row)
	# Coming back from a level, the one just played stays chosen.
	var previous: Resource = _screens.get("selected_custom_level") if _screens != null else null
	selected = 0 if not levels.is_empty() else -1
	for index in range(levels.size()):
		if previous != null and levels[index].resource_path == previous.resource_path:
			selected = index
	_refresh()


# One clickable row: a highlight behind four labels in the description screen's own text.
func _row(info: CustomLevelInfo, index: int) -> Control:
	var row := Control.new()
	row.custom_minimum_size = Vector2(0.0, ROW_HEIGHT)
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.gui_input.connect(_on_row_input.bind(index))
	var highlight := ColorRect.new()
	highlight.name = "Highlight"
	highlight.color = HIGHLIGHT
	highlight.mouse_filter = Control.MOUSE_FILTER_IGNORE
	highlight.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.add_child(highlight)
	for column: String in COLUMNS:
		var label := Label.new()
		label.name = column
		label.theme_type_variation = &"LevelDescText"
		label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.clip_text = true
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		label.horizontal_alignment = COLUMNS[column][2]
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.position = Vector2(COLUMNS[column][0], 0.0)
		label.size = Vector2(COLUMNS[column][1], ROW_HEIGHT)
		row.add_child(label)
	(row.get_node("Title") as Label).text = info.title
	(row.get_node("Author") as Label).text = info.author
	return row


func _on_row_input(event: InputEvent, index: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		select(index)


func select(index: int) -> void:
	if index >= 0 and index < levels.size():
		selected = index
		_refresh()


func start(game_mode: StringName) -> void:
	if selected < 0 or _screens == null:
		return
	_screens.call("start_custom_level", levels[selected], game_mode)


func _refresh() -> void:
	var empty := levels.is_empty()
	$SafeFrame/Empty.visible = empty
	for header in [$SafeFrame/BestTimeHeader, $SafeFrame/BestScoreHeader]:
		header.visible = not empty
	for button: TextureButton in [$SafeFrame/TimeGame, $SafeFrame/PointsGame]:
		button.disabled = empty
		(button.get_node("Label") as Label).modulate.a = 0.5 if empty else 1.0
	for index in range(rows.size()):
		var row := rows[index]
		var info := levels[index]
		(row.get_node("Highlight") as ColorRect).visible = index == selected
		row.modulate = SELECTED_TINT if index == selected else Color.WHITE
		(row.get_node("BestTime") as Label).text = _best_time_text(info.scene)
		(row.get_node("BestScore") as Label).text = _best_score_text(info.scene)
	($SafeFrame/Description as Label).text = "" if empty else levels[selected].description


func _best_time_text(scene: String) -> String:
	if _progress == null:
		return NO_TIME_TEXT
	var seconds := float(_progress.call("custom_best_time_seconds", scene))
	if is_equal_approx(seconds, LevelProgress.NO_TIME):
		return NO_TIME_TEXT
	return TIME_FORMAT % [int(seconds) / 60, int(seconds) % 60]


func _best_score_text(scene: String) -> String:
	if _progress == null:
		return NO_SCORE_TEXT
	var score := int(_progress.call("custom_best_score", scene))
	return NO_SCORE_TEXT if score == LevelProgress.NO_SCORE else SCORE_FORMAT % score


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_refresh()


func _on_back_pressed() -> void:
	if _screens != null:
		_screens.call("change_to_main_menu")
