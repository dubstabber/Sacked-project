extends CanvasLayer

# The in-level console. Element positions and what each one shows are recovered in
# docs/hud-reference.md; sub_405930 builds them and sub_403780 feeds them.

# sub_403780 prints "XX:XX" once the clock passes this.
const CLOCK_OVERFLOW_SECONDS := 5940
const IDLE_HOVER_TEXT := "..."

# player+1008 slots each lamp watches; the smoking lamp needs both of its two.
const PROGRESS_SHADER := preload("res://scenes/shared/round_bar.gdshader")

const LAMP_SLOTS := {"LampSmoke": [5, 6], "LampMatrix": [14], "LampPiss": [26]}

@onready var _score: Label = $Score
@onready var _clock: Label = $Clock
@onready var _hover: Label = $HoverText
@onready var _action_icon: Sprite2D = $ActionIcon
@onready var _progress: Sprite2D = $ClockBar

var _session: Node
var _actions: Node
var _progress_material: ShaderMaterial


func _ready() -> void:
	_session = get_tree().get_first_node_in_group("level_session")
	if _session != null:
		_session.score_changed.connect(_on_score_changed)
		_session.time_changed.connect(_on_time_changed)
		_on_score_changed(_session.score)
		_on_time_changed(int(_session.elapsed))
	set_hover_text(IDLE_HOVER_TEXT)

	# game+14724 sits at (662, 536) -- the stopwatch -- and is fed
	# player+992 * 100 / player+1000, swept rather than clipped. See docs/hud-reference.md.
	_progress_material = ShaderMaterial.new()
	_progress_material.shader = PROGRESS_SHADER
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
