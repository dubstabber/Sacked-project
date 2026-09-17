extends SceneTree


const SOLVER := preload("res://scenes/shared/grid_collision.gd")
const EPSILON := 0.00001
const RANDOM_CASES := 200
const DIRECTIONS := [
	Vector2(1, 0), Vector2(1, 1), Vector2(0, 1), Vector2(-1, 1),
	Vector2(-1, 0), Vector2(-1, -1), Vector2(0, -1), Vector2(1, -1),
]
const OBSTACLES := [
	Vector2i(2, 0), Vector2i(2, 1), Vector2i(2, 2),
	Vector2i(-1, -1), Vector2i(0, -1), Vector2i(-1, 0),
]

var _failures := 0
var _blocked: Dictionary = {}


func _init() -> void:
	_check_clearance_and_sliding()
	_set_obstacles()
	_check_shallow_approach()
	_check_adjacent_obstacle_corner()
	_check_random_sweeps(false)
	_check_random_sweeps(true)
	if _failures == 0:
		print("Grid collision: original clearance, sliding, shallow approach and 400 deterministic motion cases passed")
	quit(1 if _failures else 0)


func _check_clearance_and_sliding() -> void:
	for y in range(-10, 11):
		_blocked[Vector2i(2, y)] = true
	_expect_vector(SOLVER.constrain_motion(Vector2.ZERO, Vector2.ZERO, _is_blocked), Vector2.ZERO, "zero motion stays still")
	_expect_vector(SOLVER.constrain_motion(Vector2.ZERO, Vector2(4, 0), _is_blocked), Vector2(1.14, 0), "original 0.36 clearance from the near wall face")
	_expect_vector(SOLVER.constrain_motion(Vector2(4, 0), Vector2(-4, 0), _is_blocked), Vector2(-1.14, 0), "original clearance from the opposite wall face")
	_expect_vector(SOLVER.constrain_motion(Vector2.ZERO, Vector2(3, 1), _is_blocked), Vector2(1.14, 1), "the unobstructed logical axis keeps its requested movement")
	_expect_vector(SOLVER.constrain_motion(Vector2.ZERO, Vector2(0, -4), _is_blocked), Vector2(0, -4), "a clear route preserves its complete motion")


func _set_obstacles() -> void:
	_blocked.clear()
	for cell in OBSTACLES:
		_blocked[cell] = true


func _check_shallow_approach() -> void:
	var start := Vector2(0.918382, -0.397224)
	var motion := Vector2(0.271305, 2.181145)
	var end: Vector2 = start + SOLVER.constrain_motion(start, motion, _is_blocked)
	_expect(_has_clear_footprint(end), "the shallow approach cannot penetrate the furniture column: %s" % end)
	_expect(end.x <= 1.15 + EPSILON, "the shallow approach stops before the column")
	_expect(absf(end.y - (start.y + motion.y)) <= EPSILON, "the shallow approach preserves movement along the column")


func _check_adjacent_obstacle_corner() -> void:
	var start := Vector2(-2.362084, -3.862952)
	var motion := Vector2(2.057784, 2.057784)
	var end: Vector2 = start + SOLVER.constrain_motion(start, motion, _is_blocked)
	_expect(_has_clear_footprint(end), "a diagonal corner correction cannot push into an adjacent obstacle: %s" % end)


func _check_random_sweeps(arbitrary_angles: bool) -> void:
	var random := RandomNumberGenerator.new()
	random.seed = 1037
	var case_count := 0
	while case_count < RANDOM_CASES:
		var start := Vector2(random.randf_range(-4.0, 4.0), random.randf_range(-4.0, 4.0))
		if not _has_clear_footprint(start):
			continue
		var motion: Vector2
		if arbitrary_angles:
			motion = Vector2(random.randf_range(-6.0, 6.0), random.randf_range(-6.0, 6.0))
		else:
			motion = DIRECTIONS[random.randi_range(0, DIRECTIONS.size() - 1)] * random.randf_range(0.0, 6.0)
		var label := "%s case %d from %s toward %s" % ["arbitrary" if arbitrary_angles else "eight-direction", case_count, start, motion]
		var end: Vector2 = start + SOLVER.constrain_motion(start, motion, _is_blocked)
		_expect(_has_clear_footprint(end), "%s leaves the entire footprint clear: %s" % [label, end])
		var position := start
		for frame in range(12):
			position += SOLVER.constrain_motion(position, motion / 12.0, _is_blocked)
			_expect(_has_clear_footprint(position), "%s stays clear during frame %d: %s" % [label, frame, position])
		case_count += 1


func _has_clear_footprint(position: Vector2) -> bool:
	# Independent geometry oracle: each half-tile obstacle is expanded by the 0.35-tile feet.
	for cell in _blocked:
		var distance: Vector2 = (position - Vector2(cell)).abs()
		if distance.x < 0.85 - EPSILON and distance.y < 0.85 - EPSILON:
			return false
	return true


func _is_blocked(cell: Vector2i) -> bool:
	return _blocked.has(cell)


func _expect_vector(actual: Vector2, expected: Vector2, label: String) -> void:
	_expect(actual.distance_to(expected) <= EPSILON, "%s: expected %s, got %s" % [label, expected, actual])


func _expect(condition: bool, label: String) -> void:
	if not condition:
		_failures += 1
		push_error(label)
