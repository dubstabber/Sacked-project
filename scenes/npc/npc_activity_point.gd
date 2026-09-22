@tool
class_name NPCActivityPoint
extends Marker2D


@export var category: int = 0
@export var item_type: int = 0
@export var room_id: int = 0
# item+196: the object's quarter-turn index, which decides which side an action that
# repositions the player puts them on. See docs/player-action-reference.md.
@export var orientation: int = 0
@export var active: bool = false
# The object's prank action ids, in original slot order; see docs/prank-reference.md.
@export var action_ids: PackedInt32Array = PackedInt32Array()

var occupant: Node
# item+224. Actions 110 and 112 shut an occupant in, and only an item reset -- which a
# finished repair performs -- lets them out again. While it is set the agent inside is also
# blind, because sub_416090 never reaches the branch that clears its notice flag.
# See docs/prank-reference.md and docs/catch-reference.md.
var locked_in := false
# item+228, which sub_41B240 sets the moment the player finishes *any* action on the object.
# Two things clear it: sub_40FEF0, the item's full reset, and sub_4100B0 below, which a
# finished repair calls. An agent that walks to a tampered object reacts instead of using
# it; see docs/npc-reference.md.
var tampered := false
# item+252: one flag per slot, cleared as its action is used. sub_4100B0 enables every slot
# that carries an action id, disables everything those slots unlock, then clears item+224
# and item+228 and puts the object back to state 0.
var action_enabled: Array[bool] = []


func _enter_tree() -> void:
	add_to_group("npc_activity_points")


func _ready() -> void:
	reset_actions()


func reset_actions() -> void:
	tampered = false
	locked_in = false
	action_enabled.resize(action_ids.size())
	for slot in range(action_ids.size()):
		action_enabled[slot] = action_ids[slot] != 0
	for slot in range(action_ids.size()):
		if not action_enabled[slot]:
			continue
		for locked in ActionTable.get_action(action_ids[slot]).get("unlocks", []):
			_set_enabled_by_action(int(locked), false)


func is_action_enabled(slot: int) -> bool:
	return slot >= 0 and slot < action_enabled.size() and action_enabled[slot]


func disable_slot(slot: int) -> void:
	if slot >= 0 and slot < action_enabled.size():
		action_enabled[slot] = false


# sub_410450: an action enables everything it unlocks and disables everything it names.
func apply_action_lists(action_id: int) -> void:
	var action := ActionTable.get_action(action_id)
	for unlocked in action.get("unlocks", []):
		_set_enabled_by_action(int(unlocked), true)
	for disabled in action.get("disables", []):
		_set_enabled_by_action(int(disabled), false)


func _set_enabled_by_action(action_id: int, enabled: bool) -> void:
	if action_id == 0:
		return
	for slot in range(action_ids.size()):
		if action_ids[slot] == action_id and slot < action_enabled.size():
			action_enabled[slot] = enabled


func is_available(actor: Node) -> bool:
	return not is_instance_valid(occupant) or occupant == actor
