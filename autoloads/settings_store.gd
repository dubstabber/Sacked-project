class_name GameSettings
extends Node

# Everything the player sets outside a level: the two volumes, the language, and whether
# the window is full screen.
#
# The original keeps the volumes in the registry beside the rest of the profile --
# sub_4261A0 restores game+20690, the effects volume (SOUNDVOLUME, default 75), and
# game+20692, the music (MUSICVOLUME, default 65), and its sound-setup screen moves each by
# 5 and clamps to 0..100. The port keeps those values and that rule, and puts them in
# user://settings.cfg beside the language I18n already reads there.
# See docs/sound-reference.md.
#
# Language and display are port extensions. The original ships one language per build and
# has no display option, so neither has an original default to restore; only the volumes
# answer to the screen's own Defaults button.

signal settings_changed

const DEFAULT_PATH := "user://settings.cfg"

const LOCALE_SECTION := "locale"
const LANGUAGE_KEY := "language"
const AUDIO_SECTION := "audio"
const MUSIC_KEY := "music"
const EFFECTS_KEY := "effects"
const DISPLAY_SECTION := "display"
const FULLSCREEN_KEY := "fullscreen"

# game+20692 and game+20690, and the step the arrows on screen 11 move them by.
const DEFAULT_MUSIC := 65
const DEFAULT_EFFECTS := 75
const VOLUME_STEP := 5
const VOLUME_MIN := 0
const VOLUME_MAX := 100

const MUSIC_BUS := &"Music"
const EFFECTS_BUS := &"SFX"

@export var path := DEFAULT_PATH

var _config: ConfigFile


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	reload()
	apply_audio()
	apply_display()


func reload() -> void:
	_config = ConfigFile.new()
	# A missing file is a fresh profile, not an error.
	_config.load(path)


func save() -> void:
	var error := _config.save(path)
	if error != OK:
		push_warning("Could not write %s (error %d)" % [path, error])


# --- volumes ---------------------------------------------------------------------------

func music_volume() -> int:
	return _volume(MUSIC_KEY, DEFAULT_MUSIC)


func effects_volume() -> int:
	return _volume(EFFECTS_KEY, DEFAULT_EFFECTS)


func set_music_volume(value: int) -> void:
	_set_volume(MUSIC_KEY, value)


func set_effects_volume(value: int) -> void:
	_set_volume(EFFECTS_KEY, value)


# The arrows either side of each bar move it one step, which is the original's 5.
func step_music(direction: int) -> void:
	set_music_volume(music_volume() + VOLUME_STEP * signi(direction))


func step_effects(direction: int) -> void:
	set_effects_volume(effects_volume() + VOLUME_STEP * signi(direction))


func reset_audio_defaults() -> void:
	_config.set_value(AUDIO_SECTION, MUSIC_KEY, DEFAULT_MUSIC)
	_config.set_value(AUDIO_SECTION, EFFECTS_KEY, DEFAULT_EFFECTS)
	apply_audio()
	save()
	settings_changed.emit()


func apply_audio() -> void:
	_apply_bus(MUSIC_BUS, music_volume())
	_apply_bus(EFFECTS_BUS, effects_volume())


# A volume of 0 mutes the bus rather than being handed to linear_to_db, which answers -inf.
# The original's own mixer is not recovered; silence at 0 is the port's reading of a slider
# the screen lets you take all the way down.
func _apply_bus(bus: StringName, volume: int) -> void:
	var index := AudioServer.get_bus_index(bus)
	if index < 0:
		return
	AudioServer.set_bus_mute(index, volume <= VOLUME_MIN)
	if volume > VOLUME_MIN:
		AudioServer.set_bus_volume_db(index, linear_to_db(float(volume) / float(VOLUME_MAX)))


func _volume(key: String, fallback: int) -> int:
	return clampi(int(_config.get_value(AUDIO_SECTION, key, fallback)), VOLUME_MIN, VOLUME_MAX)


func _set_volume(key: String, value: int) -> void:
	var clamped := clampi(value, VOLUME_MIN, VOLUME_MAX)
	# Holding an arrow down at either end should not rewrite the file every press.
	if _config.has_section_key(AUDIO_SECTION, key) and int(_config.get_value(AUDIO_SECTION, key)) == clamped:
		return
	_config.set_value(AUDIO_SECTION, key, clamped)
	apply_audio()
	save()
	settings_changed.emit()


# --- language --------------------------------------------------------------------------

func language() -> String:
	return String(_config.get_value(LOCALE_SECTION, LANGUAGE_KEY, ""))


# Refuses a code the game has no translation for, so a hand-edited file cannot leave the
# player looking at keys.
func set_language(code: StringName) -> void:
	var i18n := _i18n()
	if i18n != null and not (i18n.SUPPORTED as Array).has(code):
		push_warning("Unsupported language: %s" % String(code))
		return
	_config.set_value(LOCALE_SECTION, LANGUAGE_KEY, String(code))
	save()
	if i18n != null:
		i18n.set_language(code)
	settings_changed.emit()


# --- display ---------------------------------------------------------------------------

# Resolved through the main loop rather than an absolute path, because a check builds this
# store outside the scene tree.
func _i18n() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null("I18n") if tree != null else null


func is_fullscreen() -> bool:
	return bool(_config.get_value(DISPLAY_SECTION, FULLSCREEN_KEY, false))


func set_fullscreen(on: bool) -> void:
	_config.set_value(DISPLAY_SECTION, FULLSCREEN_KEY, on)
	apply_display()
	save()
	settings_changed.emit()


func toggle_fullscreen() -> void:
	set_fullscreen(not is_fullscreen())


func apply_display() -> void:
	# The headless driver has no window to put into a mode.
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_mode(
		DisplayServer.WINDOW_MODE_FULLSCREEN if is_fullscreen() else DisplayServer.WINDOW_MODE_WINDOWED
	)
