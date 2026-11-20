#!/usr/bin/env python3
"""Read the main-menu animation constants out of sacked.exe into
resources/original/menu_animation.json.

The main menu (CMainMenu, built by sub_422F40) animates three things every frame, none of
which the port used to reproduce:

  * The 800x800 CO_GUI_SCREENS_MENU_BACKGROUND swirl rotates. The shared base update
    sub_423710 keeps a rotation angle at menu+1260 and advances it by 0.01 radians a frame
    (fld menu+1260 / fadd flt_465308 / fst menu+1260 at 0x4237EA-0x423826), then draws the
    texture as a screen-filling quad whose texture coordinates are a 500x500 region centred
    on (400, 400) rotated by that angle (two sub_42C900 triangles). It is the same 0.01 the
    duel's swirl turns by (sub_4138A0); see docs/minigame-reference.md.

  * The six menu buttons sway horizontally. sub_423630 keeps a phase at menu+1264, advances
    it by the clock's frame delta (fld clock+592 / fadd menu+1264), and sets button i's x to
    sin(i * (2*pi/10) + phase) * 32.0 + 380.0 (fmul dbl_4662B0 / fadd menu+1264 / fsin /
    fmul flt_4662AC / fadd flt_4662A8 at 0x42367E-0x423692). Its y stays on the ctor's row.

  * The menu character orbits a small circle. sub_423AE0 reads the same phase, multiplies it
    by pi/4 (fmul flt_4662BC at 0x423AE7), and sets the character's position to
    (64 - sin(phase*pi/4) * -32.0, 32 - cos(phase*pi/4) * 32.0) -- a radius-32 circle about
    (64, 32) (fmul flt_4662B8 at 0x423AFA, fmul flt_4662AC at 0x423B15).

Both accumulators start at 0 (the ctor zeroes menu+1260 and menu+1264, dwords 315 and 316).
The derived steps 2*pi/10 and pi/4 are stored as the float32 of the constant widened to the
double the x87 multiplies with. See docs/shell-reference.md, "What every menu screen shares".

--check reads them again and compares the result with the checked-in file.
"""

import argparse
import json
import math
import sys
from pathlib import Path

try:
    from original_exe import EXE_REL, EXE_SHA256, FADD, FMUL, FMUL_QWORD, at, f32, pin_readers, read_exe, repo_root
except ImportError:  # imported as tools.export_menu_animation
    from tools.original_exe import EXE_REL, EXE_SHA256, FADD, FMUL, FMUL_QWORD, at, f32, pin_readers, read_exe, repo_root


OUTPUT_REL = Path("resources/original/menu_animation.json")

# name: (the value's address, its struct format, and each instruction that reads it).
CONSTANTS = {
    "background_rotation_step": (0x465308, "f", [
        (0x4237F0, FADD),  # sub_423710, menu+1260 += 0.01 a frame
    ]),
    "button_sway_amplitude": (0x4662AC, "f", [
        (0x42368C, FMUL),  # sub_423630, the button x sine amplitude
        (0x423B15, FMUL),  # sub_423AE0, the character's y cosine amplitude
    ]),
    "button_base_x": (0x4662A8, "f", [
        (0x423692, FADD),  # sub_423630, the button x centre
    ]),
    "button_phase_step": (0x4662B0, "d", [
        (0x42367E, FMUL_QWORD),  # sub_423630, 2*pi/10 per button index
    ]),
    "char_orbit_rate": (0x4662BC, "f", [
        (0x423AE7, FMUL),  # sub_423AE0, phase * pi/4
    ]),
    "char_orbit_amplitude": (0x4662B8, "f", [
        (0x423AFA, FMUL),  # sub_423AE0, the character's x sine amplitude (negated)
    ]),
}

# The clean float32 literals, compared exactly; the derived steps the compiler stored from a
# rounded literal (char_orbit_rate reads 0.78539902, a few ULPs above pi/4), compared to the
# constant they stand for within a tolerance. The strict guards are the pinned reader
# instructions above and --check's exact file comparison.
EXPECTED_EXACT = {
    "background_rotation_step": 0.01,
    "button_sway_amplitude": 32.0,
    "button_base_x": 380.0,
    "char_orbit_amplitude": -32.0,
}
EXPECTED_APPROX = {
    "button_phase_step": 2.0 * math.pi / 10.0,
    "char_orbit_rate": math.pi / 4.0,
}


def read_params(data: bytes) -> dict:
    failures = []
    params = {}
    for name, (va, fmt, readers) in CONSTANTS.items():
        pin_readers(data, name, va, readers, failures)
        params[name] = at(data, va, fmt)
    if failures:
        raise SystemExit("\n".join(failures))
    return params


def validate(params: dict) -> list:
    failures = [
        f"{name} is {params[name]}, expected {expected}"
        for name, expected in EXPECTED_EXACT.items()
        if f32(params[name]) != f32(expected)
    ]
    failures += [
        f"{name} is {params[name]}, expected about {expected}"
        for name, expected in EXPECTED_APPROX.items()
        if abs(params[name] - expected) > 1e-5
    ]
    return failures


def render(params: dict) -> str:
    out = {
        "generated_by": "tools/export_menu_animation.py",
        "source": EXE_REL.as_posix(),
        "source_sha256": EXE_SHA256,
    }
    for name in CONSTANTS:
        out[name] = params[name]
    lines = [f"  {json.dumps(key)}: {json.dumps(value)}" for key, value in out.items()]
    return "{\n" + ",\n".join(lines) + "\n}\n"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=repo_root())
    parser.add_argument("--check", action="store_true", help="Verify the checked-in file without writing")
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
            print("Menu animation check failed:\n" + "\n".join(f"  {line}" for line in failures))
            return 1
        print("Verified the swirl's 0.01 step, the buttons' 32.0/380.0/(2*pi/10) sway and the character's pi/4 orbit.")
        return 0

    if failures:
        print("Menu animation export failed:\n" + "\n".join(f"  {line}" for line in failures))
        return 1
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(text, encoding="utf-8")
    print(f"Wrote {OUTPUT_REL}.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
