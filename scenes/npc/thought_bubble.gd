extends Sprite2D

# What an agent is thinking about. agent+1080 is its current goal and the bubble is that
# goal's own entry in the table at 0x46E7A8, so it shows for exactly as long as the goal
# lasts. sub_417460 draws it 135 pixels above the agent at alpha 180, and sub_42D780 places
# the sprite by its own pivot there, (25, 65) on every bubble, not by its centre.
# See docs/npc-reference.md.

const OriginalData := preload("res://scenes/shared/original_data.gd")
const HEAD_OFFSET := Vector2(0.0, -135.0)
# Each bubble's offset, minus its SPRITE pivot, written by tools/export_gui_assets.py.
const OFFSETS_PATH := "res://resources/effects/bubbles.json"
const ALPHA := 180.0 / 255.0
# While the colleague is hovered, sub_417460 draws over its bubble a second time (the agent's
# draw is called again for the hovered one, 0x402A24), and mode 20 blends without a key, so the
# bubble comes out as the same alpha composited over itself: 1 - (1 - a)^2. It is lighter, and
# it does not pulse. See docs/player-action-reference.md.
const HOVER_ALPHA := 1.0 - (1.0 - ALPHA) * (1.0 - ALPHA)
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
var _offsets: Array[Vector2] = []


func _ready() -> void:
	centered = false
	position = HEAD_OFFSET
	modulate.a = ALPHA
	z_index = DEPTH_INDEX
	visible = false
	var offsets: Dictionary = OriginalData.load_original(OFFSETS_PATH).get("offsets", {})
	for name in BUBBLES:
		var path := "res://images/effects/bubbles/%s.png" % name
		_textures.append(load(path) as Texture2D if ResourceLoader.exists(path) else null)
		var pivot: Array = offsets.get(path, [0, 0])
		_offsets.append(Vector2(float(pivot[0]), float(pivot[1])))

	var brain := get_parent().get_node_or_null("Brain")
	if brain != null and brain.has_signal("goal_changed"):
		brain.goal_changed.connect(show_goal)
		show_goal(int(brain.get("_goal")))


func show_goal(goal: int) -> void:
	if goal < 0 or goal >= _textures.size() or _textures[goal] == null:
		visible = false
		return
	texture = _textures[goal]
	offset = _offsets[goal]
	visible = true


# The colleague this bubble belongs to is, or is not, the one under the cursor: draw lighter
# while it is, as the hover redraw does, and back to its own alpha when it is not.
func set_emphasis(on: bool) -> void:
	modulate.a = HOVER_ALPHA if on else ALPHA
