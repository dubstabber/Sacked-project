extends CanvasLayer

# Screen 5: the duel a colleague drags the player into after catching them mid-prank.
# Recovered in docs/minigame-reference.md, which this follows field for field; the original
# is MiniGame.cpp and its own names are used where they help.
#
# The opponent casts a run of icons and the player repeats it from the answer row. Both
# sides start on eight energy and move in steps of three, so three good rounds win it.

signal finished(won: bool)

const MinigameArt := preload("res://scenes/level/catch_minigame_art.gd")

# sub_414870's constants, in the order its state machine uses them.
const GET_READY_SECONDS := 2.0
const STEP_SECONDS := 1.0
# A cast is blanked for a quarter of a step before the next one arrives.
const GAP_FRACTION := 0.25
const YOUR_TURN_SECONDS := 1.0
const ANSWER_SECONDS := 4.2999998
const RESULT_SECONDS := 3.0
const ENERGY_START := 8
const ENERGY_STEP := 3
# m_acSequence is a permutation of these; m_acSerial is drawn from its first `difficulty`.
const SEQUENCE_SIZE := 7
const SERIAL_SIZE := 64
# The seven casts are S1004 up; winning plays S1002 and losing S1001.
const CAST_SOUND_BASE := 1004
const WIN_SOUND := "S1002"
const LOSE_SOUND := "S1001"

enum State { IDLE, GET_READY, BUILD, CASTING, YOUR_TURN, ANSWERING, ROUND_LOST, ROUND_WON, WON, LOST }

@onready var _frame: Control = $SafeFrame
@onready var _enemy_portrait: Sprite2D = $SafeFrame/EnemyPortrait
@onready var _player_portrait: Sprite2D = $SafeFrame/PlayerPortrait
@onready var _cast_spell: Sprite2D = $SafeFrame/CastSpell
@onready var _answer_spell: Sprite2D = $SafeFrame/AnswerSpell
@onready var _bar_enemy: Sprite2D = $SafeFrame/BarEnemy
@onready var _bar_player: Sprite2D = $SafeFrame/BarPlayer
@onready var _countdown: Label = $SafeFrame/Countdown
@onready var _background: Sprite2D = $SafeFrame/Background
@onready var _buttons: Control = $SafeFrame/Buttons
@onready var _banners: Control = $SafeFrame/Banners

var state: State = State.IDLE
var enemy_energy := ENERGY_START
var player_energy := ENERGY_START
var cast_count := 2
var difficulty := 4

var _sequence: PackedByteArray = PackedByteArray()
var _serial: PackedByteArray = PackedByteArray()
var _cast_position := 0
var _answer_position := 0
var _answer_choice := -1
var _timer := 0.0
var _phase := 0.0
var _in_gap := false
var _cast_sound_played := false
var _answer_showing := false
var _random := RandomNumberGenerator.new()
var _banner_nodes: Dictionary = {}
var _audio: Node

@export var random_seed: int = 0


func _ready() -> void:
	add_to_group("catch_minigame")
	process_mode = Node.PROCESS_MODE_ALWAYS
	_random.seed = random_seed if random_seed != 0 else randi()
	_build_banners()
	set_process(false)


# The caller names who did the catching; everything else follows from that.
func open(catcher: StringName, character: StringName, casts: int) -> void:
	difficulty = MinigameArt.difficulty_for(catcher)
	cast_count = maxi(1, casts)
	enemy_energy = ENERGY_START
	player_energy = ENERGY_START
	_enemy_portrait.texture = MinigameArt.portrait_for(catcher)
	_player_portrait.texture = MinigameArt.player_portrait_for(character)
	_place_portrait(_enemy_portrait, true)
	_place_portrait(_player_portrait, false)
	_sequence = _shuffled_sequence()
	_build_buttons()
	_refresh_bars()
	_cast_position = 0
	_answer_position = 0
	_answer_choice = -1
	_timer = 0.0
	_phase = 0.0
	_answer_showing = false
	_cast_spell.visible = false
	_answer_spell.visible = false
	_audio = get_tree().get_first_node_in_group("level_audio")
	_show_banner(&"")
	state = State.GET_READY
	visible = true
	set_process(true)


# The portraits are flush to the bottom corners; the constructor's own numbers are just the
# resolved form of its bottom-left and bottom-right alignment flags.
func _place_portrait(portrait: Sprite2D, left: bool) -> void:
	if portrait.texture == null:
		return
	var size := portrait.texture.get_size()
	portrait.position = Vector2(0.0 if left else 800.0 - size.x, 600.0 - size.y)


# m_acSequence: seven distinct values drawn at random, which the serial is then built from.
func _shuffled_sequence() -> PackedByteArray:
	var pool: Array[int] = []
	for value in range(SEQUENCE_SIZE):
		pool.append(value)
	var result := PackedByteArray()
	while not pool.is_empty():
		result.append(pool.pop_at(_random.randi() % pool.size()))
	return result


# m_acSerial: sixty-four casts drawn from the first `difficulty` of the permutation, so a
# harder opponent draws on more of the seven icons.
func _build_serial() -> void:
	_serial = PackedByteArray()
	for i in range(SERIAL_SIZE):
		_serial.append(_sequence[_random.randi() % difficulty])


func _process(delta: float) -> void:
	# sub_4138A0 turns the backdrop a hundredth of a radian per drawn frame. It does that by
	# spinning the texture coordinates of a quad pinned to the screen, so the original never
	# shows a corner; this spins the sprite instead and scales it up enough that the frame's
	# corners stay covered at every angle. See docs/minigame-reference.md.
	_background.rotation += 0.01
	match state:
		State.GET_READY:
			_advance_get_ready(delta)
		State.BUILD:
			_advance_build()
		State.CASTING:
			_advance_casting(delta)
		State.YOUR_TURN:
			_advance_your_turn(delta)
		State.ANSWERING:
			_advance_answering(delta)
		State.WON, State.LOST:
			_advance_result(delta)
	if state == State.ROUND_WON:
		enemy_energy -= ENERGY_STEP
		_begin_round()
	elif state == State.ROUND_LOST:
		player_energy -= ENERGY_STEP
		_begin_round()
	_refresh_bars()
	_check_energy()


func _begin_round() -> void:
	_cast_position = 0
	_answer_position = 0
	_answer_choice = -1
	state = State.BUILD


func _advance_get_ready(delta: float) -> void:
	_show_banner(&"get_ready")
	_timer += delta
	if _timer > GET_READY_SECONDS:
		_timer = 0.0
		_show_banner(&"")
		state = State.BUILD


func _advance_build() -> void:
	_build_serial()
	_timer = 0.0
	_phase = 0.0
	_in_gap = false
	_cast_sound_played = false
	_answer_choice = -1
	_answer_position = 0
	_countdown_seconds = ANSWER_SECONDS
	_cast_spell.visible = false
	_answer_spell.visible = false
	state = State.CASTING


var _countdown_seconds := ANSWER_SECONDS


# The opponent's turn: each cast is up for a step and blanked for a quarter of one.
func _advance_casting(delta: float) -> void:
	_phase += delta
	if _phase > STEP_SECONDS and not _in_gap:
		_phase = 0.0
		_in_gap = true
		_cast_sound_played = false
	if _in_gap and _phase > STEP_SECONDS * GAP_FRACTION:
		_phase = 0.0
		_in_gap = false
		_cast_position += 1

	if _cast_position >= cast_count:
		_cast_spell.visible = false
		_timer = YOUR_TURN_SECONDS
		_countdown_seconds = ANSWER_SECONDS
		_answer_position = 0
		state = State.YOUR_TURN
		return

	if _in_gap:
		_cast_spell.visible = false
		return
	_cast_spell.texture = MinigameArt.spell(int(_serial[_cast_position]))
	_cast_spell.visible = true
	if not _cast_sound_played:
		_play("S%04d" % (CAST_SOUND_BASE + int(_serial[_cast_position])))
		_cast_sound_played = true


func _advance_your_turn(delta: float) -> void:
	_show_banner(&"your_turn")
	_timer -= delta
	if _timer <= 0.0:
		_show_banner(&"")
		_phase = 0.0
		_answer_showing = false
		state = State.ANSWERING


# The player's turn. Running the clock out is a miss, and so is a wrong answer; the check
# happens a step after the click, while the chosen icon is on show.
func _advance_answering(delta: float) -> void:
	_countdown_seconds -= delta
	if _countdown_seconds < 0.0:
		_countdown_seconds = 0.0
		state = State.ROUND_LOST
		return
	if not _answer_showing:
		_answer_spell.visible = false
		return
	_phase += delta
	if _phase < STEP_SECONDS:
		_answer_spell.texture = MinigameArt.answer_spell(_answer_choice)
		_answer_spell.visible = true
		return
	_answer_spell.visible = false
	_answer_showing = false
	# The original sets the won state first and lets a wrong last answer overwrite it, so
	# the final icon still has to be right.
	if _answer_position >= cast_count:
		state = State.ROUND_WON
	if int(_serial[_answer_position - 1]) != _answer_choice:
		state = State.ROUND_LOST


func _advance_result(delta: float) -> void:
	_countdown_seconds = 0.0
	_timer -= delta
	if _timer < 0.0:
		visible = false
		set_process(false)
		var won := state == State.WON
		state = State.IDLE
		finished.emit(won)


func _check_energy() -> void:
	if state == State.WON or state == State.LOST or state == State.IDLE:
		return
	if enemy_energy < 0:
		enemy_energy = 0
		_timer = RESULT_SECONDS
		state = State.WON
		_show_banner(&"win")
		_play(WIN_SOUND)
	elif player_energy < 0:
		player_energy = 0
		_timer = RESULT_SECONDS
		state = State.LOST
		_show_banner(&"lose")
		_play(LOSE_SOUND)


# An answer button was clicked. Outside the answering state the console is inert.
func answer(choice: int) -> void:
	if state != State.ANSWERING or _answer_showing:
		return
	_answer_choice = choice
	_answer_position += 1
	_answer_showing = true
	_phase = 0.0


# The enemy's bar drains from the left and the player's from the right.
func _refresh_bars() -> void:
	var full := _bar_enemy.texture.get_size() if _bar_enemy.texture != null else Vector2(370, 30)
	var enemy_width := int(full.x * clampf(float(enemy_energy) / float(ENERGY_START), 0.0, 1.0))
	_bar_enemy.region_rect = Rect2(full.x - enemy_width, 0.0, enemy_width, full.y)
	_bar_enemy.position = Vector2(20.0 + full.x - enemy_width, 20.0)
	var player_width := int(full.x * clampf(float(player_energy) / float(ENERGY_START), 0.0, 1.0))
	_bar_player.region_rect = Rect2(0.0, 0.0, player_width, full.y)
	_countdown.text = "%02d" % int(_countdown_seconds)


func _build_buttons() -> void:
	for child in _buttons.get_children():
		child.queue_free()
	for slot in MinigameArt.button_slots(difficulty, _sequence):
		var is_answer := bool(slot["answer"])
		var button := TextureButton.new()
		button.name = ("Button%d" if is_answer else "Slot%d") % int(slot["index"])
		button.texture_normal = MinigameArt.icon(int(slot["icon"]))
		button.position = Vector2(float(slot["x"]), MinigameArt.BUTTON_Y)
		button.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_buttons.add_child(button)
		if is_answer:
			button.pressed.connect(answer.bind(int(slot["answer_choice"])))
		else:
			# A sequence slot is a reminder of the round's vocabulary, not a control.
			button.mouse_filter = Control.MOUSE_FILTER_IGNORE


# Each banner is the build's own painted art where there is one, and a drawn label where
# there is not. See docs/strings-reference.md.
func _build_banners() -> void:
	for role in MinigameArt.BANNER_ROLES:
		var holder := Control.new()
		holder.name = String(role)
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.visible = false
		_banners.add_child(holder)
		var art := Sprite2D.new()
		art.name = "Art"
		art.centered = false
		art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		holder.add_child(art)
		var label := Label.new()
		label.name = "Text"
		label.text = "minigame.banner.%s" % String(role)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 40)
		label.add_theme_color_override("font_color", Color(1.0, 0.78, 0.0))
		label.add_theme_color_override("font_outline_color", Color(0.1, 0.1, 0.1))
		label.add_theme_constant_override("outline_size", 6)
		label.size = Vector2(800.0, 60.0)
		label.position = Vector2(0.0, MinigameArt.BANNER_Y)
		holder.add_child(label)
		_banner_nodes[role] = holder
	_match_banners_to_language()


func _match_banners_to_language() -> void:
	var language := StringName(TranslationServer.get_locale().substr(0, 2))
	for role in _banner_nodes:
		var holder: Control = _banner_nodes[role]
		var art := holder.get_node("Art") as Sprite2D
		var texture := MinigameArt.banner(role, language)
		art.texture = texture
		art.visible = texture != null
		if texture != null:
			art.position = Vector2((800.0 - texture.get_size().x) * 0.5, MinigameArt.BANNER_Y)
		(holder.get_node("Text") as Label).visible = texture == null


func _show_banner(role: StringName) -> void:
	for key in _banner_nodes:
		(_banner_nodes[key] as Control).visible = key == role


func _play(sound_id: String) -> void:
	if _audio != null and _audio.has_method("play_effect"):
		_audio.call("play_effect", sound_id)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and not _banner_nodes.is_empty():
		_match_banners_to_language()
