class_name ThreadedLoads
extends RefCounted

# Loads textures on worker threads ahead of the frame that shows them, so a clip's first
# frame is the only one loaded on the spot. A caller request()s the paths it will need,
# take()s each when it needs it -- which waits only if that one is still loading -- and
# release()s the rest when it no longer needs them. A threaded load has to be collected once
# it is done, and collecting it early would block, so ScreenManager polls the released ones
# every frame through collect_released(). See docs/map-rendering.md.
#
# Headless, the dummy renderer cannot create a texture off the main thread, so there every
# request is a no-op and take() is a plain load.

static var _requested: Dictionary = {}
static var _released: Dictionary = {}


static func available() -> bool:
	return DisplayServer.get_name() != "headless"


static func request(path: String) -> void:
	if not available() or path == "" or _requested.has(path):
		return
	if _released.has(path):
		_released.erase(path)
		_requested[path] = true
		return
	if ResourceLoader.has_cached(path) or not ResourceLoader.exists(path):
		return
	if ResourceLoader.load_threaded_request(path) == OK:
		_requested[path] = true


# The resource at path: a requested one once its worker thread is done, anything else loaded
# now. Null for a path with nothing there.
static func take(path: String) -> Resource:
	if _requested.has(path):
		_requested.erase(path)
		return ResourceLoader.load_threaded_get(path)
	if _released.has(path):
		_released.erase(path)
		return ResourceLoader.load_threaded_get(path)
	return load(path) if path != "" and ResourceLoader.exists(path) else null


static func release(path: String) -> void:
	if _requested.erase(path):
		_released[path] = true


static func collect_released() -> void:
	if _released.is_empty():
		return
	for path in _released.keys():
		if ResourceLoader.load_threaded_get_status(path) != ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			ResourceLoader.load_threaded_get(path)
			_released.erase(path)


static func pending_count() -> int:
	return _requested.size() + _released.size()
