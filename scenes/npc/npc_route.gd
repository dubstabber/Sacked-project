@tool
class_name NPCRoute
extends Node2D


const WAYPOINT := preload("res://scenes/npc/npc_waypoint.gd")

@export var loop: bool = true


func _ready() -> void:
	set_process(Engine.is_editor_hint())


func get_waypoints() -> Array[Marker2D]:
	var result: Array[Marker2D] = []
	for child in get_children():
		if child is WAYPOINT:
			result.append(child)
	return result


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	var points := PackedVector2Array()
	for waypoint in get_waypoints():
		points.append(to_local(waypoint.global_position))
	if points.size() < 2:
		return
	if loop:
		points.append(points[0])
	draw_polyline(points, Color(0.2, 0.9, 1.0, 0.65), 2.0)
