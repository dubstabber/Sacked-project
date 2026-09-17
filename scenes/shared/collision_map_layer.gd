@tool
class_name CollisionMapLayer
extends TileMapLayer


const GRID_COLLISION := preload("res://scenes/shared/grid_collision.gd")

@export var show_in_game := false:
	set(value):
		show_in_game = value
		if is_inside_tree() and not Engine.is_editor_hint():
			visible = show_in_game


func _enter_tree() -> void:
	add_to_group("collision_maps")


func _ready() -> void:
	if not Engine.is_editor_hint():
		visible = show_in_game


func constrain_motion(from_global: Vector2, motion_global: Vector2) -> Vector2:
	if tile_set == null or not enabled:
		return motion_global
	var origin := map_to_local(Vector2i.ZERO)
	var tile_axes := Transform2D(
		map_to_local(Vector2i(1, 0)) - origin,
		map_to_local(Vector2i(0, 1)) - origin,
		origin
	)
	var to_grid := tile_axes.affine_inverse()
	var start := to_grid * to_local(from_global)
	var finish := to_grid * to_local(from_global + motion_global)
	var allowed: Vector2 = GRID_COLLISION.constrain_motion(start, finish - start, is_blocked)
	return to_global(tile_axes * (start + allowed)) - from_global


func is_blocked(cell: Vector2i) -> bool:
	return get_cell_source_id(cell) != -1


static func constrain_body_motion(body: CharacterBody2D, motion: Vector2) -> Vector2:
	for node in body.get_tree().get_nodes_in_group("collision_maps"):
		if node.get_parent().is_ancestor_of(body):
			motion = node.constrain_motion(body.global_position, motion)
	return motion
