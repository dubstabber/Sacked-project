class_name GameSettings
extends Node

# Everything the player sets outside a level: the two volumes, the language, whether the
# window is full screen, and the coworkers' names.
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
# One key per name pool, type_1 to type_7, written only once screen 13 has saved that type.
const NAMES_SECTION := "names"
const LAUNCH_SECTION := "launch"
const LAUNCH_COUNT_KEY := "count"

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


# --- coworker names --------------------------------------------------------------------

# Screen 13 edits the fifteen names NAMES.DAT holds; the port keeps an edited pool here
# instead. A pool never saved from the screen reads as the original's defaults.
# See docs/names-reference.md.
func names_for_type(type: int) -> PackedStringArray:
	var names := CoworkerNames.defaults_for(type)
	var key := _names_key(type)
	if not _config.has_section_key(NAMES_SECTION, key):
		return names
	# A hand-edited file may hold the wrong count, so the pool keeps its own size.
	var stored = _config.get_value(NAMES_SECTION, key)
	if stored is Array or stored is PackedStringArray:
		for index in mini(names.size(), stored.size()):
			names[index] = _clean_name(String(stored[index]))
	return names


# sub_4082E0 copies the shown boxes into the table and writes NAMES.DAT. An empty box is
# saved as an empty name, which is never drawn over a coworker.
func set_names_for_type(type: int, names: PackedStringArray) -> void:
	var size := CoworkerNames.pool_size(type)
	if size == 0:
		push_warning("No coworker name pool %d" % type)
		return
	var cleaned := PackedStringArray()
	for index in size:
		cleaned.append(_clean_name(names[index]) if index < names.size() else "")
	var key := _names_key(type)
	if _config.has_section_key(NAMES_SECTION, key) and PackedStringArray(_config.get_value(NAMES_SECTION, key)) == cleaned:
		return
	_config.set_value(NAMES_SECTION, key, cleaned)
	save()
	settings_changed.emit()


# Button 3, sub_415CA0: the embedded defaults go back for the shown type only.
func reset_names_for_type(type: int) -> void:
	var key := _names_key(type)
	if not _config.has_section_key(NAMES_SECTION, key):
		return
	_config.erase_section_key(NAMES_SECTION, key)
	save()
	settings_changed.emit()


func _names_key(type: int) -> String:
	return "type_%d" % type


# Every copy in or out of a record is strncpy(..., 16); the original keeps spaces as typed.
func _clean_name(name: String) -> String:
	return name.substr(0, CoworkerNames.max_length())


# --- launches --------------------------------------------------------------------------

# game+20704: sub_405430 reads the count from the registry (sub_426230), adds one and writes
# it back (sub_426310) before the boot screen is built, and a missing value reads as 0. So the
# first launch is 1, and sub_422630 shows LOADING_EVIL on the 666th alone.
func launch_count() -> int:
	return int(_config.get_value(LAUNCH_SECTION, LAUNCH_COUNT_KEY, 0))


func count_launch() -> int:
	var count := launch_count() + 1
	_config.set_value(LAUNCH_SECTION, LAUNCH_COUNT_KEY, count)
	save()
	return count
