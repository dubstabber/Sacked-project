@tool
class_name OverlayMapLayer
extends TileMapLayer

# A layer of INFODATA a level paints but never shows: the rooms (bits 16-23) and the cells
# that block sight (bit 1). Hidden in play unless show_in_game is set, and saved hidden in the
# editor too until the eye beside it shows it for painting; CollisionMapLayer reads its cells
# either way. See docs/map-authoring.md and docs/collision-reference.md.

# Draw each painted cell's alternative tile, the room id, on it in the editor.
@export var label_cells := false:
	set(value):
		label_cells = value
		_refresh_labels()
@export var show_in_game := false:
	set(value):
		show_in_game = value
		if is_inside_tree() and not Engine.is_editor_hint():
			visible = show_in_game

var _labels: Node2D


func _ready() -> void:
	if not Engine.is_editor_hint():
		visible = show_in_game
		return
	if not changed.is_connected(_refresh_labels):
		changed.connect(_refresh_labels)
	_refresh_labels()


func _refresh_labels() -> void:
	if not Engine.is_editor_hint() or not is_inside_tree():
		return
	if _labels == null:
		_labels = Node2D.new()
		_labels.z_index = 1
		_labels.draw.connect(_draw_labels)
		add_child(_labels, false, Node.INTERNAL_MODE_FRONT)
	_labels.queue_redraw()


func _draw_labels() -> void:
	if not label_cells:
		return
	# The port's own face, which the project theme carries, as every other text in the game.
	var theme := ThemeDB.get_project_theme()
	var font: Font = theme.default_font if theme != null else null
	if font == null:
		return
	for cell in get_used_cells():
		var text := str(get_cell_alternative_tile(cell))
		var size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16)
		_labels.draw_string_outline(font, map_to_local(cell) + Vector2(-size.x * 0.5, 6), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, 4, Color.BLACK)
		_labels.draw_string(font, map_to_local(cell) + Vector2(-size.x * 0.5, 6), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)
