extends Node

# What a level sounds like. sub_406AF0 picks one of the three themes at random when the
# level starts and sub_403780 starts the looping warning ten seconds before the limit.
# Effects are named by the action table's +0x44 field. The one-shots go to ScreenManager,
# which stands in for the game's own sound handler, so they play on past the level. The one
# exception is a prank's start sound: the player holds it until the prank applies, and an
# abort or any way out of the level cuts it first. See docs/sound-reference.md.
#
# The pause key and the quit prompt only set game+12740 bit 0x20, which no sound code reads:
# sub_402590 runs the channel update sub_42A970 before its pause test (0x4025AB, 0x4025B0)
# and the music streams on its own thread (sub_42AA60 -> sub_45F450). So the players keep
# playing while the tree is paused; only this node's _process, which starts the warning, stops
# with it, as sub_403780 does.

const MANIFEST_PATH := "res://resources/original/sounds.json"
const THEMES := ["Theme1", "Theme2", "Theme3"]
const WARNING_SOUND := "S1012"
# sub_42A6A0 starts a sound at a tenth of the effects volume when its quiet flag is set.
const QUIET_SCALE := 0.1

static var _effects: Dictionary = {}
static var _music: Dictionary = {}

var _theme: AudioStreamPlayer
var _warning: AudioStreamPlayer
# player+1112 while a prank whose record plays its sound at the start (+0x48 == 1) runs.
var _action_sound: AudioStreamPlayer
var _session: Node
var _actions: Node
var _screens: Node


# Joined here rather than in _ready, as LevelSession does: CatchMinigame finds the level's
# audio by this group when a duel opens.
func _enter_tree() -> void:
	add_to_group("level_audio")


func _ready() -> void:
	_load_manifest()
	_theme = _make_player(&"Music")
	_warning = _make_player(&"SFX")
	# By path, so a level loaded without the autoloads still plays its one-shots itself.
	_screens = get_node_or_null("/root/ScreenManager")

	_session = get_tree().get_first_node_in_group("level_session")
	if _session != null:
		_session.finished.connect(_on_finished)
	_actions = get_tree().get_first_node_in_group("player_actions")
	if _actions != null:
		_actions.action_started.connect(_on_action_started)
		_actions.action_applied.connect(_on_action_applied)
		_actions.action_aborted.connect(_on_action_aborted)

	play_theme(THEMES[randi() % THEMES.size()])


# Case 3 leaving the quit prompt runs the result screens' teardown sub_407140 too (0x407507),
# so a level left mid-prank cuts its start sound as well.
func _exit_tree() -> void:
	_cut_action_sound()


func _process(_delta: float) -> void:
	if _session == null or _warning.playing or _session.is_finished:
		return
	if _session.is_warning():
		play_effect(WARNING_SOUND, true)


static func effect_stream(sound_id: String) -> AudioStream:
	_load_manifest()
	var path := String(_effects.get(sound_id, ""))
	return load(path) as AudioStream if path != "" and ResourceLoader.exists(path) else null


static func _load_manifest() -> void:
	if not _effects.is_empty():
		return
	var file := FileAccess.open(MANIFEST_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary):
		return
	for entry in parsed.get("effects", []):
		_effects[String(entry["id"])] = String(entry["stream"])
	for name in parsed.get("music", {}):
		_music[String(name)] = String(parsed["music"][name])


func play_theme(name: String) -> void:
	var path := String(_music.get(name, ""))
	if path == "" or not ResourceLoader.exists(path):
		return
	var stream := load(path) as AudioStream
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	_theme.stream = stream
	_theme.play()


# The record's sound is played once, or looped and quietened for the level's own cues. Only
# the warning loops, and it stays here so the result screens can stop it.
func play_effect(sound_id: String, looping := false, quiet := false) -> AudioStreamPlayer:
	if not looping and _screens != null and _screens.has_method("play_effect"):
		return _screens.call("play_effect", sound_id, quiet)
	var stream := effect_stream(sound_id)
	if stream == null:
		return null
	if stream is AudioStreamWAV:
		var wav := stream as AudioStreamWAV
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD if looping else AudioStreamWAV.LOOP_DISABLED
		if looping:
			# sub_42A6A0's loop flag becomes Play(0, 0, DSBPLAY_LOOPING) (sub_45F9B0), which loops
			# the whole buffer. The imported clips carry no loop points, and Godot never starts
			# a forward loop that ends at sample 0.
			wav.loop_begin = 0
			wav.loop_end = roundi(wav.get_length() * wav.mix_rate)
	var player := _warning if looping else _make_player(&"SFX", true)
	player.stream = stream
	player.volume_db = linear_to_db(QUIET_SCALE) if quiet else 0.0
	player.play()
	return player


# sub_41B240 plays the record's sound into player+1112 at the commit (0x41B69D) or at the
# apply (0x41B9A2), and the apply ends by dropping the handle without stopping it
# (0x41BA9A). So only a start sound is ever held past the frame it began in.
func _on_action_started(action: Dictionary, _point: Node) -> void:
	if bool(action.get("sound_at_start", false)):
		_action_sound = play_effect(String(action.get("sound", "")))


func _on_action_applied(action: Dictionary, _point: Node) -> void:
	_action_sound = null
	if not bool(action.get("sound_at_start", false)):
		play_effect(String(action.get("sound", "")))


func _on_action_aborted(_action: Dictionary, _point: Node) -> void:
	_cut_action_sound()


func _cut_action_sound() -> void:
	if is_instance_valid(_action_sound):
		_action_sound.stop()
		_action_sound.queue_free()
	_action_sound = null


# sub_407370 case 5 stops only the streamed music for the duel (sub_42AC30 -> sub_45F4F0 at
# 0x407571) and sub_4027B0 resumes it after either outcome (sub_42AC40 at 0x402839 and
# 0x40284D). Case 5 touches no effect slot, so a warning that has started loops on through
# the duel.
func hold_music(held: bool) -> void:
	_theme.stream_paused = held


# sub_407370 cases 7 and 8 stop the warning slot (0x4075E3, 0x407639). Their teardown
# sub_407140 (0x407017, 0x4070C6) deletes the player, whose destructor 0x41AE90 stops the
# slots it holds, so a start sound still held goes too; the win cue is ScreenManager's. Stopping the theme is the port's choice: the original leaves it playing
# under the result screens.
func _on_finished(_won: bool) -> void:
	_theme.stop()
	_warning.stop()
	_cut_action_sound()


func _make_player(bus: StringName, temporary := false) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.bus = bus
	player.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(player)
	if temporary:
		player.finished.connect(player.queue_free)
	return player
