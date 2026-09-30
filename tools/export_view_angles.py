#!/usr/bin/env python3
"""Read the view-angle floats out of sacked.exe into resources/original/view_angles.json.

Three float32 constants turn a view or a heading in degrees into radians, and the port reads
each of them in more than one place:

    45.0      at 0x465548  a view's step, view * 45
    180.0     at 0x465544  the offset that makes view 0 look along +x
    0.017453  at 0x465540  degrees to radians (not pi / 180)

Smoking's state 11 aims the smoke with a = (player+124 * 45.0 + 180.0) * 0.017453
(0x41BDDC-0x41BDE8), urinating's state 21 aims the puddle the same way for Jo and for Anne
(0x41C374-0x41C380, 0x41C3AC-0x41C3B8), and the field-of-view cone sub_428270 turns each of
its two edge angles into radians with the same 0.017453 (0x428329, 0x4285A1). So they are
exported once, here, for scenes/shared/view_angle.gd, which the smoke, the puddle and the
field-of-view mask all read.

Other code reads the same floats (0x416A33, 0x418C7C, 0x41C8E2, 0x41CA46, 0x41CA9C and 0x41DBFB
among them, and 0x4179D1, the agents' heading easing); only the readers the port reproduces
from this file are pinned here.

This tool reads each value at its address, checks that every reader listed below is the
instruction it is said to be and names that address, checks each value against the references
(player-ability-reference.md, "The smoke: CSfxSmoke" and "The puddle: CPisspuddle";
field-of-view-reference.md, "The cone"), and writes them as the exact double their float32
widens to, which is what the x87 computes with.

--check reads them again and compares the result with the checked-in file.
"""

import argparse
import json
import sys
from pathlib import Path

try:
    from original_exe import EXE_REL, EXE_SHA256, FADD, FMUL, at, f32, pin_readers, read_exe, repo_root
except ImportError:  # imported as tools.export_view_angles
    from tools.original_exe import EXE_REL, EXE_SHA256, FADD, FMUL, at, f32, pin_readers, read_exe, repo_root


OUTPUT_REL = Path("resources/original/view_angles.json")

# name: (the value's address, and each instruction that reads it with its opcode bytes).
CONSTANTS = {
    "view_degrees": (0x465548, [
        (0x41BDDC, FMUL),  # sub_41BC50 state 11, the smoke
        (0x41C374, FMUL),  # sub_41C120 state 21, Jo's puddle
        (0x41C3AC, FMUL),  # Anne's puddle
    ]),
    "view_offset": (0x465544, [
        (0x41BDE2, FADD),  # the smoke
        (0x41C37A, FADD),  # Jo's puddle
        (0x41C3B2, FADD),  # Anne's puddle
    ]),
    "degrees_to_radians": (0x465540, [
        (0x41BDE8, FMUL),  # the smoke
        (0x41C380, FMUL),  # Jo's puddle
        (0x41C3B8, FMUL),  # Anne's puddle
        (0x428329, FMUL),  # sub_428270, the cone's low edge
        (0x4285A1, FMUL),  # and its high edge
    ]),
}

# What the references recovered, compared as float32.
EXPECTED = {
    "view_degrees": 45.0,
    "view_offset": 180.0,
    "degrees_to_radians": 0.017453,
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
        "generated_by": "tools/export_view_angles.py",
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
    parser.add_argument("--check", action="store_true", help="Verify the checked-in angles without writing")
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
            print("View angle check failed:\n" + "\n".join(f"  {line}" for line in failures))
            return 1
        print("Verified 45.0, 180.0 and 0.017453 at every reader in the smoke, the puddle and the field-of-view cone.")
        return 0

    if failures:
        print("View angle export failed:\n" + "\n".join(f"  {line}" for line in failures))
        return 1
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(text, encoding="utf-8")
    print(f"Wrote {OUTPUT_REL}.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
