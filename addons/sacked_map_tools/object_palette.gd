@tool
extends VBoxContainer

# Every object prefab in scenes/objects/, shown by its picture and its name in the original's
# object database, filtered by search text and by the database's category. An entry dragged
# into the 2D view drops the prefab where it lands, as a file from the FileSystem dock would;
# a double-click drops it into the edited map's World/Objects at the centre of the view, with
# undo. A prefab carries its object's gameplay, so either way the object works as placed.
# See docs/map-authoring.md.

const PREFAB_DIR := "res://scenes/objects/"
const ICON_SIZE := 48
# CO_OBJECTS.DAT +4, the database's own folders (tools/import_original_level.py, domain_hints).
const CATEGORIES := [
	"General", "Office", "Kitchen", "WC", "Boss", "Active", "Lounge", "Foyer", "Janitor", "Meeting",
]
const DISPLAY_NAME := "metadata/display_name = "
const OBJECT_CATEGORY := "metadata/object_category = "
const COLOR_TEXTURE := "color_texture = ExtResource("

var entries: Array[Dictionary] = []
var _search: LineEdit
var _category: OptionButton
var _list: ItemList


func _ready() -> void:
	_search = LineEdit.new()
	_search.placeholder_text = "Search objects"
	_search.clear_button_enabled = true
	_search.text_changed.connect(func(_text): _fill())
	add_child(_search)
	_category = OptionButton.new()
	_category.add_item("All categories", -1)
	for index in range(CATEGORIES.size()):
		_category.add_item(CATEGORIES[index], index)
	_category.item_selected.connect(func(_index): _fill())
	add_child(_category)
	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.max_columns = 0
	_list.icon_mode = ItemList.ICON_MODE_TOP
	_list.fixed_icon_size = Vector2i(ICON_SIZE, ICON_SIZE)
	_list.fixed_column_width = ICON_SIZE * 2
	_list.same_column_width = true
	_list.item_activated.connect(_drop_into_map)
	_list.set_drag_forwarding(_drag_data, Callable(), Callable())
	add_child(_list)
	entries = read_prefabs()
	_fill()


# The prefabs' names, categories and pictures, read from the scene files' own text so the
# palette loads no scene: 609 of them would take seconds and their textures' memory.
static func read_prefabs(directory := PREFAB_DIR) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	var names := Array(DirAccess.get_files_at(directory)).filter(func(name): return String(name).ends_with(".tscn"))
	names.sort()
	for file_name in names:
		var path := directory.path_join(file_name)
		var entry := {"path": path, "name": String(file_name).get_basename(), "category": -1, "texture": ""}
		var resources := {}
		for line in FileAccess.get_file_as_string(path).split("\n"):
			if line.begins_with("[ext_resource") and line.contains("type=\"Texture2D\""):
				resources[line.get_slice(" id=\"", 1).get_slice("\"", 0)] = line.get_slice(" path=\"", 1).get_slice("\"", 0)
			elif line.begins_with(DISPLAY_NAME):
				entry["display_name"] = line.trim_prefix(DISPLAY_NAME).trim_prefix("\"").trim_suffix("\"")
			elif line.begins_with(OBJECT_CATEGORY):
				entry["category"] = int(line.trim_prefix(OBJECT_CATEGORY))
			elif line.begins_with(COLOR_TEXTURE):
				entry["texture"] = String(resources.get(line.trim_prefix(COLOR_TEXTURE).trim_suffix(")").trim_prefix("\"").trim_suffix("\""), ""))
		found.append(entry)
	return found


func _fill() -> void:
	_list.clear()
	var search := _search.text.strip_edges().to_lower()
	var category := _category.get_selected_id()
	for index in range(entries.size()):
		var entry := entries[index]
		var label := String(entry.get("display_name", entry["name"]))
		if category >= 0 and int(entry["category"]) != category:
			continue
		if search != "" and not label.to_lower().contains(search) and not String(entry["name"]).contains(search):
			continue
		var item := _list.add_item(label)
		_list.set_item_metadata(item, index)
		_list.set_item_tooltip(item, "%s\n%s" % [entry["name"], CATEGORIES[int(entry["category"])] if int(entry["category"]) in range(CATEGORIES.size()) else ""])
		if String(entry["texture"]) != "":
			EditorInterface.get_resource_previewer().queue_resource_preview(String(entry["texture"]), self, &"_on_preview", item)


func _on_preview(_path: String, preview: Texture2D, _thumbnail: Texture2D, item: int) -> void:
	if preview != null and item < _list.item_count:
		_list.set_item_icon(item, preview)


func _drag_data(at_position: Vector2) -> Variant:
	var item := _list.get_item_at_position(at_position, true)
	if item < 0:
		return null
	var entry := entries[int(_list.get_item_metadata(item))]
	var icon := TextureRect.new()
	icon.texture = _list.get_item_icon(item)
	set_drag_preview(icon)
	return {"type": "files", "files": [entry["path"]], "from": self}


func _drop_into_map(item: int) -> void:
	var root := EditorInterface.get_edited_scene_root()
	var objects := root.get_node_or_null("World/Objects") if root != null else null
	if objects == null:
		push_warning("The edited scene has no World/Objects to drop the object into.")
		return
	var entry := entries[int(_list.get_item_metadata(item))]
	var node := (load(String(entry["path"])) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE) as Node2D
	var viewport := EditorInterface.get_editor_viewport_2d()
	node.position = objects.get_global_transform().affine_inverse() * (viewport.global_canvas_transform.affine_inverse() * (Vector2(viewport.size) * 0.5))
	var undo := EditorInterface.get_editor_undo_redo()
	undo.create_action("Drop %s into the map" % String(entry.get("display_name", entry["name"])))
	undo.add_do_method(objects, &"add_child", node, true)
	undo.add_do_property(node, &"owner", root)
	undo.add_do_reference(node)
	undo.add_undo_method(objects, &"remove_child", node)
	undo.commit_action()
	EditorInterface.edit_node(node)
