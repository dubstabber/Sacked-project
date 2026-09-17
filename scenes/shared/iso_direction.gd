class_name IsoDirection
extends RefCounted


static func ground_to_screen(direction: Vector2) -> Vector2:
	return Vector2(48.0 * (direction.x - direction.y), 24.0 * (direction.x + direction.y))


static func screen_to_ground(direction: Vector2) -> Vector2:
	return Vector2(direction.x / 96.0 + direction.y / 48.0, -direction.x / 96.0 + direction.y / 48.0)


static func screen_velocity(direction: Vector2, tiles_per_second: float) -> Vector2:
	# Original movement is normalized before projection; see docs/npc-reference.md.
	return ground_to_screen(screen_to_ground(direction).normalized() * tiles_per_second)


static func snap_to_8_directions(direction: Vector2) -> Vector2:
	var directions := get_screen_directions()
	var best: Vector2 = directions[0]
	var best_dot := direction.dot(best)
	for i in range(1, directions.size()):
		var candidate: Vector2 = directions[i]
		var candidate_dot := direction.dot(candidate)
		if candidate_dot > best_dot:
			best_dot = candidate_dot
			best = candidate
	return best


static func get_screen_directions() -> Array[Vector2]:
	# Sprite suffix _NNN encodes world axes projected onto the 96x48 grid.
	return [
		Vector2(48.0, -24.0).normalized(),  # iso N  -> suffix _000 / "up-right"
		Vector2(96.0, 0.0).normalized(),    # iso NE -> suffix _045 / "right"
		Vector2(48.0, 24.0).normalized(),   # iso E  -> suffix _090 / "down-right"
		Vector2(0.0, 48.0).normalized(),    # iso SE -> suffix _135 / "down"
		Vector2(-48.0, 24.0).normalized(),  # iso S  -> suffix _180 / "down-left"
		Vector2(-96.0, 0.0).normalized(),   # iso SW -> suffix _225 / "left"
		Vector2(-48.0, -24.0).normalized(), # iso W  -> suffix _270 / "up-left"
		Vector2(0.0, -48.0).normalized(),   # iso NW -> suffix _315 / "up"
	]
