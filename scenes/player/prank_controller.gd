extends Node

# Which object the cursor is over, whether the player may act on it, and carrying the chosen
# action out. Recovered in docs/player-action-reference.md: the focus item is picked by
# bounding box under the cursor, and an action needs a non-empty menu, a gap of at most
# MAX_ACTION_RANGE tiles to the item's interaction position, and a clear sight ray. The
# player never walks to an object.

const HIGHLIGHT_SHADER := preload("res://scenes/shared/object_highlight.gdshader")
const PlayerTimer := preload("res://scenes/player/player_timer.gd")

const MAX_ACTION_RANGE := 2.0
# item+4..6 while the cursor is over it.
const TINT_READY := Color(1.0, 1.0, 1.0)
const TINT_OUT_OF_REACH := Color(1.0, 1.0, 50.0 / 255.0)
const TINT_NO_ACTION := Color(1.0, 50.0 / 255.0, 50.0 / 255.0)
const AGENT_GROUP := &"npc_agents"
# sub_42D200(120 - sin(phase * 2.5) * -80) -- the pulse the highlight is drawn with.
const PULSE_CENTRE := 120.0 / 255.0
# sub_41DC80: four action ids reach past the object they were performed on. Everything else
# in its 79..118 range falls through and does nothing. See docs/prank-reference.md.
const CONSEQUENCE_BLACKOUT := 79
const CONSEQUENCE_LOCK_IN := [110, 112]
const CONSEQUENCE_PROJECTOR := 116
const CONSEQUENCE_HEATING := 118
const CONSEQUENCE_STATE := 9
# 79 blacks out every type-253 item; 116 looks for a type-265 one. 118 heats every item whose
# kind's top byte (item+194) is 9, which is every radiator and nothing else; the agents'
# category (item+192) is a different byte.
const BLACKOUT_ITEM_TYPE := 253
const PROJECTOR_ITEM_TYPE := 265
const HEATING_GROUP := 9
# The search is a box on each axis, with strict bounds, not a radius -- a nearer candidate
# later in the world's own order loses to a farther one earlier in it.
const PROJECTOR_REACH_TILES := 5.0
# player+1068, counted down by dt * 10, so the blackout lasts forty seconds.
const BLACKOUT_TIMER := 400.0

# sub_41D820's fourth rule reads the cubicle's occupant: 43, 44 and 138 need it empty, 110
# needs an occupant who is not the boss, and 112 needs the boss.
# sub_41B240's selector-5 branch (0x41B460) steps the player onto the copier before
# photocopying. It starts from the focused item's own position (sub_42B370), not the
# interaction position sub_410030 adds item+208/+212 to, and item+196 picks the side:
# orientation 0 takes the 090 view and (x + 0.85, z + 0.80), anything else the 180 view and
# (x + 0.80, z + 0.85). Those two views are the only ones ASSCOPY ships. sub_42B330 then sets
# the height to 1.8, which sub_41A2D0 projects 24 px a unit up into both the draw anchor and
# the depth base. See docs/player-action-reference.md.
const REPOSITION_SELECTOR := 5
const REPOSITION_OFFSETS := {
	0: Vector2(0.85, 0.80),
	1: Vector2(0.80, 0.85),
}
const REPOSITION_HEIGHT := 1.8

const CUBICLE_GATED_IDS := [43, 44, 110, 112, 138]
const CUBICLE_FREE_IDS := [43, 44, 138]
const CUBICLE_BOSS_ID := 112
const BOSS_PROFILE: StringName = &"boss"

const PULSE_SWING := 80.0 / 255.0
const PULSE_RATE := 2.5
# The fixed weight the mode-54 copy is blended at (item+7 = 180 for an object, 0x403431-0x40343D).
# See docs/player-action-reference.md, "How the highlight is drawn".
const WEIGHT_OBJECT := 180.0 / 255.0
# sub_41A510 maps a record's animation selector (+0x18) to a slot in the player's animation
# table at 0x46EC04. These are every selector the campaign places. See
# tools/character_action_clips.json and docs/player-action-reference.md.
const SELECTOR_CLIPS := {
	0: "stand-use", 1: "knee-use", 2: "kick", 3: "punch", 4: "flipbag",
	5: "asscopy", 6: "steal", 7: "drink", 8: "ketchup", 9: "phone-type",
	10: "spray", 11: "phone-call", 12: "piss-2", 13: "bucket", 14: "flipbag2",
}
# ASSCOPY ships only the two views the copier can be stepped onto from, and
# _step_onto_object picks which of them by the object's own orientation. Clip names resolve
# by screen angle, so view 090 is down-right and 180 is down-left.
const ASSCOPY_FACINGS := [Vector2(1, 1), Vector2(-1, 1)]
# Selector 12 and urinating's state 20 pick a facing from +988 the same way, in this order
# (0x41B556-0x41B5C7, 0x41C1B7-0x41C1FC): Anne's views _090, _135 and _180, Jo's _000, _270 and
# _315, which are exactly the views their PISS clips ship. See piss_facing().
const PISS_VIEWS := {
	"jobless": [0, 6, 7],
	"anne": [2, 3, 4],
}
# +0x40 values that are markers rather than states.
const STATE_KEEP := 17
const STATE_IN_USE := 18
# FLIPBAG and FLIPBAG2 carry the container in the player's hands. The original leaves the
# object drawn beside that copy, and only the boss's case hides it, by a blank DESTROY_1 as
# long as its action. Port decision (2026-11-21): hide the object for any of these actions.
# See docs/player-action-reference.md, "The flip clips carry the object".
const HELD_SELECTORS := [4, 14]
const INVENTORY_SLOTS := 31

# ABILITY is modes 2 to 5, the lamps' abilities, which AbilityController runs. The prank
# controller still owns player+900's gate: in any state but FREE the ring cannot open and a
# lamp's request is dropped. See docs/player-ability-reference.md.
enum State { FREE, MENU, ACTING, ABILITY }

signal focus_changed(point: Node)
signal menu_opened(entries: Array)
signal menu_closed()
signal highlight_changed(entry: Dictionary)
signal progress_changed(elapsed: float, total: float)
signal action_started(action: Dictionary, point: Node)
signal action_applied(action: Dictionary, point: Node)
signal action_aborted(action: Dictionary, point: Node)
signal inventory_changed(inventory: PackedInt32Array)

# player+912 and the four menu arrays behind it.
var focus_point: Node = null
# game+14696: the colleague under the cursor, picked every frame whatever the player is doing.
var hovered_agent: Node2D = null
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
var _characters: CharacterDepthCompositor
# player+1068: how much of the blackout action's forty seconds is left.
var blackout_remaining := 0.0
# Where the player stood before an action moved them, restored when it applies or aborts.
var _return_position := Vector2.INF
var _acting_point: Node
var _acting_entry: Dictionary = {}
# player+1040: the object's state before a start-time result state, which an abort restores.
# -1 when the committed action changed no state as it started.
var _saved_state := -1
# +992 and +1000 while an action runs, kept as every timed player state keeps them.
var _timer := PlayerTimer.new()
# sub_41B0C0, the first mode-0 tick after an ability, writes "..." back to player+1128.
var _idle_hover_pending := false


func _enter_tree() -> void:
	add_to_group("player_actions")


func _ready() -> void:
	_player = get_parent() as Node2D
	# sub_41AF60 clears 31 bytes, +1008 to +1038 (0x41AF88-0x41AFC0), so items 0 to 30 have a
	# slot and the player starts every level holding nothing. See docs/hud-reference.md.
	inventory.resize(INVENTORY_SLOTS)


func _process(delta: float) -> void:
	_advance_blackout(delta)
	if state == State.ACTING:
		_advance_action(delta)
		_update_agent_hover()
		return
	# The item pick is gated on +900 == 0 (0x4032B8); the colleague under the cursor is
	# picked whatever the player is doing.
	if state == State.ABILITY:
		_update_agent_hover()
		return
	if state == State.MENU:
		if _menu_cancel_held():
			close_menu()
		_update_agent_hover()
		return
	if _idle_hover_pending:
		_idle_hover_pending = false
		highlight_changed.emit({})
	PerfProbe.begin(&"prank.hover")
	_update_hover()
	PerfProbe.end(&"prank.hover")


# sub_403FB0 ends every frame (0x404502) by aborting an open ring while movement bit 0x80 --
# the down arrow -- or the right button's 0x100 is held. The same test lands before the tick
# would open the ring, so holding either keeps it from opening at all.
func _menu_cancel_held() -> bool:
	return Input.is_action_pressed("move_down") or Input.is_action_pressed("mouse-movement")


func _unhandled_input(event: InputEvent) -> void:
	# The level tick reads the act input for the selection whatever the player is doing, and
	# independently of the ring, which reads it below.
	if event.is_action_pressed("interact") and is_instance_valid(hovered_agent):
		select_agent(hovered_agent)
	if state == State.ACTING or state == State.ABILITY:
		return
	if menu_open:
		# sub_4066D0 commits on 12740 & 0x14 (0x406802): space, the click, and the up arrow's
		# bit 2. Left and right turn the ring in round_menu.gd.
		if event.is_action_pressed("interact") or event.is_action_pressed("move_up"):
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
	if menu_open or focus_point == null or entries.is_empty() or _menu_cancel_held():
		return
	menu_open = true
	state = State.MENU
	_idle_hover_pending = false
	highlighted = 0
	# State 0 turns to the item before the ring comes up, and the idle then holds that view.
	if _player != null:
		_player.set("last_direction", _facing_toward_item(focus_point))
	_hold_for_menu(true)
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
	_hold_for_menu(false)
	menu_closed.emit()
	if not keep_selection:
		clear_selection()


# sub_406510 hides the cursor while the ring is up and sub_41B240's state 1 only rewrites the
# hover text, so the player stands still and the pointer is the ring's until it shuts.
func _hold_for_menu(open: bool) -> void:
	if _player == null:
		return
	_player.set("menu_open", open)
	var cursor := _player.get_node_or_null("MovementArrow")
	if cursor == null or not cursor.has_method("capture_for_menu"):
		return
	if open:
		cursor.capture_for_menu()
	else:
		cursor.release_from_menu(
			_player.call("get_player_viewport_position"),
			_player.get("is_mouse_movement_active") == true
		)


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


# sub_41B240 state 2: the action is committed and timed from its own duration, +1000 = tenths
# * 10.0 (0x41B5FA-0x41B60B).
func confirm() -> void:
	if not menu_open or highlighted < 0 or highlighted >= entries.size():
		return
	var entry: Dictionary = entries[highlighted]
	var action := ActionTable.get_action(int(entry["action_id"]))
	if action.is_empty():
		return
	_acting_point = focus_point
	_acting_entry = entry
	_timer.start(float(action.get("duration_tenths", 0)))
	close_menu(true)
	state = State.ACTING
	_draw_highlight(null, TINT_READY)
	_set_acting(true)

	_step_onto_object(int(entry["action_id"]))
	_play_action_animation(action)

	var object := _object_of(_acting_point)
	_saved_state = -1
	var result := int(action.get("result_state", 0))
	if result == STATE_IN_USE:
		_acting_point.set("in_use", true)
	elif bool(action.get("state_at_start", false)):
		# State 2 saves the item's state in +1040 before it applies the start-time one
		# (0x41B64B-0x41B661), under the same test as the change itself.
		if result != STATE_KEEP and object != null and object.has_method("set_state"):
			_saved_state = int(object.get("state"))
		_apply_result_state(object, action, int(entry["action_id"]))
	_hold(object, action, true)
	action_started.emit(action, _acting_point)
	progress_changed.emit(0.0, _timer.total_seconds())


# State 3 (0x41B6DE-0x41B711): +992 summed as a float, and the action ends once +992 * 100
# reaches +1000, which zeroes both.
func _advance_action(delta: float) -> void:
	var sum := _timer.add_elapsed(delta)
	progress_changed.emit(_timer.elapsed, _timer.total_seconds())
	if not _timer.reached(sum):
		return
	_apply_action()
	clear_selection()
	state = State.FREE
	_set_acting(false)
	_timer.zero()
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
	_hold(object, action, false)

	for required in action.get("requires_items", []):
		var item := int(required)
		if item > 0 and item < inventory.size():
			inventory[item] = clampi(inventory[item] - 1, 0, 99)

	if not bool(action.get("state_at_start", false)):
		_apply_result_state(object, action, action_id)

	point.apply_action_lists(action_id)

	var granted := int(action.get("grants_item", 0))
	if granted > 0 and granted < inventory.size():
		grant_item(granted)
		# Removal only ever fires for an action that also hands something over.
		if bool(action.get("removes_item", false)) and object != null:
			focus_point = null
			object.queue_free()

	_step_back()
	_apply_global_consequence(action_id, point)

	var session := get_tree().get_first_node_in_group("level_session")
	if session != null:
		# sub_41DE60 floats the number off the player, not off the object it acted on.
		session.add_score(int(action.get("score", 0)), _player.global_position)
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


# sub_41B240 state 4's grant. Ids 6 and 9 are inexhaustible and 22 arrives three at a time.
func grant_item(item: int) -> void:
	if item <= 0 or item >= inventory.size():
		return
	if item == 6 or item == 9:
		inventory[item] = 99
	elif item == 22:
		inventory[item] = clampi(inventory[item] + 3, 0, 99)
	else:
		inventory[item] = clampi(inventory[item] + 1, 0, 99)
	inventory_changed.emit(inventory)


# What an ability's last state takes: one of the item, clamped at 0 (smoking, 0x41C07E) or to
# 0-99 (urinating and the pill), which is the same thing for a count a grant caps at 99.
func spend_item(item: int) -> void:
	if item <= 0 or item >= inventory.size():
		return
	inventory[item] = clampi(inventory[item] - 1, 0, 99)
	inventory_changed.emit(inventory)


# AbilityController takes player+900 for a lamp's mode. sub_403780 feeds the console from the
# same player fields for an ability as for a prank (0x40384C-0x403888, 0x403AB9), so the
# ability's record name and stopwatch go out through this controller's own signals and the
# console reads them as it reads a prank's. The centre icon stays hidden: only mode 1 sets
# +920. See docs/player-ability-reference.md.
func begin_ability() -> bool:
	if state != State.FREE:
		return false
	state = State.ABILITY
	_idle_hover_pending = false
	highlighted = -1
	entries = []
	_hovered = null
	_draw_highlight(null, TINT_READY)
	if focus_point != null:
		focus_point = null
		focus_changed.emit(null)
	return true


# player+1128, which the mode's first state writes.
func show_ability_record(record_name: String) -> void:
	highlight_changed.emit({"name": record_name})


func report_ability_progress(elapsed: float, total: float) -> void:
	progress_changed.emit(elapsed, total)


func end_ability() -> void:
	if state != State.ABILITY:
		return
	state = State.FREE
	_idle_hover_pending = true


# sub_41D820, in slot order.
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
		if satisfied and _occupancy_allows(action_id, point):
			slots.append(slot)
	return slots


# sub_41D820's fourth rule: five ids care who is in the cubicle. 43, 44 and 138 need it
# empty; 110 needs somebody in it who is not the boss; 112 needs the boss.
# See docs/prank-reference.md.
func _occupancy_allows(action_id: int, point: Node) -> bool:
	if not CUBICLE_GATED_IDS.has(action_id):
		return true
	var occupant = point.get("occupant")
	if not is_instance_valid(occupant):
		return CUBICLE_FREE_IDS.has(action_id)
	if CUBICLE_FREE_IDS.has(action_id):
		return false
	var is_boss := _profile_id_of(occupant) == BOSS_PROFILE
	return is_boss if action_id == CUBICLE_BOSS_ID else not is_boss


func _profile_id_of(occupant) -> StringName:
	var profile = occupant.get("profile") if occupant != null else null
	return StringName(profile.get("id")) if profile != null else &""


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


# sub_403780 (0x4039D7-0x403A3F): the act input while a character is hovered clears agent+1788
# on every entity but the player and raises it on that one, for the rest of the level. The
# player registers no box (CObj_Player leaves +88 at 0, 0x41AE15), so only a colleague can be
# the one. See docs/names-reference.md.
func select_agent(agent: Node2D) -> void:
	for node in get_tree().get_nodes_in_group(AGENT_GROUP):
		node.set("selected", node == agent)


func _update_hover() -> void:
	# Main_RenderUpdate only picks in cursor mode 0 (0x403298), so nothing new is focused
	# while the right button walks the player. The original leaves the last focus standing
	# (0x40345F re-applies it); the port drops it, so the pulse does not freeze mid-swing and
	# a click mid-walk has nothing to open.
	var front := _front_under_cursor()
	_set_hovered_agent(front if _is_agent(front) else null)
	var object: Node2D = null
	if (_player == null or _player.get("is_mouse_movement_active") != true) and not _is_agent(front):
		object = front
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


# The original leaves the item itself alone and draws a second copy over it in mode 54, at a
# fixed weight (item+7 = 180, 200 for a colleague) with a brightness lift that pulses between 40
# and 200. So the object stays in the static composite and never turns transparent; only this
# pass pulses. object_highlight.gdshader now blends that brightened copy at the fixed weight,
# not additively: see "How the highlight is drawn" in docs/player-action-reference.md.
func _draw_highlight(object: Node2D, tint: Color) -> void:
	if object == null:
		if is_instance_valid(_highlight):
			_highlight.visible = false
		return
	var sprite := object.get_node_or_null("Sprite2D") as Sprite2D
	if sprite == null or _world_depth_mask() == null or object.get("color_texture") == null:
		return
	if not is_instance_valid(_highlight):
		_highlight = _new_pulse("FocusHighlight")
		_highlight_material = _highlight.material as ShaderMaterial
	var depth: Texture2D = object.get("depth_texture")
	_draw_pulse(_highlight, sprite, object.get("color_texture"), depth, _depth_base(object.global_position), tint, WEIGHT_OBJECT)
	_apply_cluster_depth()


# Main_RenderUpdate raises agent+92 on the hovered colleague (0x403258), so the character loop
# draws it a second time (0x402A24). Unlike an item, the agent's own draw (sub_417460) overrides
# the blend mode, so the opaque body is redrawn unchanged while its shadow and bubble, both
# blended, double and come out stronger and lighter. So a hovered colleague is not a brightened
# copy; it is the agent showing itself emphasised. See docs/player-action-reference.md.
func _update_agent_hover() -> void:
	var front := _front_under_cursor()
	_set_hovered_agent(front if _is_agent(front) else null)


func _set_hovered_agent(agent: Node2D) -> void:
	if agent == hovered_agent:
		return
	if is_instance_valid(hovered_agent):
		hovered_agent.set("hovered", false)
	hovered_agent = agent
	if is_instance_valid(agent):
		agent.set("hovered", true)


func _new_pulse(pulse_name: String) -> Sprite2D:
	var pulse := Sprite2D.new()
	pulse.name = pulse_name
	pulse.centered = false
	pulse.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var material := ShaderMaterial.new()
	material.shader = HIGHLIGHT_SHADER
	pulse.material = material
	# The original draws the copy right after the item, before anything drawn later is
	# laid over it. One z above the object's own layer and first on that layer does the
	# same: over a baked object (z 0) the characters' z 1 still covers it, and over an
	# actor (z 1) it clears the compositor's surfaces, which draw after every ordinary
	# child, yet stays under the thought bubbles at z 2. See docs/map-rendering.md.
	var mask := _world_depth_mask()
	mask.get_parent().add_child(pulse, false, Node.INTERNAL_MODE_FRONT)
	return pulse


func _draw_pulse(pulse: Sprite2D, sprite: Sprite2D, texture: Texture2D, depth: Texture2D, base_y: float, tint: Color, weight: float) -> void:
	var origin: Vector2 = sprite.to_global(sprite.offset)
	# 120 + 80*sin(2.5 t), as 0..1: the brightness added to the tinted copy, not an alpha.
	var brightness := PULSE_CENTRE + PULSE_SWING * sin(float(Time.get_ticks_msec()) * 0.001 * PULSE_RATE)
	var material := pulse.material as ShaderMaterial
	pulse.visible = true
	pulse.z_index = sprite.z_index + 1
	pulse.texture = texture
	pulse.global_position = origin
	# The copy carries the tint in its colour; the shader blends it at the fixed weight.
	pulse.modulate = Color(tint.r, tint.g, tint.b, 1.0)
	material.set_shader_parameter("weight", weight)
	material.set_shader_parameter("brightness", brightness)
	material.set_shader_parameter("pixel_snap", origin.round() - origin)
	material.set_shader_parameter("base_y", base_y)
	material.set_shader_parameter("depth_map", depth)
	material.set_shader_parameter("depth_map_enabled", depth != null)
	var mask := _world_depth_mask()
	var revision := int(mask.get("revision"))
	if int(material.get_meta(&"environment_revision", -1)) != revision:
		material.set_meta(&"environment_revision", revision)
		var buffer: Texture2D = mask.get("depth_texture")
		var bounds: Rect2 = mask.get("depth_bounds")
		material.set_shader_parameter("world_depth", buffer)
		material.set_shader_parameter("world_depth_enabled", buffer != null)
		material.set_shader_parameter("world_depth_origin", bounds.position)
		material.set_shader_parameter("world_depth_size", bounds.size)


func _depth_base(anchor: Vector2) -> float:
	return ceilf(float(int(anchor.y)) * 0.5)


# Above an actor the pass is drawn over every character too, so where the object overlaps
# one it has to test the scores the compositor composed the two with. The compositor runs
# after this node each frame and calls back once it has composed, so the test always matches
# the surface that is drawn.
func _apply_cluster_depth() -> void:
	if is_instance_valid(_hovered):
		_apply_pulse_cluster(_highlight, _hovered.get_node_or_null("Sprite2D") as Sprite2D)


func _apply_pulse_cluster(pulse: Sprite2D, sprite: Sprite2D) -> void:
	if not is_instance_valid(pulse) or not pulse.visible:
		return
	var material := pulse.material as ShaderMaterial
	var compositor := _character_compositor()
	var cluster: Dictionary = compositor.cluster_depth_for(sprite) if compositor != null else {}
	material.set_shader_parameter("cluster_depth_enabled", not cluster.is_empty())
	if cluster.is_empty():
		return
	var bounds: Rect2 = cluster["bounds"]
	material.set_shader_parameter("cluster_depth", cluster["texture"])
	material.set_shader_parameter("cluster_depth_origin", bounds.position)
	material.set_shader_parameter("cluster_depth_size", bounds.size)


func _world_depth_mask() -> Node2D:
	if is_instance_valid(_world_mask):
		return _world_mask
	if _player != null and _player.get_parent() != null:
		_world_mask = _player.get_parent().get_node_or_null("WorldDepthCompositor") as Node2D
	return _world_mask


func _character_compositor() -> CharacterDepthCompositor:
	if is_instance_valid(_characters):
		return _characters
	if _player != null and _player.get_parent() != null:
		_characters = _player.get_parent().get_node_or_null("CharacterDepthCompositor") as CharacterDepthCompositor
		if _characters != null:
			_characters.composed.connect(_apply_cluster_depth)
	return _characters


# State 0 turns the player to face the item before the clip starts; selector 12 overrides
# that with one of its own three views.
func _play_action_animation(action: Dictionary) -> void:
	if _player == null or _acting_point == null:
		return
	var selector := int(action.get("player_animation", -1))
	var clip := String(SELECTOR_CLIPS.get(selector, ""))
	var facing := _facing_toward_item(_acting_point)
	if selector == 12:
		var picked := piss_facing(String(_player.get("profile").get("id")), func() -> int: return randi())
		if picked != Vector2.ZERO:
			facing = picked
	elif selector == REPOSITION_SELECTOR:
		# The player is standing on the object by now, so the vector to it says nothing.
		# _step_onto_object already chose the side; use it.
		facing = _nearest_asscopy_facing(_player.get("last_direction"))
	_player.set("last_direction", facing)
	if clip == "" or not _player.play_action_animation(clip, facing):
		# Every selector the table uses has a clip in every view picked above, so this is only
		# a guard: the action still runs, the player just stands.
		_player.get_node("AnimationController").play_idle(facing)


# Two rand() & 8 tests: the first view half the time, the second and third a quarter each. The
# character's PISS_VIEWS entry, as a screen direction, or zero for a character with none.
static func piss_facing(profile_id: String, roll: Callable) -> Vector2:
	var views: Array = PISS_VIEWS.get(profile_id, [])
	if views.is_empty():
		return Vector2.ZERO
	var choice := 0
	if (int(roll.call()) & 8) == 0:
		choice = 1 if (int(roll.call()) & 8) != 0 else 2
	return IsoDirection.get_screen_directions()[int(views[choice])]


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


# Hidden, the object also leaves the static composite and the pick, as marker 18's is.
func _hold(object: Node, action: Dictionary, held: bool) -> void:
	if object is CanvasItem and int(action.get("player_animation", -1)) in HELD_SELECTORS:
		(object as CanvasItem).visible = not held


# sub_41B240 state 0 (0x41B290) aims at the focused item's own position, not its interaction
# point: 180 - atan2(dx, dz) in logical units, which sub_41A400 bins into
# int((a + 22.5) / 45) & 7, the index of the _NNN view.
func _facing_toward_item(point: Node) -> Vector2:
	var object := _object_of(point) as Node2D
	if _player == null or object == null:
		var current = _player.get("last_direction") if _player != null else null
		return current if current is Vector2 else Vector2.RIGHT
	var delta := IsoDirection.screen_to_ground(object.global_position - _player.global_position)
	var heading := 180.0 - rad_to_deg(atan2(delta.x, delta.y))
	return IsoDirection.get_screen_directions()[int((heading + 22.5) / 45.0) & 7]


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
# plain bounding-box test in depth order reproduces it. Every item registers its box, from
# its current frame, each frame it is drawn (sub_411E20 at 0x411F88), whatever its state, so
# an object drawn as an actor is picked like a baked one. The sprite's own visibility is not
# tested: a cluster hides an actor's Sprite2D and draws it on a surface of its own, but keeps
# its frame current.
#
# Colleagues register into the same list (0x402B09), their ids untagged where an item's carry
# 0x8000, and the character pick (0x403202) and the item pick (sub_4132E0) each take the
# first hit only if it is theirs. So one box answers both: a colleague standing in front of
# a desk takes the hover from it, and the desk from a colleague behind it. Which of two
# boxes at the same depth comes first is not recovered; the object wins here.
func _front_under_cursor() -> Node2D:
	var viewport := get_viewport()
	if viewport == null:
		return null
	var cursor: Vector2 = viewport.get_canvas_transform().affine_inverse() * viewport.get_mouse_position()
	return _front_at(cursor)


# sub_42BF20 returns the first box hit while it walks the list sub_42BE60 fills as the frame
# draws. sub_42BEF0 files each box in a bucket of its depth >> 4 and pushes it at that
# bucket's head, and sub_42BE20 links the buckets front to back. So the frontmost bucket wins,
# and inside one the box registered last: items in world order (sub_411E20, 0x411F88), then
# the agents after every item (0x402B09). A soap on a sink shares the sink's depth and wins.
# See docs/player-action-reference.md, "Which box answers".
func _front_at(cursor: Vector2) -> Node2D:
	# The camera is the player's ground anchor (sub_402590 copies it every tick).
	var camera_y := _player.global_position.y if _player != null else 0.0
	var best: Node2D = null
	var best_bucket := 0x7FFFFFFF
	for node in get_tree().get_nodes_in_group(MapObject.PICK_GROUP):
		var object := node as Node2D
		if object == null or not object.is_visible_in_tree():
			continue
		var point := object.get_node_or_null("InteractionPoint")
		if point == null or (point.get("action_ids") as PackedInt32Array).is_empty():
			continue
		var sprite := object.get_node_or_null("Sprite2D") as Sprite2D
		if not _box_has_point(sprite, cursor):
			continue
		var bucket := pick_bucket(object.global_position.y - camera_y)
		if bucket <= best_bucket:
			best_bucket = bucket
			best = object
	# CAgent's constructor sets the box flag +88 (0x415F20); the player's never does.
	for node in get_tree().get_nodes_in_group(AGENT_GROUP):
		var agent := node as Node2D
		if agent == null or not agent.is_visible_in_tree():
			continue
		var sprite := agent.get_node_or_null("Sprite2D") as Sprite2D
		if not _box_has_point(sprite, cursor):
			continue
		var bucket := pick_bucket(agent.global_position.y - camera_y)
		if bucket <= best_bucket:
			best_bucket = bucket
			best = agent
	return best


# sub_41A2D0: an entity's depth is trunc(49152 - sy * 0.5), sy its truncated screen row
# below the camera (0x41A343-0x41A365; 49152.0 at 0x46553C, 0.5 at 0x46B524), and the box
# list files it under depth >> 4 (0x411F80). Lower is nearer.
static func pick_bucket(rows_below_camera: float) -> int:
	var sy := int(rows_below_camera)
	return int(49152.0 - float(sy) * 0.5) >> 4


func _box_has_point(sprite: Sprite2D, point: Vector2) -> bool:
	if sprite == null or sprite.texture == null:
		return false
	return Rect2(sprite.to_global(sprite.offset), sprite.texture.get_size()).has_point(point)


func _is_agent(node: Node2D) -> bool:
	return node != null and node.is_in_group(AGENT_GROUP)


func _object_under_cursor() -> Node2D:
	var front := _front_under_cursor()
	return null if _is_agent(front) else front


# sub_402470 pushes the player to its mode's abort state rather than letting the action
# finish, so a prank interrupted by being caught pays nothing and leaves the object alone.
# The one thing already applied is a start-time result state, which state 5 undoes by
# putting back the state saved in +1040 (0x41BB83-0x41BBA8). State 5 also stops a
# start-time sound (0x41BB61), which LevelAudio holds and cuts on action_aborted.
func abort_action() -> void:
	if state != State.ACTING:
		return
	var point := _acting_point
	var action := ActionTable.get_action(int(_acting_entry.get("action_id", 0)))
	_acting_point = null
	_acting_entry = {}
	_step_back()
	if point != null and is_instance_valid(point):
		_hold(_object_of(point), action, false)
		if int(action.get("result_state", 0)) == STATE_IN_USE:
			point.set("in_use", false)
		elif _saved_state >= 0:
			var object := _object_of(point)
			if object != null and object.has_method("set_state"):
				object.set_state(_saved_state)
	_saved_state = -1
	clear_selection()
	state = State.FREE
	_set_acting(false)
	_timer.zero()
	progress_changed.emit(0.0, 0.0)
	action_aborted.emit(action, point if is_instance_valid(point) else null)


# ASSCOPY has two views rather than eight. _step_onto_object has already turned the player to
# the one the copier's orientation chooses, so this returns it unchanged; the nearer of the
# two only matters when there was no object to step onto. See docs/player-action-reference.md.
func _nearest_asscopy_facing(facing: Vector2) -> Vector2:
	var best := facing
	var best_dot := -INF
	for view in ASSCOPY_FACINGS:
		var dot: float = (view as Vector2).normalized().dot(facing.normalized())
		if dot > best_dot:
			best_dot = dot
			best = view
	return best


# sub_41DC80. Four ids reach past the object the action was performed on; the rest of its
# 79..118 range is a no-op. See docs/prank-reference.md.
func _apply_global_consequence(action_id: int, point: Node) -> void:
	if action_id == CONSEQUENCE_BLACKOUT:
		for node in _objects_of_type(BLACKOUT_ITEM_TYPE):
			node.call("set_state", CONSEQUENCE_STATE)
		blackout_remaining = BLACKOUT_TIMER
	elif action_id == CONSEQUENCE_HEATING:
		for node in _objects_of_group(HEATING_GROUP):
			node.call("set_state", CONSEQUENCE_STATE)
	elif action_id == CONSEQUENCE_PROJECTOR:
		var target := _first_object_in_reach(PROJECTOR_ITEM_TYPE, point)
		if target != null:
			target.call("set_state", CONSEQUENCE_STATE)
	elif CONSEQUENCE_LOCK_IN.has(action_id):
		# Only worth anything if somebody is actually in there to be shut in.
		if point != null and is_instance_valid(point) and point.get("occupant") != null:
			point.set("locked_in", true)


# player+1068, ticked at dt * 10: sub_41CFC0 reads the player clock's 10.0 (flt_4652F4) at
# 0x41D475. When it runs out the blacked-out items come back.
func _advance_blackout(delta: float) -> void:
	if blackout_remaining <= 0.0:
		return
	blackout_remaining -= delta * PlayerTimer.factor("tenths_to_hundredths")
	if blackout_remaining > 0.0:
		return
	blackout_remaining = 0.0
	for node in _objects_of_type(BLACKOUT_ITEM_TYPE):
		node.call("set_state", 0)


func _activity_points() -> Array:
	return get_tree().get_nodes_in_group("npc_activity_points")


func _objects_of_type(item_type: int) -> Array:
	var result := []
	for point in _activity_points():
		if int(point.get("item_type")) != item_type:
			continue
		var object := _object_of(point)
		if object != null and object.has_method("set_state"):
			result.append(object)
	return result


# sub_411000 walks the world's items comparing sub_40FE80's item+194.
func _objects_of_group(group: int) -> Array:
	var result := []
	for point in _activity_points():
		if int(point.get("group")) != group:
			continue
		var object := _object_of(point)
		if object != null and object.has_method("set_state"):
			result.append(object)
	return result


# The original stops at the first candidate whose offset from the focused item is inside a
# box on each axis. It never measures a distance, so this is deliberately not a nearest
# search: world order decides.
func _first_object_in_reach(item_type: int, point: Node) -> Node:
	if point == null or not is_instance_valid(point):
		return null
	var origin := IsoDirection.screen_to_ground((point as Node2D).global_position)
	for candidate in _activity_points():
		if int(candidate.get("item_type")) != item_type:
			continue
		var offset := IsoDirection.screen_to_ground((candidate as Node2D).global_position) - origin
		if absf(offset.x) >= PROJECTOR_REACH_TILES or absf(offset.y) >= PROJECTOR_REACH_TILES:
			continue
		var object := _object_of(candidate)
		if object != null and object.has_method("set_state"):
			return object
	return null


# sub_41B240 state 2 for selector 5: the player is placed on the object, lifted onto it, and
# faces the view the object's orientation chooses.
func _step_onto_object(action_id: int) -> void:
	if _player == null or _acting_point == null or not is_instance_valid(_acting_point):
		return
	if int(ActionTable.get_action(action_id).get("player_animation", -1)) != REPOSITION_SELECTOR:
		return
	var object := _object_of(_acting_point) as Node2D
	if object == null:
		return
	var orientation := int(_acting_point.get("orientation"))
	var side := 0 if orientation == 0 else 1
	var offset: Vector2 = REPOSITION_OFFSETS[side]
	_return_position = _player.global_position
	var ground := IsoDirection.screen_to_ground(object.global_position) + offset
	_player.global_position = IsoDirection.ground_to_screen(ground)
	_player.set("height", REPOSITION_HEIGHT)
	_player.set("last_direction", ASSCOPY_FACINGS[side])


# sub_41B240 states 4 and 5 both put the player back where they were, when the clip playing
# is slot 17 -- only the reposition above saves a position, so that is the same test.
func _step_back() -> void:
	if _player == null or not _return_position.is_finite():
		return
	_player.global_position = _return_position
	_player.set("height", 0.0)
	_return_position = Vector2.INF
