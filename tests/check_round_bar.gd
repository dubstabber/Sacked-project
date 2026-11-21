extends SceneTree

# RoundBarFan against the original's own stopwatch sweeps: tools/export_round_bar_goldens.py
# ran CGUIRoundBarTex::Draw (sub_45AEE0) under emulation and recorded which texel landed on
# every pixel. See docs/hud-reference.md, "How the stopwatch is swept".

const GOLDENS := "res://tests/fixtures/round_bar_goldens.json"

var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var goldens: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(GOLDENS))
	var cases: Array = goldens["cases"]
	_expect(cases.size() > 10, "the goldens hold the sweeps, got %d" % cases.size())

	# Each case from a fresh fan, then one fan carried up through every case in order, which
	# reuses the whole triangles it has already drawn, then back down, which has to drop them.
	for item in cases:
		_compare(_fan(goldens), item, goldens, "fresh")
	var climbing := _fan(goldens)
	for item in cases:
		_compare(climbing, item, goldens, "climbing")
	var reversed := cases.duplicate()
	reversed.reverse()
	for item in reversed:
		_compare(climbing, item, goldens, "falling")
	if _failures == 0:
		print("Round bar: %d stopwatch sweeps match the original texel for texel" % cases.size())
	quit(1 if _failures else 0)


func _expect(condition: bool, label: String) -> void:
	if not condition:
		_failures += 1
		push_error(label)


func _fan(goldens: Dictionary) -> RoundBarFan:
	var centre := Vector2i(int(goldens["centre"][0]), int(goldens["centre"][1]))
	return RoundBarFan.new(centre, float(goldens["radius"]), int(goldens["step"]), float(goldens["start_angle"]), int(goldens["texture_size"][0]))


func _decode(item: Dictionary, base: int) -> Dictionary:
	var pixels := {}
	for row in item["rows"]:
		var y := int(row[0])
		var x := int(row[1])
		var texel := int(row[2])
		pixels[Vector2i(x, y)] = texel
		var deltas := String(row[3])
		for index in range(deltas.length()):
			texel += deltas.unicode_at(index) - base
			pixels[Vector2i(x + 1 + index, y)] = texel
	return pixels


func _compare(fan: RoundBarFan, item: Dictionary, goldens: Dictionary, label: String) -> void:
	var expected := _decode(item, int(goldens["delta_base"]))
	var texels: PackedInt32Array = fan.draw(float(item["progress"]))[0]
	var drawn := {}
	for index in range(texels.size()):
		if texels[index] != RoundBarFan.NONE:
			@warning_ignore("integer_division")
			drawn[fan.origin + Vector2i(index % RoundBarFan.WINDOW, index / RoundBarFan.WINDOW)] = texels[index]
	var wrong := 0
	var first := ""
	for pixel in expected:
		if drawn.get(pixel, RoundBarFan.NONE) != expected[pixel]:
			wrong += 1
			if first.is_empty():
				first = "%s: original %d, port %d" % [pixel, expected[pixel], drawn.get(pixel, RoundBarFan.NONE)]
	for pixel in drawn:
		if not expected.has(pixel):
			wrong += 1
			if first.is_empty():
				first = "%s: port draws %d where the original draws nothing" % [pixel, drawn[pixel]]
	_expect(wrong == 0, "%s sweep at %f: %d pixels differ, first %s" % [label, float(item["progress"]), wrong, first])
