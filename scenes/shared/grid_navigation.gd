class_name GridNavigation
extends RefCounted


const COLLISION := preload("res://scenes/shared/grid_collision.gd")
const NEIGHBORS := [Vector2i.LEFT, Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN]
const MOTION_EPSILON := 0.00001


static func find_path(from: Vector2, to: Vector2, is_blocked: Callable, bounds: Rect2i) -> PackedVector2Array:
	var start := _cell_at(from)
	var goal := _cell_at(to)
	if not bounds.has_point(start) or not bounds.has_point(goal):
		return PackedVector2Array()
	if not _position_is_clear(from, is_blocked) or not _position_is_clear(to, is_blocked):
		return PackedVector2Array()
	if start == goal and _segment_is_clear(from, to, is_blocked):
		return PackedVector2Array([to])
	if not _segment_is_clear(from, Vector2(start), is_blocked):
		return PackedVector2Array()
	if not _segment_is_clear(Vector2(goal), to, is_blocked):
		return PackedVector2Array()

	var frontier: Array[Vector2i] = [start]
	var parents: Dictionary[Vector2i, Vector2i] = {start: start}
	while not frontier.is_empty():
		var best_index := 0
		var best_distance := (frontier[0] - goal).length_squared()
		for index in range(1, frontier.size()):
			var distance := (frontier[index] - goal).length_squared()
			if distance < best_distance:
				best_index = index
				best_distance = distance
		var current := frontier[best_index]
		frontier.remove_at(best_index)
		if current == goal:
			return _build_path(from, to, _reconstruct_cells(parents, start, goal), is_blocked, bounds)
		# Original free cells have zero cost; preserve heuristic ordering and stable ties.
		for direction: Vector2i in NEIGHBORS:
			var next := current + direction
			if not bounds.has_point(next) or parents.has(next) or is_blocked.call(next):
				continue
			if not _segment_is_clear(Vector2(current), Vector2(next), is_blocked):
				continue
			parents[next] = current
			frontier.append(next)
	return PackedVector2Array()


static func _reconstruct_cells(parents: Dictionary[Vector2i, Vector2i], start: Vector2i, goal: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = [goal]
	var current := goal
	while current != start:
		current = parents[current]
		cells.append(current)
	cells.reverse()
	return cells


static func _build_path(from: Vector2, to: Vector2, cells: Array[Vector2i], is_blocked: Callable, bounds: Rect2i) -> PackedVector2Array:
	var path := PackedVector2Array()
	if from != Vector2(cells[0]):
		path.append(Vector2(cells[0]))
	var index := 0
	while index + 1 < cells.size():
		var next_index := index + 1
		if index + 2 < cells.size() and _can_merge(cells[index], cells[index + 1], cells[index + 2], is_blocked, bounds):
			next_index = index + 2
		path.append(Vector2(cells[next_index]))
		index = next_index
	if path.is_empty() or path[-1] != to:
		path.append(to)
	var previous := from
	for point in path:
		if not _segment_is_clear(previous, point, is_blocked):
			return PackedVector2Array()
		previous = point
	return path


static func _can_merge(first: Vector2i, middle: Vector2i, last: Vector2i, is_blocked: Callable, bounds: Rect2i) -> bool:
	var first_step := middle - first
	var second_step := last - middle
	if absi(first_step.x + second_step.x) != 1 or absi(first_step.y + second_step.y) != 1:
		return false
	var other_corner := first + second_step
	if not bounds.has_point(other_corner) or is_blocked.call(middle) or is_blocked.call(other_corner):
		return false
	return _segment_is_clear(Vector2(first), Vector2(last), is_blocked)


static func _position_is_clear(position: Vector2, is_blocked: Callable) -> bool:
	var cell := _cell_at(position)
	var extent := 0.5 + COLLISION.HALF_EXTENT
	for y in range(cell.y - 1, cell.y + 2):
		for x in range(cell.x - 1, cell.x + 2):
			var neighbor := Vector2i(x, y)
			var distance := (position - Vector2(neighbor)).abs()
			if distance.x < extent and distance.y < extent and is_blocked.call(neighbor):
				return false
	return true


static func _segment_is_clear(from: Vector2, to: Vector2, is_blocked: Callable) -> bool:
	var motion := to - from
	return COLLISION.constrain_motion(from, motion, is_blocked).distance_to(motion) <= MOTION_EPSILON


static func _cell_at(position: Vector2) -> Vector2i:
	return Vector2i(floori(position.x + 0.5), floori(position.y + 0.5))
