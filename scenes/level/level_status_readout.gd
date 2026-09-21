extends Label

# Placeholder readout so the session is visible while playing. The original console
# replaces it; see docs/game-rules-reference.md for what it really shows.

@onready var _session: Node = get_node_or_null("../..")


func _ready() -> void:
	if _session == null:
		queue_free()
		return
	_session.time_changed.connect(func(_seconds: int) -> void: _refresh())
	_session.score_changed.connect(func(_score: int) -> void: _refresh())
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	# Scaffolding: a 360 second limit is not something to sit through while checking that
	# the level ends. Goes away with this placeholder when the console lands.
	if not OS.is_debug_build() or _session == null or not event is InputEventKey:
		return
	if not event.pressed or event.echo:
		return
	if event.keycode == KEY_F5:
		_session.advance(30.0)
		_refresh()
	elif event.keycode == KEY_F6:
		_session.add_score(1000)
		_refresh()


func _refresh() -> void:
	var seconds := int(_session.elapsed)
	text = "czas %02d:%02d / %02d:%02d\nwynik %05d / %d  [%s]" % [
		seconds / 60,
		seconds % 60,
		int(_session.limit_seconds()) / 60,
		int(_session.limit_seconds()) % 60,
		_session.score,
		_session.target_score(),
		String(_session.mode),
	]
