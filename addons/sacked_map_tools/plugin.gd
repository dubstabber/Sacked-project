@tool
extends EditorPlugin

# Adds the object palette (object_palette.gd) to the editor's left dock.

const ObjectPalette := preload("res://addons/sacked_map_tools/object_palette.gd")

var _palette: Control


func _enter_tree() -> void:
	_palette = ObjectPalette.new()
	_palette.name = "Objects"
	add_control_to_dock(DOCK_SLOT_LEFT_UR, _palette)


func _exit_tree() -> void:
	if _palette != null:
		remove_control_from_docks(_palette)
		_palette.queue_free()
		_palette = null
