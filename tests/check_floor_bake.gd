extends SceneTree

# The floor layer bakes its cells into one image because the original's floor is one opaque
# mosaic: sub_458DC0 copies each 94 x 48 tile row by row through the span table at 0x471C34,
# so every cell owns exactly those 2304 pixels, whole and shared with no neighbour. That is
# what this pins, on level 1 and on level 7, the largest bake. The seams the bake removes only
# show in a real render at a non-integer scale; see docs/map-rendering.md for how that was
# measured.

const FloorScriptPath := "res://scenes/shared/floor_tile_layer.gd"
const Levels: Array[String] = ["1", "7"]
const TileSize := Vector2i(94, 48)
const SpanTableArea := 2304

var _failed := false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	for label: String in Levels:
		await _check_level(label)
		if _failed:
			quit(1)
			return
	print("Floor bake matches the original's span-table mosaic on levels %s" % [Levels])
	quit(0)


# Row k of the table: (46, 2), (44, 6) ... (0, 94), (0, 94) ... (46, 2).
static func _span(row: int) -> Vector2i:
	var k := row if row < TileSize.y / 2 else TileSize.y - 1 - row
	return Vector2i(46 - 2 * k, 2 + 4 * k)


func _check_level(label: String) -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://resources/levels/level_%s.json" % label))
	var expected_cells: Array = manifest["tile_layers"][0]["cells"]
	var level := (load("res://scenes/level_%s.tscn" % label) as PackedScene).instantiate()
	var layer := level.get_node("World/FloorTileMapLayer") as TileMapLayer
	# Only the floor enters the tree, so nothing else in the level runs or bakes.
	layer.get_parent().remove_child(layer)
	level.free()
	root.add_child(layer)
	await process_frame
	_check_layer(layer, expected_cells, label)
	layer.free()


func _check_layer(layer: TileMapLayer, expected_cells: Array, label: String) -> void:
	if layer.get_script() == null or layer.get_script().resource_path != FloorScriptPath:
		_fail("level %s FloorTileMapLayer does not carry %s" % [label, FloorScriptPath])
		return
	if layer.enabled:
		_fail("level %s FloorTileMapLayer still draws its own cells after the bake" % label)
		return
	if layer.get_child_count() != 0 or layer.get_child_count(true) != 1 or not layer.get_child(0, true) is Sprite2D:
		_fail("level %s floor should hold exactly one internal Sprite2D" % label)
		return
	var bake := layer.get_child(0, true) as Sprite2D
	if bake.texture_filter != CanvasItem.TEXTURE_FILTER_NEAREST or bake.centered:
		_fail("level %s floor bake should be drawn uncentred with nearest filtering" % label)
		return

	# The cell data stays usable after the layer stops drawing.
	var cells := layer.get_used_cells()
	if cells.size() != expected_cells.size():
		_fail("level %s floor answers %d cells, manifest has %d" % [label, cells.size(), expected_cells.size()])
		return
	if layer.map_to_local(Vector2i.ZERO) != Vector2(48, 24) or layer.map_to_local(Vector2i(1, 0)) != Vector2(96, 48):
		_fail("level %s floor map_to_local no longer answers the 96 x 48 grid" % label)
		return
	for cell_data: Dictionary in expected_cells:
		var cell := Vector2i(int(cell_data["cell"][0]), int(cell_data["cell"][1]))
		var coords := Vector2i(int(cell_data["atlas_coords"][0]), int(cell_data["atlas_coords"][1]))
		if layer.get_cell_source_id(cell) != int(cell_data["source_id"]) or layer.get_cell_atlas_coords(cell) != coords:
			_fail("level %s floor cell %s no longer answers its manifest tile" % [label, cell])
			return
		# The bake copies a tile as the atlas holds it, so a flipped or transposed alternative
		# would come out wrong.
		if layer.get_cell_alternative_tile(cell) != 0:
			_fail("level %s floor cell %s uses an alternative tile the bake does not handle" % [label, cell])
			return

	var low := Vector2i(1 << 30, 1 << 30)
	var high := -low
	for cell in cells:
		var top_left := Vector2i(layer.map_to_local(cell)) - TileSize / 2
		low = low.min(top_left)
		high = high.max(top_left + TileSize)
	if bake.position != Vector2(low):
		_fail("level %s floor bake sits at %s, expected the cells' whole-pixel origin %s" % [label, bake.position, low])
		return
	var baked := bake.texture.get_image()
	if baked.get_size() != high - low or baked.get_format() != Image.FORMAT_RGBA8:
		_fail("level %s floor bake is %s, expected %s RGBA8" % [label, baked.get_size(), high - low])
		return

	var atlases := {}
	var baked_data := baked.get_data()
	for cell in cells:
		var source_id := layer.get_cell_source_id(cell)
		var source := layer.tile_set.get_source(source_id) as TileSetAtlasSource
		if not atlases.has(source_id):
			var image := source.texture.get_image()
			if image.is_compressed():
				image.decompress()
			image.convert(Image.FORMAT_RGBA8)
			atlases[source_id] = {"image": image, "data": image.get_data(), "checked": {}}
		var atlas: Dictionary = atlases[source_id]
		var region := source.get_tile_texture_region(layer.get_cell_atlas_coords(cell))
		if region.size != TileSize:
			_fail("level %s floor tile %s is %s, not the original's 94 x 48" % [label, layer.get_cell_atlas_coords(cell), region.size])
			return
		if not atlas["checked"].has(region.position):
			if not _atlas_tile_matches_span_table(atlas["image"], atlas["data"], region):
				_fail("level %s floor tile %s alpha is not the span table at 0x471C34" % [label, layer.get_cell_atlas_coords(cell)])
				return
			atlas["checked"][region.position] = true
		var top_left := Vector2i(layer.map_to_local(cell)) - TileSize / 2 - low
		var atlas_width: int = (atlas["image"] as Image).get_width()
		for row in TileSize.y:
			var span := _span(row)
			var baked_offset := ((top_left.y + row) * baked.get_width() + top_left.x + span.x) * 4
			var atlas_offset := ((region.position.y + row) * atlas_width + region.position.x + span.x) * 4
			if baked_data.slice(baked_offset, baked_offset + span.y * 4) != (atlas["data"] as PackedByteArray).slice(atlas_offset, atlas_offset + span.y * 4):
				_fail("level %s floor cell %s row %d differs from its atlas tile" % [label, cell, row])
				return

	# Every span copied whole and none overlapping: the opaque area is exactly one table per cell.
	var opaque := 0
	for index in range(3, baked_data.size(), 4):
		var alpha := baked_data[index]
		if alpha == 255:
			opaque += 1
		elif alpha != 0:
			_fail("level %s floor bake has partial alpha %d" % [label, alpha])
			return
	if opaque != SpanTableArea * cells.size():
		_fail("level %s floor bake has %d opaque px, expected %d x %d cells" % [label, opaque, SpanTableArea, cells.size()])


func _atlas_tile_matches_span_table(image: Image, data: PackedByteArray, region: Rect2i) -> bool:
	for row in TileSize.y:
		var span := _span(row)
		for column in TileSize.x:
			var alpha := data[((region.position.y + row) * image.get_width() + region.position.x + column) * 4 + 3]
			var inside := column >= span.x and column < span.x + span.y
			if alpha != (255 if inside else 0):
				return false
	return true


func _fail(message: String) -> void:
	_failed = true
	push_error(message)
	printerr(message)
