extends SceneTree

# The catch duel, screen 5. Layout and rules are recovered in docs/minigame-reference.md;
# this drives the state machine rather than the screen, so a round can be played out in a
# few hundred simulated frames.

const MinigameScene := preload("res://scenes/level/catch_minigame.tscn")
const Art := preload("res://scenes/level/catch_minigame_art.gd")
const I18N_SCRIPT := preload("res://autoloads/i18n.gd")

const STEP := 1.0 / 60.0

var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_i18n().set_language(&"pl")
	_check_the_button_row()
	_check_the_portraits()
	await _check_a_round_the_player_gets_right()
	await _check_a_round_the_player_gets_wrong()
	await _check_the_duel_lengthens_each_time()
	await _check_the_banners_follow_the_language()
	if _failures == 0:
		print("Catch minigame: the button row, the portraits, both round outcomes, the energy rule and the banners passed")
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
