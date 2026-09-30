#!/usr/bin/env python3
"""Read the urination puddle's parameters out of sacked.exe into resources/original/puddle.json.

Urinating's state 21 (sub_41C120) builds the puddle, a CPisspuddle, a short way ahead of the
player: it takes the view's angle, steps 0.2 tiles (Anne) or 0.6 (Jo) along it, lifts the
puddle 0.1 units and gives it an alpha of 0.7 (0x41C350-0x41C467). The view's angle,
(view * 45.0 + 180.0) * 0.017453, is read by tools/export_view_angles.py, which the smoke and
the field-of-view cone share. The player's tick then
spreads and fades it from ten seconds on the shared effect clock and deletes it after
seventeen (0x41D143-0x41D252); the ten is flt_4652F4, the 10.0 every timed state scales a
record's tenths by, so tools/export_ability_timers.py reads it and pins those three readers
with the rest. Its draw sub_41E1C0 turns the alpha and the scale into the
blitter's 8-bit fixed point. The projection sub_41A2D0 lifts it 24 px a unit. This tool reads
every one of those constants at the address the code reads it from, checks that each
instruction still names that address, checks each value against
docs/player-ability-reference.md ("The puddle: CPisspuddle"), and writes them for
scenes/effects/puddle.gd, so none of them is typed into GDScript by hand.

Every value is written as the exact double its float32 (or, for the two reaches, double)
widens to, which is what the x87 computes with.

--check reads them again and compares the result with the checked-in file.
"""

import argparse
import json
import sys
from pathlib import Path

try:
    from original_exe import (
        EXE_REL, EXE_SHA256, FADD, FCOMP, FLD, FMUL, FMUL_QWORD, FSUBR, IMAGE_BASE, at, f32,
        pin_readers, read_exe, repo_root,
    )
except ImportError:  # imported as tools.export_puddle_params
    from tools.original_exe import (
        EXE_REL, EXE_SHA256, FADD, FCOMP, FLD, FMUL, FMUL_QWORD, FSUBR, IMAGE_BASE, at, f32,
        pin_readers, read_exe, repo_root,
    )


OUTPUT_REL = Path("resources/original/puddle.json")


# Constants the code reads from memory: the value's address and format, and each instruction
# that reads it with its opcode bytes.
CONSTANTS = {
    # z + d cos a with fmul qword; x - d sin a multiplies by the negated double beside it.
    "reach_anne": (0x465940, "d", [(0x41C3D0, FMUL_QWORD)]),
    "reach_jo": (0x465950, "d", [(0x41C398, FMUL_QWORD)]),
    # The player tick's growth and fade (0x41D151-0x41D1C5), past the ten-second gate.
    "grow_rate": (0x465A30, "f", [(0x41D16E, FMUL)]),
    "base_scale": (0x4652B8, "f", [(0x41D174, FADD)]),
    "fade_rate": (0x465A2C, "f", [(0x41D19F, FMUL)]),
    "fade_from": (0x4652C0, "f", [(0x41D1A5, FSUBR)]),
    "remove_after": (0x465A28, "f", [(0x41D1BF, FCOMP)]),
    # sub_42B450 clamps each scale to at least this: +0x3C with a load of it, +0x40 with an
    # immediate store of the same bits (MIN_SCALE_STORE).
    "min_scale": (0x465308, "f", [(0x42B454, FCOMP), (0x42B467, FLD), (0x42B474, FCOMP)]),
    # sub_41E1C0: the alpha byte trunc(+900 * 256) and the blitter scale trunc(s * 256).
    "fixed_units": (0x465508, "f", [(0x41E1E2, FMUL), (0x41E1F9, FMUL), (0x41E207, FMUL)]),
    # sub_41A2D0: 24 px a unit, on the ground's y and on the height.
    "height_pixels": (0x465534, "f", [(0x41A32B, FMUL), (0x41A334, FMUL)]),
}
NEGATED_REACHES = {"reach_anne": (0x465948, 0x41C3C4), "reach_jo": (0x465958, 0x41C38C)}
# mov dword ptr [ecx+40h], imm32: the second clamp stores min_scale's bits as an immediate.
MIN_SCALE_STORE = (0x42B48B, bytes([0xC7, 0x41, 0x40]))

# Constants the code carries as immediates: the instruction, the bytes before the immediate,
# and the immediate's format.
IMMEDIATES = {
    # push 3DCCCCCDh, the height sub_42B330 is handed (0x41C3DD).
    "height": (0x41C3DD, bytes([0x68]), "f"),
    # mov dword ptr [eax+384h], 3F333333h: the puddle's +900 (0x41C45D).
    "alpha": (0x41C45D, bytes([0xC7, 0x80, 0x84, 0x03, 0x00, 0x00]), "f"),
}

# What docs/player-ability-reference.md recovered, compared as float32.
EXPECTED = {
    "reach_anne": 0.2,
    "reach_jo": 0.6,
    "height": 0.1,
    "alpha": 0.7,
    "grow_rate": 0.08,
    "base_scale": 1.0,
    "fade_rate": 0.085,
    "fade_from": 0.7,
    "remove_after": 17.0,
    "min_scale": 0.01,
    "fixed_units": 256.0,
    "height_pixels": 24.0,
}
ORDER = [
    "reach_anne", "reach_jo", "height", "alpha", "grow_rate", "base_scale", "fade_rate",
    "fade_from", "remove_after", "min_scale", "fixed_units", "height_pixels",
]


def read_params(data: bytes) -> dict:
    failures = []
    params = {}
    for name, (va, fmt, readers) in CONSTANTS.items():
        pin_readers(data, name, va, readers, failures)
        params[name] = at(data, va, fmt)
    for name, (va, instruction) in NEGATED_REACHES.items():
        before = len(failures)
        pin_readers(data, f"-{name}", va, [(instruction, FMUL_QWORD)], failures)
        if len(failures) == before and at(data, va, "d") != -params[name]:
            failures.append(f"0x{va:X} is {at(data, va, 'd')}, not -{params[name]}")
    store, prefix = MIN_SCALE_STORE
    if data[store - IMAGE_BASE : store - IMAGE_BASE + len(prefix)] != prefix:
        failures.append(f"0x{store:X} is not the store of the second scale's clamp")
    elif at(data, store + len(prefix), "I") != at(data, CONSTANTS["min_scale"][0], "I"):
        failures.append(f"the clamp's immediate at 0x{store + len(prefix):X} is not min_scale's bits")
    for name, (instruction, prefix, fmt) in IMMEDIATES.items():
        start = instruction - IMAGE_BASE
        if data[start : start + len(prefix)] != prefix:
            failures.append(f"0x{instruction:X} is not the instruction that carries {name}")
            continue
        params[name] = at(data, instruction + len(prefix), fmt)
    if failures:
        raise SystemExit("\n".join(failures))
    return params


def validate(params: dict) -> list:
    failures = []
    for name, expected in EXPECTED.items():
        if f32(params[name]) != f32(expected):
            failures.append(f"{name} is {params[name]}, the reference recovered {expected}")
    return failures


def render(params: dict) -> str:
    out = {
        "generated_by": "tools/export_puddle_params.py",
        "source": EXE_REL.as_posix(),
        "source_sha256": EXE_SHA256,
    }
    for name in ORDER:
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
            print("Puddle parameter check failed:\n" + "\n".join(f"  {line}" for line in failures))
            return 1
        print("Verified CPisspuddle's placement, alpha, growth and draw constants from sub_41C120, sub_41CFC0, sub_42B450, sub_41E1C0 and sub_41A2D0.")
        return 0

    if failures:
        print("Puddle parameter export failed:\n" + "\n".join(f"  {line}" for line in failures))
        return 1
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(text, encoding="utf-8")
    print(f"Wrote {OUTPUT_REL}.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
