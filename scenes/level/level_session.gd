class_name LevelSession
extends Node


signal time_changed(elapsed_seconds: int)
signal score_changed(score: int)
signal finished(won: bool)
signal aggression_changed(level: float)
signal aggravation_rose()

# sub_403780 substitutes these when a level carries no usable CONDITION; see
# docs/game-rules-reference.md.
const DEFAULT_TIME_LIMIT := 1200.0
const DEFAULT_SCORE_TARGET := 10000
# The tick starts the looping warning sound this long before the limit.
const WARNING_LEAD_SECONDS := 10.0
# sub_402350 puts the office-wide mean into four bands and hands each agent the one it is
# in; sub_419CE0 and friends turn that into 0.15 tiles a second of extra pace.
const AGGRESSION_BAND_SCALE := 0.039999999
const AGGRESSION_BAND_MAX := 3

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

# game+14728: the mean of every agent's own aggression, recomputed every frame.
var aggression := 0.0

var _elapsed_seconds := -1
var _screen_manager: Node
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
		_screen_manager = screen_manager
		finished.connect(_report_finished)
	set_physics_process(enabled)


func _process(_delta: float) -> void:
	refresh_aggression()


# sub_402350. The band handed to each agent comes from the mean as it stood at the start of
# the frame, which is what the original reads before it overwrites game+14728.
func refresh_aggression() -> void:
	var carried := int(floor(aggression * AGGRESSION_BAND_SCALE))
	var band := clampi(carried, 0, AGGRESSION_BAND_MAX)
	var total := 0.0
	var count := 0
	for agent in get_tree().get_nodes_in_group("npc_agents"):
		var brain := agent.get_node_or_null("Brain")
		if brain == null:
			continue
		total += float(brain.get("aggression"))
		count += 1
		agent.set("aggression_band", band)
	var mean := total / float(count) if count > 0 else 0.0
	# The original compares the unclamped bands, so a meter already past the top band
	# cannot announce itself again.
	if carried < int(floor(mean * AGGRESSION_BAND_SCALE)):
		aggravation_rose.emit()
	if not is_equal_approx(mean, aggression):
		aggression = mean
		aggression_changed.emit(mean)


func limit_seconds() -> float:
	var limit := points_mode_limit_seconds if mode == &"points" else time_mode_limit_seconds
	return limit if limit > 0.0 else DEFAULT_TIME_LIMIT


func target_score() -> int:
	var target := points_mode_score_target if mode == &"points" else time_mode_score_target
	return target if target > 0 else DEFAULT_SCORE_TARGET


# sub_41DE60 and sub_41DEA0 both add to player+984 and float the number off the spot that
# earned it in the same breath, so a score with a place to come from carries one.
func add_score(points: int, world_position := Vector2.INF) -> void:
	if is_finished:
		return
	score += points
	score_changed.emit(score)
	if not world_position.is_finite():
		return
	var popups := get_tree().get_first_node_in_group("score_popups")
	if popups != null:
		popups.call("spawn", world_position, points)


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


# sub_406E70 records the run it is handed, so the score and the clock travel with the
# outcome rather than being fetched back out of a level that is about to be freed.
func _report_finished(result: bool) -> void:
	_screen_manager.call("report_level_finished", result, score, elapsed)


func _finish(result: bool) -> void:
	if is_finished:
		return
	is_finished = true
	won = result
	set_physics_process(false)
	finished.emit(result)


func is_warning() -> bool:
	return _warned
