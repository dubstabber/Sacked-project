extends SceneTree

# The sound-setup screen's rule, recovered as "move each volume by 5 and clamp to 0..100,
# effects 75 and music 65 by default", plus the two rows the port adds to that screen. Everything runs
# against a temporary file rather than the player's own.
# See docs/game-rules-reference.md and docs/sound-reference.md.

const STORE_SCRIPT := preload("res://autoloads/settings_store.gd")
const TEST_PATH := "user://check_settings_store.cfg"

var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	# The live buses and locale belong to whoever ran this, so they go back afterwards.
	var i18n: Node = root.get_node_or_null("I18n")
	var restore_language: StringName = i18n.current_language() if i18n != null else &"pl"

	_check_a_fresh_profile_starts_at_the_original_defaults()
	_check_each_step_moves_five_and_stops_at_the_ends()
	_check_a_volume_reaches_its_bus()
	_check_zero_mutes_rather_than_asking_for_silence_in_decibels()
	_check_defaults_restore_only_the_volumes()
	_check_settings_survive_a_reload()
	_check_a_language_is_written_and_applied(i18n)
	_check_an_unknown_language_is_refused(i18n)
	_check_full_screen_is_remembered()
	_check_the_player_is_remembered()

	if i18n != null:
		i18n.set_language(restore_language)
	var live: Node = root.get_node_or_null("SettingsStore")
	if live != null:
		live.apply_audio()
	DirAccess.remove_absolute(TEST_PATH)
	if _failures == 0:
		print("Settings: the recovered 5-step 0..100 volumes, their buses, the port's language and display rows, and the stored player passed")
	quit(1 if _failures else 0)


func _expect(condition: bool, label: String) -> void:
	if not condition:
		_failures += 1
		push_error(label)


func _fresh_store() -> Node:
	DirAccess.remove_absolute(TEST_PATH)
	var store: Node = STORE_SCRIPT.new()
	store.path = TEST_PATH
	store.reload()
	return store


func _bus_linear(bus: StringName) -> float:
	var index := AudioServer.get_bus_index(bus)
	if index < 0 or AudioServer.is_bus_mute(index):
		return 0.0
	return db_to_linear(AudioServer.get_bus_volume_db(index))


func _check_a_fresh_profile_starts_at_the_original_defaults() -> void:
	var store := _fresh_store()
	_expect(store.music_volume() == 65, "music starts at the original's 65")
	_expect(store.effects_volume() == 75, "effects start at the original's 75")
	_expect(store.language() == "", "a fresh profile has chosen no language")
	_expect(not store.is_fullscreen(), "a fresh profile starts windowed")
	store.free()


func _check_each_step_moves_five_and_stops_at_the_ends() -> void:
	var store := _fresh_store()
	store.step_music(1)
	_expect(store.music_volume() == 70, "one step up moves music by the original's 5")
	store.step_music(-1)
	store.step_music(-1)
	_expect(store.music_volume() == 60, "one step down moves music by 5")
	for i in range(10):
		store.step_music(1)
	_expect(store.music_volume() == 100, "music clamps at 100, got %d" % store.music_volume())
	for i in range(30):
		store.step_effects(-1)
	_expect(store.effects_volume() == 0, "effects clamp at 0, got %d" % store.effects_volume())
	store.free()


func _check_a_volume_reaches_its_bus() -> void:
	var store := _fresh_store()
	store.apply_audio()
	_expect(absf(_bus_linear(&"Music") - 0.65) < 0.001, "the default music volume reaches its bus")
	_expect(absf(_bus_linear(&"SFX") - 0.75) < 0.001, "the default effects volume reaches its bus")
	store.set_music_volume(40)
	_expect(absf(_bus_linear(&"Music") - 0.40) < 0.001, "a changed volume reaches its bus at once")
	store.free()


func _check_zero_mutes_rather_than_asking_for_silence_in_decibels() -> void:
	# linear_to_db(0) is -inf, so the port mutes the bus instead. Port decision, recorded
	# in docs/sound-reference.md.
	var store := _fresh_store()
	store.set_music_volume(0)
	var index := AudioServer.get_bus_index(&"Music")
	_expect(AudioServer.is_bus_mute(index), "a volume of 0 mutes its bus")
	_expect(is_finite(AudioServer.get_bus_volume_db(index)), "the bus is never given an infinite volume")
	store.set_music_volume(50)
	_expect(not AudioServer.is_bus_mute(index), "raising the volume unmutes the bus")
	store.free()


func _check_defaults_restore_only_the_volumes() -> void:
	var store := _fresh_store()
	store.set_music_volume(10)
	store.set_effects_volume(90)
	store.set_language(&"de")
	store.set_fullscreen(true)
	store.reset_audio_defaults()
	_expect(store.music_volume() == 65, "Defaults puts music back to 65")
	_expect(store.effects_volume() == 75, "Defaults puts effects back to 75")
	# The original has no language or display option, so it has no default for either, and
	# taking the language away from under the player would be the port's own invention.
	_expect(store.language() == "de", "Defaults leaves the chosen language alone")
	_expect(store.is_fullscreen(), "Defaults leaves the display alone")
	store.free()


func _check_settings_survive_a_reload() -> void:
	var store := _fresh_store()
	store.set_music_volume(35)
	store.set_effects_volume(20)
	store.set_fullscreen(true)
	store.free()

	var reopened: Node = STORE_SCRIPT.new()
	reopened.path = TEST_PATH
	reopened.reload()
	_expect(reopened.music_volume() == 35, "music survives a restart, got %d" % reopened.music_volume())
	_expect(reopened.effects_volume() == 20, "effects survive a restart, got %d" % reopened.effects_volume())
	_expect(reopened.is_fullscreen(), "the display choice survives a restart")
	reopened.free()


func _check_a_language_is_written_and_applied(i18n: Node) -> void:
	if i18n == null:
		_expect(false, "the I18n autoload is available")
		return
	var store := _fresh_store()
	store.set_language(&"de")
	_expect(i18n.current_language() == &"de", "choosing a language applies it at once")
	# I18n resolves from the file at boot, so what was written has to be what it reads.
	_expect(
		i18n.language_from_settings(TEST_PATH) == "de",
		"the chosen language is written where I18n looks for it"
	)
	_expect(
		i18n.resolve_language(PackedStringArray(), TEST_PATH, "fr") == &"de",
		"a saved language outranks the machine's own"
	)
	store.free()


func _check_an_unknown_language_is_refused(i18n: Node) -> void:
	if i18n == null:
		return
	var store := _fresh_store()
	store.set_language(&"de")
	store.set_language(&"qq")
	_expect(store.language() == "de", "a language the game has no strings for is refused")
	_expect(i18n.current_language() == &"de", "a refused language leaves the running one alone")
	store.free()


func _check_full_screen_is_remembered() -> void:
	var store := _fresh_store()
	store.toggle_fullscreen()
	_expect(store.is_fullscreen(), "the display row toggles on")
	store.toggle_fullscreen()
	_expect(not store.is_fullscreen(), "the display row toggles back")
	store.free()


# GENDER and NAME, which sub_426260 writes beside the unlock masks.
func _check_the_player_is_remembered() -> void:
	var store := _fresh_store()
	_expect(store.player_character() == &"" and store.player_name() == "", "a fresh profile has no player yet")
	store.set_player_profile(&"anne", "Zed")
	store.free()
	var reopened: Node = STORE_SCRIPT.new()
	reopened.path = TEST_PATH
	reopened.reload()
	_expect(reopened.player_character() == &"anne", "the character survives a restart")
	_expect(reopened.player_name() == "Zed", "and so does the name")
	reopened.set_player_profile(&"jobless", "A name far longer than sixteen")
	_expect(reopened.player_name() == "A name far longe", "the name keeps the original's 16 characters")
	reopened.free()

