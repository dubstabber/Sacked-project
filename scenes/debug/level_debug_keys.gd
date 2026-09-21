extends Node

# Debug-only shortcuts. A time game runs 360 seconds and an object only leaves IDLE through
# a prank, and neither is worth sitting through while checking that a level works.

const TIME_STEP_SECONDS := 30.0
const SCORE_STEP := 1000

var _session: Node


func _ready() -> void:
	if not OS.is_debug_build():
		queue_free()
		return
	# The session joins its group in _enter_tree, so it is already there for this child.
	_session = get_tree().get_first_node_in_group("level_session")


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_F5:
			if _session != null:
				_session.advance(TIME_STEP_SECONDS)
		KEY_F6:
			if _session != null:
				_session.add_score(SCORE_STEP)
		KEY_F7:
			_cycle_state_under_cursor()
		_:
			return
	get_viewport().set_input_as_handled()


# Steps the object under the cursor through the states it ships art for, so a transition can
# be watched before anything in the game is able to trigger one.
func _cycle_state_under_cursor() -> void:
	var target := _object_nearest_to_cursor()
	if target == null:
		return
	var states := _states_with_art(target)
	var next: int = states[(states.find(target.state) + 1) % states.size()]
	target.set_state(next)
	print("F7: %s -> %s" % [target.name, MapObject.STATE_NAMES[next]])


func _states_with_art(object: MapObject) -> Array[int]:
	var states: Array[int] = []
	for state in range(MapObject.STATE_NAMES.size()):
		if object.has_state(state):
			states.append(state)
	return states


func _object_nearest_to_cursor() -> MapObject:
	var viewport := get_viewport()
	var cursor: Vector2 = viewport.get_canvas_transform().affine_inverse() * viewport.get_mouse_position()
	var best: MapObject = null
	var best_distance := INF
	for node in get_tree().get_nodes_in_group("depth_world_objects"):
		var object := node as MapObject
		if object == null:
			continue
		var distance := object.global_position.distance_squared_to(cursor)
		if distance < best_distance:
			best_distance = distance
			best = object
	return best
