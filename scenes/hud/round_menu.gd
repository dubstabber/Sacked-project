extends CanvasLayer

# The ring of action icons. sub_406510 places it at (400, 200) in an 800x600 frame --
# centred in the band the console leaves free, not in the window. The ring's own radius is
# not recovered (the third value there is the GUI layer), so RADIUS is a port choice: just
# wide enough that eight icons sit side by side without overlapping. The angles follow the
# engine's circle convention from sub_45A9E0 -- zero at the top, running clockwise.
# See docs/player-action-reference.md.

const CENTRE := Vector2(400.0, 200.0)
const RADIUS := 64.0
const ICON_SIZE := Vector2(48.0, 48.0)

var _controller: Node
var _icons: Array[TextureRect] = []


func _ready() -> void:
	visible = false
	_controller = get_tree().get_first_node_in_group("player_actions")
	if _controller == null:
		return
	_controller.menu_opened.connect(_on_menu_opened)
	_controller.menu_closed.connect(_on_menu_closed)


func _process(_delta: float) -> void:
	if not visible or _controller == null or _icons.is_empty():
		return
	_controller.set_highlighted(_entry_under_cursor())
	for index in range(_icons.size()):
		_icons[index].modulate = Color.WHITE if index == _controller.highlighted else Color(0.65, 0.65, 0.65)


func entry_position(index: int, count: int) -> Vector2:
	var angle := TAU * float(index) / float(maxi(count, 1))
	return CENTRE + Vector2(sin(angle), -cos(angle)) * RADIUS


func _entry_under_cursor() -> int:
	var cursor := get_viewport().get_mouse_position()
	for index in range(_icons.size()):
		if Rect2(_icons[index].position, ICON_SIZE).has_point(cursor):
			return index
	return _controller.highlighted


func _on_menu_opened(entries: Array) -> void:
	_clear()
	for index in range(entries.size()):
		var icon := TextureRect.new()
		icon.texture = entries[index].get("icon")
		icon.size = ICON_SIZE
		icon.position = entry_position(index, entries.size()) - ICON_SIZE * 0.5
		add_child(icon)
		_icons.append(icon)
	visible = true


func _on_menu_closed() -> void:
	_clear()
	visible = false


func _clear() -> void:
	for icon in _icons:
		icon.queue_free()
	_icons.clear()
