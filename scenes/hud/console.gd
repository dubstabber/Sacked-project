extends CanvasLayer

# The in-level console. Element positions and what each one shows are recovered in
# docs/hud-reference.md; sub_405930 builds them and sub_403780 feeds them.

# sub_403780 prints "XX:XX" once the clock passes this.
const CLOCK_OVERFLOW_SECONDS := 5940
const IDLE_HOVER_TEXT := "..."

@onready var _score: Label = $Score
@onready var _clock: Label = $Clock
@onready var _hover: Label = $HoverText

var _session: Node


func _ready() -> void:
	_session = get_tree().get_first_node_in_group("level_session")
	if _session != null:
		_session.score_changed.connect(_on_score_changed)
		_session.time_changed.connect(_on_time_changed)
		_on_score_changed(_session.score)
		_on_time_changed(int(_session.elapsed))
	set_hover_text(IDLE_HOVER_TEXT)


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
