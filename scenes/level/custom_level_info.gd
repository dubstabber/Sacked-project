@tool
class_name CustomLevelInfo
extends Resource

# One custom level in the port's Custom levels screen (scenes/screens/custom_levels.tscn): a
# .tres of this type in res://custom_levels/ naming the level's scene. The screen lists these
# rather than the scenes, so it can show every level without loading any. The time limit and
# score target are the scene's own, on its LevelRuntime, as on any level. See
# docs/map-authoring.md.
#
# The title and description are the designer's, shown as written in every language: they are
# no text of the port's to translate (docs/strings-reference.md).

const DIRECTORY := "res://custom_levels/"

@export var title := ""
@export_multiline var description := ""
@export_file("*.tscn") var scene := ""
@export var author := ""


# Every listed level in `directory`, by file name: each .tres there that is a CustomLevelInfo
# whose scene exists. ResourceLoader rather than DirAccess, so it also answers in an exported
# build, where the files are remapped.
static func all_in(directory := DIRECTORY) -> Array[CustomLevelInfo]:
	var found: Array[CustomLevelInfo] = []
	if not DirAccess.dir_exists_absolute(directory) and ResourceLoader.list_directory(directory).is_empty():
		return found
	var names := Array(ResourceLoader.list_directory(directory))
	names.sort()
	for name in names:
		if not String(name).ends_with(".tres"):
			continue
		var info := load(directory.path_join(name)) as CustomLevelInfo
		if info != null and info.scene != "" and ResourceLoader.exists(info.scene):
			found.append(info)
	return found
