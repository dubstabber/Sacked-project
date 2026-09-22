extends SceneTree

# The original's screen 15: 21 nodes on the triangular lattice, each drawn in the state the
# saved profile gives it, and a locked one that refuses the click rather than being absent.
# See docs/shell-reference.md.

const TreeScene := preload("res://scenes/screens/level_tree.tscn")
const STORE_SCRIPT := preload("res://autoloads/progress_store.gd")
const TEST_PATH := "user://check_level_tree.cfg"

const LOCKED_FACE := preload("res://images/gui/menu/level-node-locked-passive.png")
const PLAYABLE_FACE := preload("res://images/gui/menu/level-node-played-passive.png")
const CLEARED_FACE := preload("res://images/gui/menu/level-node-free-passive.png")

var _failures := 0
var _restore_path := ""


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var store := root.get_node("ProgressStore")
	_restore_path = store.path
	store.path = TEST_PATH
	DirAccess.remove_absolute(TEST_PATH)
	store.reload()

	await _check_a_fresh_profile_shows_one_open_node()
	await _check_clearing_level_one_lights_its_two_children()
	_check_every_node_sits_where_the_original_puts_it()

	store.path = _restore_path
	store.reload()
	DirAccess.remove_absolute(TEST_PATH)
	if _failures == 0:
		print("Level tree: the lattice, its three node states and the locked node's dead click passed")
	quit(1 if _failures else 0)


func _expect(condition: bool, label: String) -> void:
	if not condition:
		_failures += 1
		push_error(label)


func _mount() -> Control:
	var screen := TreeScene.instantiate() as Control
	root.add_child(screen)
	await process_frame
	return screen


func _node(screen: Control, number: int) -> TextureButton:
	return screen.get_node_or_null("SafeFrame/Nodes/Level%d" % number) as TextureButton


func _check_a_fresh_profile_shows_one_open_node() -> void:
	var screen := await _mount()
	_expect(screen.get_node_or_null("SafeFrame/Back") != null, "the tree has its main-menu button")

	var open := _node(screen, 1)
	_expect(open != null, "the tree builds a node for level 1")
	if open != null:
		_expect(open.texture_normal == PLAYABLE_FACE, "level 1 wears the playable face on a fresh profile")
		_expect(not open.disabled, "level 1 is clickable on a fresh profile")

	for number in range(2, 22):
		var button := _node(screen, number)
		_expect(button != null, "the tree builds a node for level %d" % number)
		if button != null:
			_expect(button.texture_normal == LOCKED_FACE, "level %d wears the locked face" % number)
			# sub_421FE0 gives a locked node button id 0, so the click goes nowhere.
			_expect(button.disabled, "level %d refuses the click while it is locked" % number)
	screen.queue_free()
	await process_frame


func _check_clearing_level_one_lights_its_two_children() -> void:
	var store := root.get_node("ProgressStore")
	store.record_result(1, &"time", true, 4000, 200.0, "Jo")

	var screen := await _mount()
	_expect(_node(screen, 1).texture_normal == CLEARED_FACE, "a cleared level 1 wears the cleared face")
	for number in [2, 3]:
		_expect(
			_node(screen, number).texture_normal == PLAYABLE_FACE,
			"level %d opens when level 1 is cleared" % number
		)
		_expect(not _node(screen, number).disabled, "level %d becomes clickable" % number)
	_expect(_node(screen, 4).texture_normal == LOCKED_FACE, "level 4 stays locked behind level 2")
	screen.queue_free()
	await process_frame


func _check_every_node_sits_where_the_original_puts_it() -> void:
	var text := FileAccess.get_file_as_string("res://resources/levels/index.json")
	var index: Dictionary = JSON.parse_string(text)
	var screen := TreeScene.instantiate() as Control
	root.add_child(screen)
	var size: Array = index["tree"]["node_size"]
	for entry: Dictionary in index["levels"]:
		var button := _node(screen, int(entry["number"]))
		if button == null:
			continue
		var expected := Vector2(entry["node_position"][0], entry["node_position"][1])
		_expect(
			button.position.is_equal_approx(expected),
			"level %d sits at %s, expected %s" % [entry["number"], button.position, expected]
		)
		_expect(
			button.size.is_equal_approx(Vector2(size[0], size[1])),
			"level %d is a %s node" % [entry["number"], size]
		)
	screen.queue_free()
