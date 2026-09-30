extends SceneTree

# CPisspuddle, the puddle urinating leaves: the parameters exported from sacked.exe, where it
# lands ahead of each character's three views, its growth clip played once per puddle, its
# depth base, the spread and fade after ten seconds, what the draw is handed, and the depth
# test: tick() sets it up without waiting for a frame, and on every later frame the puddle's own
# _process does, once, after the controller's tick.
# See docs/player-ability-reference.md, "The puddle: CPisspuddle".

const PUDDLE := preload("res://scenes/effects/puddle.gd")

# The table in "Where it goes": each view's offset from the player's anchor, in pixels.
const OFFSETS := [
	[true, 2, Vector2(9.6, 2.4)],
	[true, 3, Vector2(0.0, 4.4)],
	[true, 4, Vector2(-9.6, 2.4)],
	[false, 0, Vector2(28.8, -16.8)],
	[false, 6, Vector2(-28.8, -16.8)],
	[false, 7, Vector2(0.0, -22.8)],
]
# The last frame's size and pivot, from the ANIM.
const LAST_SIZE := Vector2(68, 48)
const LAST_PIVOT := Vector2(34, 22)

var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_check_the_parameters_are_the_recovered_ones()
	_check_it_lands_ahead_along_the_view()
	_check_the_clip_grows_once()
	_check_the_depth_base_and_the_quad()
	_check_the_spread_and_the_fade()
	_check_the_draw_data_once_spread()
	_check_an_empty_bounds_tests_no_actor()
	_check_tick_sets_up_the_depth_test()
	await _check_later_frames_set_up_the_test_after_the_tick()
	if _failures == 0:
		print("Puddle: the exported parameters, the six landing spots, the growth clip, the depth base, the spread and fade, the draw data, the depth test set up by tick() and, on later frames, once after it passed")
	quit(1 if _failures else 0)


func _expect(condition: bool, label: String) -> void:
	if not condition:
		_failures += 1
		push_error(label)


func _near(a: float, b: float, epsilon := 1.0e-6) -> bool:
	return absf(a - b) <= epsilon


func _puddle() -> Sprite2D:
	var puddle := PUDDLE.new() as Sprite2D
	root.add_child(puddle)
	return puddle


# tools/export_puddle_params.py reads these out of sacked.exe and its --check pins them; this
# only proves the file is the one the puddle loads.
func _check_the_parameters_are_the_recovered_ones() -> void:
	var params: Dictionary = PUDDLE.params()
	var expected := {
		"reach_anne": 0.2, "reach_jo": 0.6, "height": 0.1, "alpha": 0.7, "grow_rate": 0.08,
		"fade_rate": 0.085, "fade_from": 0.7, "remove_after": 17.0, "min_scale": 0.01,
		"fixed_units": 256.0, "height_pixels": 24.0,
	}
	for key: String in expected:
		_expect(_near(float(params.get(key, -1.0)), float(expected[key]), 1.0e-6), "%s is %s, got %s" % [key, expected[key], params.get(key)])
	# The ten-second gate is flt_4652F4, which tools/export_ability_timers.py reads with the
	# player clock's other readers of it.
	_expect(not params.has("grow_after"), "puddle.json leaves the gate to ability_timers.json")
	_expect(PUDDLE.grow_after() == 10.0, "the gate is the 10.0 at flt_4652F4, got %f" % PUDDLE.grow_after())
	var puddle := _puddle()
	_expect(puddle.alpha_byte() == 179, "a new puddle's alpha of 0.7 is byte 179, got %d" % puddle.alpha_byte())
	_expect(puddle.scale_units() == 256, "and its scale is 1.0, 256 units")
	_expect(puddle.z_index == 3, "it is drawn in the effects pass, after the characters")
	puddle.free()


# a = (view * 45 + 180) * 0.017453 and d = 0.2 or 0.6 tiles along it, 0.1 units up, which the
# projection lifts 2.4 px.
func _check_it_lands_ahead_along_the_view() -> void:
	var player_ground := Vector2(7.0, 5.0)
	var origin := Vector2(100.0, 40.0)
	var player_anchor := origin + IsoDirection.ground_to_screen(player_ground)
	for case in OFFSETS:
		var anne: bool = case[0]
		var view: int = case[1]
		var offset: Vector2 = case[2]
		var puddle := _puddle()
		puddle.place(player_ground, view, anne, origin, 3.0)
		puddle.tick(3.0)
		var a := (float(view) * 45.0 + 180.0) * 0.017453
		var reach := 0.2 if anne else 0.6
		var ground := Vector2(player_ground.x - reach * sin(a), player_ground.y + reach * cos(a))
		_expect(puddle.ground.distance_to(ground) < 1.0e-5, "view %d: the puddle lies %.1f tiles along it at %s, got %s" % [view, reach, ground, puddle.ground])
		_expect(_near(puddle.height, 0.1), "view %d: 0.1 units up" % view)
		var got: Vector2 = puddle.anchor - player_anchor
		_expect(got.distance_to(offset) < 0.05, "%s view %d lands %s px from the player's anchor, got %s" % ["Anne" if anne else "Jo", view, offset, got])
		puddle.free()


# The clip plays once from the tick state 21 built the puddle: frame trunc(t * 8), frame 10 held
# from 1.25 s, each puddle on its own start.
func _check_the_clip_grows_once() -> void:
	var puddle := _puddle()
	_expect(puddle.frame_count() == 11, "the clip has 11 frames, got %d" % puddle.frame_count())
	var cases := {0.0: 0, 0.124: 0, 0.125: 1, 0.6: 4, 1.249: 9, 1.25: 10, 7.0: 10, 16.0: 10}
	for elapsed: float in cases:
		_expect(puddle.frame_at(elapsed) == int(cases[elapsed]), "%.3f s in shows frame %d, got %d" % [elapsed, cases[elapsed], puddle.frame_at(elapsed)])
	puddle.place(Vector2(4.0, 4.0), 2, true, Vector2.ZERO, 10.0)
	var other := _puddle()
	other.place(Vector2(4.0, 4.0), 2, true, Vector2.ZERO, 10.5)
	puddle.tick(10.75)
	other.tick(10.75)
	_expect(puddle.clip_frame == 6 and other.clip_frame == 2, "each puddle runs its own clip, got %d and %d" % [puddle.clip_frame, other.clip_frame])
	_expect(puddle.texture != other.texture, "and shows its own frame")
	puddle.free()
	other.free()


# sub_41A2D0's anchor and depth base, and the quad the unscaled draw covers.
func _check_the_depth_base_and_the_quad() -> void:
	var puddle := _puddle()
	puddle.place(Vector2(6.3, 2.9), 7, false, Vector2(12.0, -30.0), 0.0)
	puddle.tick(2.0)
	var anchor := Vector2(12.0, -30.0) + IsoDirection.ground_to_screen(puddle.ground) - Vector2(0.0, 2.4)
	_expect(puddle.anchor.distance_to(anchor) < 1.0e-4, "the anchor is ground(x, z) - (0, 24 * 0.1), got %s" % puddle.anchor)
	_expect(puddle.depth_base == ceilf(float(int(anchor.y)) * 0.5), "the base score is ceil(int(y) / 2), got %s" % puddle.depth_base)
	_expect(puddle.clip_frame == 10, "the grown frame shows")
	var top_left := anchor.floor() - LAST_PIVOT
	_expect(puddle.drawn_rect == Rect2(top_left, LAST_SIZE), "unscaled, the 68 x 48 frame sits at the anchor less its pivot, got %s" % puddle.drawn_rect)
	_expect(puddle.global_position == top_left and puddle.scale == Vector2.ONE, "the sprite is placed on that quad")
	puddle.free()


# The player tick past ten seconds: s = 1 + 0.08 (age - 10) and +900 = 0.7 - 0.085 (age - 10),
# which the draw truncates to 1/256; the 68 x 48 frame then covers ((w - 1) * S >> 8) + 1
# pixels each way.
func _check_the_spread_and_the_fade() -> void:
	var puddle := _puddle()
	puddle.place(Vector2(5.0, 5.0), 2, true, Vector2.ZERO, 0.0)
	var cases := [
		[12.0, 296, 135, Vector2(78, 55)],
		[14.0, 337, 92, Vector2(89, 62)],
		[16.0, 378, 48, Vector2(99, 70)],
		[16.9, 397, 29, Vector2(104, 73)],
		[17.0, 399, 26, Vector2(105, 74)],
	]
	for case in cases:
		var age: float = case[0]
		puddle.grow(age)
		puddle.tick(age)
		_expect(puddle.scale_units() == int(case[1]), "at %.1f s the scale is %d/256, got %d (%f)" % [age, case[1], puddle.scale_units(), puddle.spread])
		_expect(puddle.alpha_byte() == int(case[2]), "at %.1f s the alpha byte is %d, got %d (%f)" % [age, case[2], puddle.alpha_byte(), puddle.alpha])
		_expect(puddle.drawn_rect.size == case[3], "at %.1f s the frame covers %s, got %s" % [age, case[3], puddle.drawn_rect.size])
	_expect(_near(puddle.spread, 1.56, 1.0e-6) and _near(puddle.alpha, 0.105, 1.0e-6), "the values themselves are float32")
	# sub_42B450 clamps each scale to 0.01.
	puddle.grow(-3.0)
	_expect(_near(puddle.spread, 0.01, 1.0e-8) and puddle.scale_units() == 2, "a scale below 0.01 is clamped to it, got %f" % puddle.spread)
	puddle.free()


# At seventeen seconds the 68 x 48 frame covers ((w - 1) * 399 >> 8) + 1 = 105 by 74 pixels,
# placed at trunc(trunc(anchor) + pivot - pivot * s) - pivot, and the shader samples it at a
# step of 0x10000 / 399.
func _check_the_draw_data_once_spread() -> void:
	var puddle := _puddle()
	puddle.place(Vector2(9.0, 7.0), 3, true, Vector2(0.0, 0.0), 0.0)
	puddle.grow(17.0)
	puddle.tick(17.0)
	var s: float = puddle.spread
	var top_left: Vector2 = (puddle.anchor.floor() + LAST_PIVOT - LAST_PIVOT * s).floor() - LAST_PIVOT
	_expect(puddle.drawn_rect == Rect2(top_left, Vector2(105, 74)), "the spread quad is 105 x 74 at %s, got %s" % [top_left, puddle.drawn_rect])
	_expect(puddle.global_position == top_left and puddle.scale.is_equal_approx(Vector2(105.0 / 68.0, 74.0 / 48.0)), "the sprite covers exactly that quad")
	var material := puddle.material as ShaderMaterial
	_expect(material != null and material.shader != null, "the puddle draws with its own shader")
	if material != null:
		_expect(float(material.get_shader_parameter("scale_units")) == 399.0, "the shader samples at scale 399")
		_expect(float(material.get_shader_parameter("alpha_byte")) == 26.0, "blends at alpha byte 26")
		_expect(material.get_shader_parameter("drawn_size") == Vector2(105, 74), "over the drawn size")
		_expect(float(material.get_shader_parameter("depth_base")) == puddle.depth_base, "from its own depth base")
		var depth := material.get_shader_parameter("depth_plane") as Texture2D
		_expect(depth != null and depth.resource_path == "res://images/effects/puddle/puddle-010-depth.png", "through the grown frame's own Z plane")
	_expect(puddle.texture != null and puddle.texture.resource_path == "res://images/effects/puddle/puddle-010.png", "and its colour")
	puddle.free()


# The shared helper only tests actors over an effect that covers something.
func _check_an_empty_bounds_tests_no_actor() -> void:
	var puddle := _puddle()
	var helper = preload("res://scenes/effects/effect_depth.gd").new()
	_expect(helper.depth_actors(puddle, Rect2()).is_empty(), "an empty quad tests no actor")
	puddle.free()


# tick() hands the shader the depth test with the rest of the draw, so the frame state 21 builds
# the puddle in, which runs none of the puddle's _process, is tested too: the world composite,
# and the depth-composited actors its quad overlaps, nearest first. Stand-ins take the place of
# the level's two compositors.
func _check_tick_sets_up_the_depth_test() -> void:
	var world := _depth_world()
	var buffer: Texture2D = world.get_node("WorldDepthCompositor").get("depth_texture")
	var plane: Texture2D = world.get_node("CharacterDepthCompositor").get("plane")
	# The puddle's first frame hangs from about (96, 388); two actors stand over it, one far off.
	var farther := _actor(world, Vector2(100, 395))
	var nearer := _actor(world, Vector2(96, 400))
	_actor(world, Vector2(600, 100))

	var puddle := PUDDLE.new() as Sprite2D
	world.add_child(puddle)
	puddle.place(Vector2(9.0, 7.0), 3, true, Vector2.ZERO, 0.0)
	puddle.tick(0.0)
	var material := puddle.material as ShaderMaterial
	_expect(material.get_shader_parameter("world_depth_enabled") == true and material.get_shader_parameter("world_depth") == buffer, "tick() sets the world composite, got %s" % material.get_shader_parameter("world_depth_enabled"))
	_expect(material.get_shader_parameter("world_depth_origin") == Vector2(-100, 200) and material.get_shader_parameter("world_depth_size") == Vector2(400, 300), "where the composite lies")
	var count = material.get_shader_parameter("actor_count")
	_expect(count != null and int(count) == 2, "and the two actors over its quad, got %s" % count)
	if count != null and int(count) == 2:
		var rects = material.get_shader_parameter("actor_rect")
		var bases = material.get_shader_parameter("actor_base")
		_expect(rects[0] == Vector4(76, 320, 40, 80) and rects[1] == Vector4(80, 315, 40, 80), "nearest first, each at its frame, got %s" % [rects.slice(0, 2)])
		_expect(float(bases[0]) == 200.0 and float(bases[1]) == 198.0, "scored ceil(int(y) / 2), got %s" % [bases.slice(0, 2)])
		_expect(material.get_shader_parameter("actor_depth_0") == plane and material.get_shader_parameter("actor_depth_1") == plane, "through the planes the compositor hands over")
	_expect(nearer != farther, "two distinct actors")
	world.free()


# On every frame after the one state 21 builds it in, the puddle's own _process sets the test
# up, once, after AbilityController's tick, which comes before the puddle in World's order.
# A stand-in for the controller spreads the puddle on one frame: its tick() leaves the test as
# it was, and by the end of that frame the shader tests the actor only the spread quad reaches.
func _check_later_frames_set_up_the_test_after_the_tick() -> void:
	var world := _depth_world()
	var controller := _stand_in("AbilityController", "var puddle: Sprite2D\nvar age := -1.0\nvar count_after_tick = null\nfunc _process(_delta: float) -> void:\n\tif age < 0.0:\n\t\treturn\n\tpuddle.grow(age)\n\tpuddle.tick(age)\n\tcount_after_tick = puddle.material.get_shader_parameter(\"actor_count\")\n\tage = -1.0\n")
	world.add_child(controller)
	var puddle := PUDDLE.new() as Sprite2D
	world.add_child(puddle)
	controller.set("puddle", puddle)
	puddle.place(Vector2(9.0, 7.0), 3, true, Vector2.ZERO, 0.0)
	puddle.tick(1.25)
	var unspread: Rect2 = puddle.drawn_rect
	# An actor whose frame ends on the column the unspread quad starts at.
	_actor(world, Vector2(unspread.position.x - 20.0, unspread.position.y + 80.0))
	var material := puddle.material as ShaderMaterial
	await process_frame
	await process_frame
	_expect(_tested_actors(material.get_shader_parameter("actor_count")) == 0, "the actor beside the unspread quad is not tested")

	controller.set("age", 15.0)
	await process_frame
	var spread: Rect2 = puddle.drawn_rect
	_expect(spread.position.x < unspread.position.x, "at 15 s the quad reaches left of %s, got %s" % [unspread, spread])
	_expect(_tested_actors(controller.get("count_after_tick")) == 0, "tick() on a later frame leaves the test to _process")
	var count := _tested_actors(material.get_shader_parameter("actor_count"))
	_expect(count == 1, "the same frame's _process tests the actor the spread quad reaches, got %d" % count)
	if count == 1:
		var rects = material.get_shader_parameter("actor_rect")
		var expected := Vector4(unspread.position.x - 40.0, unspread.position.y, 40.0, 80.0)
		_expect(rects[0] == expected, "at its frame %s, got %s" % [expected, rects[0]])
	world.free()


# An actor count the shader was never handed is its default, 0.
func _tested_actors(count) -> int:
	return 0 if count == null else int(count)


# A World holding stand-ins for the level's two compositors: the world composite, and one depth
# plane for every actor.
func _depth_world() -> Node2D:
	var world := Node2D.new()
	world.name = "World"
	root.add_child(world)
	var mask := _stand_in("WorldDepthCompositor", "var revision := 1\nvar depth_texture: Texture2D\nvar depth_bounds := Rect2()\n")
	mask.set("depth_texture", ImageTexture.create_from_image(Image.create(4, 4, false, Image.FORMAT_RF)))
	mask.set("depth_bounds", Rect2(-100, 200, 400, 300))
	world.add_child(mask)
	var characters := _stand_in("CharacterDepthCompositor", "var plane: Texture2D\nfunc depth_texture_for(_sprite: Sprite2D) -> Texture2D:\n\treturn plane\n")
	characters.set("plane", ImageTexture.create_from_image(Image.create(40, 80, false, Image.FORMAT_L8)))
	world.add_child(characters)
	return world


func _stand_in(node_name: String, body: String) -> Node:
	var script := GDScript.new()
	script.source_code = "extends Node\n" + body
	script.reload()
	var node := Node.new()
	node.set_script(script)
	node.name = node_name
	return node


# A depth-composited actor as EffectDepth finds one: a Sprite2D child showing a 40 x 80 frame
# whose feet are at the actor.
func _actor(world: Node, feet: Vector2) -> Node2D:
	var actor := Node2D.new()
	actor.add_to_group(&"depth_composited_characters")
	var sprite := Sprite2D.new()
	sprite.name = "Sprite2D"
	sprite.centered = false
	sprite.offset = Vector2(-20, -80)
	sprite.texture = ImageTexture.create_from_image(Image.create(40, 80, false, Image.FORMAT_RGBA8))
	actor.add_child(sprite)
	world.add_child(actor)
	actor.global_position = feet
	return actor
