class_name GoalText
extends RefCounted

# The level's objective, in the wording its game mode uses.
#
# sub_408B60 builds this from the level's own CONDITION and drops it into the `%s` of
# Level_XX.txt for the description screen; the pause panel restates the same two lines from
# the running session. One rule, two callers, so it lives here rather than in either.
# See docs/shell-reference.md.

const TIME_GOAL := &"prompt.time_goal"
const TIME_GOAL_FORMAT := &"prompt.time_goal_format"
const POINTS_GOAL_FORMAT := &"prompt.points_goal_format"
const POINTS_TARGET_FORMAT := &"prompt.points_target_format"


# The original divides the CONDITION's seconds by 60 and prints whole minutes.
static func lines(mode: StringName, limit_seconds: float, target_score: int) -> Array:
	var minutes := int(limit_seconds / 60.0)
	# tr() needs a Node, so a RefCounted goes to the server the same way action_table.gd does.
	if mode == &"points":
		return [
			TranslationServer.translate(POINTS_GOAL_FORMAT) % minutes,
			TranslationServer.translate(POINTS_TARGET_FORMAT) % target_score,
		]
	return [
		TranslationServer.translate(TIME_GOAL),
		TranslationServer.translate(TIME_GOAL_FORMAT) % [target_score, minutes],
	]


static func sentence(mode: StringName, limit_seconds: float, target_score: int) -> String:
	return " ".join(lines(mode, limit_seconds, target_score))
