@tool
class_name MapObject
extends Node2D


signal changed

@export var color_texture: Texture2D:
	set(value):
		color_texture = value
		_refresh_sprite()
@export var depth_texture: Texture2D:
	set(value):
		depth_texture = value
		changed.emit()
@export var pivot := Vector2.ZERO:
	set(value):
		pivot = value
		_refresh_sprite()


func _enter_tree() -> void:
	add_to_group("depth_world_objects")
	set_notify_transform(true)


func _ready() -> void:
	_refresh_sprite()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED or what == NOTIFICATION_VISIBILITY_CHANGED:
		changed.emit()


func _refresh_sprite() -> void:
	var sprite := get_node_or_null("Sprite2D") as Sprite2D
	if sprite != null:
		sprite.centered = false
		sprite.texture = color_texture
		sprite.offset = -pivot
	changed.emit()


func get_depth_actor() -> Dictionary:
	var sprite := get_node_or_null("Sprite2D") as Sprite2D
	if sprite == null or color_texture == null:
		return {}
	return {
		"node": self,
		"sprite": sprite,
		"color": color_texture,
		"depth": depth_texture,
		"position": sprite.to_global(sprite.offset),
		"size": Vector2i(color_texture.get_size()),
		# Original entity depth is half projected Y, rounded up after integer projection.
		"base_y": ceilf(float(int(global_position.y)) * 0.5),
	}
