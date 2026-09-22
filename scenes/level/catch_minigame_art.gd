class_name MinigameArt
extends RefCounted

# The duel's sprite tables and its button layout, kept apart from the state machine so both
# can be checked on their own. Recovered in docs/minigame-reference.md.

# sub_407840 maps a catcher to its portrait; the boss is also the fallback for an unknown
# one. See docs/catch-reference.md.
const PORTRAITS := {
	&"boss": "enemy-boss",
	&"secretary": "enemy-cs",
	&"janitor": "enemy-hm",
	&"female-employee-1": "enemy-worker1",
	&"female-employee-2": "enemy-worker2",
	&"male-employee-1": "enemy-worker3",
	&"male-employee-2": "enemy-worker4",
}
const FALLBACK_PORTRAIT := &"boss"
# ENEMY_ANNE and ENEMY_JOBLESS are the player's own side, not a catcher's.
const PLAYER_PORTRAITS := {
	&"jobless": "enemy-jobless",
	&"anne": "enemy-anne",
}

# sub_407370's case 5: the boss duels over seven icons and everyone else over four.
const BOSS_DIFFICULTY := 7
const DEFAULT_DIFFICULTY := 4

# The button row: fourteen slots from x 66 in steps of 52, stopping before 794, on the
# console at y 550. A sequence slot is drawn 46 further left; an answer button only exists
# once its x has reached 430.
const BUTTON_FIRST_X := 66
const BUTTON_STEP := 52
const BUTTON_LIMIT := 794
const BUTTON_Y := 550
const SEQUENCE_SHIFT := 46
const ANSWER_MIN_X := 430

# Alignment flag 16 centres a banner in the viewport, so each sits on its own height.
const BANNER_HEIGHT := 60.0
const BANNER_ROLES: Array[StringName] = [&"get_ready", &"your_turn", &"win", &"lose"]
# Both retail builds paint these; anything else draws a label instead.
const BANNER_ART := {
	&"get_ready": {&"pl": "getready", &"de": "getready-de"},
	&"your_turn": {&"pl": "yourturn", &"de": "yourturn-de"},
	&"win": {&"pl": "win", &"de": "win-de"},
	&"lose": {&"pl": "loose", &"de": "loose-de"},
}

const ROOT := "res://images/gui/minigame/"


static func difficulty_for(catcher: StringName) -> int:
	return BOSS_DIFFICULTY if catcher == &"boss" else DEFAULT_DIFFICULTY


static func portrait_for(catcher: StringName) -> Texture2D:
	var name: String = PORTRAITS.get(catcher, PORTRAITS[FALLBACK_PORTRAIT])
	return _texture(name)


static func player_portrait_for(character: StringName) -> Texture2D:
	var name: String = PLAYER_PORTRAITS.get(character, PLAYER_PORTRAITS[&"jobless"])
	return _texture(name)


static func icon(number: int) -> Texture2D:
	return _texture("icon-%d" % number)


# m_pSpell 0..6 are the opponent's casts and 7..13 the player's answers, paired index for
# index, so answer k is what counters cast k.
static func spell(index: int) -> Texture2D:
	return _texture("spell-%d" % (index + 1))


static func answer_spell(index: int) -> Texture2D:
	return _texture("spell-%d" % (index + 8))


static func banner(role: StringName, language: StringName) -> Texture2D:
	var art: Dictionary = BANNER_ART.get(role, {})
	if not art.has(language):
		return null
	return _texture(String(art[language]))


# Which of the fourteen slots exist, and what each one is for. The gap in the middle is the
# original's own: a slot whose x has not reached 430 and whose index is past the sequence is
# simply never built.
static func button_slots(difficulty: int, sequence: PackedByteArray = PackedByteArray()) -> Array:
	var slots: Array = []
	var index := 0
	var x := BUTTON_FIRST_X
	while x < BUTTON_LIMIT:
		if index < difficulty:
			# A sequence slot wears whichever icon the round's permutation put there.
			var icon_number := index + 1
			if index < sequence.size():
				icon_number = int(sequence[index]) + 1
			slots.append({
				"index": index, "x": x - SEQUENCE_SHIFT, "answer": false,
				"icon": icon_number, "answer_choice": -1,
			})
		elif x >= ANSWER_MIN_X:
			# The answer row is always indices 7..13, so choice is the index less seven.
			slots.append({
				"index": index, "x": x, "answer": true,
				"icon": index + 1, "answer_choice": index - BOSS_DIFFICULTY,
			})
		index += 1
		x += BUTTON_STEP
	return slots


static func _texture(name: String) -> Texture2D:
	var path := ROOT + name + ".png"
	return load(path) as Texture2D if ResourceLoader.exists(path) else null
