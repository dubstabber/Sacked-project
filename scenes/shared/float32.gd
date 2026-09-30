extends RefCounted

# The float32 the original keeps a value in: an x87 store to a float field (fst/fstp dword)
# rounds to nearest even, and the next load widens it back exactly. It writes into one
# reused buffer rather than a new array, because the field-of-view build calls it thousands
# of times a frame.

static var _scratch := PackedByteArray([0, 0, 0, 0])


static func f32(value: float) -> float:
	_scratch.encode_float(0, value)
	return _scratch.decode_float(0)
