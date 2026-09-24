extends SceneTree

# The catch duel, screen 5. Layout and rules are recovered in docs/minigame-reference.md;
# this drives the state machine rather than the screen, so a round can be played out in a
# few hundred simulated frames.

const MinigameScene := preload("res://scenes/level/catch_minigame.tscn")
const Art := preload("res://scenes/level/catch_minigame_art.gd")
const I18N_SCRIPT := preload("res://autoloads/i18n.gd")

const STEP := 1.0 / 60.0

var _failures := 0


# Stands in for LevelAudio, which the duel finds by group, and keeps what it was asked to play.
class SoundLog extends Node:
	var calls: Array = []

	func play_effect(sound_id: String, looping := false, quiet := false) -> AudioStreamPlayer:
		calls.append([sound_id, looping, quiet])
		return null

	func named(sound_id: String) -> Array:
		return calls.filter(func(call): return call[0] == sound_id)


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_i18n().set_language(&"pl")
	_check_the_button_row()
	_check_the_portraits()
	await _check_a_round_the_player_gets_right()
	await _check_a_round_the_player_gets_wrong()
	await _check_the_duel_lengthens_each_time()
	await _check_the_duel_sounds()
	await _check_the_answer_clock()
	await _check_the_banners_follow_the_language()
	if _failures == 0:
		print("Catch minigame: the button row, the portraits, both round outcomes, the energy rule, the sounds, the answer clock and the banners passed")
	quit(1 if _failures else 0)


func _expect(condition: bool, label: String) -> void:
	if not condition:
		_failures += 1
		push_error(label)


func _i18n() -> Node:
	return root.get_node("I18n")


# Fourteen slots from x 66 in steps of 52; a sequence slot sits 46 further left and an answer
# button only exists once its x has reached 430, which is what leaves the gap in the middle.
func _check_the_button_row() -> void:
	for difficulty in [4, 7]:
		var slots := Art.button_slots(difficulty)
		var sequence := slots.filter(func(s): return not s["answer"])
		var answers := slots.filter(func(s): return s["answer"])
		_expect(sequence.size() == difficulty, "difficulty %d shows that many sequence slots" % difficulty)
		_expect(answers.size() == 7, "the answer row is always seven buttons, got %d" % answers.size())
		for slot in answers:
			_expect(int(slot["x"]) >= Art.ANSWER_MIN_X, "an answer button never sits left of 430")
			_expect(
				int(slot["answer_choice"]) == int(slot["index"]) - 7,
				"answer button %d chooses spell %d" % [int(slot["index"]), int(slot["index"]) - 7]
			)
		var choices := answers.map(func(s): return int(s["answer_choice"]))
		choices.sort()
		_expect(choices == [0, 1, 2, 3, 4, 5, 6], "the seven answers cover every spell once")

	# At difficulty 4 the original builds nothing for indices 4, 5 and 6.
	var four := Art.button_slots(4).map(func(s): return int(s["index"]))
	_expect(four == [0, 1, 2, 3, 7, 8, 9, 10, 11, 12, 13], "the middle three slots are never built, got %s" % str(four))
	_expect(int(Art.button_slots(4)[0]["x"]) == 20, "the first sequence slot sits at x 20")

	# A sequence slot wears the round's own permutation.
	var sequence := PackedByteArray([3, 1, 6, 0, 5, 2, 4])
	var shown := Art.button_slots(4, sequence).filter(func(s): return not s["answer"])
	_expect(int(shown[0]["icon"]) == 4, "the first slot shows the first icon of the permutation")
	_expect(int(shown[2]["icon"]) == 7, "and the third shows the third")


func _check_the_portraits() -> void:
	_expect(Art.difficulty_for(&"boss") == 7, "the boss duels over seven icons")
	_expect(Art.difficulty_for(&"janitor") == 4, "everyone else over four")
	for catcher in Art.PORTRAITS:
		_expect(Art.portrait_for(catcher) != null, "%s has a portrait" % catcher)
	_expect(
		Art.portrait_for(&"nobody-at-all") == Art.portrait_for(&"boss"),
		"an unknown catcher falls back to the boss, as the original does for a null one"
	)
	for character in Art.PLAYER_PORTRAITS:
		_expect(Art.player_portrait_for(character) != null, "%s has a portrait of their own" % character)
	_expect(Art.spell(0) != null and Art.answer_spell(0) != null, "casts and answers are both drawn")


func _mount(seed_value: int) -> Node:
	var minigame := MinigameScene.instantiate()
	minigame.random_seed = seed_value
	root.add_child(minigame)
	return minigame


func _drop(minigame: Node) -> void:
	root.remove_child(minigame)
	minigame.free()


# Run the machine until it leaves the state it is in, so a test never depends on a duration.
func _advance_until(minigame: Node, leaves: int, limit := 2000) -> bool:
	for i in range(limit):
		if minigame.state != leaves:
			return true
		minigame._process(STEP)
	return false


func _play_round(minigame: Node, correct: bool) -> void:
	_advance_until(minigame, minigame.State.GET_READY)
	_advance_until(minigame, minigame.State.BUILD)
	_advance_until(minigame, minigame.State.CASTING)
	_advance_until(minigame, minigame.State.YOUR_TURN)
	# Answer every cast, then let the last one be judged.
	for step in range(minigame.cast_count):
		if minigame.state != minigame.State.ANSWERING:
			break
		var expected := int(minigame._serial[step])
		minigame.answer(expected if correct else (expected + 1) % 7)
		for i in range(80):
			minigame._process(STEP)
			if minigame.state != minigame.State.ANSWERING:
				break


func _check_a_round_the_player_gets_right() -> void:
	var minigame := _mount(9001)
	await process_frame
	minigame.open(&"janitor", &"jobless", 3)
	_expect(minigame.difficulty == 4, "a janitor duels over four icons")
	_expect(minigame.cast_count == 3, "the round is as long as it was asked for")
	_expect(minigame.enemy_energy == 8 and minigame.player_energy == 8, "both sides start on eight")

	# The permutation is seven distinct values, and the serial only ever draws on the first
	# `difficulty` of them.
	_advance_until(minigame, minigame.State.GET_READY)
	_advance_until(minigame, minigame.State.BUILD)
	var seen := {}
	for value in minigame._sequence:
		seen[int(value)] = true
	_expect(seen.size() == 7, "the permutation holds seven distinct icons")
	var pool := {}
	for i in range(minigame._sequence.size()):
		if i < minigame.difficulty:
			pool[int(minigame._sequence[i])] = true
	for value in minigame._serial:
		_expect(pool.has(int(value)), "the serial only casts icons the round drew from")

	var rounds := 0
	while minigame.state != minigame.State.WON and rounds < 6:
		_play_round(minigame, true)
		rounds += 1
	_expect(minigame.state == minigame.State.WON, "answering correctly wins the duel, state %d" % minigame.state)
	_expect(rounds == 3, "three good rounds take eight energy below zero, took %d" % rounds)
	_expect(minigame.enemy_energy == 0, "the beaten side is shown empty rather than negative")
	var reported := []
	minigame.finished.connect(func(won: bool): reported.append(won))
	_advance_until(minigame, minigame.State.WON)
	_expect(reported == [true], "the duel reports that it was won")
	_expect(not minigame.visible, "and takes itself off screen")
	_drop(minigame)


func _check_a_round_the_player_gets_wrong() -> void:
	var minigame := _mount(4242)
	await process_frame
	minigame.open(&"boss", &"anne", 2)
	_expect(minigame.difficulty == 7, "the boss duels over all seven")
	var rounds := 0
	while minigame.state != minigame.State.LOST and rounds < 6:
		_play_round(minigame, false)
		rounds += 1
	_expect(minigame.state == minigame.State.LOST, "answering wrongly loses it, state %d" % minigame.state)
	_expect(rounds == 3, "three bad rounds lose it, took %d" % rounds)
	var reported := []
	minigame.finished.connect(func(won: bool): reported.append(won))
	_advance_until(minigame, minigame.State.LOST)
	_expect(reported == [false], "the duel reports that it was lost")
	_drop(minigame)


# sub_406430 hands the duel the count of duels so far plus two, then advances and clamps it.
func _check_the_duel_lengthens_each_time() -> void:
	var screens := root.get_node("ScreenManager")
	var restore: int = screens.duels_fought
	screens.duels_fought = 0
	_expect(screens.begin_duel() == 2, "the first duel is two casts long")
	_expect(screens.begin_duel() == 3, "the second is three")
	for i in range(20):
		screens.begin_duel()
	_expect(screens.duels_fought == 9, "the counter stops at nine")
	_expect(screens.begin_duel() == 11, "so a duel never runs past eleven casts")
	screens.duels_fought = restore


# sub_414870 plays three sounds, all through the game's handler with loop and quiet clear:
# each cast's S(serial + 1004) once as it appears (0x414BEE), S1002 on a win (0x414EA0) and
# S1001 on a loss (0x414F1E). Nothing plays for get ready, your turn or a round's outcome.
func _check_the_duel_sounds() -> void:
	var sounds := SoundLog.new()
	root.add_child(sounds)
	sounds.add_to_group("level_audio")

	var minigame := _mount(9001)
	await process_frame
	minigame.open(&"janitor", &"jobless", 3)
	_expect(minigame._audio == sounds, "the duel finds the level's audio by its group")
	_advance_until(minigame, minigame.State.GET_READY)
	_expect(sounds.calls.is_empty(), "nothing plays for get ready")
	_advance_until(minigame, minigame.State.BUILD)
	_advance_until(minigame, minigame.State.CASTING)
	var casts: Array = []
	for k in range(minigame.cast_count):
		casts.append(["S%04d" % (1004 + int(minigame._serial[k])), false, false])
	_expect(sounds.calls == casts, "each cast plays its own sound once, at full volume: %s" % str(sounds.calls))
	sounds.calls.clear()
	_expect(minigame.state == minigame.State.YOUR_TURN, "the casts hand over to the player")
	minigame.answer(int(minigame._serial[0]))
	_advance_until(minigame, minigame.State.YOUR_TURN)
	_expect(sounds.calls.is_empty(), "a click before the answer clock runs plays nothing")
	# sub_413C80 plays S(index + 997), the answered icon's own cast sound, once per click.
	var first := int(minigame._serial[0])
	minigame.answer(first)
	_expect(sounds.calls == [["S%04d" % (1004 + first), false, false]], "an answer plays its icon's own cast sound")
	minigame.answer((first + 1) % 7)
	_expect(sounds.calls.size() == 1, "a second click while the answer is on show plays nothing")
	var rounds := 0
	while minigame.state != minigame.State.WON and rounds < 6:
		_play_round(minigame, true)
		rounds += 1
	_expect(sounds.named("S1002") == [["S1002", false, false]], "winning plays S1002 once")
	_expect(sounds.named("S1001").is_empty(), "and never the losing cue")
	_advance_until(minigame, minigame.State.WON)
	_expect(sounds.named("S1002").size() == 1, "the result banner plays nothing more")
	_drop(minigame)

	sounds.calls.clear()
	minigame = _mount(4242)
	await process_frame
	minigame.open(&"boss", &"anne", 2)
	rounds = 0
	while minigame.state != minigame.State.LOST and rounds < 6:
		_play_round(minigame, false)
		rounds += 1
	_expect(sounds.named("S1001") == [["S1001", false, false]], "losing plays S1001 once")
	_expect(sounds.named("S1002").is_empty(), "and never the winning cue")
	_drop(minigame)

	root.remove_child(sounds)
	sounds.free()


# The clock starts each round at 3.999 (0x414932, 0x414B65) and every accepted click puts it
# back to 4.0 (sub_413C80, 0x413CFF). So each answer gets its own four seconds, which is what
# lets a duel of up to eleven casts be won; one clock for the whole round could not last.
func _check_the_answer_clock() -> void:
	for casts in [3, 5, 11]:
		var minigame := _mount(1234)
		await process_frame
		minigame.open(&"janitor", &"jobless", casts)
		for leaving in [minigame.State.GET_READY, minigame.State.BUILD, minigame.State.CASTING, minigame.State.YOUR_TURN]:
			_advance_until(minigame, leaving)
		_expect(minigame.state == minigame.State.ANSWERING, "%d casts reach the player's turn" % casts)
		_expect(is_equal_approx(minigame._countdown_seconds, 3.999), "the round's clock starts at 3.999")
		_expect(minigame._countdown.text == "03", "which reads 03, got %s" % minigame._countdown.text)
		if casts == 3:
			# Answer once, then leave it: the round runs out four seconds after that click.
			minigame.answer(int(minigame._serial[0]))
			_expect(is_equal_approx(minigame._countdown_seconds, 4.0), "a click puts the clock back to 4.0")
			var waited := 0.0
			while minigame.state == minigame.State.ANSWERING and waited < 10.0:
				minigame._advance_answering(STEP)
				waited += STEP
			_expect(minigame.state == minigame.State.ROUND_LOST, "an answer left too long is a miss")
			_expect(absf(waited - 4.0) < 2.0 * STEP, "four seconds after the last click, took %.2f" % waited)
		else:
			# Perfect play: the right icon the first frame the console takes a click.
			var answered := 0
			var guard := 0
			while minigame.state == minigame.State.ANSWERING and guard < casts * 200:
				if not minigame._answer_showing and answered < casts:
					minigame.answer(int(minigame._serial[answered]))
					answered += 1
				minigame._advance_answering(STEP)
				guard += 1
			_expect(
				minigame.state == minigame.State.ROUND_WON,
				"a %d-cast round played perfectly is won, state %d after %d answers" % [casts, minigame.state, answered]
			)
		_drop(minigame)


func _check_the_banners_follow_the_language() -> void:
	var minigame := _mount(7)
	await process_frame
	for language: StringName in [&"pl", &"de"]:
		_i18n().set_language(language)
		await process_frame
		for role in Art.BANNER_ROLES:
			var holder := minigame._banner_nodes[role] as Control
			_expect((holder.get_node("Art") as Sprite2D).texture != null, "%s has painted art for %s" % [language, role])
			_expect(not (holder.get_node("Text") as Label).visible, "%s draws no label over its art" % language)
	_i18n().set_language(&"en")
	await process_frame
	for role in Art.BANNER_ROLES:
		var holder := minigame._banner_nodes[role] as Control
		_expect((holder.get_node("Art") as Sprite2D).texture == null, "English has no painted banner for %s" % role)
		var label := holder.get_node("Text") as Label
		_expect(label.visible, "so English draws one for %s" % role)
		_expect(label.atr(label.text) != label.text, "and it is translated")
	_i18n().set_language(&"pl")
	_drop(minigame)
