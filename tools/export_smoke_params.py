#!/usr/bin/env python3
"""Read CSfxSmoke's parameters out of sacked.exe into resources/original/smoke.json.

sub_427290 initialises the cigarette smoke: it re-allocates the particle array for 200
(`push 0C8h` at 0x427296) and copies a 112-byte block from 0x471378 (`push 471378h` at
0x4272C4) to the effect's +136. The block holds each particle's ramps, the lifetime and the
emission rate as float32. The spawn in smoking's state 11 and the projection sub_426920 add a
few constants of their own. This tool reads all of them at the addresses the code uses, checks
that each instruction listed below still names that address, checks that each value is the one
docs/player-ability-reference.md recovered ("The smoke: CSfxSmoke"), and writes them for
scenes/effects/smoke.gd, so none of them is typed into GDScript by hand. The spawn's view angle,
(view * 45.0 + 180.0) * 0.017453, is read by tools/export_view_angles.py, which the puddle and
the field-of-view cone share.

Every value is written as the exact double its float32 (or, for the reach, double) widens to,
which is what the x87 computes with.

--check reads them again and compares the result with the checked-in file.
"""

import argparse
import json
import struct
import sys
from pathlib import Path

try:
    from original_exe import (
        EXE_REL, EXE_SHA256, FADD, FCOMP, FMUL, FMUL_QWORD, IMAGE_BASE, at, f32, pin_readers,
        read_exe, repo_root,
    )
except ImportError:  # imported as tools.export_smoke_params
    from tools.original_exe import (
        EXE_REL, EXE_SHA256, FADD, FCOMP, FMUL, FMUL_QWORD, IMAGE_BASE, at, f32, pin_readers,
        read_exe, repo_root,
    )


OUTPUT_REL = Path("resources/original/smoke.json")


BLOCK_VA = 0x471378
BLOCK_SIZE = 112
BLOCK_PUSH_VA = 0x4272C4  # push 471378h, the block sub_426550 copies to +136
CAPACITY_PUSH_VA = 0x427296  # push 0C8h, the count sub_4264A0 allocates

# The block's float32 fields by their offset on the effect; the block starts at +136. A ramp
# is [start, spread, end]: a particle is born at start + spread * r and reaches end at the
# lifetime. The age is only [start, spread].
BLOCK_BASE = 136
RAMPS = {
    "age": (136, 2),
    "speed": (144, 3),
    "rise": (156, 3),
    "red": (168, 3),
    "green": (180, 3),
    "blue": (192, 3),
    "alpha": (204, 3),
    "size": (216, 3),
}
SCALARS = {
    "lifetime": 228,
    "inverse_lifetime": 232,
    "interval": 236,
    "per_interval": 240,
    "accumulator": 244,
}

# Constants the spawn (0x41BDA4-0x41BF7E), the tick (sub_426730), slot 11 (0x4272E0) and the
# projection (sub_426920) read: the value's address and format, and each instruction that
# reads it with its opcode bytes.
CONSTANTS = {
    # 0.21 as a double: z + d cos a with fmul qword; x - d sin a multiplies by the negated
    # double beside it.
    "mouth_reach": (0x465930, "d", [(0x41BDFE, FMUL_QWORD)]),
    "mouth_height": (0x4658F8, "f", [(0x41BE6A, FADD)]),  # 1.85
    # slot 11's 1.4, on x and z
    "velocity_scale": (0x4667A0, "f", [(0x4272E3, FMUL), (0x4272F9, FMUL)]),
    # 0.1 on dt * g, and the floor on y
    "rise_scale": (0x466798, "f", [(0x426825, FMUL), (0x426830, FCOMP)]),
    # 48 px: the ground's x axis (0x426982, 0x42698A), a unit of height (0x4269A9) and the Z bias
    # (0x4269D0).
    "height_pixels": (0x465538, "f", [(0x426982, FMUL), (0x42698A, FMUL), (0x4269A9, FMUL), (0x4269D0, FADD)]),
    "scale_units": (0x46679C, "f", [(0x426BDC, FMUL)]),  # 255.0: s = max(1, trunc(size * 255))
}
NEGATED_REACH_VA = 0x465938
NEGATED_REACH_READER = 0x41BDF2

# What docs/player-ability-reference.md recovered, compared as float32.
EXPECTED = {
    "capacity": 200,
    "age": [0.0, 0.6],
    "speed": [1.2, 0.0, 0.0],
    "rise": [0.0, -0.1, -6.0],
    "red": [235.0, 10.0, 185.0],
    "green": [235.0, 10.0, 185.0],
    "blue": [245.0, 10.0, 195.0],
    "alpha": [240.0, 1.0, 1.0],
    "size": [0.01, 0.01, 0.6],
    "lifetime": 5.0,
    "inverse_lifetime": 0.2,
    "interval": 2.0,
    "per_interval": 25.0,
    "accumulator": 0.0,
    "mouth_reach": 0.21,
    "mouth_height": 1.85,
    "velocity_scale": 1.4,
    "rise_scale": 0.1,
    "height_pixels": 48.0,
    "scale_units": 255.0,
}


def read_params(data: bytes) -> dict:
    failures = []
    if data[BLOCK_PUSH_VA - IMAGE_BASE] != 0x68 or at(data, BLOCK_PUSH_VA + 1, "I") != BLOCK_VA:
        failures.append(f"0x{BLOCK_PUSH_VA:X} does not push the block's address 0x{BLOCK_VA:X}")
    if data[CAPACITY_PUSH_VA - IMAGE_BASE] != 0x68:
        failures.append(f"0x{CAPACITY_PUSH_VA:X} is not a push of the particle count")
    for name, (va, _fmt, readers) in CONSTANTS.items():
        pin_readers(data, name, va, readers, failures)
    pin_readers(data, "-mouth_reach", NEGATED_REACH_VA, [(NEGATED_REACH_READER, FMUL_QWORD)], failures)
    if failures:
        raise SystemExit("\n".join(failures))

    block = struct.unpack_from(f"<{BLOCK_SIZE // 4}f", data, BLOCK_VA - IMAGE_BASE)
    params = {"capacity": at(data, CAPACITY_PUSH_VA + 1, "I")}
    for name, (offset, count) in RAMPS.items():
        first = (offset - BLOCK_BASE) // 4
        params[name] = list(block[first : first + count])
    for name, offset in SCALARS.items():
        params[name] = block[(offset - BLOCK_BASE) // 4]
    for name, (va, fmt, _readers) in CONSTANTS.items():
        params[name] = at(data, va, fmt)
    params["negated_reach"] = at(data, NEGATED_REACH_VA, "d")
    return params


def validate(params: dict) -> list:
    failures = []
    for name, expected in EXPECTED.items():
        actual = params[name]
        if isinstance(expected, list):
            matches = len(actual) == len(expected) and all(f32(a) == f32(e) for a, e in zip(actual, expected))
        elif isinstance(expected, int):
            matches = actual == expected
        else:
            matches = f32(actual) == f32(expected)
        if not matches:
            failures.append(f"{name} is {actual}, the reference recovered {expected}")
    if params["negated_reach"] != -params["mouth_reach"]:
        failures.append(f"0x{NEGATED_REACH_VA:X} is {params['negated_reach']}, not -{params['mouth_reach']}")
    return failures


def render(params: dict) -> str:
    out = {
        "generated_by": "tools/export_smoke_params.py",
        "source": EXE_REL.as_posix(),
        "source_sha256": EXE_SHA256,
        "block": "0x%06X" % BLOCK_VA,
        "ramp_layout": "[start, spread, end]: born at start + spread * r, end reached at the lifetime; age is [start, spread]",
    }
    for name in ["capacity", *RAMPS, *SCALARS, *CONSTANTS]:
        out[name] = params[name]
    lines = [f"  {json.dumps(key)}: {json.dumps(value)}" for key, value in out.items()]
    return "{\n" + ",\n".join(lines) + "\n}\n"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=repo_root())
    parser.add_argument("--check", action="store_true", help="Verify the checked-in parameters without writing")
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
            print("Smoke parameter check failed:\n" + "\n".join(f"  {line}" for line in failures))
            return 1
        print(f"Verified CSfxSmoke's parameters from 0x{BLOCK_VA:X} and the spawn, tick and projection constants at every reader.")
        return 0

    if failures:
        print("Smoke parameter export failed:\n" + "\n".join(f"  {line}" for line in failures))
        return 1
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(text, encoding="utf-8")
    print(f"Wrote {OUTPUT_REL}.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
