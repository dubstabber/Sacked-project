extends SceneTree

# The editor's object palette (addons/sacked_map_tools) reads every prefab's name, category and
# picture from the scene files' text rather than loading them. That reading has to find all of
# them, and each with what the builder wrote: the original's name for the object, its
# CO_OBJECTS.DAT category and its own image.

const ObjectPalette := preload("res://addons/sacked_map_tools/object_palette.gd")

var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var entries := ObjectPalette.read_prefabs()
	var prefabs := Array(DirAccess.get_files_at(ObjectPalette.PREFAB_DIR)).filter(func(name): return String(name).ends_with(".tscn"))
	_expect(entries.size() == prefabs.size() and entries.size() >= 600, "every prefab is listed, %d of %d" % [entries.size(), prefabs.size()])
	var named := 0
	for entry in entries:
		if String(entry.get("display_name", "")) != "":
			named += 1
		_expect(int(entry["category"]) >= 0 and int(entry["category"]) < ObjectPalette.CATEGORIES.size(), "%s has a database category, got %d" % [entry["name"], entry["category"]])
		_expect(ResourceLoader.exists(String(entry["texture"])), "%s's picture %s exists" % [entry["name"], entry["texture"]])
	_expect(named == entries.size(), "every prefab carries the original's name, %d of %d" % [named, entries.size()])
	var colamat := entries.filter(func(entry): return entry["name"] == "aktiv-colamat-000")
	_expect(colamat.size() == 1 and colamat[0]["display_name"] == "Colaautomat" and int(colamat[0]["category"]) == 5, "the cola machine is the active Colaautomat, got %s" % [colamat])
	_expect(String(colamat[0]["texture"]) == "res://images/objects/aktiv-colamat-000.png" if not colamat.is_empty() else false, "with its own image")
	if _failures == 0:
		print("Object palette: all %d prefabs listed with the original's name, category and picture" % entries.size())
	quit(1 if _failures else 0)


func _expect(condition: bool, label: String) -> void:
	if not condition:
		_failures += 1
		push_error(label)
