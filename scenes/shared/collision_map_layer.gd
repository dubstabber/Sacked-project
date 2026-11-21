@tool
class_name CollisionMapLayer
extends TileMapLayer


const GRID_COLLISION := preload("res://scenes/shared/grid_collision.gd")

@export var show_in_game := false:
	set(value):
		show_in_game = value
		if is_inside_tree() and not Engine.is_editor_hint():
			visible = show_in_game

# The rest of a cell's INFODATA is painted on two sibling layers (OverlayMapLayer) of these
# names: the rooms, bits 16-23, as the alternative tile of the one room diamond, and the cells
# that block sight, bit 1. A few cells block sight without blocking movement, so they cannot
# share this layer, where any tile blocks movement.
const ROOM_LAYER := "RoomTileMapLayer"
const SIGHT_LAYER := "SightTileMapLayer"

# The map's size in cells, which bounds the rooms, the sight grid and the field of view the way
# the original's INFODATA covers its whole map; a cell off it is room 0 and blocks no sight.
# Left at zero it is the floor's painted extent.
@export var map_size := Vector2i.ZERO:
	set(value):
		map_size = value
		_painted_rooms = PackedByteArray()

# INFODATA bit 1. The interaction ray and the field-of-view mask read it. Assigned, as a test's
# hand-built map does, the list stands in for the painted layer.
var sight_blocked_cells: PackedVector2Array:
	get:
		return _sight_override if _sight_overridden else _painted_sight_cells()
	set(value):
		_sight_override = value
		_sight_overridden = true
		_sight_lookup.clear()
		for cell in value:
			_sight_lookup[Vector2i(cell)] = true

# INFODATA bits 16-23, the room each cell belongs to, row by row (x + width * z) as the
# importer reads collision_grid.room_ids. sub_412AE0 mode 4 answers it at run time; see
# docs/collision-reference.md and docs/player-ability-reference.md. Assigned, both stand in for
# the painted room layer and the map's size.
var room_ids: PackedByteArray:
	get:
		return _rooms_override if _rooms_overridden else _painted_room_ids()
	set(value):
		_rooms_override = value
		_rooms_overridden = true
var room_grid_size: Vector2i:
	get:
		if _grid_size_override != Vector2i.ZERO:
			return _grid_size_override
		return map_size if map_size != Vector2i.ZERO else _painted_extent()
	set(value):
		_grid_size_override = value

var _sight_override := PackedVector2Array()
var _sight_overridden := false
var _sight_lookup: Dictionary = {}
var _rooms_override := PackedByteArray()
var _rooms_overridden := false
var _grid_size_override := Vector2i.ZERO
# The painted rooms as the flat grid, rebuilt when the room layer changes.
var _painted_rooms := PackedByteArray()


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
	if _sight_overridden:
		return _sight_lookup.has(cell)
	var layer := _overlay(SIGHT_LAYER)
	return layer != null and layer.get_cell_source_id(cell) != -1


# The same cells as a row-major byte grid over the map's width and height, nonzero where a cell
# blocks sight, which is how the field-of-view walk (sub_428BC0) reads the map.
func sight_grid() -> PackedByteArray:
	var size := room_grid_size
	var grid := PackedByteArray()
	grid.resize(size.x * size.y)
	for cell in sight_blocked_cells:
		if cell.x >= 0.0 and cell.y >= 0.0 and cell.x < size.x and cell.y < size.y:
			grid[int(cell.y) * size.x + int(cell.x)] = 1
	return grid


# The painted sight blockers in the importer's order, row by row.
func _painted_sight_cells() -> PackedVector2Array:
	var layer := _overlay(SIGHT_LAYER)
	if layer == null:
		return PackedVector2Array()
	var cells := layer.get_used_cells()
	cells.sort_custom(func(a: Vector2i, b: Vector2i): return a.y < b.y or (a.y == b.y and a.x < b.x))
	var points := PackedVector2Array()
	for cell in cells:
		points.append(Vector2(cell))
	return points


func _painted_room_ids() -> PackedByteArray:
	var size := room_grid_size
	if _painted_rooms.size() == size.x * size.y and not _painted_rooms.is_empty():
		return _painted_rooms
	var rooms := PackedByteArray()
	rooms.resize(size.x * size.y)
	var layer := _overlay(ROOM_LAYER)
	if layer != null:
		for cell in layer.get_used_cells():
			if cell.x >= 0 and cell.y >= 0 and cell.x < size.x and cell.y < size.y:
				rooms[cell.y * size.x + cell.x] = layer.get_cell_alternative_tile(cell)
	_painted_rooms = rooms
	return rooms


# The floor's painted cells, from the origin to the farthest one, for a map with no map_size.
func _painted_extent() -> Vector2i:
	var floor_layer := get_parent().get_node_or_null("FloorTileMapLayer") as TileMapLayer if get_parent() != null else null
	var used := floor_layer.get_used_rect() if floor_layer != null else get_used_rect()
	return Vector2i(maxi(used.end.x, 0), maxi(used.end.y, 0))


func _overlay(layer_name: String) -> TileMapLayer:
	var parent := get_parent()
	var layer := parent.get_node_or_null(layer_name) as TileMapLayer if parent != null else null
	if layer != null and layer_name == ROOM_LAYER and not layer.changed.is_connected(_on_rooms_changed):
		layer.changed.connect(_on_rooms_changed)
	return layer


func _on_rooms_changed() -> void:
	_painted_rooms = PackedByteArray()


func to_grid_position(global_point: Vector2) -> Vector2:
	var origin := map_to_local(Vector2i.ZERO)
	var tile_axes := Transform2D(
		map_to_local(Vector2i(1, 0)) - origin,
		map_to_local(Vector2i(0, 1)) - origin,
		origin
	)
	return tile_axes.affine_inverse() * to_local(global_point)


func from_grid_position(tile: Vector2) -> Vector2:
	var origin := map_to_local(Vector2i.ZERO)
	var tile_axes := Transform2D(
		map_to_local(Vector2i(1, 0)) - origin,
		map_to_local(Vector2i(0, 1)) - origin,
		origin
	)
	return to_global(tile_axes * tile)


# sub_412AE0(int(x + 0.5), int(z + 0.5), 4), which the lamps' abilities ask about the
# player's position (0x41BCA5-0x41BCDF, 0x4652B4). int() truncates toward zero as ftol does,
# so -0.9 still lands on column 0; a cell off the grid answers 0.
func room_category(tile: Vector2) -> int:
	var cell := Vector2i(int(tile.x + 0.5), int(tile.y + 0.5))
	if cell.x < 0 or cell.y < 0 or cell.x >= room_grid_size.x or cell.y >= room_grid_size.y:
		return 0
	var index := cell.y * room_grid_size.x + cell.x
	return int(room_ids[index]) if index < room_ids.size() else 0


func room_category_at(global_point: Vector2) -> int:
	return room_category(to_grid_position(global_point))


# Both ends are shifted to their cell centre and scaled to quarter cells, exactly as
# Main_RenderUpdate does before calling sub_412E30.
func has_line_of_sight(from_global: Vector2, to_global: Vector2) -> bool:
	var from_tile := (to_grid_position(from_global) + Vector2(0.5, 0.5)) * 4.0
	var to_tile := (to_grid_position(to_global) + Vector2(0.5, 0.5)) * 4.0
	return GRID_COLLISION.has_line_of_sight(Vector2i(from_tile), Vector2i(to_tile), is_sight_blocked)


# The map of the level `node` stands in: the first enabled layer whose parent holds it.
static func of(node: Node) -> CollisionMapLayer:
	if node == null or not node.is_inside_tree():
		return null
	for layer in node.get_tree().get_nodes_in_group("collision_maps"):
		if layer is CollisionMapLayer and layer.enabled and layer.get_parent().is_ancestor_of(node):
			return layer
	return null


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
