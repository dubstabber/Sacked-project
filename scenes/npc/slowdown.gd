extends RefCounted

# The Matrix pill's slow-down as tools/export_slowdown_params.py reads it out of sacked.exe: the
# agents' 0.2, the green copies' blend and jitter, and the overlay's corners and clip. Loaded
# once for the agents, their copies and the overlay. See docs/player-ability-reference.md,
# "Mode 5: the Matrix pill".

const OriginalData := preload("res://scenes/shared/original_data.gd")
const PATH := "res://resources/original/slowdown.json"


static func params() -> Dictionary:
	return OriginalData.load_original(PATH)
