class_name ActionTable
extends RefCounted

# The 156 prank action records traced out of sacked.exe by tools/export_action_table.py.
# Field meanings are in docs/prank-reference.md.

const TABLE_PATH := "res://resources/original/actions.json"

static var _actions: Array = []
static var _icon_images: Array = []
static var _icons: Dictionary = {}


static func _load() -> void:
	if not _actions.is_empty():
		return
	var file := FileAccess.open(TABLE_PATH, FileAccess.READ)
	if file == null:
		push_warning("Action table is missing: %s" % TABLE_PATH)
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		_actions = parsed.get("actions", [])
		_icon_images = parsed.get("icon_images", [])


static func size() -> int:
	_load()
	return _actions.size()


static func get_action(action_id: int) -> Dictionary:
	_load()
	if action_id <= 0 or action_id >= _actions.size():
		return {}
	return _actions[action_id]


# The hover bar and the ring show this, so it follows the language. tr() is a Node method
# and this is a RefCounted, hence TranslationServer directly. A key with no translation
# comes back as itself, which is the signal to fall back to the record's own Polish.
static func action_name(action_id: int) -> String:
	var recorded := String(get_action(action_id).get("name", ""))
	if recorded == "":
		return ""
	var key := "action.%d.name" % action_id
	var translated := TranslationServer.translate(key)
	return recorded if translated == key else String(translated)


static func icon_texture(action_id: int) -> Texture2D:
	var action := get_action(action_id)
	if action.is_empty():
		return null
	var index := int(action.get("icon", -1))
	if index < 0 or index >= _icon_images.size():
		return null
	if not _icons.has(index):
		var path := "res://" + String(_icon_images[index])
		_icons[index] = load(path) as Texture2D if ResourceLoader.exists(path) else null
	return _icons[index] as Texture2D
