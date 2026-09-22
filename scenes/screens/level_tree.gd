extends Control

# The original's screen 15. Twenty-one nodes on a triangular lattice: column c holds c of
# them, and clearing one opens the two directly beneath it in the next column. The linking
# bars are painted into the backdrop, so the screen is that one picture plus the nodes.
#
# Coordinates, the state of each node and which levels it opens all come out of
# resources/levels/index.json and the saved profile; nothing here is laid out by hand.
# See docs/shell-reference.md.

# sub_421FE0 gives each state its own pair of node faces. The original's art names are
# counter-intuitive -- FREE is a level already cleared and PLAYED one you may play now --
# so the port names the states after what they mean and maps them here.
const NODE_TEXTURES := {
	LevelProgress.State.LOCKED: [
		preload("res://images/gui/menu/level-node-locked-passive.png"),
		preload("res://images/gui/menu/level-node-locked-active.png"),
	],
	LevelProgress.State.PLAYABLE: [
		preload("res://images/gui/menu/level-node-played-passive.png"),
		preload("res://images/gui/menu/level-node-played-active.png"),
	],
	LevelProgress.State.CLEARED: [
		preload("res://images/gui/menu/level-node-free-passive.png"),
		preload("res://images/gui/menu/level-node-free-active.png"),
	],
}

# Resolved by path rather than by the autoload name: a singleton's global name is not bound
# while this script is compiled, which is how the headless tests load the scene.
@onready var _nodes: Control = $SafeFrame/Nodes
@onready var _screens: Node = get_node_or_null("/root/ScreenManager")
@onready var _progress: LevelProgress = get_node_or_null("/root/ProgressStore")


func _ready() -> void:
	_build_nodes()
	($SafeFrame/Back as TextureButton).pressed.connect(_on_back_pressed)


func _build_nodes() -> void:
	if _progress == null:
		return
	var mode: StringName = &"time"
	if _screens != null:
		mode = StringName(_screens.get("selected_game_mode"))
	var states := _progress.states(mode)
	var size := _progress.node_size()
	for number in range(1, _progress.level_count() + 1):
		var entry := _progress.level(number)
		var state: LevelProgress.State = states[number - 1]
		var button := TextureButton.new()
		button.name = "Level%d" % number
		button.position = Vector2(entry["node_position"][0], entry["node_position"][1])
		button.size = size
		var faces: Array = NODE_TEXTURES[state]
		button.texture_normal = faces[0]
		button.texture_pressed = faces[1]
		button.texture_hover = faces[1]
		# sub_421FE0 gives a locked node button id 0, which the dispatcher ignores. The node
		# is still drawn, so it stays here and simply refuses the click.
		button.disabled = state == LevelProgress.State.LOCKED
		button.tooltip_text = tr(&"level.%d.title" % number)
		button.pressed.connect(_on_level_pressed.bind(number))
		_nodes.add_child(button)


func _retitle_nodes() -> void:
	# A language change can arrive before the nodes exist; @onready has not run yet.
	if _nodes == null:
		return
	for child in _nodes.get_children():
		var button := child as TextureButton
		if button != null:
			button.tooltip_text = tr(&"level.%s.title" % button.name.trim_prefix("Level"))


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		_retitle_nodes()


func _on_level_pressed(number: int) -> void:
	if _screens != null:
		_screens.call("open_level_description", number)


func _on_back_pressed() -> void:
	if _screens != null:
		_screens.call("change_to_main_menu")
