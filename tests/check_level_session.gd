extends SceneTree


const SessionScript := preload("res://scenes/level/level_session.gd")
const LEVEL_1_TIME := 360.0
const LEVEL_1_TIME_TARGET := 4000
const LEVEL_1_POINTS := 300.0
const LEVEL_1_POINTS_TARGET := 3000

var _failures := 0


func _init() -> void:
	# Deferred so the run happens once the tree and its autoloads exist.
	call_deferred("_run")


func _run() -> void:
	_check_level_1_conditions()
	_check_time_mode_wins_on_reaching_the_target()
	_check_time_mode_loses_past_the_limit()
	_check_points_mode_runs_the_full_time()
	_check_points_mode_loses_when_short()
	_check_fallbacks()
	_check_score_stops_after_the_end()
	_check_warning_lead()
	_check_level_reports_its_outcome()
	if _failures == 0:
		print("Level session: original CONDITION values, both mode predicates and the fallbacks passed")
	quit(1 if _failures else 0)


func _expect(condition: bool, label: String) -> void:
	if not condition:
		_failures += 1
		push_error(label)


func _session(mode: StringName) -> Node:
	var session: Node = SessionScript.new()
	session.time_mode_limit_seconds = LEVEL_1_TIME
	session.time_mode_score_target = LEVEL_1_TIME_TARGET
	session.points_mode_limit_seconds = LEVEL_1_POINTS
	session.points_mode_score_target = LEVEL_1_POINTS_TARGET
	session.mode = mode
	return session


# Drives whole seconds, which is what the original compares against the limit.
func _run_for(session: Node, seconds: int) -> void:
	for i in range(seconds):
		session.advance(1.0)


func _check_level_1_conditions() -> void:
	var scene := load("res://scenes/level_1.tscn") as PackedScene
	var level := scene.instantiate()
	var runtime := level.get_node_or_null("LevelRuntime")
	_expect(runtime != null, "level 1 carries a LevelRuntime")
	if runtime == null:
		level.free()
		return
	_expect(runtime.time_mode_limit_seconds == LEVEL_1_TIME, "level 1 time-game limit is the original 360 s")
	_expect(runtime.time_mode_score_target == LEVEL_1_TIME_TARGET, "level 1 time-game target is the original 4000")
	_expect(runtime.points_mode_limit_seconds == LEVEL_1_POINTS, "level 1 points-game limit is the original 300 s")
	_expect(runtime.points_mode_score_target == LEVEL_1_POINTS_TARGET, "level 1 points-game target is the original 3000")
	level.free()


func _check_time_mode_wins_on_reaching_the_target() -> void:
	var session := _session(&"time")
	var results: Array = []
	session.finished.connect(func(won: bool) -> void: results.append(won))
	_run_for(session, 10)
	_expect(results.is_empty(), "time game does not end before the target is reached")
	session.add_score(LEVEL_1_TIME_TARGET)
	session.advance(1.0)
	_expect(results == [true], "time game is won the moment the target is reached")
	session.free()


func _check_time_mode_loses_past_the_limit() -> void:
	var session := _session(&"time")
	var results: Array = []
	session.finished.connect(func(won: bool) -> void: results.append(won))
	session.add_score(LEVEL_1_TIME_TARGET - 1)
	_run_for(session, int(LEVEL_1_TIME))
	_expect(results.is_empty(), "time game is still running at exactly the limit")
	session.advance(1.0)
	_expect(results == [false], "time game is lost once the clock passes the limit")
	session.free()


func _check_points_mode_runs_the_full_time() -> void:
	var session := _session(&"points")
	var results: Array = []
	session.finished.connect(func(won: bool) -> void: results.append(won))
	session.add_score(LEVEL_1_POINTS_TARGET)
	_run_for(session, int(LEVEL_1_POINTS) - 1)
	_expect(results.is_empty(), "points game does not end early even once the target is reached")
	session.advance(1.0)
	_expect(results == [true], "points game is won at the limit when the target is met")
	session.free()


func _check_points_mode_loses_when_short() -> void:
	var session := _session(&"points")
	var results: Array = []
	session.finished.connect(func(won: bool) -> void: results.append(won))
	session.add_score(LEVEL_1_POINTS_TARGET - 1)
	_run_for(session, int(LEVEL_1_POINTS))
	_expect(results == [false], "points game is lost at the limit when the target is missed")
	session.free()


func _check_fallbacks() -> void:
	# sub_403780 substitutes 1200 s and 10000 points when a level carries neither.
	var session: Node = SessionScript.new()
	session.mode = &"time"
	_expect(session.limit_seconds() == 1200.0, "missing time limit falls back to 1200 s")
	_expect(session.target_score() == 10000, "missing score target falls back to 10000")
	session.free()


func _check_score_stops_after_the_end() -> void:
	var session := _session(&"time")
	session.add_score(LEVEL_1_TIME_TARGET)
	session.advance(1.0)
	var settled: int = session.score
	session.add_score(500)
	_expect(session.score == settled, "score is frozen once the level has finished")
	session.free()


# The isolated cases above build a session by hand; this one runs the real level scene so
# a broken wiring between the builder, the session and the autoload cannot pass unnoticed.
func _check_level_reports_its_outcome() -> void:
	var manager := root.get_node_or_null("ScreenManager")
	if manager == null:
		_expect(false, "the ScreenManager autoload is available to the level")
		return
	var level := (load("res://scenes/level_1.tscn") as PackedScene).instantiate()
	var runtime: Node = level.get_node_or_null("LevelRuntime")
	_expect(runtime != null, "the level scene carries its session")
	if runtime == null:
		level.free()
		return
	runtime.enabled = false
	root.add_child(level)
	var reported: Array = []
	runtime.finished.connect(func(won: bool) -> void: reported.append(won))
	runtime.mode = &"time"
	runtime.add_score(runtime.target_score())
	runtime.advance(1.0)
	_expect(reported == [true], "the level's own session reports its win")
	_expect(manager.last_level_won, "the autoload records the outcome for the result screen")
	manager.last_level_won = false
	root.remove_child(level)
	level.free()


func _check_warning_lead() -> void:
	var session := _session(&"points")
	_run_for(session, int(LEVEL_1_POINTS) - 11)
	_expect(not session.is_warning(), "the countdown warning has not started 11 s out")
	session.advance(1.0)
	_expect(session.is_warning(), "the countdown warning starts 10 s before the limit")
	session.free()
