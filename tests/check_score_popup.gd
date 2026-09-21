extends SceneTree

# The floating score numbers: sub_40A0D0 queues, sub_40A310 ages, sub_40A390 draws, and
# sub_409E40 builds the two animation tables. See docs/hud-reference.md.

const POPUP := preload("res://scenes/effects/score_popup.gd")

var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_check_the_font_matches_the_glyph_geometry()
	_check_the_animation_tables()
	_check_spawning_and_ageing()
	await _check_a_score_with_a_place_floats_there()
	if _failures == 0:
		print("Score popups: glyph geometry, both animation tables, ageing and the session hook passed")
	quit(1 if _failures else 0)


func _expect(condition: bool, label: String) -> void:
	if not condition:
		_failures += 1
		push_error(label)


func _popup() -> Node2D:
	var node := POPUP.new()
	root.add_child(node)
	return node


func _release(node: Node) -> void:
	root.remove_child(node)
	node.free()


# CO_EFFECT_FONT_SCORE has to be exactly the strip the draw indexes into.
func _check_the_font_matches_the_glyph_geometry() -> void:
	var font := POPUP.FONT as Texture2D
	_expect(font != null, "the score font is present")
	if font == null:
		return
	_expect(
		font.get_size() == Vector2(POPUP.GLYPH_SIZE.x * POPUP.GLYPH_COUNT, POPUP.GLYPH_SIZE.y),
		"the font is 13 glyphs of 24x32, got %s" % font.get_size()
	)
	# sub_40A0D0 stores `c - 44` and the draw sources at `24 * (byte - 1)`, so the port's
	# single bias of 45 has to put the minus sign on glyph 0 and the digits on 3..12.
	_expect("-".unicode_at(0) - POPUP.GLYPH_BIAS == 0, "the minus sign is glyph 0")
	_expect("0".unicode_at(0) - POPUP.GLYPH_BIAS == 3, "zero is glyph 3, after the two blanks")
	_expect("9".unicode_at(0) - POPUP.GLYPH_BIAS == 12, "nine is the last glyph")


# sub_409E40's own formulas, at the indices where it changes its mind.
func _check_the_animation_tables() -> void:
	var popup := _popup()

	_expect(popup.alpha_at(0) == 0, "a number starts invisible")
	_expect(popup.alpha_at(32) == 128, "the fade in is four a step, got %d" % popup.alpha_at(32))
	_expect(popup.alpha_at(63) == 252, "the fade in stops one step short of opaque")
	_expect(popup.alpha_at(64) == 255, "the number is opaque from step 64")
	_expect(popup.alpha_at(767) == 255, "it stays opaque until step 768")
	_expect(popup.alpha_at(768) == 255, "the fade out starts from opaque")
	_expect(popup.alpha_at(896) == 127, "the fade out is linear, got %d" % popup.alpha_at(896))
	_expect(popup.alpha_at(1023) == 0, "it is gone by step 1024")
	_expect(popup.alpha_at(1024) == 0, "and stays gone")

	# The rise climbs straight for two seconds, then hangs and bobs.
	_expect(is_equal_approx(popup.rise_at(0), 0.0), "a number starts where it was spawned")
	_expect(is_equal_approx(popup.rise_at(256), 72.0), "one second of phase is 72 pixels, got %f" % popup.rise_at(256))
	_expect(is_equal_approx(popup.rise_at(511), 143.0), "the climb ends just short of 144, got %f" % popup.rise_at(511))
	for index in range(512, POPUP.TABLE_SIZE):
		var rise: float = popup.rise_at(index)
		if rise < 128.0 or rise > 160.0:
			_expect(false, "the hanging number stays between 128 and 160, got %f at %d" % [rise, index])
			break
	# The table is exactly long enough for the last live phase of the longest number.
	_expect(POPUP.TABLE_SIZE > 1023 + POPUP.GLYPH_PHASE_STEP * 14, "the tables cover a 15 character number")
	_release(popup)


func _check_spawning_and_ageing() -> void:
	var popup := _popup()
	_expect(popup.live_count() == 0, "nothing floats until something is scored")

	popup.spawn(Vector2(100.0, 200.0), 250)
	_expect(popup.live_count() == 1, "scoring floats a number")

	# sub_40A310 drops a number the moment its phase reaches four.
	popup.advance(3.9)
	_expect(popup.live_count() == 1, "a number lives for four seconds")
	popup.advance(0.2)
	_expect(popup.live_count() == 0, "and is dropped once it runs out, not before")

	# A value with no drawable glyphs is not queued at all.
	popup.spawn(Vector2.ZERO, 0)
	_expect(popup.live_count() == 1, "a zero still floats")
	popup.advance(POPUP.LIFETIME)
	_expect(popup.live_count() == 0, "the queue empties")
	_release(popup)


# LevelSession only floats a number when the score came from somewhere in the world.
func _check_a_score_with_a_place_floats_there() -> void:
	var level := (load("res://scenes/level_1.tscn") as PackedScene).instantiate()
	root.add_child(level)
	await process_frame

	var runtime := level.get_node_or_null("LevelRuntime")
	var popups := runtime.get_node_or_null("ScorePopups") if runtime != null else null
	_expect(popups != null, "the level runtime carries its score popups")
	if runtime == null or popups == null:
		_release(level)
		return
	_expect(popups.z_index > 2, "the numbers are drawn over the world, the characters and a bubble")

	runtime.add_score(100)
	_expect(popups.live_count() == 0, "a score from nowhere floats nothing")
	runtime.add_score(250, Vector2(320.0, 240.0))
	_expect(popups.live_count() == 1, "a score from a place floats there")
	_expect(runtime.score == 350, "both scores still land on the session, got %d" % runtime.score)
	_release(level)
