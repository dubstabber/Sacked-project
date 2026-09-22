extends Control

# The original's screen 16. sub_421CD0 fills five fields from the level's highscore record
# and its .col header, and sub_408B60 drops the level's objective into the `%s` of
# Level_XX.txt. See docs/shell-reference.md.
#
# One divergence, recorded rather than hidden: the original can start any level whose node
# the tree let you click, because every level ships with it. This port has only imported
# some of the 21, so a level with no scene yet opens its description and refuses to start.

# sub_421CD0 formats these as C literals rather than text-table slots, so unlike every other
# string on this screen they are the same in all three languages.
const NO_TIME_TEXT := "--:--"
const NO_SCORE_TEXT := "---"
const SCORE_FORMAT := "%06d"
const TIME_FORMAT := "%02d:%02d"
const TITLE_FORMAT := "%s (#%02d)"
const SIZE_FORMAT := "%d x %d"

var _level := 1

# Resolved by path rather than by the autoload name: a singleton's global name is not bound
# while this script is compiled, which is how the headless tests load the scene.
@onready var _screens: Node = get_node_or_null("/root/ScreenManager")
@onready var _progress: LevelProgress = get_node_or_null("/root/ProgressStore")


func _ready() -> void:
	if _screens != null:
		_level = int(_screens.get("selected_level"))
	($SafeFrame/Back as TextureButton).pressed.connect(_on_back_pressed)
	var start := $SafeFrame/Continue as TextureButton
	start.pressed.connect(_on_continue_pressed)
	start.disabled = _screens != null and not bool(_screens.call("is_level_available", _level))
	($SafeFrame/Continue/Label as Label).modulate.a = 0.5 if start.disabled else 1.0
	_fill()


# Everything here is either formatted or looked up by a key that varies with the level, so
# none of it can auto-translate and all of it is rebuilt when the language changes.
func _fill() -> void:
	if _progress == null:
		return
	var entry := _progress.level(_level)
	if entry.is_empty():
		return

	($SafeFrame/Title as Label).text = TITLE_FORMAT % [tr(&"level.%d.title" % _level), _level]
	($SafeFrame/DescText as Label).text = _description(entry)

	var info := $SafeFrame/Info
	(info.get_node("BestTimeValue") as Label).text = _best_time_text()
	(info.get_node("BestScoreValue") as Label).text = _best_score_text()
	(info.get_node("SizeValue") as Label).text = SIZE_FORMAT % [entry["width"], entry["height"]]
	(info.get_node("DifficultyValue") as Label).text = tr(&"difficulty.%d" % int(entry["difficulty"]))


# Level_XX.txt is a description, a lone `%s` and a hint. The exporter splits it into two
# keys, so the screen puts the objective back between them in the original's own shape.
func _description(entry: Dictionary) -> String:
	var mode: StringName = &"time"
	if _screens != null:
		mode = StringName(_screens.get("selected_game_mode"))
	var condition: Dictionary = entry["points_game"] if mode == &"points" else entry["time_game"]
	var goal := GoalText.sentence(
		mode, float(condition["time_limit_seconds"]), int(condition["score_target"])
	)
	return "\n\n".join([tr(&"level.%d.description" % _level), goal, tr(&"level.%d.hint" % _level)])


func _best_time_text() -> String:
	if not _progress.has_best_time(_level):
		return NO_TIME_TEXT
	var seconds := int(_progress.best_time_seconds(_level))
	return TIME_FORMAT % [seconds / 60, seconds % 60]


func _best_score_text() -> String:
	if not _progress.has_best_score(_level):
		return NO_SCORE_TEXT
	return SCORE_FORMAT % _progress.best_score(_level)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_fill()


func _on_back_pressed() -> void:
	if _screens != null:
		_screens.call("change_to_level_tree")


func _on_continue_pressed() -> void:
	if _screens != null:
		_screens.call("start_level", _level)
