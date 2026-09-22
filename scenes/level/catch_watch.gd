extends Node

# sub_402470, which sub_402590 calls once a frame after every entity has been updated and
# only while the level is being played and unpaused.
#
# The player is caught only mid-prank: the original tests states 2 and 3 of whichever action
# mode is running, which is the stretch the clip is actually playing. The first agent in the
# world's own order that notices the player and is not shut in a cubicle catches them; there
# is no chase and nothing accumulates. See docs/catch-reference.md.

const PrankController := preload("res://scenes/player/prank_controller.gd")

signal caught(agent: Node2D)

# sub_407990 shows the AGGRO_UP banner and one of these four, picked with rand() & 3. The
# index is the original's slot order; see docs/strings-reference.md.
const EXCLAMATIONS := [
	&"catch.exclaim.0",
	&"catch.exclaim.1",
	&"catch.exclaim.2",
	&"catch.exclaim.3",
]

# sub_407990 holds the banner for this long before sub_407370 opens screen 5.
const BANNER_SECONDS := 2.0

# Kept so a check can watch the trigger without the duel opening on top of it.
@export var hands_off_to_minigame := true

var caught_by: Node2D = null

var _minigame: Node
var _banner_remaining := 0.0

var _session: Node
var _player: Node2D
var _prank: Node
var _console: Node
var _layer: Node
var _random := RandomNumberGenerator.new()


func _ready() -> void:
	_random.randomize()
	call_deferred("_bind")


func _bind() -> void:
	_session = get_tree().get_first_node_in_group("level_session")
	_prank = get_tree().get_first_node_in_group("player_actions")
	_console = get_tree().get_first_node_in_group("level_console")
	_player = _prank.get_parent() as Node2D if _prank != null else null
	for layer in get_tree().get_nodes_in_group("collision_maps"):
		if layer.has_method("has_line_of_sight"):
			_layer = layer
			break


func _process(delta: float) -> void:
	# sub_407990 holds the banner for two seconds and sub_407370 then opens screen 5, so the
	# duel arrives underneath a banner that is already up.
	if _banner_remaining > 0.0:
		_banner_remaining -= delta
		if _banner_remaining <= 0.0:
			_banner_remaining = 0.0
			_open_duel()
		return
	if caught_by != null or get_tree().paused:
		return
	if _player == null or _prank == null or _layer == null:
		return
	if _session != null and bool(_session.get("is_finished")):
		return
	if not _is_mid_prank():
		return
	var agent := _first_agent_that_notices()
	if agent != null:
		_catch(agent)


# The port collapses sub_41B240's six states into three, and only ACTING covers the stretch
# in which the original can be caught.
func _is_mid_prank() -> bool:
	return int(_prank.get("state")) == PrankController.State.ACTING


func _first_agent_that_notices() -> Node2D:
	for node in get_tree().get_nodes_in_group("npc_agents"):
		var agent := node as Node2D
		if agent == null or not is_instance_valid(agent) or not agent.is_inside_tree():
			continue
		var brain := agent.get_node_or_null("Brain")
		if brain == null or not brain.has_method("notices"):
			continue
		if brain.is_blind():
			continue
		if brain.notices(_player, _layer):
			return agent
	return null


func _catch(agent: Node2D) -> void:
	caught_by = agent
	# The action is pushed to its abort state rather than completed, so an interrupted
	# prank pays nothing.
	if _prank.has_method("abort_action"):
		_prank.abort_action()
	if _console != null and _console.has_method("warn_of_catch"):
		_console.warn_of_catch(EXCLAMATIONS[_random.randi() & 3])
	caught.emit(agent)
	if not hands_off_to_minigame:
		return
	# The banner is up for two seconds and the duel opens underneath it, which is the order
	# sub_407990 and sub_407370 run in.
	_banner_remaining = BANNER_SECONDS


func reset() -> void:
	caught_by = null


func _open_duel() -> void:
	if _minigame == null:
		_minigame = get_tree().get_first_node_in_group("catch_minigame")
	if _minigame == null or not _minigame.has_method("open"):
		return
	var screens := get_node_or_null("/root/ScreenManager")
	var character: StringName = &"jobless"
	var casts := 2
	if screens != null:
		character = StringName(screens.get("selected_character"))
		casts = int(screens.call("begin_duel"))
	if not _minigame.is_connected("finished", _on_duel_finished):
		_minigame.connect("finished", _on_duel_finished)
	_minigame.call("open", _catcher_id(), character, casts)
	get_tree().paused = true


func _catcher_id() -> StringName:
	if not is_instance_valid(caught_by):
		return &"boss"
	var profile = caught_by.get("profile")
	return StringName(profile.get("id")) if profile != null else &"boss"


# Winning resumes the level in memory, which is what sub_4027B0 does with screen 1; losing
# ends it through the session, so the run's own score and clock reach the result screen and
# the level's music stops. Neither touches the score or the office's temper.
func _on_duel_finished(won: bool) -> void:
	get_tree().paused = false
	reset()
	if won:
		return
	if _session != null and _session.has_method("lose"):
		_session.lose()
