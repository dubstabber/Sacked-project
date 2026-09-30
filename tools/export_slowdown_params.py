#!/usr/bin/env python3
"""Read the Matrix pill's slow-down constants out of sacked.exe into resources/original/slowdown.json.

The pill's state 43 (sub_41CD90) sets agent+1792 on every agent through sub_41CD10 and starts
the slow-down, record 73's +0x14 tenths times 10.0 in hundredths (0x41CEB7-0x41CEC5); the
player tick ends it once the elapsed time times 100.0 passes that (0x41D401-0x41D458). While
the flag is up, the four agent ticks put 0.2 instead of 1.0 into the walk multiplier +76 and
the current clip's speed (0x41975A, 0x419CFB, 0x41A8EA, 0x41E37B), and the agent draw
sub_417460 adds three jittered green copies of its frame (0x41762D-0x41772F), which the
mode-54 blitter 0x43B050 blends. While player+1044 is up, the player's draw sub_41D500 first
lays a four-corner gradient over the world pass's clip (0x41D514-0x41D5A8), which sub_4584D0
averages with the scene; Main_RenderUpdate sets that clip (0x40292E-0x402989).

This tool reads every one of those constants at the instruction that carries or reads it,
checks the instructions around them that give them their meaning, checks each value against
docs/player-ability-reference.md ("Mode 5: the Matrix pill"), and writes them for
scenes/npc/npc.gd, scenes/npc/slowed_copies.gd and scenes/player/slowdown_overlay.gd, so none
of them is typed into GDScript by hand. The 400 tenths themselves come from record 73 in
resources/original/actions.json (effect_duration_tenths). The 10.0 and 100.0 that time the
slow-down are the ones every lamp ability shares, so tools/export_ability_timers.py reads them.

Floats are written as the exact double their float32 widens to, which is what the x87 uses.

--check reads them again and compares the result with the checked-in file.
"""

import argparse
import json
import sys
from pathlib import Path

try:
    from original_exe import EXE_REL, EXE_SHA256, at, bytes_at, f32, read_exe, repo_root
except ImportError:  # imported as tools.export_slowdown_params
    from tools.original_exe import EXE_REL, EXE_SHA256, at, bytes_at, f32, read_exe, repo_root


OUTPUT_REL = Path("resources/original/slowdown.json")


# The agent ticks, in the order docs/player-ability-reference.md lists them: the boss, the
# coworkers, the janitor and the secretary. Each tests +1792 (mov eax, [esi+700h]), then
# loads 0.2 or 1.0 into ecx (mov ecx, imm32), stores it to +76 (mov [esi+4Ch], ecx) and to the
# current clip's +536 (mov [eax+218h], ecx).
AGENT_TICKS = {
    "boss": {"test": 0x41975A, "slowed": 0x41976C, "normal": 0x41977D, "multiplier": (0x419773, 0x419784), "clip": 0x419789},
    "coworkers": {"test": 0x419CFB, "slowed": 0x419D0F, "normal": 0x419D22, "multiplier": (0x419D16, 0x419D29), "clip": 0x419D2E},
    "janitor": {"test": 0x41A8EA, "slowed": 0x41A8FC, "normal": 0x41A90D, "multiplier": (0x41A903, 0x41A914), "clip": 0x41A919},
    "secretary": {"test": 0x41E37B, "slowed": 0x41E38F, "normal": 0x41E3A2, "multiplier": (0x41E396, 0x41E3A9), "clip": 0x41E3AE},
}

# Constants the code carries as immediates: the instruction, the bytes before the immediate,
# and the immediate's format.
IMMEDIATES = {
    # sub_417460's copies: mode 36h into the context's +18h, then sub_42D1D0(78h), the weight;
    # sub_42D1E0(28h, 0FFh, 28h), the tint bytes 0, 1 and 2 (the first argument is pushed
    # last); sub_42D200(3Ch), the brightness.
    "copy_blend_mode": (0x41763F, bytes([0xC7, 0x41, 0x18]), "I"),
    "copy_weight": (0x41763D, bytes([0x6A]), "B"),
    "copy_tint_0": (0x417658, bytes([0x6A]), "B"),
    "copy_tint_1": (0x417653, bytes([0x68]), "I"),
    "copy_tint_2": (0x417651, bytes([0x6A]), "B"),
    "copy_brightness": (0x417662, bytes([0x6A]), "B"),
    # 0x43B050: the destination keeps (0FFh - weight) / 256 (mov ecx, 0FFh; sub ecx, edi), and
    # each brightened channel is capped at 0FFh.
    "copy_full_weight": (0x43B181, bytes([0xB9]), "I"),
    "copy_brightness_limit": (0x43B1B8, bytes([0xBB]), "I"),
    # sub_41D500: the rectangle 0..320h x 0..258h, the weight sub_42D1D0(0) and the corners.
    "overlay_width": (0x41D52B, bytes([0xC7, 0x44, 0x24, 0x10]), "I"),
    "overlay_height": (0x41D53E, bytes([0xC7, 0x44, 0x24, 0x08]), "I"),
    "overlay_weight": (0x41D568, bytes([0x6A]), "B"),
    "overlay_top_left": (0x41D546, bytes([0xC7, 0x44, 0x24, 0x2C]), "I"),
    "overlay_top_right": (0x41D54E, bytes([0xC7, 0x44, 0x24, 0x30]), "I"),
    "overlay_bottom_left": (0x41D556, bytes([0xC7, 0x44, 0x24, 0x34]), "I"),
    "overlay_bottom_right": (0x41D55E, bytes([0xC7, 0x44, 0x24, 0x38]), "I"),
    # sub_4584D0: the gradient's steps are 1000h / the clipped size, in 12-bit fixed point
    # (mov eax, 1000h; cdq; idiv).
    "overlay_fixed_one": (0x4585A2, bytes([0xB8]), "I"),
    # sar eax, 0Ch: each row's and each column's accumulator is shifted down to whole levels.
    "overlay_fixed_shift": (0x45891C, bytes([0xC1, 0xF8]), "B"),
    # Main_RenderUpdate's world clip: x and y from ebp = 1, the width w - 1 and the height
    # h - 5Bh (sub edx, 5Bh).
    "world_clip_origin": (0x4028EB, bytes([0xBD]), "I"),
    "world_clip_height_less": (0x402941, bytes([0x83, 0xEA]), "B"),
}

# Instructions that must be where the reading above assumes, byte for byte.
PINNED = {
    # sub_41CD10 writes +1792 on every entry of type 2 that is not the player.
    0x41CD4B: bytes([0x83, 0x78, 0x70, 0x02]),
    0x41CD51: bytes([0x3B, 0xC1]),
    0x41CD55: bytes([0x89, 0xB8, 0x00, 0x07, 0x00, 0x00]),
    # State 43: sub_41CD10(1) after +1004 = fild [record 73 + 14h] * 10.0.
    0x41CEB5: bytes([0x6A, 0x01]),
    0x41CEB7: bytes([0xDB, 0x05, 0xC0, 0x61, 0x47, 0x00]),
    0x41CEC5: bytes([0xD9, 0x9E, 0xEC, 0x03, 0x00, 0x00]),
    0x41CECB: bytes([0xE8, 0x40, 0xFE, 0xFF, 0xFF]),
    # The slow-down: +1044 = 1, +996 += dt, and a strict test of +996 * 100 against +1004.
    0x41D415: bytes([0xD9, 0x44, 0x24, 0x0C]),
    0x41D419: bytes([0xD8, 0x86, 0xE4, 0x03, 0x00, 0x00]),
    0x41D41F: bytes([0xC7, 0x86, 0x14, 0x04, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00]),
    0x41D435: bytes([0xD8, 0x9E, 0xEC, 0x03, 0x00, 0x00]),
    0x41D43D: bytes([0xF6, 0xC4, 0x41]),
    0x41D451: bytes([0xE8, 0xBA, 0xF8, 0xFF, 0xFF]),
    # sub_417730's walk step reads +76 once (mov edx, [esi+4Ch]).
    0x417934: bytes([0x8B, 0x56, 0x4C]),
    # sub_417460 draws the copies only while +1792 is 1, with rand() from the import table.
    0x41762D: bytes([0x83, 0xBE, 0x00, 0x07, 0x00, 0x00, 0x01]),
    0x41766F: bytes([0x8B, 0x3D, 0xEC, 0x50, 0x46, 0x00]),
    # 0x43B050 is mode 54's entry in the 8-bpp, Z-plane blitter table at 0x47184C.
    0x43B18C: bytes([0x2B, 0xCF]),
    # sub_41D500 paints the gradient only while +1044 is 1, with sub_42D1D0(0).
    0x41D514: bytes([0x39, 0x86, 0x14, 0x04, 0x00, 0x00]),
    0x41D583: bytes([0xE8, 0x48, 0xFC, 0x00, 0x00]),
    0x41D5A8: bytes([0xE8, 0xB3, 0xF5, 0x00, 0x00]),
    # sub_42CB60 makes the clip inclusive (x + w - 1, y + h - 1) for sub_4584D0.
    0x42CBA7: bytes([0x8D, 0x4C, 0x0F, 0xFF]),
    0x42CBAF: bytes([0x8D, 0x4C, 0x10, 0xFF]),
    0x42CC14: bytes([0xE8, 0xB7, 0xB8, 0x02, 0x00]),
    # sub_4584D0: weight 0 takes the averaging branch, both steps come from 1000h, each
    # accumulator is shifted down 12, and scene and gradient are halved with 7F7F7Fh.
    0x458649: bytes([0x83, 0x7B, 0x48, 0x00]),
    0x45864D: bytes([0x0F, 0x84, 0x1A, 0x02, 0x00, 0x00]),
    0x4585B6: bytes([0xB8, 0x00, 0x10, 0x00, 0x00]),
    0x4589EA: bytes([0x81, 0xE2, 0x7F, 0x7F, 0x7F, 0x00]),
    0x4589FB: bytes([0x81, 0xE2, 0x7F, 0x7F, 0x7F, 0x00]),
    # Main_RenderUpdate: x = y = 1 (mov [eax+38h], ebp; mov [eax+3Ch], ebp), the width w - 1
    # (dec ecx; mov [eax+40h], ecx) and the height (mov [eax+44h], edx).
    0x4028DB: bytes([0xBD, 0x01, 0x00, 0x00, 0x00]),
    0x402944: bytes([0x49]),
    0x402947: bytes([0x89, 0x68, 0x38]),
    0x40294A: bytes([0x89, 0x68, 0x3C]),
    0x402962: bytes([0x89, 0x48, 0x40]),
    0x402989: bytes([0x89, 0x50, 0x44]),
}

# sub_417460's three copies, each read from its sub eax, 2, 3Bh bytes apart. Each draws the
# frame 2 depth units nearer than the agent, takes rand() % 4 - 2 for y first (the and with
# 80000003h is the compiler's signed % 4), then rand() % 6 - 3 for x, and draws through
# sub_42D780.
COPY_STARTS = (0x417675, 0x4176B0, 0x4176EB)
COPY_LAYOUT = {
    # offset from the copy's start: the bytes before the immediate and its format, or None
    # for an instruction that is only pinned.
    "depth": (0x00, bytes([0x83, 0xE8]), "B"),
    "y_rand": (0x05, bytes([0xFF, 0xD7]), None),
    "y_mask": (0x07, bytes([0x25]), "I"),
    "y_offset": (0x16, bytes([0x8D, 0x54, 0x08]), "b"),
    "x_rand": (0x1B, bytes([0xFF, 0xD7]), None),
    "x_modulus": (0x1E, bytes([0xB9]), "I"),
    "x_divide": (0x23, bytes([0xF7, 0xF9]), None),
    "x_offset": (0x28, bytes([0x8D, 0x4C, 0x02]), "b"),
    "draw": (0x30, bytes([0xE8]), "i"),
}
COPY_DRAW = 0x42D780

TINT_ORDER = ("copy_tint_0", "copy_tint_1", "copy_tint_2")
CORNER_ORDER = ("overlay_top_left", "overlay_top_right", "overlay_bottom_left", "overlay_bottom_right")

# What docs/player-ability-reference.md recovered.
EXPECTED = {
    "slowed_factor": 0.2,
    "normal_factor": 1.0,
    "copy_count": 3,
    "copy_blend_mode": 54,
    "copy_weight": 120,
    "copy_full_weight": 255,
    "copy_tint": [40, 255, 40],
    "copy_brightness": 60,
    "copy_brightness_limit": 255,
    "copy_depth_offset": -2,
    "copy_jitter_y": [4, -2],
    "copy_jitter_x": [6, -3],
    "overlay_rect": [800, 600],
    "overlay_weight": 0,
    # Bytes 0, 1 and 2 of each corner dword, which the back buffer holds as R, G and B.
    "overlay_corners": [[0, 160, 0], [160, 0, 0], [0, 0, 160], [0, 160, 160]],
    "overlay_fixed_one": 4096,
    "overlay_fixed_shift": 12,
    "world_clip": [1, 1, 1, 91],
}
ORDER = list(EXPECTED)


def _immediate(data: bytes, va: int, prefix: bytes, fmt: str, failures: list, name: str):
    if bytes_at(data, va, len(prefix)) != prefix:
        failures.append(f"0x{va:X} is not the instruction that carries {name}")
        return None
    return at(data, va + len(prefix), fmt)


def _rand_import(data: bytes) -> str:
    """The name the import table gives the pointer at 0x4650EC."""
    hint_name = at(data, 0x4650EC, "I")
    start = hint_name + 2
    return data[start : data.index(b"\0", start)].decode("ascii")


def read_params(data: bytes) -> dict:
    failures = []
    raw = {}

    for va, expected in PINNED.items():
        if bytes_at(data, va, len(expected)) != expected:
            failures.append(f"0x{va:X} is not {expected.hex(' ')}")
    if at(data, 0x47184C + 54 * 4, "I") != 0x43B050:
        failures.append("mode 54's 8-bpp Z-plane blitter is not 0x43B050")
    if _rand_import(data) != "rand":
        failures.append("the pointer at 0x4650EC is not the rand import")

    slowed, normal = set(), set()
    for tick, where in AGENT_TICKS.items():
        if bytes_at(data, where["test"], 6) != bytes([0x8B, 0x86, 0x00, 0x07, 0x00, 0x00]):
            failures.append(f"the {tick} tick does not test +1792 at 0x{where['test']:X}")
        for store in where["multiplier"]:
            if bytes_at(data, store, 3) != bytes([0x89, 0x4E, 0x4C]):
                failures.append(f"the {tick} tick does not store +76 at 0x{store:X}")
        if bytes_at(data, where["clip"], 6) != bytes([0x89, 0x88, 0x18, 0x02, 0x00, 0x00]):
            failures.append(f"the {tick} tick does not store the clip's speed at 0x{where['clip']:X}")
        slowed.add(_immediate(data, where["slowed"], bytes([0xB9]), "f", failures, f"the {tick} tick's slowed factor"))
        normal.add(_immediate(data, where["normal"], bytes([0xB9]), "f", failures, f"the {tick} tick's normal factor"))
    if len(slowed) != 1 or len(normal) != 1:
        failures.append(f"the four ticks disagree: slowed {sorted(slowed, key=str)}, normal {sorted(normal, key=str)}")

    for name, (va, prefix, fmt) in IMMEDIATES.items():
        raw[name] = _immediate(data, va, prefix, fmt, failures, name)

    copies = []
    for start in COPY_STARTS:
        copy = {}
        for field, (offset, prefix, fmt) in COPY_LAYOUT.items():
            va = start + offset
            if fmt is None:
                if bytes_at(data, va, len(prefix)) != prefix:
                    failures.append(f"0x{va:X} is not the copy's {field}")
                continue
            copy[field] = _immediate(data, va, prefix, fmt, failures, f"the copy's {field}")
        if copy.get("draw") is not None:
            copy["draw"] = start + COPY_LAYOUT["draw"][0] + 5 + copy["draw"]
        copies.append(copy)
    if any(copy != copies[0] for copy in copies):
        failures.append(f"the three copies differ: {copies}")
    if copies[0].get("draw") != COPY_DRAW:
        failures.append(f"the copies do not draw through sub_{COPY_DRAW:X}")

    if failures:
        raise SystemExit("\n".join(failures))

    copy = copies[0]
    y_mask = copy["y_mask"]
    if y_mask & 0x80000000 == 0 or (y_mask & 0x7FFFFFFF) + 1 & (y_mask & 0x7FFFFFFF) != 0:
        raise SystemExit(f"the y jitter's mask {y_mask:#x} is not a signed power-of-two remainder")
    return {
        "slowed_factor": slowed.pop(),
        "normal_factor": normal.pop(),
        "copy_count": len(copies),
        "copy_blend_mode": raw["copy_blend_mode"],
        "copy_weight": raw["copy_weight"],
        "copy_full_weight": raw["copy_full_weight"],
        "copy_tint": [raw[name] for name in TINT_ORDER],
        "copy_brightness": raw["copy_brightness"],
        "copy_brightness_limit": raw["copy_brightness_limit"],
        "copy_depth_offset": -copy["depth"],
        "copy_jitter_y": [(y_mask & 0x7FFFFFFF) + 1, copy["y_offset"]],
        "copy_jitter_x": [copy["x_modulus"], copy["x_offset"]],
        "overlay_rect": [raw["overlay_width"], raw["overlay_height"]],
        "overlay_weight": raw["overlay_weight"],
        "overlay_corners": [[(raw[name] >> shift) & 0xFF for shift in (0, 8, 16)] for name in CORNER_ORDER],
        "overlay_fixed_one": raw["overlay_fixed_one"],
        "overlay_fixed_shift": raw["overlay_fixed_shift"],
        "world_clip": [raw["world_clip_origin"], raw["world_clip_origin"], 1, raw["world_clip_height_less"]],
    }


def validate(params: dict) -> list:
    failures = []
    for name, expected in EXPECTED.items():
        value = params[name]
        same = f32(value) == f32(expected) if isinstance(expected, float) else value == expected
        if not same:
            failures.append(f"{name} is {value}, the reference recovered {expected}")
    return failures


def render(params: dict) -> str:
    out = {
        "generated_by": "tools/export_slowdown_params.py",
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
            print("Slow-down parameter check failed:\n" + "\n".join(f"  {line}" for line in failures))
            return 1
        print("Verified the pill's slow-down, the agents' 0.2, the green copies and the overlay from sub_41CD90, sub_41CFC0, the four agent ticks, sub_417460, 0x43B050, sub_41D500, sub_4584D0 and Main_RenderUpdate.")
        return 0

    if failures:
        print("Slow-down parameter export failed:\n" + "\n".join(f"  {line}" for line in failures))
        return 1
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(text, encoding="utf-8")
    print(f"Wrote {OUTPUT_REL}.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
