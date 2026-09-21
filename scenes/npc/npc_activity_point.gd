@tool
class_name NPCActivityPoint
extends Marker2D


@export var category: int = 0
@export var item_type: int = 0
@export var room_id: int = 0
@export var active: bool = false
# The object's prank action ids, in original slot order; see docs/prank-reference.md.
@export var action_ids: PackedInt32Array = PackedInt32Array()

var occupant: Node


func _enter_tree() -> void:
	add_to_group("npc_activity_points")


func is_available(actor: Node) -> bool:
	return not is_instance_valid(occupant) or occupant == actor
