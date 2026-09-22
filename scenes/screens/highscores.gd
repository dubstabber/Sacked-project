extends Control

# The original's screen 14, `CHighscore`. Seven records per page over three reachable pages,
# four columns each, and one button that flips the whole board between the score and the
# time. The toggle moves the name column with the value column, because each board names
# whoever set that board's record. See docs/shell-reference.md.

# sub_421120's four column rects, as (x, y, width) offsets from each row's own origin; every
# column is 40 px tall. The name and value columns change meaning with the board.
const COLUMNS := {
	"number": Vector3(0.0, 0.0, 64.0),
	"title": Vector3(72.0, 0.0, 400.0),
	"name": Vector3(480.0, 0.0, 184.0),
	"value": Vector3(672.0, 0.0, 96.0),
}
const ROW_HEIGHT := 40.0
const ROW_X := 16.0
const ROW_FIRST_Y := 154.0
const ROW_STEP := 46.0
const ROWS_PER_PAGE := 7
# sub_420A20 builds buttons for pages 0 to 2 only; the fourth page's caption exists but its
# button is never constructed, so the seven records behind it are unreachable.
const PAGE_COUNT := 3

const NUMBER_FORMAT := "(#%d)"
const TIME_FORMAT := "%02d:%02d"
const NO_TIME_TEXT := "--:--"
const NO_SCORE_TEXT := "---"

# +1261: 1 is the score board, 0 the time board. The ctor starts on the score board, so its
# button offers the other one.
const BOARD_SCORE := 1
const BOARD_TIME := 0

@onready var _rows: Control = $SafeFrame/Rows
@onready var _screens: Node = get_node_or_null("/root/ScreenManager")
@onready var _progress: LevelProgress = get_node_or_null("/root/ProgressStore")

var _page := 0
var _board := BOARD_SCORE


func _ready() -> void:
	_build_rows()
	($SafeFrame/Back as TextureButton).pressed.connect(_on_back_pressed)
	($SafeFrame/Column as TextureButton).pressed.connect(_on_column_pressed)
	for page in PAGE_COUNT:
		var button := $SafeFrame.get_node("Page%d" % page) as TextureButton
		button.pressed.connect(_on_page_pressed.bind(page))
	_fill()


func _build_rows() -> void:
	for row in ROWS_PER_PAGE:
		var holder := Control.new()
		holder.name = "Row%d" % row
		holder.position = Vector2(ROW_X, ROW_FIRST_Y + ROW_STEP * row)
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_rows.add_child(holder)
		for column: String in COLUMNS:
			var spec: Vector3 = COLUMNS[column]
			var label := Label.new()
			label.name = column
			label.position = Vector2(spec.x, spec.y)
			label.size = Vector2(spec.z, ROW_HEIGHT)
			label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			label.add_theme_font_size_override(&"font_size", 20)
			# The original space-pads the value to right-align it in a fixed-width font; the
			# port's font is proportional, so the column is right-aligned instead.
			if column == "value":
				label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			label.clip_text = true
			holder.add_child(label)


func _fill() -> void:
	($SafeFrame/Column/Label as Label).text = (
		"highscore.time" if _board == BOARD_SCORE else "highscore.score"
	)
	for row in ROWS_PER_PAGE:
		var level := _page * ROWS_PER_PAGE + row + 1
		var holder := _rows.get_node("Row%d" % row)
		(holder.get_node("number") as Label).text = NUMBER_FORMAT % level
		(holder.get_node("title") as Label).text = tr(&"level.%d.title" % level)
		(holder.get_node("name") as Label).text = _name_for(level)
		(holder.get_node("value") as Label).text = _value_for(level)


func _name_for(level: int) -> String:
	if _progress == null:
		return LevelProgress.NO_NAME
	if _board == BOARD_SCORE:
		return _progress.best_score_name(level)
	return _progress.best_time_name(level)


func _value_for(level: int) -> String:
	if _progress == null:
		return NO_SCORE_TEXT if _board == BOARD_SCORE else NO_TIME_TEXT
	if _board == BOARD_SCORE:
		if not _progress.has_best_score(level):
			return NO_SCORE_TEXT
		return str(_progress.best_score(level))
	if not _progress.has_best_time(level):
		return NO_TIME_TEXT
	var seconds := int(_progress.best_time_seconds(level))
	return TIME_FORMAT % [seconds / 60, seconds % 60]


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_fill()


func _on_page_pressed(page: int) -> void:
	_page = page
	_fill()


func _on_column_pressed() -> void:
	_board = BOARD_TIME if _board == BOARD_SCORE else BOARD_SCORE
	_fill()


func _on_back_pressed() -> void:
	if _screens != null:
		_screens.call("change_to_main_menu")
