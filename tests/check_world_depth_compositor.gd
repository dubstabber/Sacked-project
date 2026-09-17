extends SceneTree


const WORLD_SCRIPT := preload("res://scenes/shared/world_depth_compositor.gd")
const OBJECT_SCRIPT := preload("res://scenes/shared/map_object.gd")

var _failures := 0


class FixtureCharacters:


	extends "res://scenes/shared/character_depth_compositor.gd"


	var fixture_depth: Image
	var output_image: Image


	func _make_actor(node: Node2D, sprite: Sprite2D, actor_index: int) -> Dictionary:
		var actor := super._make_actor(node, sprite, actor_index)
		if not actor.is_empty():
			actor["color"] = sprite.texture.get_image()
			actor["depth"] = fixture_depth
		return actor


	func _set_composite_image(image: Image) -> void:
		# The headless dummy renderer keeps stale ImageTexture readbacks after update().
		output_image = image
		super._set_composite_image(image)


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_check_partial_static_overlap_and_cache()
	_check_equal_depth_uses_authored_order()
	_check_editor_remove_and_restore()
	await _check_character_mask_tracks_object_changes()
	if _failures == 0:
		print("World depth compositor: partial occlusion, draw order, cache and live masks passed")
	quit(1 if _failures else 0)


func _check_partial_static_overlap_and_cache() -> void:
	var world := Node2D.new()
	root.add_child(world)
	var red := _add_object(world, Color.RED, [5, 8, 5, 8], Vector2(0, 20), Vector2(0, 20))
	var blue := _add_object(world, Color.BLUE, [3, 0, 5, 0], Vector2(0, 10), Vector2(0, 10))
	var mask = _add_world_mask(world)
	mask.rebuild()
	_expect(mask.depth_bounds == Rect2(0, 0, 4, 1), "static mask uses sprite pivots for its bounds")
	_expect(mask.depth_scores == PackedFloat32Array([5, 5, 5, 5]), "static scores use half anchor Y minus decoded depth")
	_expect_pixels(mask._composite.texture.get_image(), [Color.RED, Color.BLUE, Color.RED, Color.BLUE], "intersecting objects")
	_expect(red.get_node("Sprite2D").visible and blue.get_node("Sprite2D").visible, "composing objects preserves authored Sprite2D visibility")
	var revision: int = mask.revision
	var texture: Texture2D = mask._composite.texture
	mask.rebuild()
	_expect(mask.revision == revision, "unchanged static scene does not rebuild its mask")
	_expect(mask._composite.texture == texture, "unchanged static scene reuses its composite texture")
	world.free()


func _check_equal_depth_uses_authored_order() -> void:
	var world := Node2D.new()
	root.add_child(world)
	_add_object(world, Color.RED, [5, 5, 5, 5], Vector2(0, 20), Vector2(0, 20))
	_add_object(world, Color.BLUE, [0, 0, 0, 0], Vector2(0, 10), Vector2(0, 10))
	var mask = _add_world_mask(world)
	mask.rebuild()
	_expect_pixels(mask._composite.texture.get_image(), [Color.BLUE, Color.BLUE, Color.BLUE, Color.BLUE], "later object wins equal pixel depths despite its smaller anchor Y")
	world.free()


func _check_editor_remove_and_restore() -> void:
	var world := Node2D.new()
	root.add_child(world)
	var object := _add_object(world, Color.RED, [0, 0, 0, 0], Vector2.ZERO, Vector2.ZERO)
	var mask = _add_world_mask(world)
	mask.rebuild()
	world.remove_child(mask)
	world.add_child(mask)
	mask.rebuild()
	_expect_pixels(mask._composite.texture.get_image(), [Color.RED, Color.RED, Color.RED, Color.RED], "editor undo restores static mask")
	object.position.x = 10
	mask.rebuild()
	_expect(mask.depth_bounds.position.x == 10, "object remains editable after compositor remove and restore")
	_expect(mask.get_child_count(true) == 1, "editor undo does not duplicate transient preview sprites")
	world.free()


func _check_character_mask_tracks_object_changes() -> void:
	var world := Node2D.new()
	root.add_child(world)
	var object := _add_object(world, Color.RED, [0, 20, 0, 20], Vector2.ZERO, Vector2.ZERO)
	var mask = _add_world_mask(world)
	mask.rebuild()
	var character := Node2D.new()
	character.add_to_group("depth_composited_characters")
	var sprite := Sprite2D.new()
	sprite.name = "Sprite2D"
	sprite.centered = false
	sprite.texture = ImageTexture.create_from_image(_color_image(Color.BLUE))
	sprite.texture.take_over_path("res://tests/synthetic-world-character.png")
	character.add_child(sprite)
	world.add_child(character)
	var characters := FixtureCharacters.new()
	characters.fixture_depth = _depth_image([10, 10, 10, 10])
	world.add_child(characters)
	characters.set_process(false)
	characters.update_composition()
	await process_frame
	_expect(characters.visible, "a single character is composited against the static world")
	_expect_pixels(characters.output_image, [Color.TRANSPARENT, Color.BLUE, Color.TRANSPARENT, Color.BLUE], "character is partially masked by an intersecting object")
	_expect(not sprite.visible and object.get_node("Sprite2D").visible, "masking hides the runtime character and preserves authored object visibility")

	object.depth_texture = ImageTexture.create_from_image(_depth_image([10, 20, 0, 20]))
	mask.rebuild()
	characters.update_composition()
	await process_frame
	_expect(characters.environment_scores == mask.depth_scores, "character compositor refreshes static depth data after a texture change")
	_expect(characters.composed_scores[0] == -10, "equal-depth character pixel reaches the output depth buffer")
	_expect_pixels(characters.output_image, [Color.BLUE, Color.BLUE, Color.TRANSPARENT, Color.BLUE], "character draws over static pixels at equal depth")

	var previous_revision: int = mask.revision
	object.position.x = 10
	mask.rebuild()
	characters.update_composition()
	await process_frame
	_expect(characters.composed_scores == PackedFloat32Array([-10, -10, -10, -10]), "moving an object clears its prior depth values from character output")
	_expect(mask.revision == previous_revision + 1, "moving an object rebuilds the static mask once")
	_expect(mask.depth_bounds == Rect2(10, 0, 4, 1), "moving an object repositions its mask")
	_expect_pixels(characters.output_image, [Color.BLUE, Color.BLUE, Color.BLUE, Color.BLUE], "moving an object clears its previous character occlusion")

	object.position.x = 0
	mask.rebuild()
	characters.update_composition()
	await process_frame
	_expect_pixels(characters.output_image, [Color.BLUE, Color.BLUE, Color.TRANSPARENT, Color.BLUE], "moving an object back restores its mask")
	previous_revision = mask.revision
	world.remove_child(object)
	object.free()
	mask.rebuild()
	characters.update_composition()
	_expect(mask.revision == previous_revision + 1, "removing the last object rebuilds the static mask")
	_expect(mask.depth_scores.is_empty() and mask.depth_bounds == Rect2(), "removing the last object clears all static depth data")
	_expect(mask._composite.texture == null, "removing the last object clears the displayed static composite")
	_expect(not characters.visible and sprite.visible, "single character returns to its source sprite after static objects are removed")
	world.free()


func _add_world_mask(world: Node2D) -> Node2D:
	var mask = WORLD_SCRIPT.new()
	mask.name = "WorldDepthCompositor"
	world.add_child(mask)
	mask.set_process(false)
	return mask


func _add_object(world: Node2D, color: Color, depths: Array, anchor: Vector2, pivot: Vector2) -> Node2D:
	var object = OBJECT_SCRIPT.new()
	object.position = anchor
	object.pivot = pivot
	object.color_texture = ImageTexture.create_from_image(_color_image(color))
	object.depth_texture = ImageTexture.create_from_image(_depth_image(depths))
	var sprite := Sprite2D.new()
	sprite.name = "Sprite2D"
	object.add_child(sprite)
	world.add_child(object)
	return object


func _color_image(color: Color) -> Image:
	var image := Image.create(4, 1, false, Image.FORMAT_RGBA8)
	image.fill(color)
	return image


func _depth_image(depths: Array) -> Image:
	var image := Image.create(depths.size(), 1, false, Image.FORMAT_RGBA8)
	for index in range(depths.size()):
		var depth := int(depths[index])
		image.set_pixel(index, 0, Color(float(depth & 255) / 255.0, float(depth >> 8) / 255.0, 0.0, 1.0))
	return image


func _expect_pixels(image: Image, expected: Array, label: String) -> void:
	_expect(image.get_size() == Vector2i(expected.size(), 1), "%s image dimensions" % label)
	for index in range(mini(expected.size(), image.get_width())):
		var actual := image.get_pixel(index, 0)
		var expected_color: Color = expected[index]
		var matches := is_zero_approx(actual.a) if is_zero_approx(expected_color.a) else actual.is_equal_approx(expected_color)
		_expect(matches, "%s pixel %d: expected %s, got %s" % [label, index, expected[index], actual])


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
