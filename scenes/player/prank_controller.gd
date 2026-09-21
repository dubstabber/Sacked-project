extends Node

# Which object the cursor is over, whether the player may act on it, and carrying the chosen
# action out. Recovered in docs/player-action-reference.md: the focus item is picked by
# bounding box under the cursor, and an action needs a non-empty menu, a gap of at most
# MAX_ACTION_RANGE tiles to the item's interaction position, and a clear sight ray. The
# player never walks to an object.

const HIGHLIGHT_SHADER := preload("res://scenes/shared/object_highlight.gdshader")

const MAX_ACTION_RANGE := 2.0
# item+4..6 while the cursor is over it.
const TINT_READY := Color(1.0, 1.0, 1.0)
const TINT_OUT_OF_REACH := Color(1.0, 1.0, 50.0 / 255.0)
const TINT_NO_ACTION := Color(1.0, 50.0 / 255.0, 50.0 / 255.0)
# sub_42D200(120 - sin(phase * 2.5) * -80) -- the pulse the highlight is drawn with.
const PULSE_CENTRE := 120.0 / 255.0
const PULSE_SWING := 80.0 / 255.0
const PULSE_RATE := 2.5
# sub_41A510 maps a record's animation selector (+0x18) to a slot in the player's animation
# table at 0x46EC04. Only the clips level 1 can reach are imported; see
# tools/character_action_clips.json and docs/player-action-reference.md.
const SELECTOR_CLIPS := {
	0: "stand-use", 1: "knee-use", 2: "kick", 3: "punch",
	6: "steal", 7: "drink", 8: "ketchup", 9: "phone-type", 12: "piss-2",
}
# Selector 12 picks its facing at random from the three views its clip ships.
const PISS_FACINGS := {
	"jobless": [Vector2(1, 0), Vector2(0, -1), Vector2(1, -1)],
	"anne": [Vector2(0, 1), Vector2(-1, 1), Vector2(-1, 0)],
}
# +0x40 values that are markers rather than states.
const STATE_KEEP := 17
const STATE_IN_USE := 18

enum State { FREE, MENU, ACTING }

signal focus_changed(point: Node)
signal menu_opened(entries: Array)
signal menu_closed()
signal highlight_changed(entry: Dictionary)
signal progress_changed(elapsed: float, total: float)
signal action_started(action: Dictionary, point: Node)
signal action_applied(action: Dictionary, point: Node)
signal inventory_changed(inventory: PackedInt32Array)

# player+912 and the four menu arrays behind it.
var focus_point: Node = null
var entries: Array = []
var highlighted := -1
var menu_open := false
var state: State = State.FREE
# player+1008, one count per item id.
var inventory: PackedInt32Array = PackedInt32Array()

var _player: Node2D
var _hovered: Node2D
var _highlight: Sprite2D
var _highlight_material: ShaderMaterial
var _world_mask: Node2D
var _environment_revision := -1
var _acting_point: Node
var _acting_entry: Dictionary = {}
var _elapsed := 0.0
var _duration := 0.0


func _enter_tree() -> void:
	add_to_group("player_actions")


func _ready() -> void:
	_player = get_parent() as Node2D
	# sub_41AF60 clears 0x1C bytes: the player starts every level holding nothing.
	inventory.resize(28)


func _process(delta: float) -> void:
	if state == State.ACTING:
		_advance_action(delta)
		return
	if state == State.FREE:
		_update_hover()


func _unhandled_input(event: InputEvent) -> void:
	if state == State.ACTING:
		return
	if menu_open:
		if event.is_action_pressed("interact"):
			confirm()
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("ui_cancel") or event.is_action_pressed("mouse-movement"):
			close_menu()
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("interact") and focus_point != null:
		open_menu()
		get_viewport().set_input_as_handled()


func open_menu() -> void:
	if menu_open or focus_point == null or entries.is_empty():
		return
	menu_open = true
	state = State.MENU
	highlighted = 0
	menu_opened.emit(entries)
	highlight_changed.emit(entries[0])


# sub_41B240 clears player+920 in its case 4 and its case 5 -- when the action applies, and
# when it is cancelled -- never when the ring itself shuts. So committing leaves the chosen
# action's icon and name on the console for as long as it runs, and only the tick that is
# not an action session (sub_41B0C0) puts the hover bar back to "...".
func close_menu(keep_selection := false) -> void:
	if not menu_open:
		return
	menu_open = false
	if state == State.MENU:
		state = State.FREE
	menu_closed.emit()
	if not keep_selection:
		clear_selection()


func clear_selection() -> void:
	if highlighted < 0:
		return
	highlighted = -1
	highlight_changed.emit({})


func set_highlighted(index: int) -> void:
	if not menu_open or index == highlighted or index < 0 or index >= entries.size():
		return
	highlighted = index
	highlight_changed.emit(entries[index])


# sub_41B240 state 2: the action is committed and timed from its own duration.
func confirm() -> void:
	if not menu_open or highlighted < 0 or highlighted >= entries.size():
		return
	var entry: Dictionary = entries[highlighted]
	var action := ActionTable.get_action(int(entry["action_id"]))
	if action.is_empty():
		return
	_acting_point = focus_point
	_acting_entry = entry
	_elapsed = 0.0
	_duration = float(action.get("duration_tenths", 0)) / 10.0
	close_menu(true)
	state = State.ACTING
	_draw_highlight(null, TINT_READY)
	_set_acting(true)

	_play_action_animation(action)

	var object := _object_of(_acting_point)
	if int(action.get("result_state", 0)) == STATE_IN_USE:
		_acting_point.set("in_use", true)
	elif bool(action.get("state_at_start", false)):
		_apply_result_state(object, action, int(entry["action_id"]))
	action_started.emit(action, _acting_point)
	progress_changed.emit(0.0, _duration)


func _advance_action(delta: float) -> void:
	_elapsed += delta
	progress_changed.emit(_elapsed, _duration)
	if _elapsed < _duration:
		return
	_apply_action()
	clear_selection()
	state = State.FREE
	_set_acting(false)
	_elapsed = 0.0
	_duration = 0.0
	progress_changed.emit(0.0, 0.0)


# sub_41B240 state 4, in its original order.
func _apply_action() -> void:
	var point := _acting_point
	_acting_point = null
	if point == null or not is_instance_valid(point):
		return
	var action_id := int(_acting_entry.get("action_id", 0))
	var slot := int(_acting_entry.get("slot", -1))
	var action := ActionTable.get_action(action_id)
	if action.is_empty():
		return
	var object := _object_of(point)

	point.disable_slot(slot)
	# The slot flag and item+228 are written together and unconditionally: finishing any
	# action on an object is what leaves it tampered with, whatever the action did.
	point.set("tampered", true)
	if int(action.get("result_state", 0)) == STATE_IN_USE:
		point.set("in_use", false)

	for required in action.get("requires_items", []):
		var item := int(required)
		if item > 0 and item < inventory.size():
			inventory[item] = clampi(inventory[item] - 1, 0, 99)

	if not bool(action.get("state_at_start", false)):
		_apply_result_state(object, action, action_id)

	point.apply_action_lists(action_id)

	var granted := int(action.get("grants_item", 0))
	if granted > 0 and granted < inventory.size():
		# Ids 6 and 9 are inexhaustible and 22 arrives three at a time.
		if granted == 6 or granted == 9:
			inventory[granted] = 99
		elif granted == 22:
			inventory[granted] = clampi(inventory[granted] + 3, 0, 99)
		else:
			inventory[granted] = clampi(inventory[granted] + 1, 0, 99)
		inventory_changed.emit(inventory)
		# Removal only ever fires for an action that also hands something over.
		if bool(action.get("removes_item", false)) and object != null:
			focus_point = null
			object.queue_free()

	var session := get_tree().get_first_node_in_group("level_session")
	if session != null:
		session.add_score(int(action.get("score", 0)))
	action_applied.emit(action, point)


# sub_40FDA0, plus the four ids that read the object's current state instead of the table.
func _apply_result_state(object: Node, action: Dictionary, action_id: int) -> void:
	if object == null or not object.has_method("set_state"):
		return
	var result := int(action.get("result_state", 0))
	if result == STATE_KEEP or result == STATE_IN_USE:
		return
	var current := int(object.get("state"))
	match action_id:
		12:
			object.set_state(6 if current == 12 else (4 if current == 9 else 3))
		44:
			object.set_state(5 if current == 11 else 2)
		46:
			object.set_state(4 if current == 9 else 3)
		99:
			object.set_state(6 if current == 12 else (4 if current == 15 else 3))
		_:
			object.set_state(result)


# sub_41D820, in slot order. Cubicle occupancy is not modelled yet, so the five ids that
# depend on it are reported as they stand.
func available_slots(point: Node) -> PackedInt32Array:
	var slots := PackedInt32Array()
	if point == null:
		return slots
	var ids: PackedInt32Array = point.get("action_ids")
	for slot in range(ids.size()):
		var action_id := ids[slot]
		if action_id == 0 or not point.is_action_enabled(slot):
			continue
		var action := ActionTable.get_action(action_id)
		if action.is_empty():
			continue
		var satisfied := true
		for required in action.get("requires_items", []):
			var item := int(required)
			if item > 0 and item < inventory.size() and inventory[item] <= 0:
				satisfied = false
		if satisfied:
			slots.append(slot)
	return slots


# sub_41DA50 fills the menu from the surviving slots.
func build_entries(point: Node) -> Array:
	var built: Array = []
	if point == null:
		return built
	var ids: PackedInt32Array = point.get("action_ids")
	for slot in available_slots(point):
		var action_id := ids[slot]
		built.append({
			"slot": slot,
			"action_id": action_id,
			"name": ActionTable.action_name(action_id),
			"icon": ActionTable.icon_texture(action_id),
		})
	return built


func _update_hover() -> void:
	var object := _object_under_cursor()
	var point: Node = null
	var tint := TINT_NO_ACTION
	if object != null:
		point = object.get_node_or_null("InteractionPoint")
		entries = build_entries(point)
		if entries.is_empty():
			point = null
		elif _is_within_reach(point):
			tint = TINT_READY
		else:
			tint = TINT_OUT_OF_REACH
			point = null
	else:
		entries = []

	_hovered = object
	_draw_highlight(object, tint)

	if point != focus_point:
		focus_point = point
		focus_changed.emit(point)


# The original leaves the item itself alone and draws a second, additive copy over it whose
# alpha swings between 40 and 200. The object therefore stays in the static composite and
# never turns transparent; only this pass pulses.
func _draw_highlight(object: Node2D, tint: Color) -> void:
	if object == null:
		if is_instance_valid(_highlight):
			_highlight.visible = false
		return
	var sprite := object.get_node_or_null("Sprite2D") as Sprite2D
	var mask := _world_depth_mask()
	if sprite == null or mask == null or object.get("color_texture") == null:
		return
	if not is_instance_valid(_highlight):
		_highlight = Sprite2D.new()
		_highlight.name = "FocusHighlight"
		_highlight.centered = false
		_highlight.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_highlight_material = ShaderMaterial.new()
		_highlight_material.shader = HIGHLIGHT_SHADER
		_highlight.material = _highlight_material
		# Added after the compositor so it lands on top of the composite, and kept at its
		# z_index so a character standing in front still covers it.
		mask.get_parent().add_child(_highlight)

	var origin: Vector2 = sprite.to_global(sprite.offset)
	var pulse := PULSE_CENTRE + PULSE_SWING * sin(float(Time.get_ticks_msec()) * 0.001 * PULSE_RATE)
	_highlight.visible = true
	_highlight.texture = object.get("color_texture")
	_highlight.global_position = origin
	_highlight.modulate = Color(tint.r, tint.g, tint.b, pulse)
	_highlight_material.set_shader_parameter("pixel_snap", origin.round() - origin)
	_highlight_material.set_shader_parameter("base_y", ceilf(float(int(object.global_position.y)) * 0.5))
	var depth: Texture2D = object.get("depth_texture")
	_highlight_material.set_shader_parameter("depth_map", depth)
	_highlight_material.set_shader_parameter("depth_map_enabled", depth != null)
	if _environment_revision != int(mask.get("revision")):
		_environment_revision = int(mask.get("revision"))
		var buffer: Texture2D = mask.get("depth_texture")
		var bounds: Rect2 = mask.get("depth_bounds")
		_highlight_material.set_shader_parameter("world_depth", buffer)
		_highlight_material.set_shader_parameter("world_depth_enabled", buffer != null)
		_highlight_material.set_shader_parameter("world_depth_origin", bounds.position)
		_highlight_material.set_shader_parameter("world_depth_size", bounds.size)


func _world_depth_mask() -> Node2D:
	if is_instance_valid(_world_mask):
		return _world_mask
	if _player != null and _player.get_parent() != null:
		_world_mask = _player.get_parent().get_node_or_null("WorldDepthCompositor") as Node2D
	return _world_mask


# State 0 turns the player to face the item before the clip starts; selector 12 overrides
# that with one of its own three views.
func _play_action_animation(action: Dictionary) -> void:
	if _player == null or _acting_point == null:
		return
	var selector := int(action.get("player_animation", -1))
	var clip := String(SELECTOR_CLIPS.get(selector, ""))
	var facing: Vector2 = (_acting_point as Node2D).global_position - _player.global_position
	if facing == Vector2.ZERO:
		facing = _player.get("last_direction")
	facing = IsoDirection.snap_to_8_directions(facing)
	if selector == 12:
		var views: Array = PISS_FACINGS.get(String(_player.get("profile").get("id")), [])
		if not views.is_empty():
			facing = views[randi() % views.size()]
	_player.set("last_direction", facing)
	if clip == "" or not _player.play_action_animation(clip, facing):
		# No clip for this selector yet: the action still runs, the player just stands.
		_player.get_node("AnimationController").play_idle(facing)


# sub_4154B0 mode 1: the clock cursor while an action runs. The player is held still for
# the same stretch -- the original is playing an animation there.
func _set_acting(acting: bool) -> void:
	if _player != null:
		_player.set("input_locked", acting)
	var cursor := _player.get_node_or_null("MovementArrow") if _player != null else null
	if cursor != null and cursor.has_method("show_busy_cursor"):
		if acting:
			cursor.show_busy_cursor()
		else:
			cursor.show_main_cursor()


func _object_of(point: Node) -> Node:
	return point.get_parent() if point != null else null


func _is_within_reach(point: Node) -> bool:
	if _player == null or point == null:
		return false
	var layer := _collision_layer()
	if layer == null:
		return false
	var from: Vector2 = layer.to_grid_position(_player.global_position)
	var to: Vector2 = layer.to_grid_position((point as Node2D).global_position)
	if from.distance_to(to) > MAX_ACTION_RANGE:
		return false
	return layer.has_line_of_sight(_player.global_position, (point as Node2D).global_position)


func _collision_layer() -> Node:
	for layer in get_tree().get_nodes_in_group("collision_maps"):
		if layer.has_method("has_line_of_sight") and layer.get_parent().is_ancestor_of(_player):
			return layer
	return null


# sub_42BF20 walks the registered sprite boxes front to back and takes the first hit, so a
# plain bounding-box test in depth order reproduces it.
func _object_under_cursor() -> Node2D:
	var viewport := get_viewport()
	if viewport == null:
		return null
	var cursor: Vector2 = viewport.get_canvas_transform().affine_inverse() * viewport.get_mouse_position()
	var best: Node2D = null
	var best_depth := -INF
	for node in get_tree().get_nodes_in_group("depth_world_objects"):
		var object := node as Node2D
		if object == null or not object.is_visible_in_tree():
			continue
		var point := object.get_node_or_null("InteractionPoint")
		if point == null or (point.get("action_ids") as PackedInt32Array).is_empty():
			continue
		var sprite := object.get_node_or_null("Sprite2D") as Sprite2D
		if sprite == null or sprite.texture == null:
			continue
		if not Rect2(sprite.to_global(sprite.offset), sprite.texture.get_size()).has_point(cursor):
			continue
		var depth := ceilf(float(int(object.global_position.y)) * 0.5)
		if depth > best_depth:
			best_depth = depth
			best = object
	return best
