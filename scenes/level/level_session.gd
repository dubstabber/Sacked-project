class_name LevelSession
extends Node


signal time_changed(elapsed_seconds: int)
signal score_changed(score: int)
signal finished(won: bool)

# sub_403780 substitutes these when a level carries no usable CONDITION; see
# docs/game-rules-reference.md.
const DEFAULT_TIME_LIMIT := 1200.0
const DEFAULT_SCORE_TARGET := 10000
# The tick starts the looping warning sound this long before the limit.
const WARNING_LEAD_SECONDS := 10.0

# The original ships one CONDITION per mode in two files: the plain level for the time
# game and the S variant for the points game.
@export var time_mode_limit_seconds: float = 0.0
@export var time_mode_score_target: int = 0
@export var points_mode_limit_seconds: float = 0.0
@export var points_mode_score_target: int = 0
# Only gates the session's own clock; advance() still works so tests can drive it.
@export var enabled := true

var mode: StringName = &"time"
var score := 0
var elapsed := 0.0
var is_finished := false
var won := false

var _elapsed_seconds := -1
var _warned := false


# Joined here rather than in _ready: children are made ready before their parent, and the
# console looks the session up by group while it becomes ready.
func _enter_tree() -> void:
	add_to_group("level_session")


func _ready() -> void:
	# Resolved by path, not by the autoload name: the level tests load this scene from a
	# SceneTree script where the autoloads do not exist.
	var screen_manager := get_node_or_null("/root/ScreenManager")
	if screen_manager != null:
		mode = StringName(screen_manager.get("selected_game_mode"))
		finished.connect(screen_manager.report_level_finished)
	set_physics_process(enabled)


func limit_seconds() -> float:
	var limit := points_mode_limit_seconds if mode == &"points" else time_mode_limit_seconds
	return limit if limit > 0.0 else DEFAULT_TIME_LIMIT


func target_score() -> int:
	var target := points_mode_score_target if mode == &"points" else time_mode_score_target
	return target if target > 0 else DEFAULT_SCORE_TARGET


func add_score(points: int) -> void:
	if is_finished:
		return
	score += points
	score_changed.emit(score)


func advance(delta: float) -> void:
	if is_finished:
		return
	elapsed += delta
	# The original compares a whole-second counter against the float limit, and its clock
	# counts up rather than down.
	var whole := int(elapsed)
	if whole != _elapsed_seconds:
		_elapsed_seconds = whole
		time_changed.emit(whole)
	if not _warned and float(whole) >= limit_seconds() - WARNING_LEAD_SECONDS:
		_warned = true
	_evaluate(float(whole))


func _physics_process(delta: float) -> void:
	advance(delta)


func _evaluate(seconds: float) -> void:
	var limit := limit_seconds()
	var target := target_score()
	if mode == &"points":
		# The points game always runs the full time and is judged at the end.
		if seconds >= limit:
			_finish(score >= target)
		return
	# The time game ends the moment the target is reached, and is lost once the clock
	# passes the limit.
	if seconds <= limit and score >= target:
		_finish(true)
	elif seconds > limit:
		_finish(false)


func _finish(result: bool) -> void:
	if is_finished:
		return
	is_finished = true
	won = result
	set_physics_process(false)
	finished.emit(result)


func is_warning() -> bool:
	return _warned
