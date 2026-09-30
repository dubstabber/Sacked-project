#!/usr/bin/env python3
"""Replay sacked.exe's field-of-view shadow tables into resources/original/fov_tables.json.

Nothing in the original loads these tables from a file. sub_427DC0 builds them at run time,
once, from the first field-of-view constructor (sub_428140, 0x42817D). This tool replays that
builder in Python, at the x87's 53-bit precision and with float32 rounding exactly where the
original stores a float, reading the builder's constants out of the executable itself. The
replay was checked byte for byte against the original running under emulation. See "The
shadow tables, sub_427DC0" in docs/field-of-view-reference.md.

The four tables it builds:

    0x47F02C  [start, count] per sample (r, j), 1596 used, sample index r(r - 1)/2 + j
    0x47F030  {u8 a, u8 b, u8 k, u8 0} spans, 30856 used
    0x47F034  57 x 57 float32 distances, dist[57i + j] = sqrt(i^2 + j^2)
    0x47F040  114 row offsets, 113 * i

Beside the tables it writes the five float32 constants the rest of the field of view reads,
each checked at every instruction that reads it: the 12.0 of sub_402260's gate (flt_4652CC),
the 7.0 that places sub_4298E0's diamond (0x4667B8, which is also the builder's far edge), the
0.022222 that sub_428270 turns an edge angle into a sector with (0x4667D4, beside its exact
negation at 0x4667D0), and the 8.0 and 0.125 that sub_428BC0 turns the radius into texels with
and steps its shadow walk by (0x465878, 0x465854, which the builder reads too). The cone's
other constant, 0.017453 at 0x465540, is shared with the smoke and the puddle, so
tools/export_view_angles.py reads it.

--check replays the builder again, checks the counts and the SHA-1 of the serialised tables
against the values recovered in the reference, and compares the result with the checked-in
file.
"""

import argparse
import hashlib
import json
import math
import struct
import sys
from decimal import Decimal
from pathlib import Path

try:
    from original_exe import EXE_REL, EXE_SHA256, FADD, FCOMP, FMUL, FSUB, at, f32, pin_readers, read_exe, repo_root
except ImportError:  # imported as tools.export_fov_tables
    from tools.original_exe import EXE_REL, EXE_SHA256, FADD, FCOMP, FMUL, FSUB, at, f32, pin_readers, read_exe, repo_root


OUTPUT_REL = Path("resources/original/fov_tables.json")

BUILDER_VA = 0x427DC0

# float32 constants the builder reads, by the address of the value.
EIGHTH_VA = 0x465854  # 0.125: r / 8, j / 8 and the row step
ONE_VA = 0x4652B8  # 1.0: the unit step along each corner's ray
HALF_ROW_VA = 0x4667BC  # 0.0625: the first row's centre
SEVEN_VA = 0x4667B8  # 7.0: the far edge, which also replaces an out-of-range x2
EIGHT_VA = 0x465878  # 8.0: tiles to texels before ceil
TEN_IMMEDIATE_VA = 0x427F79  # 10.0: the row line's second point (the mov at 0x427F75)
PARALLEL_IMMEDIATE_VA = 0x427CEF  # -1000.0: sub_427C80's answer for parallel lines (mov at 0x427CED)

# The constants the field of view reads beside the tables: the value's address, and each
# instruction that reads it with its opcode bytes.
VIEW_CONSTANTS = {
    # sub_402260: agent - player on x, then on z, strictly below 12.
    "gate_tiles": (0x4652CC, [(0x4022CF, FCOMP), (0x4022E0, FCOMP)]),
    # The builder's far edge, then sub_4298E0's diamond: x - 7, z - 7, x + 7, z + 7.
    "reach_tiles": (0x4667B8, [
        (0x427FF8, FCOMP), (0x42991F, FSUB), (0x429944, FSUB), (0x429962, FADD), (0x42996D, FADD),
    ]),
    # sub_428270: hi and a non-negative lo to their sectors; a negative lo takes the negation.
    "sector_scale": (0x4667D4, [(0x4282BE, FMUL), (0x4282E1, FMUL)]),
    # The builder's ceil(x1 * 8) and ceil(x2 * 8), then sub_428BC0's radius * 8.
    "texels_per_tile": (EIGHT_VA, [(0x428024, FMUL), (0x42803F, FMUL), (0x428C00, FMUL)]),
    # The builder's r / 8, (r - 1) / 8, j / 8, (j + 1) / 8 and its row step; then the offsets
    # sub_428BC0's shadow walk adds 0.125 to, the minor one and the major one for each octant.
    "sample_step": (EIGHTH_VA, [
        (0x427E56, FMUL), (0x427E64, FMUL), (0x427E7F, FMUL), (0x427EE3, FMUL), (0x4280BD, FADD),
        (0x428D19, FADD), (0x428D3F, FADD), (0x428E76, FADD), (0x428E98, FADD),
        (0x428FC5, FADD), (0x428FE7, FADD), (0x42911A, FADD), (0x42913C, FADD),
        (0x429292, FADD), (0x4292B8, FADD), (0x4293FB, FADD), (0x429421, FADD),
        (0x429578, FADD), (0x42959E, FADD), (0x4296E2, FADD), (0x429708, FADD),
    ]),
}
NEGATED_SECTOR_VA = 0x4667D0
NEGATED_SECTOR_READER = 0x4282CD
VIEW_EXPECTED = {
    "gate_tiles": 12.0, "reach_tiles": 7.0, "sector_scale": 0.022222, "texels_per_tile": 8.0,
    "sample_step": 0.125,
}

MAJOR_ROWS = 56
SAMPLE_COUNT = 1596  # 56 * 57 / 2
ENTRY_COUNT = 30856
DISTANCE_SIDE = 57
ROW_OFFSET_COUNT = 114
MASK_SIDE = 113

# The SHA-1 recorded in docs/field-of-view-reference.md, over the four tables serialised
# little-endian and concatenated: the 1596 [start, count] pairs as int32, the 30856 four-byte
# entries, the 3249 float32 distances and the 114 uint32 row offsets.
TABLES_SHA1 = "ce708fa9a3190076ec37df25bd7369435c875c13"
SHA1_OVER = (
    "the 1596 [start, count] pairs as int32, then the 30856 {a, b, k, 0} byte entries, "
    "then the 3249 float32 distances, then the 114 uint32 row offsets, little-endian and "
    "concatenated in that order"
)


def float_at(data: bytes, va: int) -> float:
    return at(data, va, "f")


def builder_constants(data: bytes) -> dict:
    constants = {
        "eighth": float_at(data, EIGHTH_VA),
        "one": float_at(data, ONE_VA),
        "half_row": float_at(data, HALF_ROW_VA),
        "seven": float_at(data, SEVEN_VA),
        "eight": float_at(data, EIGHT_VA),
        "ten": float_at(data, TEN_IMMEDIATE_VA),
        "parallel": float_at(data, PARALLEL_IMMEDIATE_VA),
    }
    expected = {"eighth": 0.125, "one": 1.0, "half_row": 0.0625, "seven": 7.0, "eight": 8.0, "ten": 10.0, "parallel": -1000.0}
    if constants != expected:
        raise SystemExit(f"the builder's constants are not where they were recovered: {constants}")
    return constants


def view_constants(data: bytes) -> dict:
    failures = []
    constants = {}
    for name, (va, readers) in VIEW_CONSTANTS.items():
        pin_readers(data, name, va, readers, failures)
        constants[name] = float_at(data, va)
    before = len(failures)
    pin_readers(data, "-sector_scale", NEGATED_SECTOR_VA, [(NEGATED_SECTOR_READER, FMUL)], failures)
    if len(failures) == before and float_at(data, NEGATED_SECTOR_VA) != -constants["sector_scale"]:
        failures.append(f"0x{NEGATED_SECTOR_VA:X} is {float_at(data, NEGATED_SECTOR_VA)}, not -{constants['sector_scale']}")
    for name, expected in VIEW_EXPECTED.items():
        if constants[name] != f32(expected):
            failures.append(f"{name} is {constants[name]}, the reference recovered {expected}")
    if failures:
        raise SystemExit("\n".join(failures))
    return constants


def intersect(a, b, c, d, parallel):
    """sub_427C80: line a-b against line c-d, storing float32 where the original does."""
    c_minus_d_y = c[1] - d[1]
    bx = f32(b[0] - a[0])
    by = f32(b[1] - a[1])
    c_minus_d_x = c[0] - d[0]
    det = bx * c_minus_d_y - c_minus_d_x * by
    if det == 0.0:
        return (parallel, parallel)
    det = f32(det)
    cy = c[1] - a[1]
    cx = c[0] - a[0]
    numerator_u = f32(cy * bx - cx * by)
    t = f32((cx * c_minus_d_y - cy * c_minus_d_x) / det)
    u = numerator_u / det  # the only quotient the original leaves unrounded
    return (f32((b[0] - a[0]) * t + a[0]), f32(u * (d[1] - c[1]) + c[1]))


def build_tables(constants: dict) -> dict:
    eighth = constants["eighth"]
    one = constants["one"]
    seven = constants["seven"]
    eight = constants["eight"]
    ten = f32(constants["ten"])
    samples = []
    entries = []
    for r in range(1, MAJOR_ROWS + 1):
        near = f32(r * eighth)
        far = f32((r - 1) * eighth)
        for j in range(r):
            minor = f32(j * eighth)
            minor_next = f32((j + 1) * eighth)
            inverse = one / math.sqrt(near * near + minor * minor)
            ray_one = (f32(f32(inverse * minor) + minor), f32(inverse * near + near))
            inverse = one / math.sqrt(minor_next * minor_next + far * far)
            ray_two = (f32(f32(inverse * minor_next) + minor_next), f32(inverse * far + far))
            start = len(entries)
            row_y = constants["half_row"]
            for k in range(MAJOR_ROWS):
                x1, y1 = intersect((0.0, row_y), (ten, row_y), (minor, near), ray_one, constants["parallel"])
                x2, _ = intersect((0.0, row_y), (ten, row_y), (minor_next, far), ray_two, constants["parallel"])
                if x1 < minor:
                    x1 = minor
                if x2 < 0.0 or x2 > seven:
                    x2 = seven
                if not y1 < far:
                    entries.append((math.ceil(x1 * eight) & 0xFF, math.ceil(x2 * eight) & 0xFF, k))
                row_y = f32(row_y + eighth)
            samples.append((r, j, start, len(entries) - start))
    distances = [f32(math.sqrt(i * i + j * j)) for i in range(DISTANCE_SIDE) for j in range(DISTANCE_SIDE)]
    row_offsets = [MASK_SIDE * i for i in range(ROW_OFFSET_COUNT)]
    return {"samples": samples, "entries": entries, "distances": distances, "row_offsets": row_offsets}


def serialise(tables: dict) -> bytes:
    """The tables as they sit in the original's memory, in the order the SHA-1 covers."""
    out = bytearray()
    for _r, _j, start, count in tables["samples"]:
        out += struct.pack("<ii", start, count)
    for a, b, k in tables["entries"]:
        out += bytes((a, b, k, 0))
    out += struct.pack("<%df" % len(tables["distances"]), *tables["distances"])
    out += struct.pack("<%dI" % len(tables["row_offsets"]), *tables["row_offsets"])
    return bytes(out)


def validate(tables: dict) -> list:
    failures = []
    samples = tables["samples"]
    entries = tables["entries"]
    if len(samples) != SAMPLE_COUNT:
        failures.append(f"{len(samples)} samples, expected {SAMPLE_COUNT}")
    if len(entries) != ENTRY_COUNT:
        failures.append(f"{len(entries)} entries, expected {ENTRY_COUNT}")
    digest = hashlib.sha1(serialise(tables)).hexdigest()
    if digest != TABLES_SHA1:
        failures.append(f"the replayed tables hash to {digest}, expected {TABLES_SHA1}")
    for index, (r, j, start, count) in enumerate(samples):
        if index != r * (r - 1) // 2 + j:
            failures.append(f"sample ({r}, {j}) is at index {index}")
        rows = [k for _a, _b, k in entries[start : start + count]]
        # The file leaves k implicit: every sample owns exactly the rows r - 1 to 55.
        if rows != list(range(r - 1, MAJOR_ROWS)):
            failures.append(f"sample ({r}, {j}) owns rows {rows[:3]}..., not {r - 1} to {MAJOR_ROWS - 1}")
    return failures


def _shortest_f32(value: float) -> str:
    """The shortest decimal that reads back as the same float32, written without an exponent."""
    for digits in range(1, 10):
        text = "%.*g" % (digits, value)
        if f32(float(text)) == value:
            text = format(Decimal(text), "f")
            return text if "." in text else text + ".0"
    raise ValueError(value)


def _numbers(values) -> str:
    return ", ".join(_shortest_f32(value) if isinstance(value, float) else str(value) for value in values)


def render(tables: dict, constants: dict) -> str:
    """Compact, one sample per line: [r, j, start, [a, b, a, b, ...]] for rows r - 1 to 55."""
    header = {
        "generated_by": "tools/export_fov_tables.py",
        "source": EXE_REL.as_posix(),
        "source_sha256": EXE_SHA256,
        "builder": "0x%06X" % BUILDER_VA,
        "sample_count": len(tables["samples"]),
        "entry_count": len(tables["entries"]),
        "sha1": hashlib.sha1(serialise(tables)).hexdigest(),
        "sha1_over": SHA1_OVER,
        "sample_layout": "[r, j, start, [a, b, ...]]: sample r(r - 1)/2 + j, whose spans cover rows k = r - 1 to 55 in order",
        "gate_tiles": constants["gate_tiles"],
        "reach_tiles": constants["reach_tiles"],
        "sector_scale": constants["sector_scale"],
        "texels_per_tile": constants["texels_per_tile"],
        "sample_step": constants["sample_step"],
    }
    lines = ["{"]
    for key, value in header.items():
        lines.append(f"  {json.dumps(key)}: {json.dumps(value)},")
    lines.append('  "distances": [')
    distances = tables["distances"]
    rows = [distances[i * DISTANCE_SIDE : (i + 1) * DISTANCE_SIDE] for i in range(DISTANCE_SIDE)]
    lines += [f"    [{_numbers(row)}]" + ("," if i + 1 < len(rows) else "") for i, row in enumerate(rows)]
    lines.append("  ],")
    lines.append(f'  "row_offsets": [{_numbers(tables["row_offsets"])}],')
    lines.append('  "samples": [')
    entries = tables["entries"]
    samples = tables["samples"]
    for index, (r, j, start, count) in enumerate(samples):
        spans = [value for a, b, _k in entries[start : start + count] for value in (a, b)]
        comma = "," if index + 1 < len(samples) else ""
        lines.append(f"    [{r}, {j}, {start}, [{_numbers(spans)}]]{comma}")
    lines.append("  ]")
    lines.append("}")
    return "\n".join(lines) + "\n"


def parse(text: str) -> dict:
    """The tables back out of the file, for a test that has no executable to replay."""
    data = json.loads(text)
    samples = []
    entries = []
    for r, j, start, spans in data["samples"]:
        if start != len(entries):
            raise ValueError(f"sample ({r}, {j}) starts at {start}, not {len(entries)}")
        for offset in range(0, len(spans), 2):
            entries.append((spans[offset], spans[offset + 1], r - 1 + offset // 2))
        samples.append((r, j, start, len(spans) // 2))
    distances = [f32(value) for row in data["distances"] for value in row]
    return {"samples": samples, "entries": entries, "distances": distances, "row_offsets": data["row_offsets"]}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=repo_root())
    parser.add_argument("--check", action="store_true", help="Verify the checked-in tables without writing")
    args = parser.parse_args()

    data = read_exe(args.root)
    tables = build_tables(builder_constants(data))
    failures = validate(tables)
    text = render(tables, view_constants(data))
    output = args.root / OUTPUT_REL

    if args.check:
        if not output.is_file():
            failures.append(f"{OUTPUT_REL} is missing")
        elif output.read_text(encoding="utf-8") != text:
            failures.append(f"{OUTPUT_REL} is stale")
        if failures:
            print("Field-of-view table check failed:\n" + "\n".join(f"  {line}" for line in failures))
            return 1
        print(
            f"Verified the field-of-view tables replayed from sub_{BUILDER_VA:X}: "
            f"{len(tables['samples'])} samples, {len(tables['entries'])} entries, SHA-1 {TABLES_SHA1}; "
            "and the gate, the reach, the sector constant, the texel scale and the walk's step at every reader."
        )
        return 0

    if failures:
        print("Field-of-view table export failed:\n" + "\n".join(f"  {line}" for line in failures))
        return 1
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(text, encoding="utf-8")
    print(f"Wrote {OUTPUT_REL}: {len(tables['samples'])} samples, {len(tables['entries'])} entries.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
