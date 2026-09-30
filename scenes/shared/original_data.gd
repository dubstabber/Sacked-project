extends RefCounted

# The small tables the exporters in tools/ read out of sacked.exe into resources/original/, each
# parsed once and shared by every script that reads it. A table that cannot be read is a broken
# checkout: it is reported, and asked for again on the next read.


static var _tables: Dictionary = {}


static func load_original(path: String) -> Dictionary:
	if _tables.has(path):
		return _tables[path]
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		push_error("Cannot read %s" % path)
		return {}
	_tables[path] = parsed
	return parsed
