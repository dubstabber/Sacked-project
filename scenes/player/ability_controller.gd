extends Node

# The console lamps' abilities: smoking (mode 2), urinating (3) and the Matrix pill (5). This is
# the rest of the player's world tick sub_41CFC0 once the prank is taken out: sub_41CF20 turns
# a lamp's request into a mode (0x41D003), that mode's handler runs one state (0x41D013), the
# player's effects are held to the one clock they share, the pill's slow-down timer runs after
# the dispatch (0x41D401), and the clip's frame is picked last (0x41D4D6). The effects the
# player spawned then tick, as game+1960 does after the character list.
#
# PrankController keeps player+900's gate, the inventory and the console's feed: a lamp only
# starts from its FREE state, and an ability writes the hover bar and the stopwatch through
# it, so scenes/hud/console.gd reads an ability exactly as it reads a prank.
# See docs/player-ability-reference.md.

const SmokeScript := preload("res://scenes/effects/smoke.gd")
const PuddleScript := preload("res://scenes/effects/puddle.gd")
const PrankController := preload("res://scenes/player/prank_controller.gd")
const SlowdownOverlay := preload("res://scenes/player/slowdown_overlay.gd")
# +992/+1000 as a prank keeps them too, with the clock's shared 10.0 and 100.0, smoking's 0.4
# (flt_46587C) and the smoke's 4.5 (flt_465A34).
const PlayerTimer := preload("res://scenes/player/player_timer.gd")

# The input register's lamp bits, which sub_403FB0 raises from the lamp's id
# (0x404070-0x404086) and sub_41CF20 tests in this order. 0x2000, foam, is never raised.
const REQUEST_SMOKE := 0x800
const REQUEST_PISS := 0x1000
const REQUEST_FOAM := 0x2000
const REQUEST_PILL := 0x4000
const REQUEST_ORDER := [REQUEST_SMOKE, REQUEST_PISS, REQUEST_FOAM, REQUEST_PILL]

enum Mode { FREE = 0, SMOKING = 2, URINATING = 3, FOAM = 4, PILL = 5 }

const REQUEST_MODES := {
	REQUEST_SMOKE: Mode.SMOKING,
	REQUEST_PISS: Mode.URINATING,
	REQUEST_FOAM: Mode.FOAM,
	REQUEST_PILL: Mode.PILL,
}
# sub_41CF20 writes these as the mode's first state (0x41CF67, 0x41CF81, 0x41CF9B, 0x41CFB5).
const FIRST_STATES := {Mode.SMOKING: 10, Mode.URINATING: 20, Mode.FOAM: 30, Mode.PILL: 40}
# The modes this controller has states for. A request for any other is dropped.
const RUNNABLE_MODES := [Mode.SMOKING, Mode.URINATING, Mode.PILL]
# sub_402470 catches in these (0x40248E-0x4024AA) and writes the mode's abort state.
const CATCH_STATES := {11: 14, 12: 14, 21: 24, 22: 24}

# sub_41BC50 reads its records as globals by the room at the player (0x41BCF1-0x41BD5C).
const SMOKE_RECORDS := {3: 22, 4: 76, 8: 24}
const SMOKE_RECORD_ANYWHERE := 23
const SMOKE_CLIP := "smoke"
const ITEM_CIGARETTES := 5

# sub_41C120 reads its two records as globals by the room at the player (0x41C175-0x41C1B1),
# and state 23 asks the room again for the score it pays (0x41C52A-0x41C55F).
const PISS_RECORDS := {8: 75}
const PISS_RECORD_ANYWHERE := 74
const PISS_CLIP := "piss-1"
# The literal state 21 hands sub_42A6A0 (0x46EE04), not looped and not positional (0x41C4B7).
const PISS_SOUND := "S0174"
const ITEM_BLADDER := 26
# sub_41CD90 reads record 73 as a global: its name, duration, score and +0x14, the slow-down's
# length in tenths (0x41CDA9-0x41CEC5).
const PILL_RECORD := 73
const ITEM_PILL := 14
# sub_41CD10 walks the character list for type 2, the agents, and skips the player.
const AGENT_GROUP := &"npc_agents"

# +988 is set for Anne (sub_4049F0, 0x404AE1).
const ANNE_PROFILE := "anne"

# player+900 while an ability runs, and +904.
var mode: int = Mode.FREE
var state := 0
# +992 and +1000, summed and tested as scenes/player/player_timer.gd says.
var timer := PlayerTimer.new()
# +996 and +1004, the same pair for the pill's slow-down, and +1044 while it runs.
var slow_timer := PlayerTimer.new()
var slowdown_shown := false
# +992 in seconds and +1000 in hundredths, and the slow-down's two, by name.
var elapsed: float:
	get:
		return timer.elapsed
	set(value):
		timer.elapsed = value
var total: float:
	get:
		return timer.total
	set(value):
		timer.total = value
var slow_elapsed: float:
	get:
		return slow_timer.elapsed
	set(value):
		slow_timer.elapsed = value
var slow_total: float:
	get:
		return slow_timer.total
	set(value):
		slow_timer.total = value
# +1048, the one timestamp every effect the player spawns is measured from.
var effect_clock := 0.0
# The level's clock. It stands still whenever the tree is paused, as the original's only
# advances on screen 1 while unpaused.
var now := 0.0
# +1052.
var smoke: Node2D
# +1080.
var puddle: Node2D
# sub_41D500's gradient while +1044 is up, built the first time it is.
var overlay: Node2D
# +1116, the S0174 player; null stands for its -1.
var piss_sound: AudioStreamPlayer
# Everything this player pushed onto the effects list, which ticks each of them.
var effects: Array[Node] = []
# The record the running ability's first state picked, whose name the hover bar shows.
var record := 0
# Handed to every smoke this controller spawns when set, so a check can fix the particles.
var random_source: Callable
# rand(), which state 20 tests with & 8 to pick the facing. A check can fix it.
var facing_roll: Callable = func() -> int: return randi()

var _requests := 0
var _clip := ""
var _clip_start := 0.0
var _clip_finished := true
var _progress_shown := false
var _player: Node2D
var _prank: Node
var _cursor: Node
var _layer: Node
var _session: Node
var _audio: Node


func _enter_tree() -> void:
	add_to_group("player_abilities")


func _ready() -> void:
	_player = get_parent() as Node2D
	_prank = _player.get_node_or_null("PrankController") if _player != null else null
	_cursor = _player.get_node_or_null("MovementArrow") if _player != null else null


# ~CObj_Player stops the slots the player holds, +1116 among them (0x41AF1C), and every way out
# of a level deletes the player.
func _exit_tree() -> void:
	_stop_piss_sound()


# The pause loses a lamp's press: sub_403780 returns before it copies the register
# (0x40378D). Returning from the quit prompt or the duel clears the id as well (sub_407370,
# 0x40741F and 0x407447).
func _notification(what: int) -> void:
	if what == NOTIFICATION_PAUSED or what == NOTIFICATION_UNPAUSED:
		_requests = 0


func _process(delta: float) -> void:
	advance(delta)


# A lamp's press, raised by the console. It is looked at on this controller's next tick only,
# and only if the player is free then; otherwise it is lost, never queued.
func request(bit: int) -> void:
	_requests |= bit


func is_free() -> bool:
	return mode == Mode.FREE and _prank != null and int(_prank.get("state")) == PrankController.State.FREE


func is_catchable() -> bool:
	return mode != Mode.FREE and CATCH_STATES.has(state)


# sub_402470's store: the abort state, and nothing else. The item, the score and the effects
# are left as they are, and the stopwatch holds its sweep until the abort state zeroes it.
# Screen 4 goes on ticking the player at a zero step under the caught banner (0x40287B,
# 0x411AD1) where CatchWatch pauses the tree, so the abort state gets that tick here: 24 idles,
# frees the player and stops S0174 at once, and 14 waits for SMOKE on the frozen clock.
func catch() -> void:
	if not is_catchable():
		return
	state = int(CATCH_STATES[state])
	if _cursor != null:
		_cursor.show_main_cursor()
	advance(0.0)


func advance(delta: float) -> void:
	now += delta
	_take_request()
	match mode:
		Mode.SMOKING:
			_smoking(delta)
		Mode.URINATING:
			_urinating(delta)
		Mode.PILL:
			_pill(delta)
	_hold_effects_to_clock()
	_advance_slowdown(delta)
	_select_clip_frame()
	_report_progress()
	for effect in effects.duplicate():
		if is_instance_valid(effect):
			effect.tick(now)
		else:
			effects.erase(effect)


# The lamp bit sub_41CF20 would find, in its test order.
static func pick_request(bits: int) -> int:
	for bit in REQUEST_ORDER:
		if bits & bit:
			return bit
	return 0


func _take_request() -> void:
	var bits := _requests
	_requests = 0
	var bit := pick_request(bits)
	if bit == 0 or not is_free():
		return
	var next: int = REQUEST_MODES[bit]
	if not RUNNABLE_MODES.has(next) or not _prank.begin_ability():
		return
	mode = next
	state = FIRST_STATES[next]


# sub_41BC50.
func _smoking(delta: float) -> void:
	match state:
		10:
			record = SMOKE_RECORDS.get(room_category(), SMOKE_RECORD_ANYWHERE)
			timer.start(float(ActionTable.get_action(record).get("duration_tenths", 0)))
			_prank.show_ability_record(ActionTable.action_name(record))
			_hold_player()
			_play_once(SMOKE_CLIP)
			effect_clock = now
			state = 11
		11:
			# Passed strictly (0x41BDAA-0x41BDBA).
			if timer.add_elapsed(delta) > PlayerTimer.factor("smoke_spawn_after"):
				_spawn_smoke()
				effect_clock = now
				state = 12
		12:
			if _clip != "" and _clip_finished:
				_play_idle()
			# The timers are zeroed on the way to 13 (0x41BFF6, 0x41BFFC), so the stopwatch
			# reads empty from that tick; state 13 does not zero them again.
			if timer.reached(timer.add_elapsed(delta)):
				timer.zero()
				state = 13
		13:
			# 13 asks the room at the player again for the score (0x41C023-0x41C07E); the name
			# on the hover bar is still state 10's.
			_pay(SMOKE_RECORDS.get(room_category(), SMOKE_RECORD_ANYWHERE))
			_prank.spend_item(ITEM_CIGARETTES)
			_free()
		14:
			if _clip != "" and not _clip_finished:
				return
			_play_idle()
			timer.zero()
			_free()


# sub_41C120.
func _urinating(delta: float) -> void:
	match state:
		20:
			record = PISS_RECORDS.get(room_category(), PISS_RECORD_ANYWHERE)
			timer.start(float(ActionTable.get_action(record).get("duration_tenths", 0)))
			_prank.show_ability_record(ActionTable.action_name(record))
			var facing: Vector2 = PrankController.piss_facing(_profile_id(), facing_roll)
			if facing != Vector2.ZERO:
				_player.set("last_direction", facing)
			_hold_player()
			_play_looping(PISS_CLIP)
			state = 21
		21:
			timer.add_elapsed(delta)
			_remove_puddle()
			effect_clock = now
			_spawn_puddle()
			if piss_sound == null:
				piss_sound = _play_sound(PISS_SOUND)
			state = 22
		22:
			if timer.reached(timer.add_elapsed(delta)):
				timer.zero()
				state = 23
		23:
			_pay(PISS_RECORDS.get(room_category(), PISS_RECORD_ANYWHERE))
			_prank.spend_item(ITEM_BLADDER)
			_play_idle()
			timer.zero()
			_free()
			_stop_piss_sound()
		24:
			_play_idle()
			timer.zero()
			_free()
			_stop_piss_sound()


# sub_41CD90. States 40 to 42 change no clip and no sound and move nobody: a walking player keeps
# WALK looping where they stand, the footstep with it, until 43 hands them back. The pill is
# never caught. 44 is never written, so it is not here.
func _pill(delta: float) -> void:
	match state:
		40:
			record = PILL_RECORD
			timer.start(float(ActionTable.get_action(PILL_RECORD).get("duration_tenths", 0)))
			# Record 73's name is "...", the same pointer free mode writes (0x41CDBB).
			_prank.show_ability_record(ActionTable.action_name(PILL_RECORD))
			_hold_player(false)
			state = 41
		41:
			state = 42
		42:
			if timer.reached(timer.add_elapsed(delta)):
				timer.zero()
				state = 43
		43:
			# 0x41CE3B-0x41CECB: the score, slot 0 looping from 0, mode and state 0, one pill spent,
			# then +996 = 0, +1004 = record 73's +0x14 * 10.0, and sub_41CD10(1).
			_pay(PILL_RECORD)
			_play_idle()
			timer.zero()
			_free()
			_prank.spend_item(ITEM_PILL)
			slow_timer.start(float(ActionTable.get_action(PILL_RECORD).get("effect_duration_tenths", 0)))
			set_agents_slowed(true)


# sub_41CD10: agent+1792 on every agent of this level, the boss, the secretary and the janitor
# among them, and never on the player.
func set_agents_slowed(value: bool) -> void:
	var world := _player.get_parent() if _player != null else null
	for agent in get_tree().get_nodes_in_group(AGENT_GROUP):
		if world == null or world.is_ancestor_of(agent):
			agent.set("slowed", value)


# sub_412AE0 mode 4 at the player, which is how every ability picks its record.
func room_category() -> int:
	var layer := _collision_layer()
	if layer == null or _player == null:
		return 0
	return int(layer.room_category_at(_player.global_position))


# player+124, the view the player faces: view d looks along 45 * d degrees, 0 being _000.
func view_index() -> int:
	return IsoDirection.view_index(_player.get("last_direction") if _player != null else Vector2.RIGHT)


# State 11's spawn (0x41BDA4-0x41BF7E). It overwrites +1052 without a look at what was there
# (0x41BE3B), so a smoke still emitting when the next one starts is orphaned, and keeps
# puffing until the level ends; the port keeps that.
func _spawn_smoke() -> void:
	var layer := _collision_layer()
	var world := _player.get_parent() if _player != null else null
	if layer == null or world == null:
		return
	var effect := SmokeScript.new()
	effect.name = "Smoke"
	if random_source.is_valid():
		effect.random = random_source
	world.add_child(effect, true)
	effect.start(
		layer.to_grid_position(_player.global_position),
		float(_player.get("height")),
		view_index(),
		layer.from_grid_position(Vector2.ZERO)
	)
	smoke = effect
	effects.append(effect)


# State 21's new CPisspuddle (0x41C305-0x41C4A3), pushed onto the effects list.
func _spawn_puddle() -> void:
	var layer := _collision_layer()
	var world := _player.get_parent() if _player != null else null
	if layer == null or world == null:
		return
	var effect := PuddleScript.new()
	effect.name = "Puddle"
	world.add_child(effect, true)
	effect.place(
		layer.to_grid_position(_player.global_position),
		view_index(),
		_profile_id() == ANNE_PROFILE,
		layer.from_grid_position(Vector2.ZERO),
		now
	)
	puddle = effect
	effects.append(effect)


# Off the effects list and deleted at once, with no fade: a new urination's (0x41C26E-0x41C2FF)
# and the tick's at seventeen seconds (0x41D1D0-0x41D252).
func _remove_puddle() -> void:
	if is_instance_valid(puddle):
		effects.erase(puddle)
		puddle.queue_free()
	puddle = null


func _hold_effects_to_clock() -> void:
	_hold_smoke_to_clock()
	_hold_puddle_to_clock()


# The player tick's gate for the smoke (0x41D072-0x41D13D): once the shared clock is 4.5 s
# past, stop its emission for good, and delete it on the tick that finds no particle left.
func _hold_smoke_to_clock() -> void:
	if not is_instance_valid(smoke):
		smoke = null
		return
	if now - effect_clock <= PlayerTimer.factor("smoke_stop_after"):
		return
	if smoke.stop():
		effects.erase(smoke)
		smoke.queue_free()
		smoke = null


# And for the puddle (0x41D143-0x41D252): past ten seconds on the same clock it spreads and
# fades, and past seventeen it is deleted, both on the tick that crosses. Only these writes set
# its scale and alpha, so an age the smoke restarts leaves them where they were.
func _hold_puddle_to_clock() -> void:
	if not is_instance_valid(puddle):
		puddle = null
		return
	var age := now - effect_clock
	if age > PuddleScript.grow_after():
		puddle.grow(age)
	if age > float(PuddleScript.params()["remove_after"]):
		_remove_puddle()


# sub_41CFC0 0x41D401-0x41D458. +1044 stays up for the tick that releases the slow-down. +996
# is summed as +992 is (0x41D415-0x41D435), and tested strictly past.
func _advance_slowdown(delta: float) -> void:
	if slow_timer.total <= 0.0:
		slowdown_shown = false
	else:
		var sum := slow_timer.add_elapsed(delta)
		slowdown_shown = true
		if slow_timer.passed(sum):
			slow_timer.zero()
			set_agents_slowed(false)
	_show_overlay()


# sub_41D500 paints the overlay before the player, and the player is the character list's
# first entry. So it is the player's first child, at the characters' z: after the items, the
# looping ones among them, and before the player's sprite and every agent. Built once and kept,
# it goes with the player.
func _show_overlay() -> void:
	if slowdown_shown and not is_instance_valid(overlay):
		if _player == null:
			return
		overlay = SlowdownOverlay.new()
		overlay.name = "SlowdownOverlay"
		_player.add_child(overlay, false, Node.INTERNAL_MODE_FRONT)
	if is_instance_valid(overlay):
		overlay.visible = slowdown_shown


func _pay(paid_record: int) -> void:
	var session := _level_session()
	if session != null and _player != null:
		# sub_41DE60 floats the number off the player.
		session.add_score(int(ActionTable.get_action(paid_record).get("score", 0)), _player.global_position)


# sub_403780 feeds the stopwatch +992 * 100 / +1000 while +1000 > 0, and 0 otherwise.
func _report_progress() -> void:
	if _prank == null:
		return
	if mode == Mode.FREE and not _progress_shown:
		return
	_prank.report_ability_progress(timer.elapsed, timer.total_seconds())
	_progress_shown = mode != Mode.FREE


# Mode and state back to 0. The clock gives way to the pointer, or to the walk if the right
# button is still held.
func _free() -> void:
	mode = Mode.FREE
	state = 0
	record = 0
	if _prank != null:
		_prank.end_ability()
	if _cursor != null:
		_cursor.show_main_cursor()
	if _player != null:
		_player.release_from_ability()


# sub_4154B0 shows the clock while the mode runs, and the player stands. The pill leaves the
# footstep alone.
func _hold_player(stop_footsteps := true) -> void:
	if _player == null:
		return
	_player.hold_for_ability(stop_footsteps)
	if _cursor != null:
		_cursor.show_main_cursor()
		_cursor.show_busy_cursor()


# The clip's loop flag cleared, its start set to now and its finished flag cleared, in the
# facing the player already has.
func _play_once(action: String) -> void:
	_clip = ""
	_clip_finished = true
	if _player == null:
		return
	var anim_name: String = _player.action_animation_name(action, _player.get("last_direction"))
	if anim_name == "" or not _player.animation_controller.play_once(anim_name):
		return
	_clip = anim_name
	_clip_start = now
	_clip_finished = false


# PISS#1 keeps the loop flag and the start of 0 its registration gave it, so the frame follows
# the clock, as the idle's does.
func _play_looping(action: String) -> void:
	_clip = ""
	_clip_finished = true
	if _player != null:
		_player.play_action_animation(action, _player.get("last_direction"))


# Slot 0 is clock-driven: every store to its start writes 0.
func _play_idle() -> void:
	_clip = ""
	_clip_finished = true
	if _player != null:
		_player.animation_controller.play_idle(_player.get("last_direction"))


# CObjectAnim_SelectFrameFromTime, called last in the player tick, raises the finished flag
# that the next tick's state reads, so the clip's last frame stays up for one extra tick.
func _select_clip_frame() -> void:
	if _clip == "" or _player == null:
		return
	if _player.animation_controller.current_animation != _clip:
		_clip = ""
		_clip_finished = true
		return
	_clip_finished = _player.animation_controller.show_once_frame(now - _clip_start)


func _play_sound(sound_id: String) -> AudioStreamPlayer:
	var audio := _level_audio()
	return audio.play_effect(sound_id) if audio != null else null


# sub_42A7C0(+1116, 0), then +1116 = -1 (0x41C630-0x41C63D). S0174 lasts 6.762 s, so by state
# 23 the handler has usually freed its player; +1116 still held the slot, and so does this.
func _stop_piss_sound() -> void:
	var audio := _level_audio()
	if audio != null:
		audio.stop_effect(piss_sound)
	piss_sound = null


func _profile_id() -> String:
	var profile = _player.get("profile") if _player != null else null
	return String(profile.get("id")) if profile != null else ""


func _collision_layer() -> Node:
	if is_instance_valid(_layer):
		return _layer
	_layer = CollisionMapLayer.of(_player)
	return _layer


func _level_session() -> Node:
	if not is_instance_valid(_session):
		_session = get_tree().get_first_node_in_group("level_session")
	return _session


func _level_audio() -> Node:
	if not is_instance_valid(_audio) and is_inside_tree():
		_audio = get_tree().get_first_node_in_group("level_audio")
	return _audio
