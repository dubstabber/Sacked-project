class_name GridCollision
extends RefCounted


# Original collision pass at 0x4019D0; see docs/collision-reference.md.
const HALF_EXTENT := 0.35
const CONTACT_CLEARANCE := 0.36
# Keep long frames within a cell neighborhood before applying the original correction.
const MAX_STEP := 0.25


static func constrain_motion(from: Vector2, motion: Vector2, is_blocked: Callable) -> Vector2:
	if motion == Vector2.ZERO:
		return Vector2.ZERO
	var step_count := maxi(1, ceili(maxf(absf(motion.x), absf(motion.y)) / MAX_STEP))
	var step := motion / float(step_count)
	var position := from
	var original_direction := motion.x == 0.0 or motion.y == 0.0 or absf(motion.x) == absf(motion.y)
	for _index in range(step_count):
		if original_direction:
			var resolved := _constrain_step(position, position + step, is_blocked)
			if _overlaps_blocker(resolved, is_blocked):
				resolved = _constrain_swept_step(position, step, is_blocked)
			position = resolved
		else:
			position = _constrain_swept_step(position, step, is_blocked)
	return position - from


static func _overlaps_blocker(position: Vector2, is_blocked: Callable) -> bool:
	var center := Vector2i(floori(position.x + 0.5), floori(position.y + 0.5))
	var extent := 0.5 + HALF_EXTENT
	for y in range(center.y - 1, center.y + 2):
		for x in range(center.x - 1, center.x + 2):
			var cell := Vector2i(x, y)
			var distance := (position - Vector2(cell)).abs()
			if distance.x < extent and distance.y < extent and is_blocked.call(cell):
				return true
	return false


static func _constrain_swept_step(from: Vector2, motion: Vector2, is_blocked: Callable) -> Vector2:
	# The original side-line tests assume eight directions; sweep the same footprint for other angles.
	var position := from
	var remaining := motion
	for _axis in range(2):
		if remaining == Vector2.ZERO:
			break
		var end := position + remaining
		var first := Vector2i(floori(minf(position.x, end.x) + 0.5), floori(minf(position.y, end.y) + 0.5)) - Vector2i.ONE
		var last := Vector2i(floori(maxf(position.x, end.x) + 0.5), floori(maxf(position.y, end.y) + 0.5)) + Vector2i.ONE
		var hit := Vector3(INF, 0.0, 0.0)
		for y in range(first.y, last.y + 1):
			for x in range(first.x, last.x + 1):
				var cell := Vector2i(x, y)
				if not is_blocked.call(cell):
					continue
				var candidate := _sweep_cell(position, remaining, cell)
				if candidate.x < hit.x:
					hit = candidate
		if is_inf(hit.x):
			return position + remaining
		position += remaining * hit.x
		var axis := int(hit.y)
		position[axis] -= hit.z * (CONTACT_CLEARANCE - HALF_EXTENT)
		remaining *= 1.0 - hit.x
		remaining[axis] = 0.0
	return position + remaining


static func _sweep_cell(from: Vector2, motion: Vector2, cell: Vector2i) -> Vector3:
	var extent := 0.5 + HALF_EXTENT
	var low := Vector2(cell) - Vector2(extent, extent)
	var high := Vector2(cell) + Vector2(extent, extent)
	var entry := -INF
	var exit_time := INF
	var hit_axis := 0
	for axis in range(2):
		if motion[axis] == 0.0:
			if from[axis] <= low[axis] or from[axis] >= high[axis]:
				return Vector3(INF, 0.0, 0.0)
			continue
		var first := (low[axis] - from[axis]) / motion[axis]
		var last := (high[axis] - from[axis]) / motion[axis]
		var near_time := minf(first, last)
		var far_time := maxf(first, last)
		if near_time >= entry:
			entry = near_time
			hit_axis = axis
		exit_time = minf(exit_time, far_time)
	if entry < 0.0 or entry > 1.0 or entry >= exit_time:
		return Vector3(INF, 0.0, 0.0)
	return Vector3(entry, float(hit_axis), signf(motion[hit_axis]))


static func _constrain_step(from: Vector2, to: Vector2, is_blocked: Callable) -> Vector2:
	var start := from + Vector2(0.5, 0.5)
	var target := to + Vector2(0.5, 0.5)
	var cell := Vector2i(floori(start.x), floori(start.y))
	var end_cell := Vector2i(floori(target.x), floori(target.y))
	var distance := (end_cell - cell).abs()
	var direction := Vector2i(1 if cell.x <= end_cell.x else -1, 1 if cell.y <= end_cell.y else -1)
	var error := 2 * mini(distance.x, distance.y) - maxi(distance.x, distance.y)
	while true:
		target = _resolve_cell(start, target, cell, is_blocked)
		if cell == end_cell:
			break
		if distance.x >= distance.y:
			cell.x += direction.x
			if error > 0:
				cell.y += direction.y
				error -= 2 * distance.x
			error += 2 * distance.y
		else:
			cell.y += direction.y
			if error > 0:
				cell.x += direction.x
				error -= 2 * distance.y
			error += 2 * distance.x
	return target - Vector2(0.5, 0.5)


static func _resolve_cell(from: Vector2, to: Vector2, cell: Vector2i, is_blocked: Callable) -> Vector2:
	var mask := 0
	for row in range(3):
		for column in range(3):
			if is_blocked.call(cell + Vector2i(column - 1, row - 1)):
				mask |= 1 << (row * 3 + column)
	if mask == 0:
		return to

	var left := float(cell.x)
	var top := float(cell.y)
	var right := left + 1.0
	var bottom := top + 1.0
	var motion := to - from
	var crosses_top := false
	var crosses_bottom := false
	var crosses_left := false
	var crosses_right := false
	if motion.y != 0.0:
		var top_x := from.x + motion.x * (top - from.y) / motion.y
		var bottom_x := from.x + motion.x * (bottom - from.y) / motion.y
		crosses_top = top_x >= left - HALF_EXTENT and top_x <= right + HALF_EXTENT
		crosses_bottom = bottom_x >= left - HALF_EXTENT and bottom_x <= right + HALF_EXTENT
	if motion.x != 0.0:
		var left_y := from.y + motion.y * (left - from.x) / motion.x
		var right_y := from.y + motion.y * (right - from.x) / motion.x
		crosses_left = left_y >= top - HALF_EXTENT and left_y <= bottom + HALF_EXTENT
		crosses_right = right_y >= top - HALF_EXTENT and right_y <= bottom + HALF_EXTENT

	if mask & 2 and to.y < top + HALF_EXTENT and crosses_top:
		to.y = top + CONTACT_CLEARANCE
	if mask & 128 and to.y > bottom - HALF_EXTENT and crosses_bottom:
		to.y = bottom - CONTACT_CLEARANCE
	if mask & 8 and to.x < left + HALF_EXTENT and crosses_left:
		to.x = left + CONTACT_CLEARANCE
	if mask & 32 and to.x > right - HALF_EXTENT and crosses_right:
		to.x = right - CONTACT_CLEARANCE
	if mask & 1 and to.y < top + HALF_EXTENT and to.x < left + HALF_EXTENT:
		if crosses_top:
			to.y = top + CONTACT_CLEARANCE
		elif crosses_left:
			to.x = left + CONTACT_CLEARANCE
	if mask & 4 and to.y < top + HALF_EXTENT and to.x > right - HALF_EXTENT:
		if crosses_top:
			to.y = top + CONTACT_CLEARANCE
		elif crosses_right:
			to.x = right - CONTACT_CLEARANCE
	if mask & 64 and to.y > bottom - HALF_EXTENT and to.x < left + HALF_EXTENT:
		if crosses_bottom:
			to.y = bottom - CONTACT_CLEARANCE
		elif crosses_left:
			to.x = left + CONTACT_CLEARANCE
	if mask & 256 and to.y > bottom - HALF_EXTENT and to.x > right - HALF_EXTENT:
		if crosses_bottom:
			to.y = bottom - CONTACT_CLEARANCE
		elif crosses_right:
			to.x = right - CONTACT_CLEARANCE
	return to
