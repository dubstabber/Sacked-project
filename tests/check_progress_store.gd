extends SceneTree

# Saved progress: the unlock predicate recovered from sub_421F80, and the write policy
# recovered from sub_406E70. Both run against a temporary file rather than the player's own.
# See docs/shell-reference.md.

const STORE_SCRIPT := preload("res://autoloads/progress_store.gd")
const TEST_PATH := "user://check_progress_store.cfg"

var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_check_a_fresh_profile_opens_only_level_one()
	_check_clearing_a_level_opens_its_two_children()
	_check_a_cleared_level_stays_cleared_when_it_is_also_a_child()
	_check_the_two_game_modes_do_not_share_progress()
	_check_only_a_win_records_anything()
	_check_each_mode_writes_only_its_own_half()
	_check_a_worse_run_does_not_replace_a_better_one()
	_check_progress_survives_a_reload()

	DirAccess.remove_absolute(TEST_PATH)
	if _failures == 0:
		print("Saved progress: the unlock triangle, per-mode masks and the win-only write policy passed")
	quit(1 if _failures else 0)


func _expect(condition: bool, label: String) -> void:
	if not condition:
		_failures += 1
		push_error(label)


func _fresh_store() -> Node:
	DirAccess.remove_absolute(TEST_PATH)
	var store: Node = STORE_SCRIPT.new()
	store.path = TEST_PATH
	store.load_index()
	store.reload()
	return store


func _win(store: Node, level: int, mode: StringName, score: int, seconds: float, who: String) -> void:
	store.record_result(level, mode, true, score, seconds, who)


func _check_a_fresh_profile_opens_only_level_one() -> void:
	var store := _fresh_store()
	_expect(store.level_count() == 21, "the index should describe 21 levels, saw %d" % store.level_count())
	_expect(store.state(1, &"time") == STORE_SCRIPT.State.PLAYABLE, "level 1 should be playable on a fresh profile")
	for level in range(2, 22):
		_expect(
			store.state(level, &"time") == STORE_SCRIPT.State.LOCKED,
			"level %d should be locked on a fresh profile" % level
		)
	store.free()


func _check_clearing_a_level_opens_its_two_children() -> void:
	var store := _fresh_store()
	_win(store, 1, &"time", 4000, 200.0, "Jo")
	_expect(store.state(1, &"time") == STORE_SCRIPT.State.CLEARED, "level 1 should be cleared after a win")
	# The triangle: entry 0 in column 1 opens entries 1 and 2.
	_expect(store.state(2, &"time") == STORE_SCRIPT.State.PLAYABLE, "level 2 should open when 1 is cleared")
	_expect(store.state(3, &"time") == STORE_SCRIPT.State.PLAYABLE, "level 3 should open when 1 is cleared")
	_expect(store.state(4, &"time") == STORE_SCRIPT.State.LOCKED, "level 4 should still be locked")

	# Entry 1 in column 2 opens entries 3 and 4; entry 2 opens 4 and 5.
	_win(store, 2, &"time", 7000, 300.0, "Jo")
	_expect(store.state(4, &"time") == STORE_SCRIPT.State.PLAYABLE, "level 4 should open when 2 is cleared")
	_expect(store.state(5, &"time") == STORE_SCRIPT.State.PLAYABLE, "level 5 should open when 2 is cleared")
	_expect(store.state(6, &"time") == STORE_SCRIPT.State.LOCKED, "level 6 needs level 3, not level 2")
	_win(store, 3, &"time", 6000, 300.0, "Jo")
	_expect(store.state(6, &"time") == STORE_SCRIPT.State.PLAYABLE, "level 6 should open when 3 is cleared")
	store.free()


func _check_a_cleared_level_stays_cleared_when_it_is_also_a_child() -> void:
	var store := _fresh_store()
	# Level 5 is a child of both 2 and 3, so its own CLEARED must survive their PLAYABLE.
	_win(store, 1, &"time", 4000, 200.0, "Jo")
	_win(store, 5, &"time", 8500, 400.0, "Jo")
	_win(store, 2, &"time", 7000, 300.0, "Jo")
	_expect(
		store.state(5, &"time") == STORE_SCRIPT.State.CLEARED,
		"level 5 was cleared, so being a child of level 2 must not knock it back to playable"
	)
	store.free()


func _check_the_two_game_modes_do_not_share_progress() -> void:
	var store := _fresh_store()
	_win(store, 1, &"time", 4000, 200.0, "Jo")
	_expect(store.state(2, &"time") == STORE_SCRIPT.State.PLAYABLE, "level 2 should be open in the time game")
	_expect(
		store.state(2, &"points") == STORE_SCRIPT.State.LOCKED,
		"the points game keeps its own mask, so level 2 should still be locked there"
	)
	_expect(store.state(1, &"points") == STORE_SCRIPT.State.PLAYABLE, "level 1 is always playable in both modes")
	store.free()


func _check_only_a_win_records_anything() -> void:
	var store := _fresh_store()
	store.record_result(1, &"time", false, 9999, 10.0, "Jo")
	_expect(store.state(1, &"time") == STORE_SCRIPT.State.PLAYABLE, "a loss must not clear the level")
	_expect(store.state(2, &"time") == STORE_SCRIPT.State.LOCKED, "a loss must not open anything")
	_expect(not store.has_best_time(1), "a loss must not record a time")
	_expect(not store.has_best_score(1), "a loss must not record a score")
	_expect(store.best_time_name(1) == STORE_SCRIPT.NO_NAME, "an unplayed level keeps the --- name")
	store.free()


func _check_each_mode_writes_only_its_own_half() -> void:
	var store := _fresh_store()
	_win(store, 1, &"time", 4000, 174.0, "Anne")
	_expect(store.has_best_time(1), "the time game should record a time")
	_expect(not store.has_best_score(1), "the time game must not record a score")
	_expect(store.best_time_name(1) == "Anne", "the time name should be the winner's")
	_expect(store.best_score_name(1) == STORE_SCRIPT.NO_NAME, "the score name should still be ---")

	_win(store, 1, &"points", 5200, 300.0, "Jo")
	_expect(store.best_score(1) == 5200, "the points game should record a score")
	_expect(
		is_equal_approx(store.best_time_seconds(1), 174.0),
		"the points game must not disturb the best time"
	)
	_expect(store.best_time_name(1) == "Anne", "the points game must not disturb the time's name")
	store.free()


func _check_a_worse_run_does_not_replace_a_better_one() -> void:
	var store := _fresh_store()
	_win(store, 1, &"time", 0, 174.0, "Anne")
	_win(store, 1, &"time", 0, 300.0, "Jo")
	_expect(is_equal_approx(store.best_time_seconds(1), 174.0), "a slower run must not take the best time")
	_expect(store.best_time_name(1) == "Anne", "a slower run must not take the name")

	_win(store, 1, &"points", 5200, 300.0, "Anne")
	_win(store, 1, &"points", 100, 300.0, "Jo")
	_expect(store.best_score(1) == 5200, "a lower score must not take the best score")

	# sub_406E70 compares inclusively, so an equal run does take the name over.
	_win(store, 1, &"points", 5200, 300.0, "Jo")
	_expect(store.best_score_name(1) == "Jo", "an equal score should take the name, as the original's >= does")
	store.free()


func _check_progress_survives_a_reload() -> void:
	var store := _fresh_store()
	_win(store, 1, &"time", 4000, 174.0, "Anne")
	store.free()

	var reopened: Node = STORE_SCRIPT.new()
	reopened.path = TEST_PATH
	reopened.load_index()
	reopened.reload()
	_expect(reopened.state(1, &"time") == STORE_SCRIPT.State.CLEARED, "the cleared level should survive a reload")
	_expect(reopened.state(2, &"time") == STORE_SCRIPT.State.PLAYABLE, "the opened level should survive a reload")
	_expect(is_equal_approx(reopened.best_time_seconds(1), 174.0), "the best time should survive a reload")
	_expect(reopened.best_time_name(1) == "Anne", "the best name should survive a reload")
	reopened.free()
