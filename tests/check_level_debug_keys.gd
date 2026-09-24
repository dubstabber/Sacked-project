extends SceneTree

# DebugKeys' F5 moves the level's clock on, and a clock that ends the level reports the
# result, which changes scene before advance() returns. The level is the tree's current
# scene here, the way ScreenManager runs it: one added under the root is never taken out of
# the tree by a scene change, which is how F5's null-viewport error went unseen.

const TEST_PATH := "user://check_level_debug_keys.cfg"


# A GDScript runtime error leaves a --script run's exit code alone, so the check listens for
# one itself.
class ErrorLog extends Logger:
	var errors: Array[String] = []
	var _mutex := Mutex.new()

	func _log_error(
		function: String, file: String, line: int, code: String, rationale: String,
		_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]
	) -> void:
		_mutex.lock()
		errors.append("%s:%d %s: %s (type %d)" % [file, line, function, rationale if rationale != "" else code, error_type])
		_mutex.unlock()

	func count() -> int:
		_mutex.lock()
		var size := errors.size()
		_mutex.unlock()
		return size

	func since(mark: int) -> Array[String]:
		_mutex.lock()
		var found := errors.slice(mark)
		_mutex.unlock()
		return found


var _failures := 0
var _restore_path := ""


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	# A win records progress, so it goes to a file of the check's own.
	var store := root.get_node("ProgressStore")
	_restore_path = store.path
	store.path = TEST_PATH
	DirAccess.remove_absolute(TEST_PATH)
	store.reload()
	var error_log := ErrorLog.new()
	OS.add_logger(error_log)

	await _check_f5_can_end_the_level(error_log, true)
	await _check_f5_can_end_the_level(error_log, false)

	OS.remove_logger(error_log)
	store.path = _restore_path
	store.reload()
	DirAccess.remove_absolute(TEST_PATH)
	if _failures == 0:
		print("Level debug keys: F5 can end the level and leave for the result screen without an error")
	quit(1 if _failures else 0)


func _expect(condition: bool, label: String) -> void:
	if not condition:
		_failures += 1
		push_error(label)


# Whether the key was consumed; the flag holds after push_input returns.
func _key(code: Key) -> bool:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	root.push_input(event)
	return root.is_input_handled()


func _check_f5_can_end_the_level(error_log: ErrorLog, win: bool) -> void:
	var outcome := "a win" if win else "a loss"
	var manager := root.get_node("ScreenManager")
	manager.start_level(1)
	await process_frame
	await process_frame
	var level := current_scene
	if level == null or level.scene_file_path != manager.level_scene_path(1):
		_expect(false, "start_level(1) makes the level the current scene")
		return
	var session: Node = level.get_node("LevelRuntime")
	# Held so only F5 moves the clock: the time game ends on the next evaluation once the
	# target is met, and is lost once the clock passes the limit.
	session.set_physics_process(false)
	if win:
		session.add_score(session.target_score())
	else:
		session.elapsed = session.limit_seconds()
	var level_ref: WeakRef = weakref(level)

	var mark := error_log.count()
	var handled := _key(KEY_F5)
	var errors_on_key := error_log.since(mark)
	var screen_on_key: int = manager.current
	mark = error_log.count()
	for i in range(3):
		await process_frame
	var errors_after_swap := error_log.since(mark)

	_expect(errors_on_key.is_empty(), "F5 ending the level in %s raises no error: %s" % [outcome, errors_on_key])
	_expect(handled, "F5 is consumed although it ended the level (%s)" % outcome)
	_expect(screen_on_key == manager.Screen.LEVEL_RESULT, "F5 reaches the result screen (%s)" % outcome)
	_expect(bool(manager.last_level_won) == win, "the result screen is told of %s" % outcome)
	_expect(errors_after_swap.is_empty(), "the scene swap after %s raises no error: %s" % [outcome, errors_after_swap])
	_expect(level_ref.get_ref() == null, "the level is freed once it has ended (%s)" % outcome)
