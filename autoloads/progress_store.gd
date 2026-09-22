class_name LevelProgress
extends Node

# Saved progress: which levels are open, and the best run on each.
#
# The original keeps these in two places. Which levels are open is a 32-bit mask per game
# mode, written to the registry under STATUS (time game) and CHECK (points game); the best
# score and best time per level live in HIGHSCORE.DAT, 52 bytes each. The port keeps the
# original's fields, its write policy and its two sentinels, but puts all of it in one
# user://progress.cfg rather than the registry and a binary file. See docs/shell-reference.md.
#
# Only a win records anything. The points game writes the score and the time game writes the
# time, so a level can hold a best score and a best time set by different people.

signal progress_changed

enum State {
	LOCKED,    # sub_421F80 state 0, drawn on the LOCKED node art
	PLAYABLE,  # state 1, the PLAYED art -- open but not yet cleared
	CLEARED,   # state 2, the FREE art -- the mask bit is set
}

const INDEX_PATH := "res://resources/levels/index.json"
const DEFAULT_PATH := "user://progress.cfg"

const PROGRESS_SECTION := "progress"
# One key per game mode, holding the original's own unlock bitmask.
const CLEARED_KEYS := {
	&"time": "time_cleared",
	&"points": "points_cleared",
}

# HIGHSCORE.DAT's own empty markers: a name that was never set, and a time that was never
# run. The description screen turns them into "---" and "--:--".
const NO_NAME := "---"
const NO_TIME := 12345.0
const NO_SCORE := 0

@export var path := DEFAULT_PATH

var _levels: Array[Dictionary] = []
var _tree: Dictionary = {}
var _config: ConfigFile


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_index()
	reload()


func load_index() -> void:
	if not _levels.is_empty():
		return
	var text := FileAccess.get_file_as_string(INDEX_PATH)
	if text == "":
		push_error("Missing %s; run tools/export_level_index.py" % INDEX_PATH)
		return
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("%s is not a JSON object" % INDEX_PATH)
		return
	_tree = (parsed as Dictionary).get("tree", {}) as Dictionary
	for entry: Variant in (parsed as Dictionary).get("levels", []):
		_levels.append(entry as Dictionary)


# The 48x48 node art sub_421FE0 places, and where it puts the back button.
func node_size() -> Vector2:
	var value: Array = _tree.get("node_size", [48, 48])
	return Vector2(value[0], value[1])


func level_count() -> int:
	return _levels.size()


func level(number: int) -> Dictionary:
	if number < 1 or number > _levels.size():
		return {}
	return _levels[number - 1]


func reload() -> void:
	_config = ConfigFile.new()
	# A missing file is a fresh profile, not an error.
	_config.load(path)


func save() -> void:
	var error := _config.save(path)
	if error != OK:
		push_warning("Could not write %s (error %d)" % [path, error])


func clear() -> void:
	_config = ConfigFile.new()
	save()
	progress_changed.emit()


# ---------------------------------------------------------------------------- unlock state

func cleared_mask(game_mode: StringName) -> int:
	var key: Variant = CLEARED_KEYS.get(game_mode)
	if key == null:
		return 0
	return int(_config.get_value(PROGRESS_SECTION, String(key), 0))


func is_cleared(level_number: int, game_mode: StringName) -> bool:
	if level_number < 1 or level_number > _levels.size():
		return false
	return cleared_mask(game_mode) & (1 << (level_number - 1)) != 0


# sub_421F80: a set bit is CLEARED and opens the two entries below it in the next column,
# and level 1 is always at least playable. A cleared level stays CLEARED even when it is
# also a child, because the original's loop reaches its own bit after any parent's.
func states(game_mode: StringName) -> Array[State]:
	var result: Array[State] = []
	result.resize(_levels.size())
	result.fill(State.LOCKED)
	var mask := cleared_mask(game_mode)
	for index in _levels.size():
		if mask & (1 << index) == 0:
			continue
		for child: int in (_levels[index].get("unlocks", []) as Array):
			result[child - 1] = State.PLAYABLE
	for index in _levels.size():
		if mask & (1 << index) != 0:
			result[index] = State.CLEARED
	if not result.is_empty() and result[0] == State.LOCKED:
		result[0] = State.PLAYABLE
	return result


func state(level_number: int, game_mode: StringName) -> State:
	if level_number < 1 or level_number > _levels.size():
		return State.LOCKED
	return states(game_mode)[level_number - 1]


func is_playable(level_number: int, game_mode: StringName) -> bool:
	return state(level_number, game_mode) != State.LOCKED


# ---------------------------------------------------------------------------- the records

func _section(level_number: int) -> String:
	return "level_%d" % level_number


func best_score(level_number: int) -> int:
	return int(_config.get_value(_section(level_number), "best_score", NO_SCORE))


func best_score_name(level_number: int) -> String:
	return String(_config.get_value(_section(level_number), "best_score_name", NO_NAME))


func best_time_seconds(level_number: int) -> float:
	return float(_config.get_value(_section(level_number), "best_time_seconds", NO_TIME))


func best_time_name(level_number: int) -> String:
	return String(_config.get_value(_section(level_number), "best_time_name", NO_NAME))


func has_best_score(level_number: int) -> bool:
	return best_score(level_number) != NO_SCORE


func has_best_time(level_number: int) -> bool:
	return not is_equal_approx(best_time_seconds(level_number), NO_TIME)


# sub_406E70. A loss writes nothing at all; a win sets the mode's unlock bit and then updates
# only that mode's half of the record. Both comparisons are inclusive, so an equal run takes
# the name over.
func record_result(
	level_number: int,
	game_mode: StringName,
	won: bool,
	score: int,
	elapsed_seconds: float,
	player_name: String
) -> void:
	if not won or level_number < 1 or level_number > _levels.size():
		return

	var key: Variant = CLEARED_KEYS.get(game_mode)
	if key != null:
		var mask := cleared_mask(game_mode) | (1 << (level_number - 1))
		_config.set_value(PROGRESS_SECTION, String(key), mask)

	var section := _section(level_number)
	if game_mode == &"points":
		if score >= best_score(level_number):
			_config.set_value(section, "best_score", score)
			_config.set_value(section, "best_score_name", player_name)
	elif elapsed_seconds <= best_time_seconds(level_number):
		_config.set_value(section, "best_time_seconds", elapsed_seconds)
		_config.set_value(section, "best_time_name", player_name)

	save()
	progress_changed.emit()
