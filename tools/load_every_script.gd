extends SceneTree

# Loads every GDScript in the project, so that each one compiles once. Run under --debug, the
# compiler prints each warning it finds as "WARNING: ..." followed by "at: GDScript::reload
# (res://path:line)", the same warnings the editor's debugger lists while the game runs.
# tools/check_script_warnings.py reads them; see there.

const SKIPPED := ["extract-sacked-assets", "sacked-reference-images"]


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var paths: Array = []
	_collect("res://", paths)
	paths.sort()
	for path in paths:
		load(path)
	print("Loaded %d scripts" % paths.size())
	quit(0)


func _collect(directory: String, paths: Array) -> void:
	for sub in DirAccess.get_directories_at(directory):
		if sub.begins_with(".") or sub in SKIPPED:
			continue
		_collect(directory.path_join(sub), paths)
	for file in DirAccess.get_files_at(directory):
		if file.ends_with(".gd"):
			paths.append(directory.path_join(file))
