extends SceneTree


const NAVIGATION := preload("res://scenes/shared/grid_navigation.gd")
const COLLISION := preload("res://scenes/shared/grid_collision.gd")

var _failures := 0


func _init() -> void:
	_check_gap_and_detour()
	_check_unreachable_and_bounds()
	_check_corner_merging()
	_check_fractional_endpoints()
	_check_negative_coordinates_and_determinism()
	if _failures == 0:
		print("Grid navigation: detours, gaps, unreachable goals, corners, fractional endpoints, bounds and deterministic clearance passed")
	quit(1 if _failures else 0)


func _check_gap_and_detour() -> void:
	var blocked := {Vector2i(2, 0): true, Vector2i(2, 1): true, Vector2i(2, 2): true, Vector2i(2, 4): true}
	var start := Vector2(0, 1)
	var goal := Vector2(4, 1)
	var bounds := Rect2i(0, 0, 5, 5)
	var path := NAVIGATION.find_path(start, goal, _is_blocked.bind(blocked), bounds)
	_expect(not path.is_empty(), "a wall gap can be reached by a detour")
	_expect(path.has(Vector2(2, 3)), "the route crosses the actual one-cell doorway")
	_check_path(path, start, goal, blocked, bounds, "wall gap")


func _check_unreachable_and_bounds() -> void:
	var blocked := {}
	for y in range(-2, 3):
		blocked[Vector2i(2, y)] = true
	var bounds := Rect2i(-1, -2, 6, 5)
	_expect(NAVIGATION.find_path(Vector2.ZERO, Vector2(4, 0), _is_blocked.bind(blocked), bounds).is_empty(), "a separating wall is unreachable within the supplied bounds")
	_expect(NAVIGATION.find_path(Vector2(2, 0), Vector2.ZERO, _is_blocked.bind(blocked), bounds).is_empty(), "a blocked starting cell is rejected")
	_expect(NAVIGATION.find_path(Vector2.ZERO, Vector2(2, 0), _is_blocked.bind(blocked), bounds).is_empty(), "a blocked destination is rejected")
	_expect(NAVIGATION.find_path(Vector2(-2, 0), Vector2.ZERO, _is_blocked.bind(blocked), bounds).is_empty(), "an out-of-bounds start is rejected")
	_expect(NAVIGATION.find_path(Vector2.ZERO, Vector2(5, 0), _is_blocked.bind(blocked), bounds).is_empty(), "the exclusive bounds end is rejected")
	_expect(NAVIGATION.find_path(Vector2.ZERO, Vector2.ZERO, _is_blocked.bind(blocked), Rect2i()).is_empty(), "an empty search area is rejected")


func _check_corner_merging() -> void:
	var bounds := Rect2i(0, 0, 3, 3)
	var empty := {}
	var diagonal := NAVIGATION.find_path(Vector2.ZERO, Vector2(2, 2), _is_blocked.bind(empty), bounds)
	_expect(diagonal == PackedVector2Array([Vector2(1, 1), Vector2(2, 2)]), "eligible cardinal pairs merge into diagonals")
	_check_path(diagonal, Vector2.ZERO, Vector2(2, 2), empty, bounds, "merged diagonal")
	var one_corner := {Vector2i(1, 0): true}
	var detour := NAVIGATION.find_path(Vector2.ZERO, Vector2.ONE, _is_blocked.bind(one_corner), bounds)
	_expect(detour == PackedVector2Array([Vector2(0, 1), Vector2.ONE]), "one blocked orthogonal neighbor prevents a diagonal merge")
	_check_path(detour, Vector2.ZERO, Vector2.ONE, one_corner, bounds, "single corner")
	var two_corners := {Vector2i(1, 0): true, Vector2i(0, 1): true}
	_expect(NAVIGATION.find_path(Vector2.ZERO, Vector2.ONE, _is_blocked.bind(two_corners), bounds).is_empty(), "a diagonal cannot cross between two touching blockers")


func _check_fractional_endpoints() -> void:
	var bounds := Rect2i(-2, -2, 7, 7)
	var blocked := {Vector2i(2, 0): true}
	var start := Vector2(-0.23, 0.17)
	var goal := Vector2(0.12, 1.23)
	var path := NAVIGATION.find_path(start, goal, _is_blocked.bind(blocked), bounds)
	_check_path(path, start, goal, blocked, bounds, "fractional endpoints")
	_expect(NAVIGATION.find_path(Vector2.ZERO, Vector2(1.2, 0), _is_blocked.bind(blocked), bounds).is_empty(), "a fractional goal whose feet overlap an adjacent wall is rejected")
	_expect(NAVIGATION.find_path(Vector2(1.2, 0), Vector2.ZERO, _is_blocked.bind(blocked), bounds).is_empty(), "an overlapping fractional start is rejected")
	var nearby := NAVIGATION.find_path(Vector2.ZERO, Vector2(0.1, 0.1), _is_blocked.bind(blocked), bounds)
	_expect(nearby == PackedVector2Array([Vector2(0.1, 0.1)]), "a clear goal in the same cell stays exact")
	_expect(NAVIGATION.find_path(Vector2.ZERO, Vector2.ZERO, _is_blocked.bind(blocked), bounds) == PackedVector2Array([Vector2.ZERO]), "already at the goal is a reachable zero-length route")
	var corner := {Vector2i.ONE: true}
	var from_corner := Vector2(0.4, 0.1)
	var to_corner := Vector2(0.1, 0.4)
	var around_corner := NAVIGATION.find_path(from_corner, to_corner, _is_blocked.bind(corner), bounds)
	_expect(around_corner == PackedVector2Array([Vector2.ZERO, to_corner]), "fractional points in one cell detour through its center when a direct segment clips a corner")
	_check_path(around_corner, from_corner, to_corner, corner, bounds, "fractional corner")


func _check_negative_coordinates_and_determinism() -> void:
	var bounds := Rect2i(-4, -4, 8, 8)
	var negative_blockers := {Vector2i(-2, -1): true}
	var start := Vector2(-3.2, -1.1)
	var goal := Vector2(-0.8, -0.7)
	var path := NAVIGATION.find_path(start, goal, _is_blocked.bind(negative_blockers), bounds)
	_check_path(path, start, goal, negative_blockers, bounds, "negative coordinates")
	var symmetric := {Vector2i(1, 0): true}
	var expected := NAVIGATION.find_path(Vector2.ZERO, Vector2(2, 0), _is_blocked.bind(symmetric), bounds)
	_expect(not expected.is_empty() and expected[0] == Vector2.UP, "equal heuristic scores use stable left, up, right, down expansion order")
	for iteration in range(10):
		_expect(NAVIGATION.find_path(Vector2.ZERO, Vector2(2, 0), _is_blocked.bind(symmetric), bounds) == expected, "repeated queries return the identical route")
	_check_path(expected, Vector2.ZERO, Vector2(2, 0), symmetric, bounds, "stable detour")


func _check_path(path: PackedVector2Array, start: Vector2, goal: Vector2, blocked: Dictionary, bounds: Rect2i, label: String) -> void:
	_expect(not path.is_empty(), "%s is reachable" % label)
	if path.is_empty():
		return
	_expect(path[-1] == goal, "%s ends at the exact requested position" % label)
	_expect(not path.has(start), "%s omits the original start" % label)
	var previous := start
	for point in path:
		_expect(bounds.has_point(Vector2i(floori(point.x + 0.5), floori(point.y + 0.5))), "%s stays inside its search area" % label)
		var motion := point - previous
		_expect(COLLISION.constrain_motion(previous, motion, _is_blocked.bind(blocked)).distance_to(motion) <= 0.00001, "%s segment is unchanged by physical collision" % label)
		for sample in range(65):
			var position := previous.lerp(point, float(sample) / 64.0)
			for cell: Vector2i in blocked:
				var distance := (position - Vector2(cell)).abs()
				_expect(distance.x >= 0.85 or distance.y >= 0.85, "%s keeps its entire feet clear throughout each segment" % label)
		previous = point


func _is_blocked(cell: Vector2i, blocked: Dictionary) -> bool:
	return blocked.has(cell)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
