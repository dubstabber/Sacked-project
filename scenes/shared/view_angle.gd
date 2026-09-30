extends RefCounted

# A view or a heading in degrees, turned into radians as the original turns it: with the float32
# 45.0 (0x465548), 180.0 (0x465544) and 0.017453 (0x465540, not pi / 180) that
# tools/export_view_angles.py reads out of sacked.exe. The smoke and the puddle aim along the
# player's view with all three, and the field-of-view cone turns its edges with the last. See
# docs/player-ability-reference.md and docs/field-of-view-reference.md, "The cone".

const Float32 := preload("res://scenes/shared/float32.gd")
const OriginalData := preload("res://scenes/shared/original_data.gd")
const PATH := "res://resources/original/view_angles.json"


# a = (view * 45 + 180) * 0.017453 for player+124's view, as smoking's state 11 aims the smoke
# (0x41BDD8-0x41BDE8) and urinating's state 21 the puddle (0x41C370-0x41C380, 0x41C3A8-0x41C3B8).
static func of_view(view: int) -> float:
	var values := OriginalData.load_original(PATH)
	return (float(view) * float(values.get("view_degrees", 0.0)) + float(values.get("view_offset", 0.0))) * degrees_to_radians()


# 0.017453, as the float32 it is.
static func degrees_to_radians() -> float:
	return Float32.f32(float(OriginalData.load_original(PATH).get("degrees_to_radians", 0.0)))
