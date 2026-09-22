extends SceneTree

# Screens 7 and 8. Each is its own picture plus two buttons in the same two places, but the
# second button leads somewhere different: a win returns to the tree (despite its caption
# promising the next level) and a loss reloads the same level. See docs/shell-reference.md.

const ResultScene := preload("res://scenes/screens/level_result.tscn")
const ScreenManagerScript := preload("res://autoloads/screen_manager.gd")

const WIN_TEXTURE := preload("res://images/gui/screens/win.png")
const LOSE_TEXTURE := preload("res://images/gui/screens/lose.png")

var _failures := 0
var _screens: Node


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_screens = root.get_node("ScreenManager")
	var restore_level: int = _screens.selected_level
	var restore_won: bool = _screens.last_level_won

	await _check_a_win_offers_the_tree()
	await _check_a_loss_offers_a_retry()
	await _check_a_retry_reloads_the_same_level()

	_screens.selected_level = restore_level
	_screens.last_level_won = restore_won
	if _failures == 0:
		print("Level result: both outcomes, their two buttons and the retry's reload passed")
	quit(1 if _failures else 0)


func _expect(condition: bool, label: String) -> void:
	if not condition:
		_failures += 1
		push_error(label)


func _open(won: bool) -> Control:
	_screens.last_level_won = won
	var screen := ResultScene.instantiate() as Control
	root.add_child(screen)
	await process_frame
	return screen


func _label(screen: Control, path: String) -> String:
	return (screen.get_node(path) as Label).text


func _check_a_win_offers_the_tree() -> void:
	var screen := await _open(true)
	_expect(
		(screen.get_node("SafeFrame/Image") as TextureRect).texture == WIN_TEXTURE,
		"a win shows the win picture"
	)
	_expect(_label(screen, "SafeFrame/Back/Label") == "common.main_menu", "button 1 is the main menu")
	_expect(
		_label(screen, "SafeFrame/Forward/Label") == "result.next_level",
		"a win's button 2 is captioned Następny poziom"
	)

	(screen.get_node("SafeFrame/Forward") as TextureButton).pressed.emit()
	await process_frame
	# The caption promises the next level; sub_403F20's case 7 goes to screen 15.
	_expect(
		_screens.current == ScreenManagerScript.Screen.LEVEL_TREE,
		"Następny poziom returns to the level tree, not to a level"
	)
	screen.queue_free()
	await process_frame


func _check_a_loss_offers_a_retry() -> void:
	var screen := await _open(false)
	_expect(
		(screen.get_node("SafeFrame/Image") as TextureRect).texture == LOSE_TEXTURE,
		"a loss shows the loss picture"
	)
	_expect(
		_label(screen, "SafeFrame/Forward/Label") == "result.retry",
		"a loss's button 2 is captioned Powtórz"
	)

	(screen.get_node("SafeFrame/Back") as TextureButton).pressed.emit()
	await process_frame
	_expect(
		_screens.current == ScreenManagerScript.Screen.MAIN_MENU,
		"button 1 reaches the main menu from a loss"
	)
	screen.queue_free()
	await process_frame


func _check_a_retry_reloads_the_same_level() -> void:
	_screens.selected_level = 1
	var screen := await _open(false)
	(screen.get_node("SafeFrame/Forward") as TextureButton).pressed.emit()
	await process_frame
	# sub_407320 reloads the same .col and lands on screen 1, keeping nothing.
	_expect(_screens.current == ScreenManagerScript.Screen.LEVEL, "Powtórz goes straight back into a level")
	_expect(_screens.selected_level == 1, "Powtórz reloads the level that was just lost")
	screen.queue_free()
	await process_frame
