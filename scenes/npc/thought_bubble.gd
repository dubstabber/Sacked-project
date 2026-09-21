extends Sprite2D

# What an agent is thinking about. agent+1080 is its current goal and the bubble is that
# goal's own entry in the table at 0x46E7A8, so it shows for exactly as long as the goal
# lasts. sub_417460 draws it 135 pixels above the agent at alpha 180.
# See docs/npc-reference.md.

const HEAD_OFFSET := Vector2(0.0, -135.0)
const ALPHA := 180.0 / 255.0
# sub_417460 switches the blitter to mode 20 for the bubble and back afterwards, and mode 20
# is the one entry the tables share between the z-tested and untested sprite paths
# (0x431030 in both): it blends and writes z but never tests it, so nothing already in the
# buffer can hide the bubble. Here that means drawing above the world composite (0) and the
# characters the depth compositor raises to 1.
const DEPTH_INDEX := 2
# The table's order, which is also the goal order; 8 and 9 are the reaction goals.
const BUBBLES := [
	"food", "coffee", "happy", "back-to-work", "toilett",
	"social", "cigarette", "relax", "angry", "repair",
]

var _textures: Array[Texture2D] = []


func _ready() -> void:
	centered = true
	position = HEAD_OFFSET
	modulate.a = ALPHA
	z_index = DEPTH_INDEX
	visible = false
	for name in BUBBLES:
		var path := "res://images/effects/bubbles/%s.png" % name
		_textures.append(load(path) as Texture2D if ResourceLoader.exists(path) else null)

	var brain := get_parent().get_node_or_null("Brain")
	if brain != null and brain.has_signal("goal_changed"):
		brain.goal_changed.connect(show_goal)
		show_goal(int(brain.get("_goal")))


func show_goal(goal: int) -> void:
	if goal < 0 or goal >= _textures.size() or _textures[goal] == null:
		visible = false
		return
	texture = _textures[goal]
	visible = true
