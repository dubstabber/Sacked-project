@tool
class_name NPCActivityPoint
extends Marker2D


@export var category: int = 0
@export var item_type: int = 0
# item+194, the top byte of the item's kind (sub_40FEA0, 0x40FEA9). Only action 118's search
# reads it (sub_411000), and it is 9 on exactly the radiators. See docs/prank-reference.md.
@export var group: int = 0
# The room the object stands in, as room() answers it. Left at -1 it is read off the level's
# painted rooms, so an object moved or dropped into a map is in whichever room it stands in; a
# room set here wins. A plain value rather than a getter: saving a scene reads every exported
# property, and a resolved room would be written into the prefab.
@export var room_id: int = -1
# item+196: the object's quarter-turn index, which decides which side an action that
# repositions the player puts them on. See docs/player-action-reference.md.
@export var orientation: int = 0
@export var active: bool = false
# The object's prank action ids, in original slot order; see docs/prank-reference.md.
@export var action_ids: PackedInt32Array = PackedInt32Array()

var occupant: Node
var _resolved_room := -1
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
# item+216 on the copier. sub_417B00 claims it for the first NPC to use it (0x417E6E) and
# nothing frees it again before the level restarts: sub_416340 leaves it set, and so does
# sub_4100B0 below. Seats and cubicles keep their claim in `occupant` instead.
# See docs/npc-reference.md.
var copier_claimed := false
# item+252: one flag per slot, cleared as its action is used. sub_4100B0 enables every slot
# that carries an action id, disables everything those slots unlock, then clears item+224
# and item+228 and puts the object back to state 0.
var action_enabled: Array[bool] = []
# item+232, the hide flag a marker-18 action raises for as long as it runs (sub_41B240). A
# hidden item is neither drawn nor given a click box (sub_41A2D0 through sub_40FCE0), so the
# port hides the object, which takes it out of the static composite and the pick as well.
# Only the action sets and clears it; sub_4100B0's reset leaves it alone.
# See docs/prank-reference.md.
var in_use := false:
	set(value):
		in_use = value
		var object := get_parent() as CanvasItem
		if object != null:
			object.visible = not value


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


# INFODATA bits 16-23 at the object's anchor cell, rounded as the builder always has,
# floori(tile + 0.5): the cell sub_4187F0 files a goal's candidates by (docs/npc-reference.md).
func room() -> int:
	if room_id >= 0:
		return room_id
	if _resolved_room >= 0:
		return _resolved_room
	var resolved := _room_from_map()
	# Not kept in the editor, where the object and the rooms both move under it.
	if not Engine.is_editor_hint():
		_resolved_room = resolved
	return resolved


func _room_from_map() -> int:
	var object := get_parent() as Node2D
	var layer := _collision_layer()
	if object == null or layer == null:
		return 0
	var tile := _anchor_tile(object, layer)
	var cell := Vector2i(floori(tile.x + 0.5), floori(tile.y + 0.5))
	var size: Vector2i = layer.room_grid_size
	if cell.x < 0 or cell.y < 0 or cell.x >= size.x or cell.y >= size.y:
		return 0
	var rooms: PackedByteArray = layer.room_ids
	var index := cell.y * size.x + cell.x
	return int(rooms[index]) if index < rooms.size() else 0


# The object's anchor in tiles. An imported object still standing where the importer put it
# answers its manifest tile exactly, as the builder did, since recomputing it from float32
# pixels can land on the other side of a half-cell boundary; one moved since, or dropped into
# a map, answers where it stands. Neither needs the scene tree.
func _anchor_tile(object: Node2D, layer: TileMapLayer) -> Vector2:
	var origin := layer.map_to_local(Vector2i.ZERO)
	var axes := Transform2D(layer.map_to_local(Vector2i(1, 0)) - origin, layer.map_to_local(Vector2i(0, 1)) - origin, origin)
	if object.has_meta("original_tile_position"):
		var tile: Vector2 = object.get_meta("original_tile_position")
		if origin + axes.x * tile.x + axes.y * tile.y == object.position:
			return tile
	return axes.affine_inverse() * object.position


func _collision_layer() -> CollisionMapLayer:
	var node: Node = get_parent()
	while node != null:
		var layer := node.get_node_or_null("CollisionTileMapLayer") as CollisionMapLayer
		if layer != null:
			return layer
		node = node.get_parent()
	return null


func is_available(actor: Node) -> bool:
	return not is_instance_valid(occupant) or occupant == actor
