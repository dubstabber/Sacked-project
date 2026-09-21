@tool
class_name NPCWaypoint
extends Marker2D


@export_range(0.0, 300.0, 0.1, "suffix:s") var wait_seconds: float = 0.0
@export var facing := Vector2.ZERO
@export_enum("idle", "sit-idle", "sit-use") var animation: String = "idle"


func _ready() -> void:
	set_process(Engine.is_editor_hint())


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	draw_circle(Vector2.ZERO, 5.0, Color(0.2, 0.9, 1.0, 0.8))
	if facing != Vector2.ZERO:
		draw_line(Vector2.ZERO, facing.normalized() * 24.0, Color(1.0, 0.8, 0.2), 2.0)
