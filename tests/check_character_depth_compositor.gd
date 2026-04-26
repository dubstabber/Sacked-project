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
	return {
		"index": 0,
		"color": _single_pixel_image(color),
		"depth": _single_pixel_depth(depth, color.a),
		"position": Vector2.ZERO,
		"size": Vector2i.ONE,
		"base_y": base_y,
	}


func _single_pixel_image(color: Color) -> Image:
	var image := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	image.set_pixel(0, 0, color)
	return image


func _single_pixel_depth(depth: int, alpha: float) -> Image:
	var image := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	image.set_pixel(
		0,
		0,
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


func _fail(message: String) -> void:
	if _failed:
		return
	_failed = true
	push_error(message)
	quit(1)
