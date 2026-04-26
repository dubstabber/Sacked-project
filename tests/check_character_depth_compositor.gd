extends SceneTree


const CharacterDepthCompositorScript := preload("res://scenes/shared/character_depth_compositor.gd")
const EPSILON := 0.01

var _failed := false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_check_lower_actor_wins_normal_overlap()
	if _failed:
		return
	_check_local_depth_can_reverse_overlap()
	if _failed:
		return
	_check_transparent_pixels_do_not_write()
	if _failed:
		return
	_check_non_overlapping_actor_excluded()
	if _failed:
		return
	_check_transparent_padding_does_not_overlap()
	if not _failed:
		quit(0)


func _check_lower_actor_wins_normal_overlap() -> void:
	var result := _compose_two_pixels(
		Color.RED,
		10,
		100.0,
		Color.BLUE,
		10,
		90.0
	)
	_assert_color_close(result, Color.RED, "lower actor overlap")


func _check_local_depth_can_reverse_overlap() -> void:
	var result := _compose_two_pixels(
		Color.RED,
		70,
		100.0,
		Color.BLUE,
		10,
		90.0
	)
	_assert_color_close(result, Color.BLUE, "local depth overlap")


func _check_transparent_pixels_do_not_write() -> void:
	var compositor = CharacterDepthCompositorScript.new()
	var actors := [
		_make_actor(Color.RED, 10, 100.0),
		_make_actor(Color(0.0, 0.0, 1.0, 0.0), 10, 120.0),
	]
	var result: Dictionary = compositor.compose_images_for_test(actors)
	var image := result["image"] as Image
	_assert_color_close(image.get_pixel(0, 0), Color.RED, "transparent overlap")
	compositor.free()


func _check_non_overlapping_actor_excluded() -> void:
	var compositor = CharacterDepthCompositorScript.new()
	var actors := [
		_make_actor_at(Color.RED, 10, 100.0, Vector2.ZERO, Vector2i.ONE),
		_make_actor_at(Color.BLUE, 10, 110.0, Vector2.ZERO, Vector2i.ONE),
		_make_actor_at(Color.GREEN, 10, 120.0, Vector2(10.0, 10.0), Vector2i.ONE),
	]
	var overlapping := compositor.overlapping_actors_for_test(actors)
	_assert_equal_int(overlapping.size(), 2, "overlapping actor count")
	compositor.free()


func _check_transparent_padding_does_not_overlap() -> void:
	var compositor = CharacterDepthCompositorScript.new()
	var actors := [
		_make_padded_actor(Color.RED, 10, 100.0, Rect2i(Vector2i(0, 0), Vector2i(1, 1))),
		_make_padded_actor(Color.BLUE, 10, 110.0, Rect2i(Vector2i(3, 0), Vector2i(1, 1))),
	]
	var overlapping := compositor.overlapping_actors_for_test(actors)
	_assert_equal_int(overlapping.size(), 0, "transparent padding overlap count")
	compositor.free()


func _compose_two_pixels(
	left_color: Color,
	left_depth: int,
	left_base_y: float,
	right_color: Color,
	right_depth: int,
	right_base_y: float
) -> Color:
	var compositor = CharacterDepthCompositorScript.new()
	var actors := [
		_make_actor(left_color, left_depth, left_base_y),
		_make_actor(right_color, right_depth, right_base_y),
	]
	var result: Dictionary = compositor.compose_images_for_test(actors)
	var image := result["image"] as Image
	var pixel := image.get_pixel(0, 0)
	compositor.free()
	return pixel


func _make_actor(color: Color, depth: int, base_y: float) -> Dictionary:
	return _make_actor_at(color, depth, base_y, Vector2.ZERO, Vector2i.ONE)


func _make_actor_at(color: Color, depth: int, base_y: float, position: Vector2, size: Vector2i) -> Dictionary:
	return {
		"index": 0,
		"color": _solid_image(color, size),
		"depth": _solid_depth(depth, color.a, size),
		"position": position,
		"size": size,
		"base_y": base_y,
	}


func _make_padded_actor(color: Color, depth: int, base_y: float, opaque_rect: Rect2i) -> Dictionary:
	var actor := _make_actor_at(color, depth, base_y, Vector2.ZERO, Vector2i(4, 1))
	actor["opaque_rect"] = opaque_rect
	return actor


func _single_pixel_image(color: Color) -> Image:
	return _solid_image(color, Vector2i.ONE)


func _solid_image(color: Color, size: Vector2i) -> Image:
	var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	image.fill(color)
	return image


func _single_pixel_depth(depth: int, alpha: float) -> Image:
	return _solid_depth(depth, alpha, Vector2i.ONE)


func _solid_depth(depth: int, alpha: float, size: Vector2i) -> Image:
	var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	image.fill(
		Color(
			float(depth & 0xFF) / 255.0,
			float((depth >> 8) & 0xFF) / 255.0,
			0.0,
			alpha
		)
	)
	return image


func _assert_color_close(actual: Color, expected: Color, label: String) -> void:
	if absf(actual.r - expected.r) > EPSILON or absf(actual.g - expected.g) > EPSILON or absf(actual.b - expected.b) > EPSILON or absf(actual.a - expected.a) > EPSILON:
		_fail("%s expected %s, got %s" % [label, expected, actual])


func _assert_equal_int(actual: int, expected: int, label: String) -> void:
	if actual != expected:
		_fail("%s expected %d, got %d" % [label, expected, actual])


func _fail(message: String) -> void:
	if _failed:
		return
	_failed = true
	push_error(message)
	quit(1)
