extends CanvasLayer

# The in-level console. Element positions and what each one shows are recovered in
# docs/hud-reference.md; sub_405930 builds them and sub_403780 feeds them.

# sub_403780 prints "XX:XX" once the clock passes this.
const CLOCK_OVERFLOW_SECONDS := 5940
const IDLE_HOVER_TEXT := "..."

const PROGRESS_SHADER := preload("res://scenes/shared/round_bar.gdshader")
# CGUIRoundBarTex's own fields: +96 is the fan radius and +1140 the angle its sweep starts
# at, which is short of the top because the painted dial is tilted.
const CLOCK_BAR_RADIUS := 36.0
const CLOCK_BAR_START_ANGLE := 0.5

# player+1008 slots each lamp watches; the smoking lamp needs both of its two.
const LAMP_SLOTS := {"LampSmoke": [5, 6], "LampMatrix": [14], "LampPiss": [26]}

# game+14732 is fed `188 - (game+14728 * 1.42 + 46)` as the width to crop off its right
# edge, so a calm office still leaves 46 of the sprite's 188 pixels showing.
const AGGRO_BAR_SIZE := Vector2(188.0, 40.0)
const AGGRO_BAR_BASE := 46.0
const AGGRO_BAR_SCALE := 1.42
# sub_407960 raises THERMO_UP and sets game+14748 to 2.0; sub_403780 counts it back down.
const THERMO_SECONDS := 2.0

@onready var _score: Label = $Score
@onready var _clock: Label = $Clock
@onready var _hover: Label = $HoverText
@onready var _action_icon: Sprite2D = $ActionIcon
@onready var _progress: Sprite2D = $ClockBar
@onready var _aggro: Sprite2D = $AggroBar
@onready var _thermo: Sprite2D = $ThermoUp

var _session: Node
var _actions: Node
var _progress_material: ShaderMaterial
var _thermo_remaining := 0.0


func _ready() -> void:
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


func _process(delta: float) -> void:
	if _thermo_remaining <= 0.0:
		return
	_thermo_remaining -= delta
	if _thermo_remaining <= 0.0:
		_thermo_remaining = 0.0
		_thermo.visible = false


func set_inventory(inventory: PackedInt32Array) -> void:
	for lamp_name in LAMP_SLOTS:
		var lamp := get_node_or_null(lamp_name) as Sprite2D
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
