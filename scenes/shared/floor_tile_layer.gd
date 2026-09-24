extends TileMapLayer

# The original's floor is one opaque mosaic: sub_4120A0 draws layer 0 first, truncated to whole
# pixels, through sub_458DC0, which copies each of a tile's 48 rows through the span table at
# 0x471C34 with no colour key, alpha or scaling. Drawn as one quad per cell, the staircase edges
# of two neighbouring diamonds are sampled separately, and at any non-integer scale or camera
# offset the clear colour shows through between them. So the cells are baked into one image and
# the layer itself stops drawing. See docs/map-rendering.md.
#
# The floor is assumed static: nothing calls set_cell on it at runtime, and a cell changed after
# _ready would not show. Not @tool, so the editor still paints and draws the cells themselves.

const BAKE_NAME := "FloorBake"


func _ready() -> void:
	var cells := get_used_cells()
	if cells.is_empty():
		return
	var atlases := {}
	var blits := []
	var low := Vector2i(1 << 30, 1 << 30)
	var high := -low
	for cell in cells:
		var source_id := get_cell_source_id(cell)
		var source := tile_set.get_source(source_id) as TileSetAtlasSource
		if not atlases.has(source_id):
			var atlas := source.texture.get_image()
			if atlas.is_compressed():
				atlas.decompress()
			atlas.convert(Image.FORMAT_RGBA8)
			atlases[source_id] = atlas
		var region := source.get_tile_texture_region(get_cell_atlas_coords(cell))
		# Where TileSetAtlasSource draws the tile's quad, which the 96 x 48 grid puts on whole pixels.
		var top_left := Vector2i(map_to_local(cell)) - region.size / 2 - get_cell_tile_data(cell).texture_origin
		blits.append([atlases[source_id], region, top_left])
		low = low.min(top_left)
		high = high.max(top_left + region.size)
	var image := Image.create_empty(high.x - low.x, high.y - low.y, false, Image.FORMAT_RGBA8)
	# The atlas alpha is exactly the span table, 0 or 255, so masking by it copies each diamond
	# whole and leaves its neighbours' pixels alone.
	for blit in blits:
		image.blit_rect_mask(blit[0], blit[0], blit[1], blit[2] - low)
	var bake := Sprite2D.new()
	bake.name = BAKE_NAME
	bake.centered = false
	bake.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	bake.texture = ImageTexture.create_from_image(image)
	bake.position = Vector2(low)
	add_child(bake, false, Node.INTERNAL_MODE_FRONT)
	enabled = false
