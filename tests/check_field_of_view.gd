extends SceneTree

# The selected colleague's field of view, as recovered in docs/field-of-view-reference.md.
# The GDScript build must equal, byte for byte, the masks and texels the original built under
# emulation (tests/fixtures/fov_golden_masks.json, written by tools/export_fov_goldens.py).
# In level 1 the tint follows only the selected agent, only through sub_402260's signed,
# strict 12-tile gate, and sits between the floor and everything drawn after it. The level's
# stores are pointed at files of the check's own before the level loads.

const MASK := preload("res://scenes/shared/field_of_view_mask.gd")
const FIELD_OF_VIEW := preload("res://scenes/level/field_of_view.gd")
const SHADER := preload("res://scenes/shared/field_of_view.gdshader")
const LEVEL := preload("res://scenes/level_1.tscn")
const FIXTURE := "res://tests/fixtures/fov_golden_masks.json"
const SETTINGS_PATH := "user://check_field_of_view_settings.cfg"
const PROGRESS_PATH := "user://check_field_of_view_progress.cfg"
const SOURCES := ["res://scenes/level/field_of_view.gd", "res://scenes/shared/field_of_view_mask.gd"]

var _failures := 0
var _scratch := PackedByteArray([0, 0, 0, 0])


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_check_the_constants_are_the_originals()
	_check_every_golden()
	_check_the_mask_reads_as_a_view()
	_check_the_gate()
	_check_the_sources_write_no_player_data()
	var restore := _redirect_stores()
	await _check_level_one()
	_restore_stores(restore)
	if _failures == 0:
		print("Field of view: every golden mask and texel, the gate, the draw order and the pause passed")
	quit(1 if _failures else 0)


func _expect(condition: bool, label: String) -> void:
	if not condition:
		_failures += 1
		push_error(label)


func _bits(value: float) -> int:
	_scratch.encode_float(0, value)
	return _scratch.decode_u32(0)


func _float(bits: int) -> float:
	_scratch.encode_u32(0, bits)
	return _scratch.decode_float(0)


# tools/export_fov_tables.py and tools/export_view_angles.py read these out of sacked.exe and
# their --check pins every instruction that reads them; this proves the files are the ones the
# mask and the node load, and that each reaches GDScript as the very float32.
func _check_the_constants_are_the_originals() -> void:
	_expect(MASK.load_tables(), "the mask loads its tables")
	_expect(_bits(MASK.INVERSE_45) == 0x3CB60AE9, "the sector constant is the float32 at 0x4667D4")
	_expect(_bits(MASK.DEGREES) == 0x3C8EF998, "the degree constant is the float32 at 0x465540")
	_expect(MASK.GATE_TILES == 12.0, "the gate is the 12.0 at flt_4652CC, got %f" % MASK.GATE_TILES)
	_expect(MASK.REACH_TILES == 7.0, "the diamond reaches the 7.0 at 0x4667B8, got %f" % MASK.REACH_TILES)
	_expect(MASK.TEXELS_PER_TILE == 8.0, "a tile is the 8.0 texels at 0x465878, got %f" % MASK.TEXELS_PER_TILE)
	_expect(MASK.SAMPLE_STEP == 0.125, "the shadow walk steps by the 0.125 at 0x465854, got %f" % MASK.SAMPLE_STEP)


func _check_every_golden() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	var grids := {}
	for name: String in data["maps"]:
		var level_map: Dictionary = data["maps"][name]
		var grid := PackedByteArray()
		grid.resize(int(level_map["width"]) * int(level_map["height"]))
		for cell: Array in level_map["sight"]:
			grid[int(cell[1]) * int(level_map["width"]) + int(cell[0])] = 1
		grids[name] = [grid, int(level_map["width"]), int(level_map["height"])]
	var cases: Array = data["cases"]
	_expect(cases.size() >= 76, "the fixture holds the recorded cases, got %d" % cases.size())
	# One build object for the lot, run forwards and then backwards, so the cached disc,
	# octant templates and shadows are exercised across changes of map, radius and position.
	var built := MASK.new()
	var total := 0
	var order := range(cases.size())
	order.append_array(range(cases.size() - 1, -1, -1))
	for index: int in order:
		var golden: Dictionary = cases[index]
		var values := []
		for bits in golden["float32_bits"]:
			values.append(_float(int(bits)))
		var grid: Array = grids[golden["map"]]
		var started := Time.get_ticks_usec()
		built.build(values[0], values[1], values[2], values[3], values[4], grid[0], grid[1], grid[2])
		total += Time.get_ticks_usec() - started
		var label := String(golden["name"])
		_expect(built.octants == int(golden["octants"]), "%s: octants %02x, the original %02x" % [label, built.octants, int(golden["octants"])])
		var mask := built.hidden_bytes()
		var expected_mask := _decode(golden["mask"], true)
		if mask != expected_mask:
			_expect(false, "%s: the mask differs from the original's at %s" % [label, _first_difference(mask, expected_mask)])
		var expected_texels := _decode(golden["texels"], false)
		if built.texels != expected_texels:
			_expect(false, "%s: the texels differ from the original's at %s" % [label, _first_difference(built.texels, expected_texels)])
	print("Field of view: %d golden builds, %.0f us each on average" % [order.size(), float(total) / order.size()])


func _first_difference(got: PackedByteArray, expected: PackedByteArray) -> String:
	for index in mini(got.size(), expected.size()):
		if got[index] != expected[index]:
			@warning_ignore("integer_division")
			return "row %d, column %d (%d, expected %d)" % [index / MASK.SIDE, index % MASK.SIDE, got[index], expected[index]]
	return "size %d, expected %d" % [got.size(), expected.size()]


# Rows joined by "/", "=" repeating the row above; a mask row is alternating run lengths from
# 0, a texel row is value*count tokens.
func _decode(text: String, is_mask: bool) -> PackedByteArray:
	var out := PackedByteArray()
	var previous := PackedByteArray()
	for row_text in text.split("/"):
		var row := PackedByteArray()
		if row_text == "=":
			row = previous
		elif is_mask:
			var value := 0
			for run in row_text.split(","):
				for _count in int(run):
					row.append(value)
				value = 1 - value
		else:
			for token in row_text.split(" "):
				var parts := token.split("*")
				var count := int(parts[1]) if parts.size() > 1 else 1
				for _count in count:
					row.append(int(parts[0]))
		out.append_array(row)
		previous = row
	return out


# In the open, looking along +x: the floor ahead is tinted, the floor behind is not, and a
# sight-blocking cell three tiles ahead hides what lies behind it.
func _check_the_mask_reads_as_a_view() -> void:
	var open := PackedByteArray()
	open.resize(400)
	var built := MASK.new()
	built.build(10.0, 10.0, 5.0, 90.0, 60.0, open, 20, 20)
	_expect(not built.is_hidden(56, 56 + 24) and built.texel(56, 56 + 24) == 64, "three tiles ahead is visible and fully tinted")
	_expect(built.is_hidden(56, 56 - 24) and built.texel(56, 56 - 24) == 0, "three tiles behind is hidden and untinted")
	_expect(built.is_hidden(56, 56) and built.texel(56, 56) < 64, "the agent's own texel is always hidden")
	var walled := open.duplicate()
	walled[10 * 20 + 13] = 1
	built.build(10.0, 10.0, 5.0, 90.0, 60.0, walled, 20, 20)
	_expect(not built.is_hidden(56, 56 + 16), "two tiles ahead is still visible before the wall")
	_expect(built.is_hidden(56, 56 + 36), "four and a half tiles ahead is in the wall's shadow")


func _check_the_gate() -> void:
	_expect(FIELD_OF_VIEW.passes_gate(Vector2(11.999, 0.0), Vector2.ZERO), "11.999 tiles on x passes")
	_expect(not FIELD_OF_VIEW.passes_gate(Vector2(12.0, 0.0), Vector2.ZERO), "exactly 12.0 on x does not: the compare is strict")
	_expect(not FIELD_OF_VIEW.passes_gate(Vector2(0.0, 12.0), Vector2.ZERO), "exactly 12.0 on z does not")
	_expect(not FIELD_OF_VIEW.passes_gate(Vector2(20.0, 30.0), Vector2(8.0, 10.0)), "12.0 on x with the player off the origin does not")
	_expect(FIELD_OF_VIEW.passes_gate(Vector2(-50.0, -50.0), Vector2.ZERO), "50 tiles toward -x and -z passes: the compare is signed")
	_expect(FIELD_OF_VIEW.passes_gate(Vector2(NAN, 0.0), Vector2.ZERO), "a NaN passes, as an unordered fcomp does")


func _check_the_sources_write_no_player_data() -> void:
	for path: String in SOURCES:
		var source := (load(path) as Script).source_code
		for forbidden in ["user://", "SettingsStore", "ProgressStore", "FileAccess.WRITE", "save_png", ".save("]:
			_expect(not source.contains(forbidden), "%s never writes player data, but mentions %s" % [path, forbidden])


func _redirect_stores() -> Array:
	var restore := []
	for entry in [["SettingsStore", SETTINGS_PATH], ["ProgressStore", PROGRESS_PATH]]:
		var store: Node = root.get_node_or_null(entry[0])
		if store == null:
			continue
		restore.append([store, store.path, entry[1]])
		store.path = entry[1]
		DirAccess.remove_absolute(entry[1])
		store.reload()
	return restore


func _restore_stores(restore: Array) -> void:
	for entry: Array in restore:
		var store: Node = entry[0]
		store.path = entry[1]
		store.reload()
		DirAccess.remove_absolute(entry[2])


func _check_level_one() -> void:
	var level := LEVEL.instantiate()
	level.get_node("LevelRuntime").enabled = false
	root.add_child(level)
	await process_frame
	await process_frame
	var world := level.get_node("World") as Node2D
	# The agents stand still, so the heading moves only when the check moves it.
	for agent in get_nodes_in_group("npc_agents"):
		agent.process_mode = Node.PROCESS_MODE_DISABLED
	level.get_node("LevelRuntime/CatchWatch").process_mode = Node.PROCESS_MODE_DISABLED
	var player := world.get_node("Player") as Node2D
	player.set_physics_process(false)
	var controller := player.get_node("PrankController")
	controller.set_process(false)
	var view := level.get_node("LevelRuntime/FieldOfView") as Node2D
	var layer := world.get_node("CollisionTileMapLayer") as Node2D
	var boss := world.get_node("Npc080Boss") as Node2D
	var coworker := world.get_node("Npc079MaleEmployee1") as Node2D
	var boss_at: Vector2 = layer.to_grid_position(boss.global_position)
	var stores_before := [FileAccess.file_exists(SETTINGS_PATH), FileAccess.file_exists(PROGRESS_PATH)]

	await _frames(2)
	_expect(view.agent == null and not view.visible, "nothing is drawn while nobody is selected")

	_place(player, layer, boss_at + Vector2(3.0, -2.0))
	controller.select_agent(boss)
	await _frames(2)
	_expect(view.agent == boss and view.visible, "the selected boss's field of view is drawn")
	_check_it_is_the_boss_mask(view, layer, boss)
	_check_the_diamond(view, boss)
	_check_the_draw_order(level, world, view)

	var builds: int = view.builds
	await _frames(3)
	_expect(view.builds == builds, "nothing is rebuilt while nothing moves")
	boss.set("notice_heading", fposmod(float(boss.get("notice_heading")) + 30.0, 360.0))
	await _frames(2)
	_expect(view.builds == builds + 1, "turning the heading rebuilds the mask once")
	_check_it_is_the_boss_mask(view, layer, boss)

	# The tree is paused under the caught banner, the quit prompt and the pause panel; the
	# node keeps what it drew last.
	paused = true
	builds = view.builds
	boss.set("notice_heading", fposmod(float(boss.get("notice_heading")) + 30.0, 360.0))
	await _frames(3)
	_expect(view.visible and view.agent == boss and view.builds == builds, "a paused tree keeps the last mask on the floor")
	paused = false
	await _frames(2)
	_expect(view.builds == builds + 1, "the mask follows the heading again once the tree runs")

	_place(player, layer, boss_at + Vector2(-12.5, 0.0))
	await _frames(2)
	_expect(view.agent == null and not view.visible, "12.5 tiles past the player on x draws nothing")
	_place(player, layer, boss_at + Vector2(0.0, -12.5))
	await _frames(2)
	_expect(view.agent == null and not view.visible, "12.5 tiles past the player on z draws nothing")
	_place(player, layer, boss_at + Vector2(40.0, 40.0))
	await _frames(2)
	_expect(view.agent == boss and view.visible, "40 tiles away toward -x and -z still draws, as the signed gate does")

	_place(player, layer, boss_at + Vector2(3.0, -2.0))
	controller.select_agent(coworker)
	await _frames(2)
	_expect(view.agent == coworker, "selecting a colleague moves the tint to them")
	controller.select_agent(null)
	await _frames(2)
	_expect(view.agent == null and not view.visible, "clearing the selection clears the tint")
	_expect(
		[FileAccess.file_exists(SETTINGS_PATH), FileAccess.file_exists(PROGRESS_PATH)] == stores_before,
		"drawing the field of view saves nothing, not even to the check's own stores"
	)

	# The level's theme is playing; a playback freed mid-stream outlives the check.
	for music: AudioStreamPlayer in level.find_children("*", "AudioStreamPlayer", true, false):
		music.stop()
	await _frames(2)
	root.remove_child(level)
	level.free()


func _frames(count: int) -> void:
	for _frame in count:
		await process_frame


func _place(node: Node2D, layer: Node2D, grid: Vector2) -> void:
	var origin: Vector2 = layer.map_to_local(Vector2i.ZERO)
	var axis_x: Vector2 = layer.map_to_local(Vector2i(1, 0)) - origin
	var axis_z: Vector2 = layer.map_to_local(Vector2i(0, 1)) - origin
	node.global_position = layer.to_global(origin + axis_x * grid.x + axis_z * grid.y)


func _check_it_is_the_boss_mask(view: Node2D, layer: Node2D, boss: Node2D) -> void:
	var brain := boss.get_node("Brain")
	var at: Vector2 = layer.to_grid_position(boss.global_position)
	var cells: PackedVector2Array = layer.get("sight_blocked_cells")
	var width := 0
	var height := 0
	for cell in cells:
		width = maxi(width, int(cell.x) + 1)
		height = maxi(height, int(cell.y) + 1)
	var sight := PackedByteArray()
	sight.resize(width * height)
	for cell in cells:
		sight[int(cell.y) * width + int(cell.x)] = 1
	_expect(is_equal_approx(brain.notice_radius_tiles(), 5.8) and is_equal_approx(brain.notice_cone_degrees(), 75.0), "the boss sees 5.8 tiles through 75 degrees, unbanded")
	var expected := MASK.new()
	expected.build(at.x, at.y, brain.notice_radius_tiles(), float(boss.get("notice_heading")), brain.notice_cone_degrees(), sight, width, height)
	var built = view.get("mask")
	_expect(built.image.get_data() == expected.image.get_data(), "the drawn mask is the boss's, from his heading, radius, cone and level 1's sight cells")
	_expect(built.texels == expected.texels, "and so are its texels")
	_expect(built.octants == expected.octants, "and the octants walked")


func _check_the_diamond(view: Node2D, boss: Node2D) -> void:
	var corners: PackedVector2Array = view.call("corners")
	var anchor := view.to_local(boss.global_position)
	var offsets := [Vector2(0.0, -336.0), Vector2(672.0, 0.0), Vector2(0.0, 336.0), Vector2(-672.0, 0.0)]
	_expect(corners.size() == 4, "the tint is one four-cornered diamond")
	for index in mini(corners.size(), 4):
		_expect(
			(corners[index] - anchor).is_equal_approx(offsets[index]),
			"corner %d sits at %s from the agent's anchor, got %s" % [index, offsets[index], corners[index] - anchor]
		)
	_expect(view.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "the texels are sampled nearest")
	_expect(view.texture_repeat == CanvasItem.TEXTURE_REPEAT_DISABLED, "and never repeat")
	var material := view.material as ShaderMaterial
	_expect(material != null and material.shader == SHADER, "the tint is drawn by the field-of-view shader, not the depth test")
	_expect(material != null and material.shader.code.contains("blend_add"), "and added to what lies under it")
	# The port clips none of its world to the original's (1, 1, w - 1, h - 91), and the tint
	# lies on the floor it draws, so beside the console band at widescreen it reaches the
	# bottom of the canvas as the floor does. See "Clipping" in the reference.
	_expect(material != null and material.shader.get_shader_uniform_list().is_empty(), "the tint is clipped nowhere the floor is not: its shader takes no clip")
	_expect(material != null and not material.shader.code.contains("SCREEN_UV"), "and never asks where on the canvas it is")
	_expect(not ProjectSettings.get_setting("rendering/viewport/hdr_2d", false), "the canvas is 8-bit, so the add saturates as paddusb does")


# The tint lies on the floor and under everything the original paints after sub_402260.
func _check_the_draw_order(level: Node, world: Node2D, view: Node2D) -> void:
	var floor_layer := world.get_node("FloorTileMapLayer") as CanvasItem
	var fov_z := _absolute_z(view)
	var floor_bakes := floor_layer.get_children(true).filter(func(child: Node) -> bool: return child is Sprite2D)
	_expect(not floor_bakes.is_empty(), "the floor is baked into a sprite")
	for bake: CanvasItem in floor_bakes:
		_expect(_absolute_z(bake) < fov_z, "the floor bake (z %d) is under the tint (z %d)" % [_absolute_z(bake), fov_z])
	var above: Array[CanvasItem] = [world.get_node("WallTileMapLayer"), world.get_node("GlassTileMapLayer"), world.get_node("Objects")]
	for child in world.get_node("WorldDepthCompositor").get_children(true):
		if child is CanvasItem:
			above.append(child)
	for character in get_nodes_in_group("depth_composited_characters"):
		for child in character.get_children():
			if child is CanvasItem:
				above.append(child)
	above.append(level.get_node("LevelRuntime/ScorePopups"))
	for item in above:
		_expect(_absolute_z(item) > fov_z, "%s (z %d) is drawn over the tint (z %d)" % [item.name, _absolute_z(item), fov_z])
	var console := level.get_node("LevelRuntime/Console") as CanvasLayer
	_expect(console != null and console.layer > 0, "the HUD is a canvas layer of its own, above the world")
	var parent := view.get_parent()
	while parent != null:
		_expect(not parent is CanvasLayer, "the tint is drawn in the world's canvas, not a layer of its own")
		parent = parent.get_parent()


func _absolute_z(item: CanvasItem) -> int:
	var z := 0
	var node: Node = item
	while node is CanvasItem:
		z += (node as CanvasItem).z_index
		if not (node as CanvasItem).z_as_relative:
			break
		node = node.get_parent()
	return z
