extends SceneTree

# agent+1080 is the agent's current goal and the bubble is that goal's own entry in the
# table at 0x46E7A8, drawn 135 pixels above it at alpha 180 by sub_417460.

const BUBBLE := preload("res://scenes/npc/thought_bubble.gd")
const LEVEL := preload("res://scenes/level_1.tscn")

var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await _check_bubbles_follow_goals()
	if _failures == 0:
		print("Thought bubbles: every goal shows its own bubble, over the agent's head")
	quit(1 if _failures else 0)


func _expect(condition: bool, label: String) -> void:
	if not condition:
		_failures += 1
		push_error(label)


func _check_bubbles_follow_goals() -> void:
	var level := LEVEL.instantiate()
	root.add_child(level)
	await process_frame

	var npc := level.get_node_or_null("World/Npc080Boss")
	var bubble := npc.get_node_or_null("ThoughtBubble") as Sprite2D if npc != null else null
	var brain := npc.get_node_or_null("Brain") if npc != null else null
	_expect(bubble != null and brain != null, "an agent carries a brain and a bubble")
	if bubble == null or brain == null:
		level.free()
		return

	_expect(bubble.position == BUBBLE.HEAD_OFFSET, "the bubble sits over the agent's head")
	_expect(is_equal_approx(bubble.modulate.a, BUBBLE.ALPHA), "the bubble is drawn at the original's alpha")
	_expect(brain.has_signal("goal_changed"), "the brain reports the goal it is pursuing")

	# Blitter mode 20 blends without testing z, so a wall between the camera and the bubble
	# cannot hide it. Here that means above the world composite and above the characters.
	var characters := level.get_node_or_null("World/CharacterDepthCompositor") as CanvasItem
	var world := level.get_node_or_null("World/WorldDepthCompositor") as CanvasItem
	_expect(bubble.z_index == BUBBLE.DEPTH_INDEX, "the bubble keeps its own draw order")
	_expect(
		characters != null and bubble.z_index > characters.z_index,
		"the bubble is drawn over the characters, got %d against %d" % [
			bubble.z_index, characters.z_index if characters != null else 0
		]
	)
	_expect(
		world != null and bubble.z_index > world.z_index,
		"the bubble is drawn over the world composite, not into it"
	)

	# Every entry in the table, including the two reaction goals the brain cannot pick yet.
	for goal in range(BUBBLE.BUBBLES.size()):
		bubble.show_goal(goal)
		_expect(bubble.visible, "goal %d shows a bubble" % goal)
		_expect(
			bubble.texture != null and bubble.texture.resource_path.get_file() == "%s.png" % BUBBLE.BUBBLES[goal],
			"goal %d shows %s" % [goal, BUBBLE.BUBBLES[goal]]
		)
	bubble.show_goal(-1)
	_expect(not bubble.visible, "an agent with no goal thinks about nothing")

	# The signal is what drives it, not a poll.
	brain._goal = 1
	await process_frame
	_expect(bubble.texture.resource_path.get_file() == "coffee.png", "taking up a goal raises its bubble")

	level.free()
