extends CanvasLayer

# The in-level console. Element positions and what each one shows are recovered in
# docs/hud-reference.md; sub_405930 builds them and sub_403780 feeds them.
#
# The recovered coordinates are absolute in the original's 800x600 viewport, so they live as
# offsets inside two 800x600 bands: Band carries the original's bottom-aligned elements and
# Banners its top-aligned ones. See docs/widescreen.md.

# sub_403780 prints "XX:XX" once the clock passes this.
const CLOCK_OVERFLOW_SECONDS := 5940
const IDLE_HOVER_TEXT := "..."

# Both retail builds paint their two field labels into the console art, so each ships its
# own. The Polish one has them over the wrong fields, which the port keeps by showing that
# build's art unaltered; the German one is correct. Anything else gets the frame with the
# words removed and draws its own, in the German build's order.
# See docs/strings-reference.md and docs/hud-reference.md.
const PAINTED_FRAMES := {
	&"pl": preload("res://images/gui/hud/console.png"),
	&"de": preload("res://images/gui/hud/console-de.png"),
}
const UNLABELLED_FRAME := preload("res://images/gui/hud/console-unlabelled.png")

const PROGRESS_SHADER := preload("res://scenes/shared/round_bar.gdshader")
# CGUIRoundBarTex's own fields: +96 is the fan radius and +1140 the angle its sweep starts
# at, which is short of the top because the painted dial is tilted.
const CLOCK_BAR_RADIUS := 36.0
const CLOCK_BAR_START_ANGLE := 0.5

const AbilityController := preload("res://scenes/player/ability_controller.gd")

# player+1008 slots each lamp watches; the smoking lamp needs both of its two.
const LAMP_SLOTS := {"LampSmoke": [5, 6], "LampMatrix": [14], "LampPiss": [26]}
# sub_405930 registers the lamps in this order (0x4060E0), and sub_459AE0 walks them in it, so
# where the urination and smoking rects overlap the urination lamp takes the press.
const LAMP_ORDER := ["LampMatrix", "LampPiss", "LampSmoke"]
# The bit sub_403FB0 turns each lamp's id into (0x404070-0x404086).
const LAMP_REQUESTS := {
	"LampMatrix": AbilityController.REQUEST_PILL,
	"LampPiss": AbilityController.REQUEST_PISS,
	"LampSmoke": AbilityController.REQUEST_SMOKE,
}
# Only these three have a release edge in sub_45D850's byte (0x45D8BC-0x45D90B).
const RELEASE_BUTTONS := [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]

# game+14732 is fed `188 - (game+14728 * 1.42 + 46)` as the width to crop off its right
# edge, so a calm office still leaves 46 of the sprite's 188 pixels showing.
const AGGRO_BAR_SIZE := Vector2(188.0, 40.0)
const AGGRO_BAR_BASE := 46.0
const AGGRO_BAR_SCALE := 1.42
# sub_407960 raises THERMO_UP and sets game+14748 to 2.0; sub_403780 counts it back down.
const THERMO_SECONDS := 2.0
# sub_407990 raises AGGRO_UP on a catch, and both sub_403780 and Main_RenderUpdate watch
# game+72 while the screen is 4: at 2.0 s the banner comes down and the minigame opens.
const AGGRO_SECONDS := 2.0

@onready var _score: Label = $Band/Score
@onready var _clock: Label = $Band/Clock
@onready var _hover: Label = $Band/HoverText
@onready var _action_icon: Sprite2D = $Band/ActionIcon
@onready var _progress: Sprite2D = $Band/ClockBar
@onready var _aggro: Sprite2D = $Band/AggroBar
@onready var _thermo: Sprite2D = $Banners/ThermoUp
@onready var _aggro_up: Sprite2D = $Banners/AggroUp
@onready var _aggro_up_text: Label = $Banners/AggroUp/AggroUpText
@onready var _frame: Sprite2D = $Band/Frame
@onready var _painted_labels: Array[Label] = [$Band/LeftLabel, $Band/RightLabel]

var _session: Node
var _actions: Node
var _abilities: Node
# The GUI manager's left button (+64 & 1), its click latch (+68) and its own cursor (+52/+56).
var _left_held := false
var _latched := false
var _pointer := Vector2.INF
var _progress_material: ShaderMaterial
var _thermo_remaining := 0.0
var _aggro_up_remaining := 0.0


func _ready() -> void:
	add_to_group("level_console")
	_session = get_tree().get_first_node_in_group("level_session")
	if _session != null:
		_session.score_changed.connect(_on_score_changed)
		_session.time_changed.connect(_on_time_changed)
		_session.aggression_changed.connect(set_aggression)
		_session.aggravation_rose.connect(warn_of_aggravation)
		_on_score_changed(_session.score)
		_on_time_changed(int(_session.elapsed))
		set_aggression(float(_session.aggression))
	set_hover_text(IDLE_HOVER_TEXT)
	_match_frame_to_language()

	# game+14724 sits at (662, 536) -- the stopwatch -- and is fed
	# player+992 * 100 / player+1000, swept rather than clipped. That position is the centre
	# of the sweep, not the texture's corner, which is why the sprite hangs a radius up and
	# left of it. See docs/hud-reference.md.
	_progress_material = ShaderMaterial.new()
	_progress_material.shader = PROGRESS_SHADER
	_progress_material.set_shader_parameter("radius", CLOCK_BAR_RADIUS)
	_progress_material.set_shader_parameter("start_angle", CLOCK_BAR_START_ANGLE)
	_progress.material = _progress_material
	set_action_progress(0.0, 0.0)

	_actions = get_tree().get_first_node_in_group("player_actions")
	if _actions != null:
		_actions.highlight_changed.connect(_on_highlight_changed)
		_actions.progress_changed.connect(set_action_progress)
		_actions.inventory_changed.connect(set_inventory)
		set_inventory(_actions.inventory)
	_abilities = get_tree().get_first_node_in_group("player_abilities")


# The centre field carries the highlighted action's icon and the hover bar its name.
func _on_highlight_changed(entry: Dictionary) -> void:
	var icon := entry.get("icon") as Texture2D
	_action_icon.texture = icon
	_action_icon.visible = icon != null
	set_hover_text(String(entry.get("name", "")))


func set_action_progress(elapsed: float, total: float) -> void:
	if _progress.texture == null:
		return
	var fraction := clampf(elapsed / total, 0.0, 1.0) if total > 0.0 else 0.0
	_progress.visible = fraction > 0.0
	_progress_material.set_shader_parameter("progress", fraction)


# The original crops the bar's right edge by a truncated width, so what survives is the
# complement of that truncation rather than a truncation of the fill itself.
func set_aggression(level: float) -> void:
	var crop := int(AGGRO_BAR_SIZE.x - (level * AGGRO_BAR_SCALE + AGGRO_BAR_BASE))
	var width := clampi(int(AGGRO_BAR_SIZE.x) - crop, 0, int(AGGRO_BAR_SIZE.x))
	_aggro.region_rect = Rect2(0.0, 0.0, float(width), AGGRO_BAR_SIZE.y)


func warn_of_aggravation() -> void:
	_thermo_remaining = THERMO_SECONDS
	_thermo.visible = true


# sub_407990: the banner and one of four exclamations, for as long as the two-second caught
# pause (screen 4) that follows a catch. See docs/catch-reference.md. The Label translates the key itself.
func warn_of_catch(exclamation_key: StringName) -> void:
	_aggro_up_text.text = String(exclamation_key)
	_aggro_up_remaining = AGGRO_SECONDS
	_aggro_up.visible = true


func hide_catch_warning() -> void:
	_aggro_up_remaining = 0.0
	_aggro_up.visible = false


# The lamps are buttons. sub_459AE0 clicks a visible lamp on the first button event with the
# left button down, the cursor strictly inside the lamp's sprite and the latch clear, and a
# button event goes out on every frame a button is held; any release edge clears the latch.
# So one press fires once, a drag onto a lit lamp fires, and the right and middle buttons
# never do. The port takes the press here, before the world sees it, so it never opens the
# ring or selects anyone behind the lamp. See docs/player-ability-reference.md.
func _input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button != null:
		_pointer = button.position
		if not button.pressed:
			if RELEASE_BUTTONS.has(button.button_index):
				_latched = false
				if button.button_index == MOUSE_BUTTON_LEFT:
					_left_held = false
			return
		if button.button_index != MOUSE_BUTTON_LEFT:
			return
		_left_held = true
		if _press_lamp(button.position):
			get_viewport().set_input_as_handled()
		return
	var motion := event as InputEventMouseMotion
	if motion != null:
		_pointer = motion.position
		if _left_held:
			_press_lamp(motion.position)


func _press_lamp(viewport_position: Vector2) -> bool:
	var lamp_name := lamp_at(viewport_position)
	if lamp_name == "" or _latched:
		return false
	_latched = true
	if is_instance_valid(_abilities):
		_abilities.request(LAMP_REQUESTS[lamp_name])
	return true


# Which lit lamp a viewport position is strictly inside, the rect being the sprite's own size
# (slot 34, sub_45B720). Nothing while the ring is up or still closing: sub_4066D0 re-centres
# both cursors on every tick of the close (0x40685A, 0x406873), so a lamp cannot be reached.
func lamp_at(viewport_position: Vector2) -> String:
	if _ring_is_up():
		return ""
	var band := get_node("Band") as Control
	var local := band.get_global_transform_with_canvas().affine_inverse() * viewport_position
	var cursor := Vector2i(floori(local.x), floori(local.y))
	for lamp_name: String in LAMP_ORDER:
		var lamp := get_node_or_null("Band/" + lamp_name) as Sprite2D
		if lamp == null or not lamp.visible or lamp.texture == null:
			continue
		var corner := Vector2i(lamp.position)
		var size := Vector2i(lamp.texture.get_size())
		if cursor.x > corner.x and cursor.y > corner.y and cursor.x < corner.x + size.x and cursor.y < corner.y + size.y:
			return lamp_name
	return ""


func _ring_is_up() -> bool:
	var ring := get_parent().get_node_or_null("RoundMenu") if get_parent() != null else null
	return ring != null and bool(ring.get("visible"))


func _process(delta: float) -> void:
	if _left_held and not _latched and _pointer.is_finite():
		_press_lamp(_pointer)
	if _thermo_remaining > 0.0:
		_thermo_remaining -= delta
		if _thermo_remaining <= 0.0:
			_thermo_remaining = 0.0
			_thermo.visible = false
	if _aggro_up_remaining > 0.0:
		_aggro_up_remaining -= delta
		if _aggro_up_remaining <= 0.0:
			_aggro_up_remaining = 0.0
			_aggro_up.visible = false


func set_inventory(inventory: PackedInt32Array) -> void:
	for lamp_name in LAMP_SLOTS:
		var lamp := get_node_or_null("Band/" + lamp_name) as Sprite2D
		if lamp == null:
			continue
		var lit := true
		for slot in LAMP_SLOTS[lamp_name]:
			if int(slot) >= inventory.size() or inventory[int(slot)] <= 0:
				lit = false
		lamp.visible = lit


# The original puts the score in the left field and the clock in the right one, under
# labels painted the other way round. See docs/hud-reference.md.
func _on_score_changed(score: int) -> void:
	_score.text = "%05d" % clampi(score, 0, 99999)


func _on_time_changed(seconds: int) -> void:
	if seconds > CLOCK_OVERFLOW_SECONDS:
		_clock.text = "XX:XX"
	else:
		_clock.text = "%02d:%02d" % [seconds / 60, seconds % 60]


func set_hover_text(text: String) -> void:
	_hover.text = text if text != "" else IDLE_HOVER_TEXT


func _match_frame_to_language() -> void:
	var language := StringName(TranslationServer.get_locale().substr(0, 2))
	var painted: Texture2D = PAINTED_FRAMES.get(language)
	_frame.texture = painted if painted != null else UNLABELLED_FRAME
	for label in _painted_labels:
		label.visible = painted == null


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and _frame != null:
		_match_frame_to_language()
	# A paused console hears no release, but sub_45D850 still polls the buttons.
	elif what == NOTIFICATION_UNPAUSED and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_left_held = false
		_latched = false
