class_name CoworkerNames
extends RefCounted

# The fifteen default coworker names and their seven pools, read out of NAMES.DAT and both
# builds by tools/export_names.py. A pool is a type, 1 to 7: the boss, the secretary, the
# janitor, then the two male and two female coworker variants, and the pool's records are
# fixed positions in the table. See docs/names-reference.md.
#
# The names are proper nouns, identical in both retail builds, so nothing here goes through
# tr().

const TABLE_PATH := "res://resources/original/names.json"

static var _types: Array = []
static var _records: Array = []
static var _placeholder := ""
static var _max_length := 16


static func _load() -> void:
	if not _records.is_empty():
		return
	var file := FileAccess.open(TABLE_PATH, FileAccess.READ)
	if file == null:
		push_error("Coworker name table is missing: %s" % TABLE_PATH)
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary):
		push_error("Coworker name table is not readable: %s" % TABLE_PATH)
		return
	_types = parsed.get("types", [])
	_records = parsed.get("records", [])
	_placeholder = String(parsed.get("placeholder", ""))
	_max_length = int(parsed.get("max_length", _max_length))


static func type_count() -> int:
	_load()
	return _types.size()


# The name sub_4156E0 hands out once a pool is empty.
static func placeholder() -> String:
	_load()
	return _placeholder


# Every copy in or out of a record is strncpy(..., 16), and screen 13's boxes cap at 16.
static func max_length() -> int:
	_load()
	return _max_length


static func profile_id(type: int) -> StringName:
	var entry := _type_entry(type)
	return StringName(entry.get("profile_id", ""))


static func pool_size(type: int) -> int:
	return (_type_entry(type).get("records", []) as Array).size()


# The pool's names as shipped, in record order.
static func defaults_for(type: int) -> PackedStringArray:
	var names := PackedStringArray()
	for index in _type_entry(type).get("records", []):
		names.append(String((_records[int(index)] as Dictionary).get("name", "")))
	return names


static func _type_entry(type: int) -> Dictionary:
	_load()
	for entry in _types:
		if int((entry as Dictionary).get("type", 0)) == type:
			return entry
	return {}
