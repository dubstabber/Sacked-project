extends CanvasLayer

# The ring of action icons. `CGUIRoundMenu` is built by sub_406510, ticked by sub_4066D0 and
# laid out every frame by its draw, sub_45BC90. See docs/player-action-reference.md.

# sub_406510 places the menu at (400, 200) -- centred in the band the console leaves free,
# not in the 600-pixel window.
const CENTRE := Vector2(400.0, 200.0)
# The draw's own constants. Entries sit a fixed 0.6 radians apart rather than sharing a full
# turn, the ring is drawn at 1.5x the radius the tick animates, and every button is nudged
# 16 pixels left -- on x only, which is why the ring hangs low and slightly left of centre.
const ENTRY_PITCH := 0.60000002
const RADIUS_SCALE := 1.5
const ICON_OFFSET := Vector2(-16.0, 0.0)
# Every CO_GUI_ACTICON sprite is 48x48, and CGUIRectangle draws one from its top left.
const ICON_SIZE := Vector2(48.0, 48.0)
# sub_4066D0 grows the radius toward 60 at 150 a second while the menu is open and shrinks
# it the same way while it closes, hiding the ring once it reaches zero.
const RADIUS_LIMIT := 60.0
const RADIUS_RATE := 150.0
# The rotation eases toward the highlighted entry's angle at this+112 per second, which
# sub_405930 raises from the constructor's 0.1 to 5.0, and snaps inside this gap.
const ROTATION_RATE := 5.0
const SETTLED_EPSILON := 0.01
# sub_403FB0 raises the ring's two step bits from a mouse motion whose dx runs past eight
# pixels -- the ring turns under a fixed cursor rather than the cursor moving over it.
const STEP_THRESHOLD := 8.0
# sub_45BC90 tints the selected button and leaves the rest white, but only once this+120
# reaches 255, and sub_4066D0 feeds that radius / 60 * 254 + 1. So the colour arrives with
# the last pixel of the opening ring.
const SELECTED_TINT := Color(1.0, 1.0, 128.0 / 255.0)

var _controller: Node
var _icons: Array[TextureRect] = []
var _radius := 0.0
var _rotation := 0.0
var _target_index := 0
var _settled := true
var _closing := false
var _step_down := false
var _step_up := false


func _ready() -> void:
	visible = false
	_controller = get_tree().get_first_node_in_group("player_actions")
	if _controller == null:
		return
	_controller.menu_opened.connect(_on_menu_opened)
	_controller.menu_closed.connect(_on_menu_closed)


func _process(delta: float) -> void:
	if not visible:
		return
	advance(delta)


# Split out so a test can step the ring without a running tree. sub_4066D0 moves the radius
# and then sub_45BC90 turns the ring and places the buttons, in that order.
func advance(delta: float) -> void:
	_apply_step()
	_advance_radius(delta)
	if _closing and _radius <= 0.0:
		_clear()
		visible = false
		return
	_advance_rotation(delta)
	_layout()


# sub_45BC90: entry i sits at this+104 - i * 0.6 + PI, on a circle of this+96 * 1.5. The
# sign of the y term is the draw's own -- the + PI already mirrors both axes.
func entry_position(index: int) -> Vector2:
	var angle := _rotation - ENTRY_PITCH * float(index) + PI
	var radius := _radius * RADIUS_SCALE
	return CENTRE + ICON_OFFSET + Vector2(sin(angle), cos(angle)) * radius


# sub_403FB0 rebuilds its input bits every frame, so a step the ring was too busy to take
# is dropped rather than queued, and bit 0 is tested before bit 1.
func _apply_step() -> void:
	var down := _step_down
	var up := _step_up
	_step_down = false
	_step_up = false
	if _controller == null or not _settled or not (down or up):
		return
	var count := (_controller.entries as Array).size()
	var step := -1 if down else 1
	_controller.set_highlighted(clampi(int(_controller.highlighted) + step, 0, maxi(count - 1, 0)))


func _unhandled_input(event: InputEvent) -> void:
	if not visible or _closing:
		return
	var motion := event as InputEventMouseMotion
	if motion == null:
		return
	if motion.relative.x < -STEP_THRESHOLD:
		_step_down = true
	elif motion.relative.x > STEP_THRESHOLD:
		_step_up = true


func is_settled() -> bool:
	return _settled


func rotation_angle() -> float:
	return _rotation


func ring_radius() -> float:
	return _radius


func _advance_radius(delta: float) -> void:
	if _closing:
		_radius = maxf(_radius - delta * RADIUS_RATE, 0.0)
	else:
		_radius = minf(_radius + delta * RADIUS_RATE, RADIUS_LIMIT)


func _advance_rotation(delta: float) -> void:
	# sub_4066D0 only feeds the target while the menu is open, so a closing ring keeps
	# turning toward wherever it was left rather than unwinding to the first entry.
	if not _closing and _controller != null:
		_target_index = maxi(int(_controller.highlighted), 0)
	var target := ENTRY_PITCH * float(_target_index)
	var gap := target - _rotation
	_rotation += delta * ROTATION_RATE * (1.0 if gap >= 0.0 else -1.0)
	if (gap < 0.0 and _rotation < target) or (gap > 0.0 and _rotation > target):
		_rotation = target
	_settled = absf(gap) < SETTLED_EPSILON
	if _settled:
		_rotation = target


func _layout() -> void:
	var lit := is_fully_open()
	var highlighted := int(_controller.highlighted) if _controller != null else -1
	for index in range(_icons.size()):
		_icons[index].position = entry_position(index)
		_icons[index].modulate = SELECTED_TINT if lit and index == highlighted else Color.WHITE


# this+120, which the draw only ever compares against 255.
func is_fully_open() -> bool:
	return int(_radius / RADIUS_LIMIT * 254.0 + 1.0) >= 255


func _on_menu_opened(entries: Array) -> void:
	_clear()
	for index in range(entries.size()):
		var icon := TextureRect.new()
		icon.texture = entries[index].get("icon")
		icon.size = ICON_SIZE
		add_child(icon)
		_icons.append(icon)
	# sub_406510 reopens from a standstill: no radius, no rotation, first entry selected.
	_radius = 0.0
	_rotation = 0.0
	_target_index = 0
	_settled = true
	_closing = false
	_step_down = false
	_step_up = false
	visible = true
	_layout()


func _on_menu_closed() -> void:
	# The icons stay until the ring has shrunk away; sub_4066D0 hides it at radius zero.
	_closing = true


func _clear() -> void:
	for icon in _icons:
		icon.queue_free()
	_icons.clear()
