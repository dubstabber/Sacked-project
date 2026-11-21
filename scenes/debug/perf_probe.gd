class_name PerfProbe
extends RefCounted

# Named timing sections for the frame-spike log and the level benchmark. Every call is a
# no-op until PerfMonitor turns the probe on, so the instrumented code costs one branch in
# ordinary play and in the headless checks. See docs/map-rendering.md, "Measured cost".

static var enabled := false
# Section -> microseconds spent in it since the last take_frame(), and how often it ran.
static var _usec: Dictionary = {}
static var _calls: Dictionary = {}
static var _open: Dictionary = {}
# Every section ever seen, so the editor's custom monitors can be registered once each.
static var _seen: Dictionary = {}
static var _last: Dictionary = {}


static func begin(section: StringName) -> void:
	if enabled:
		_open[section] = Time.get_ticks_usec()


static func end(section: StringName) -> void:
	if not enabled:
		return
	var started: int = _open.get(section, -1)
	if started < 0:
		return
	_open.erase(section)
	_usec[section] = int(_usec.get(section, 0)) + Time.get_ticks_usec() - started
	_calls[section] = int(_calls.get(section, 0)) + 1
	if not _seen.has(section):
		_seen[section] = true
		_register_monitor(section)


# Adds time measured some other way, such as a whole scene change.
static func add(section: StringName, usec: int) -> void:
	if not enabled:
		return
	_usec[section] = int(_usec.get(section, 0)) + usec
	_calls[section] = int(_calls.get(section, 0)) + 1
	if not _seen.has(section):
		_seen[section] = true
		_register_monitor(section)


# Hands back {section: [usec, calls]} for the frame that just ended and starts the next.
static func take_frame() -> Dictionary:
	var frame := {}
	for section in _usec:
		frame[section] = [int(_usec[section]), int(_calls.get(section, 0))]
	_last = frame
	_usec = {}
	_calls = {}
	return frame


static func last_ms(section: StringName) -> float:
	var entry: Array = _last.get(section, [0, 0])
	return float(entry[0]) / 1000.0


static func _register_monitor(section: StringName) -> void:
	var id := "sacked/%s_ms" % String(section)
	if not Performance.has_custom_monitor(id):
		Performance.add_custom_monitor(id, PerfProbe.last_ms.bind(section))
