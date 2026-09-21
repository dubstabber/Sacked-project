extends SceneTree

# The office's temper. sub_417B00 raises an agent's own meter, sub_402350 averages them into
# game+14728 every frame and bands that mean, and sub_419CE0 turns the band into pace.
# See docs/npc-reference.md.

const LEVEL := preload("res://scenes/level_1.tscn")
const BRAIN := preload("res://scenes/npc/npc_brain.gd")

var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await _check_an_agent_takes_offence_once_per_goal()
	await _check_the_office_mean_and_its_bands()
	if _failures == 0:
		print("Aggression: the per-goal share, the office mean, its four bands and the pace they set passed")
	quit(1 if _failures else 0)


func _expect(condition: bool, label: String) -> void:
	if not condition:
		_failures += 1
		push_error(label)


func _level() -> Node:
	var level := LEVEL.instantiate()
	root.add_child(level)
	return level


func _release(level: Node) -> void:
	root.remove_child(level)
	level.free()


# sub_4187F0 divides a full meter by the goals the map can offer, and sub_417B00 hands over
# one share per goal, never twice for the same one.
func _check_an_agent_takes_offence_once_per_goal() -> void:
	var level := _level()
	await process_frame
	var actor := level.get_node("World/Npc079MaleEmployee1")
	var brain := actor.get_node("Brain")
	brain.enabled = false

	_expect(is_equal_approx(brain.aggression, 0.0), "an agent starts unbothered")
	var share: float = brain._aggression_share
	_expect(share > 0.0, "the agent knows what one goal is worth, got %f" % share)
	var shared := 0
	for goal in BRAIN.AGGRESSION_SHARED_GOALS:
		if not brain._goal_disabled[goal]:
			shared += 1
	_expect(
		is_equal_approx(share, BRAIN.AGGRESSION_LIMIT / float(shared)),
		"the share is a full meter split across the %d goals level 1 offers it" % shared
	)

	brain._take_offence(0)
	_expect(is_equal_approx(brain.aggression, share), "the first spoiled goal raises the meter by one share")
	brain._take_offence(0)
	_expect(is_equal_approx(brain.aggression, share), "the same goal spoiled again changes nothing")
	brain._take_offence(1)
	_expect(is_equal_approx(brain.aggression, share * 2.0), "a different goal raises it again")

	# An agent that finds its own workstation spoiled gives up on working.
	_expect(not brain._goal_disabled[BRAIN.WORK_GOAL], "an agent starts out willing to work")
	brain._take_offence(BRAIN.WORK_GOAL)
	_expect(brain._goal_disabled[BRAIN.WORK_GOAL], "a spoiled workstation ends the working day")
	_expect(is_equal_approx(brain._rates[BRAIN.WORK_GOAL], 0.0), "and stops the work need decaying")

	# A disabled goal cannot be taken offence at, so it never pays a share.
	var before: float = brain.aggression
	brain._take_offence(BRAIN.WORK_GOAL)
	_expect(is_equal_approx(brain.aggression, before), "a goal already given up on raises nothing further")

	# The meter never runs past a full one.
	for goal in range(8):
		brain._aggravated[goal] = false
		brain._goal_disabled[goal] = false
		brain._take_offence(goal)
	_expect(brain.aggression <= BRAIN.AGGRESSION_LIMIT, "the meter stops at full, got %f" % brain.aggression)
	_release(level)


# sub_402350 runs every frame over every agent.
func _check_the_office_mean_and_its_bands() -> void:
	var level := _level()
	await process_frame
	var runtime := level.get_node("LevelRuntime")
	var actors := []
	for name in ["Npc079MaleEmployee1", "Npc081FemaleEmployee1", "Npc080Boss"]:
		var actor := level.get_node("World/" + name)
		actor.get_node("Brain").enabled = false
		actor.get_node("Brain").aggression = 0.0
		actors.append(actor)

	runtime.refresh_aggression()
	_expect(is_equal_approx(runtime.aggression, 0.0), "a calm office reads zero")

	# The mean, not the total: one furious agent out of three is a third of the way up.
	actors[0].get_node("Brain").aggression = 90.0
	runtime.refresh_aggression()
	_expect(is_equal_approx(runtime.aggression, 30.0), "the office reads the mean, got %f" % runtime.aggression)

	# Bands are quarters of the meter, and each agent is handed the one the office is in.
	runtime.refresh_aggression()
	_expect(actors[0].aggression_band == 1, "a mean of 30 is the second band, got %d" % actors[0].aggression_band)
	for actor in actors:
		actor.get_node("Brain").aggression = 100.0
	runtime.refresh_aggression()
	runtime.refresh_aggression()
	_expect(is_equal_approx(runtime.aggression, 100.0), "a furious office reads full")
	_expect(actors[0].aggression_band == 3, "a full office is the top band, got %d" % actors[0].aggression_band)

	# Only a rise announces itself, and only while there is a higher band to reach.
	# Held in an array because a lambda captures a plain local by value.
	var rises := [0]
	runtime.aggravation_rose.connect(func(): rises[0] += 1)
	runtime.refresh_aggression()
	_expect(rises[0] == 0, "a settled office announces nothing")
	for actor in actors:
		actor.get_node("Brain").aggression = 0.0
	runtime.refresh_aggression()
	runtime.refresh_aggression()
	_expect(rises[0] == 0, "a calming office announces nothing either")
	for actor in actors:
		actor.get_node("Brain").aggression = 60.0
	runtime.refresh_aggression()
	_expect(rises[0] == 1, "crossing into a higher band announces itself once, got %d" % rises[0])

	# sub_419CE0 walks 0.15 faster per band; sub_419740, the boss, does not.
	var coworker: Node = actors[0]
	var boss: Node = actors[2]
	var coworker_base: float = coworker.profile.walk_speed_tiles
	var boss_base: float = boss.profile.walk_speed_tiles
	coworker.aggression_band = 0
	boss.aggression_band = 0
	_expect(is_equal_approx(coworker.get_move_speed_tiles(), coworker_base), "a calm coworker keeps its profile pace")
	coworker.aggression_band = 3
	boss.aggression_band = 3
	_expect(
		is_equal_approx(coworker.get_move_speed_tiles(), coworker_base + 0.45),
		"the top band adds 0.45 tiles a second, got %f" % coworker.get_move_speed_tiles()
	)
	_expect(is_equal_approx(boss.get_move_speed_tiles(), boss_base), "the boss walks at his own pace whatever the office does")
	_release(level)
