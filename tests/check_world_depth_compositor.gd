extends SceneTree


const WORLD_SCRIPT := preload("res://scenes/shared/world_depth_compositor.gd")
const OBJECT_SCRIPT := preload("res://scenes/shared/map_object.gd")

var _failures := 0


class FixtureCharacters:


	extends "res://scenes/shared/character_depth_compositor.gd"


	var fixture_depth: Image
	var fixture_depths: Dictionary = {}
	var output_image: Image


	func _make_actor(node: Node2D, sprite: Sprite2D, actor_index: int) -> Dictionary:
		var actor := super._make_actor(node, sprite, actor_index)
		if not actor.is_empty():
			actor["color"] = sprite.texture.get_image()
			actor["depth"] = fixture_depths.get(node.name, fixture_depth)
		return actor


	func _depth_texture(path: String) -> Texture2D:
		return ImageTexture.create_from_image(fixture_depths.get(path.get_file(), fixture_depth))


	func _set_surface_image(index: int, image: Image) -> void:
		# The headless dummy renderer keeps stale ImageTexture readbacks after update().
		output_image = image
		super._set_surface_image(index, image)


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
	var character := _add_character(world, "Character", Color.BLUE)
	var characters := FixtureCharacters.new()
	characters.fixture_depth = _depth_image([10, 10, 10, 10])
	world.add_child(characters)
	characters.set_process(false)
	characters.update_composition()
	await process_frame

	var sprite := character.get_node("Sprite2D") as Sprite2D
	var material := sprite.material as ShaderMaterial
	_expect(material != null, "a lone character is masked against the world by its own shader")
	_expect(sprite.visible and not characters.visible, "GPU masking leaves the character drawing itself with no CPU composite")
	_expect(object.get_node("Sprite2D").visible, "masking preserves authored object visibility")
	if material != null:
		_expect(bool(material.get_shader_parameter("depth_map_enabled")), "character shader receives its own depth plane")
		_expect(bool(material.get_shader_parameter("world_depth_enabled")), "character shader receives the static world depth buffer")
		_expect(material.get_shader_parameter("world_depth_origin") == mask.depth_bounds.position, "character shader receives the world buffer origin")
		_expect(material.get_shader_parameter("world_depth_size") == mask.depth_bounds.size, "character shader receives the world buffer size")
		_expect(float(material.get_shader_parameter("base_y")) == 0.0, "character shader receives its half-anchor base depth")

	# The shader reads the same scores the CPU compositor computes, so both paths agree.
	var buffer: Image = mask.depth_texture.get_image()
	_expect(buffer.get_format() == Image.FORMAT_RF, "static depth buffer is a single-channel float texture")
	_expect(buffer.get_data().to_float32_array() == mask.depth_scores, "static depth buffer carries the exact composited scores")

	object.depth_texture = ImageTexture.create_from_image(_depth_image([10, 20, 0, 20]))
	mask.rebuild()
	characters.update_composition()
	await process_frame
	_expect(characters.environment_scores == mask.depth_scores, "character compositor refreshes static depth data after a texture change")
	if material != null:
		_expect(material.get_shader_parameter("world_depth") == mask.depth_texture, "character shader follows the rebuilt world depth buffer")

	var previous_revision: int = mask.revision
	object.position.x = 10
	mask.rebuild()
	characters.update_composition()
	await process_frame
	_expect(mask.revision == previous_revision + 1, "moving an object rebuilds the static mask once")
	_expect(mask.depth_bounds == Rect2(10, 0, 4, 1), "moving an object repositions its mask")
	if material != null:
		_expect(material.get_shader_parameter("world_depth_origin") == Vector2(10, 0), "character shader follows the moved world buffer")

	# Two characters on the same pixels still need the CPU to resolve mutual depth.
	object.position.x = 0
	mask.rebuild()
	var second := _add_character(world, "Second", Color.GREEN)
	characters.fixture_depths["Second"] = _depth_image([30, 5, 30, 5])
	characters.update_composition()
	await process_frame
	_expect(characters.visible, "overlapping characters fall back to a CPU composite")
	_expect(not sprite.visible and not second.get_node("Sprite2D").visible, "the composite replaces both overlapping bodies")
	_expect_pixels(characters.output_image, [Color.BLUE, Color.GREEN, Color.TRANSPARENT, Color.GREEN], "composite resolves character depth against each other and the world")
	_expect(characters.composed_scores[1] == -5, "nearer character pixel reaches the output depth buffer")

	world.remove_child(second)
	second.free()
	characters.update_composition()
	await process_frame
	_expect(not characters.visible and sprite.visible, "a separated character returns to its own shaded sprite")

	previous_revision = mask.revision
	world.remove_child(object)
	object.free()
	mask.rebuild()
	characters.update_composition()
	_expect(mask.revision == previous_revision + 1, "removing the last object rebuilds the static mask")
	_expect(mask.depth_scores.is_empty() and mask.depth_bounds == Rect2(), "removing the last object clears all static depth data")
	_expect(mask._composite.texture == null and mask.depth_texture == null, "removing the last object clears the displayed static composite")
	if material != null:
		_expect(not bool(material.get_shader_parameter("world_depth_enabled")), "character shader stops masking once the world has no depth")
	world.free()


func _add_character(world: Node2D, name: String, color: Color) -> Node2D:
	var character := Node2D.new()
	character.name = name
	character.add_to_group("depth_composited_characters")
	var sprite := Sprite2D.new()
	sprite.name = "Sprite2D"
	sprite.centered = false
	sprite.texture = ImageTexture.create_from_image(_color_image(color))
	sprite.texture.take_over_path("res://tests/synthetic-%s.png" % name.to_lower())
	character.add_child(sprite)
	world.add_child(character)
	return character


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
