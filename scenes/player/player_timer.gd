extends RefCounted

# player+992 and +1000, the clock every timed player state keeps: a prank's (mode 1, sub_41B240)
# and each lamp ability's (modes 2, 3 and 5), and, as +996 and +1004, the pill's slow-down.
#
# The first state zeroes +992 and stores +1000 = tenths * 10.0 as a float (flt_4652F4, 0x41B605
# for a prank). Each tick adds the frame step, itself a float (0x41CFDA), stores the sum with
# fst, and compares the sum still on the x87 stack, times 100.0 (flt_465304), against +1000
# (0x41B6DE-0x41B6F4 for a prank). The CRT's _controlfp(0x10000, 0x30000) at 0x461CEE holds the
# x87 to 53 bits, so that sum and its product round as doubles do. Both floats come from
# tools/export_ability_timers.py, which pins every instruction that reads them. See "The
# controller" in docs/player-ability-reference.md.

const Float32 := preload("res://scenes/shared/float32.gd")
const OriginalData := preload("res://scenes/shared/original_data.gd")
const TIMERS_PATH := "res://resources/original/ability_timers.json"

# +992 in seconds and +1000 in hundredths, both float32.
var elapsed := 0.0
var total := 0.0


# The first state's +992 = 0 and +1000 = tenths * 10.0.
func start(tenths: float) -> void:
	elapsed = 0.0
	total = Float32.f32(tenths * factor("tenths_to_hundredths"))


# +992 += dt, stored as a float. The sum the state compares is returned unrounded.
func add_elapsed(delta: float) -> float:
	var sum := elapsed + Float32.f32(delta)
	elapsed = Float32.f32(sum)
	return sum


# A timed state's test: sum * 100 >= +1000.
func reached(sum: float) -> bool:
	return sum * factor("hundredths_per_second") >= total


# The slow-down's test, strictly past (0x41D42F).
func passed(sum: float) -> bool:
	return sum * factor("hundredths_per_second") > total


func zero() -> void:
	elapsed = 0.0
	total = 0.0


# sub_403780 feeds the stopwatch +992 * 100 / +1000 (0x40386B); the console takes the pair as
# seconds.
func total_seconds() -> float:
	return total / factor("hundredths_per_second")


# 10.0, 100.0, smoking's 0.4 and the smoke's 4.5, by name.
static func factor(key: String) -> float:
	return float(OriginalData.load_original(TIMERS_PATH).get(key, 0.0))
