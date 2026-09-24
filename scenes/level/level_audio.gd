extends Node

# What a level sounds like. sub_406AF0 picks one of the three themes at random when the
# level starts; sub_403780 starts the looping warning ten seconds before the limit and the
# win screen plays S1100. Effects are named by the action table's +0x44 field.
# See docs/sound-reference.md.
#
# The pause key and the quit prompt only set game+12740 bit 0x20, which no sound code reads:
# sub_402590 runs the channel update sub_42A970 before its pause test (0x4025AB, 0x4025B0)
# and the music streams on its own thread (sub_42AA60 -> sub_45F450). So the players keep
# playing while the tree is paused; only this node's _process, which starts the warning, stops
# with it, as sub_403780 does.

const MANIFEST_PATH := "res://resources/original/sounds.json"
const THEMES := ["Theme1", "Theme2", "Theme3"]
const WARNING_SOUND := "S1012"
const WIN_SOUND := "S1100"
# sub_42A6A0 drops a sound to a tenth of the effects volume when its quiet flag is set.
const QUIET_SCALE := 0.1

static var _effects: Dictionary = {}
static var _music: Dictionary = {}

var _theme: AudioStreamPlayer
var _warning: AudioStreamPlayer
var _session: Node
var _actions: Node


func _ready() -> void:
	_load_manifest()
	_theme = _make_player(&"Music")
	_warning = _make_player(&"SFX")

	_session = get_tree().get_first_node_in_group("level_session")
	if _session != null:
		_session.finished.connect(_on_finished)
	_actions = get_tree().get_first_node_in_group("player_actions")
	if _actions != null:
		_actions.action_started.connect(_on_action_started)
		_actions.action_applied.connect(_on_action_applied)

	play_theme(THEMES[randi() % THEMES.size()])


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


# The record's sound is played once, or looped and quietened for the level's own cues.
func play_effect(sound_id: String, looping := false, quiet := false) -> AudioStreamPlayer:
	var stream := effect_stream(sound_id)
	if stream == null:
		return null
	if stream is AudioStreamWAV:
		(stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD if looping else AudioStreamWAV.LOOP_DISABLED
	var player := _warning if looping else _make_player(&"SFX", true)
	player.stream = stream
	player.volume_db = linear_to_db(QUIET_SCALE) if quiet else 0.0
	player.play()
	return player


func _on_action_started(action: Dictionary, _point: Node) -> void:
	if bool(action.get("sound_at_start", false)):
		play_effect(String(action.get("sound", "")))


func _on_action_applied(action: Dictionary, _point: Node) -> void:
	if not bool(action.get("sound_at_start", false)):
		play_effect(String(action.get("sound", "")))


# sub_407370 case 5 stops the streamed music for the duel (sub_42AC30 -> sub_45F4F0 at
# 0x407571) and sub_4027B0 resumes it when the duel ends (sub_42AC40 -> sub_45F530). What
# screen 5 does to the effect channels is not recovered, so the warning stays as silent as it
# was when the duel paused everything.
func hold_music(held: bool) -> void:
	_theme.stream_paused = held
	_warning.stream_paused = held


func _on_finished(won: bool) -> void:
	_theme.stop()
	_warning.stop()
	if won:
		play_effect(WIN_SOUND)


func _make_player(bus: StringName, temporary := false) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.bus = bus
	player.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(player)
	if temporary:
		player.finished.connect(player.queue_free)
	return player
