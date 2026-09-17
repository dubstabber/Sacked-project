@tool
class_name MapTileLayer
extends TileMapLayer


func _enter_tree() -> void:
	add_to_group("depth_world_tiles")
	set_notify_transform(true)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED or what == NOTIFICATION_VISIBILITY_CHANGED:
		changed.emit()
