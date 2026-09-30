#!/usr/bin/env python3
"""Read the timers the player's timed states share out of sacked.exe into resources/original/ability_timers.json.

A prank (mode 1) and the three modes a lamp starts keep their clock, player+992 and +1000, the
same way. Each first state turns its record's duration from tenths into hundredths with the
float32 10.0 at flt_4652F4: the prank's sub_41B240 in state 2, smoking's sub_41BC50 once per
room branch, urinating's sub_41C120 once per branch, and the pill's sub_41CD90 for its own
total and, in state 43, for the slow-down's. Each timed state then multiplies its elapsed
seconds by the float32 100.0 at flt_465304 before comparing; so does the player tick
sub_41CFC0 for the pill's slow-down, and so does sub_403780 when it feeds the stopwatch
+992 * 100 / +1000. The player tick reads the 10.0 three more ways: as the puddle's
ten-second gate on the shared effect clock (0x41D15B, 0x41D168, 0x41D199), as the rate of
prank 79's blackout countdown, player+1068 -= dt * 10 (0x41D475), and as the same gate for the
foam effect, which nothing reaches (0x41D270, 0x41D27D). The puddle and the blackout take it
from here too.
Smoking's state 11 spawns the smoke once its elapsed time passes 0.4 (flt_46587C), and the
player tick stops the smoke's emission once the shared effect clock passes 4.5 (flt_465A34).

10.0 and 100.0 are read in many other places of the executable (agents among them); only the
readers in the functions above are pinned here.

This tool reads each value at its address, checks that every reader listed below is the
instruction it is said to be and names that address, checks each value against
docs/player-ability-reference.md ("The controller"), and writes them for
scenes/player/player_timer.gd, scenes/effects/puddle.gd and scenes/player/prank_controller.gd,
so none of them is typed into GDScript by hand. Floats are written as the exact double their
float32 widens to, which is what the x87 uses.

--check reads them again and compares the result with the checked-in file.
"""

import argparse
import json
import sys
from pathlib import Path

try:
    from original_exe import EXE_REL, EXE_SHA256, FCOM, FCOMP, FMUL, FSUB, at, f32, pin_readers, read_exe, repo_root
except ImportError:  # imported as tools.export_ability_timers
    from tools.original_exe import EXE_REL, EXE_SHA256, FCOM, FCOMP, FMUL, FSUB, at, f32, pin_readers, read_exe, repo_root


OUTPUT_REL = Path("resources/original/ability_timers.json")

# name: (the value's address, and each instruction that reads it with its opcode bytes).
CONSTANTS = {
    "tenths_to_hundredths": (0x4652F4, [
        (0x41B605, FMUL),  # sub_41B240 state 2, a prank's record
        (0x41BCF7, FMUL),  # sub_41BC50 state 10, anywhere else (record 23)
        (0x41BD10, FMUL),  # room category 8 (record 24)
        (0x41BD30, FMUL),  # room category 4 (record 76)
        (0x41BD50, FMUL),  # room category 3 (record 22)
        (0x41C180, FMUL),  # sub_41C120 state 20, anywhere else (record 74)
        (0x41C19F, FMUL),  # room category 8 (record 75)
        (0x41CDAF, FMUL),  # sub_41CD90 state 40, record 73's duration
        (0x41CEBF, FMUL),  # state 43, record 73's +0x14, the slow-down
        (0x41D15B, FCOM),  # sub_41CFC0, the puddle's gate on the shared effect clock
        (0x41D168, FSUB),  # age - 10 for the spread
        (0x41D199, FSUB),  # and for the fade
        (0x41D270, FCOM),  # the foam effect's (+0x444) same gate; mode 4 is unreachable
        (0x41D27D, FSUB),  # and its age - 10
        (0x41D475, FMUL),  # prank 79's blackout, player+1068 -= dt * 10
    ]),
    "hundredths_per_second": (0x465304, [
        (0x41B6EE, FMUL),  # sub_41B240 state 3, a prank
        (0x41BFDF, FMUL),  # sub_41BC50 state 12
        (0x41C4ED, FMUL),  # sub_41C120 state 22
        (0x41CDFE, FMUL),  # sub_41CD90 state 42
        (0x41D42F, FMUL),  # sub_41CFC0, the slow-down
        (0x40386B, FMUL),  # sub_403780, the stopwatch's +992 * 100 / +1000
    ]),
    "smoke_spawn_after": (0x46587C, [
        (0x41BDBA, FCOMP),  # sub_41BC50 state 11, strictly past
    ]),
    "smoke_stop_after": (0x465A34, [
        (0x41D08B, FCOMP),  # sub_41CFC0, the shared effect clock, strictly past
    ]),
}

# What docs/player-ability-reference.md recovered, compared as float32.
EXPECTED = {
    "tenths_to_hundredths": 10.0,
    "hundredths_per_second": 100.0,
    "smoke_spawn_after": 0.4,
    "smoke_stop_after": 4.5,
}


def read_params(data: bytes) -> dict:
    failures = []
    params = {}
    for name, (va, readers) in CONSTANTS.items():
        pin_readers(data, name, va, readers, failures)
        params[name] = at(data, va, "f")
    if failures:
        raise SystemExit("\n".join(failures))
    return params


def validate(params: dict) -> list:
    return [
        f"{name} is {params[name]}, the reference recovered {expected}"
        for name, expected in EXPECTED.items()
        if f32(params[name]) != f32(expected)
    ]


def render(params: dict) -> str:
    out = {
        "generated_by": "tools/export_ability_timers.py",
        "source": EXE_REL.as_posix(),
        "source_sha256": EXE_SHA256,
    }
    for name in EXPECTED:
        out[name] = params[name]
    lines = [f"  {json.dumps(key)}: {json.dumps(value)}" for key, value in out.items()]
    return "{\n" + ",\n".join(lines) + "\n}\n"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=repo_root())
    parser.add_argument("--check", action="store_true", help="Verify the checked-in timers without writing")
    args = parser.parse_args()

    params = read_params(read_exe(args.root))
    failures = validate(params)
    text = render(params)
    output = args.root / OUTPUT_REL

    if args.check:
        if not output.is_file():
            failures.append(f"{OUTPUT_REL} is missing")
        elif output.read_text(encoding="utf-8") != text:
            failures.append(f"{OUTPUT_REL} is stale")
        if failures:
            print("Ability timer check failed:\n" + "\n".join(f"  {line}" for line in failures))
            return 1
        print("Verified the player clock's 10.0, 100.0, 0.4 and 4.5 at every reader in sub_41B240, sub_41BC50, sub_41C120, sub_41CD90, sub_41CFC0 (the puddle's and the foam's gates and the blackout among them) and sub_403780.")
        return 0

    if failures:
        print("Ability timer export failed:\n" + "\n".join(f"  {line}" for line in failures))
        return 1
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(text, encoding="utf-8")
    print(f"Wrote {OUTPUT_REL}.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
