@tool
class_name CollisionMapLayer
extends TileMapLayer


const GRID_COLLISION := preload("res://scenes/shared/grid_collision.gd")

@export var show_in_game := false:
	set(value):
		show_in_game = value
		if is_inside_tree() and not Engine.is_editor_hint():
			visible = show_in_game

# INFODATA bit 1, kept apart from the painted movement cells: a few cells block sight
# without blocking movement. Only the interaction ray reads it.
@export var sight_blocked_cells: PackedVector2Array = PackedVector2Array():
	set(value):
		sight_blocked_cells = value
		_sight_lookup.clear()
		for cell in value:
			_sight_lookup[Vector2i(cell)] = true

var _sight_lookup: Dictionary = {}


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


func is_sight_blocked(cell: Vector2i) -> bool:
	return _sight_lookup.has(cell)


func to_grid_position(global_point: Vector2) -> Vector2:
	var origin := map_to_local(Vector2i.ZERO)
	var tile_axes := Transform2D(
		map_to_local(Vector2i(1, 0)) - origin,
		map_to_local(Vector2i(0, 1)) - origin,
		origin
	)
	return tile_axes.affine_inverse() * to_local(global_point)


# Both ends are shifted to their cell centre and scaled to quarter cells, exactly as
# Main_RenderUpdate does before calling sub_412E30.
func has_line_of_sight(from_global: Vector2, to_global: Vector2) -> bool:
	var from_tile := (to_grid_position(from_global) + Vector2(0.5, 0.5)) * 4.0
	var to_tile := (to_grid_position(to_global) + Vector2(0.5, 0.5)) * 4.0
	return GRID_COLLISION.has_line_of_sight(Vector2i(from_tile), Vector2i(to_tile), is_sight_blocked)


static func line_of_sight_between(node: Node, from_global: Vector2, to_global: Vector2) -> bool:
	for layer in node.get_tree().get_nodes_in_group("collision_maps"):
		if layer.get_parent().is_ancestor_of(node) and layer.has_method("has_line_of_sight"):
			return layer.has_line_of_sight(from_global, to_global)
	return true


static func constrain_body_motion(body: CharacterBody2D, motion: Vector2) -> Vector2:
	for node in body.get_tree().get_nodes_in_group("collision_maps"):
		if node.get_parent().is_ancestor_of(body):
			motion = node.constrain_motion(body.global_position, motion)
	return motion
