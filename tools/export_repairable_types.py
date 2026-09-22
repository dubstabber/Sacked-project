#!/usr/bin/env python3
"""Recover which item types a janitor will repair, into resources/original/repairable_types.json.

`sub_4180F0` answers "is this item worth a repair job?". It is a compiler-built jump table:
the item's type is biased by a constant, bounds-checked, used to index a byte selector table,
and that byte picks one of two branches -- one stores the job and returns 1, the other
returns 0. Rather than transcribe the thirty types into GDScript, this tool decodes those
instructions, reads the selector table and reports the types whose byte picks the storing
branch.

Every instruction it expects is asserted, so a different build or a mis-set address fails
loudly instead of producing a plausible list. See docs/npc-reference.md.
"""

import argparse
import hashlib
import json
import struct
from pathlib import Path

try:
    from export_action_table import Image, object_action_ids
except ImportError:  # imported as tools.export_repairable_types by the tests
    from tools.export_action_table import Image, object_action_ids


EXE_REL = Path("extract-sacked-assets/sacked/sacked.exe")
OUTPUT_REL = Path("resources/original/repairable_types.json")

FUNCTION_VA = 0x4180F0
# sub_4181F0, the cubicle rule that follows it, is where this function's body ends.
FUNCTION_END_VA = 0x4181F0

# The one field the storing branch writes: the agent's pending repair job.
REPAIR_JOB_OFFSET = 0x728


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def decode_switch(image: Image) -> dict:
    """Walk the function's prologue, asserting each instruction, and read the switch out."""
    va = FUNCTION_VA

    def take(expected: bytes) -> None:
        nonlocal va
        offset = image.offset(va)
        actual = image.data[offset : offset + len(expected)]
        if actual != expected:
            raise SystemExit(
                f"sub_4180F0 is not the function these addresses were recovered from: "
                f"at 0x{va:08x} expected {expected.hex()}, found {actual.hex()}"
            )
        va += len(expected)

    def read(fmt: str) -> tuple:
        nonlocal va
        values = struct.unpack_from(fmt, image.data, image.offset(va))
        va += struct.calcsize(fmt)
        return values

    take(b"\x56\x57")                  # push esi ; push edi
    take(b"\x8b\x7c\x24\x0c")          # mov edi, [esp+0xC]   -- the item
    take(b"\x8b\xf1")                  # mov esi, ecx         -- the agent
    take(b"\x8b\xcf")                  # mov ecx, edi
    take(b"\xe8")                      # call
    type_reader, = read("<i")
    type_reader += va                  # the call that returns the item's type
    take(b"\x0f\xbf\xc0")              # movsx eax, ax

    take(b"\x83\xc0")                  # add eax, imm8
    bias, = read("<b")
    take(b"\x3d")                      # cmp eax, imm32
    limit, = read("<I")
    take(b"\x77")                      # ja short -- out of range falls to the default
    default_skip, = read("<b")
    default_va = va + default_skip

    take(b"\x33\xc9")                  # xor ecx, ecx
    take(b"\x8a\x88")                  # mov cl, [eax + disp32]
    selector_va, = read("<I")
    take(b"\xff\x24\x8d")              # jmp dword ptr [ecx*4 + disp32]
    jump_va, = read("<I")

    base = -bias                       # the type the selector table starts at
    count = limit + 1
    if not 0 < count <= FUNCTION_END_VA - selector_va:
        raise SystemExit(f"the selector table of {count} bytes does not fit before sub_4181F0")

    # Two branches: one stores the job and returns 1, the other returns 0.
    targets = [
        struct.unpack_from("<I", image.data, image.offset(jump_va) + 4 * index)[0]
        for index in range(2)
    ]
    storing = [index for index, target in enumerate(targets) if _stores_the_job(image, target)]
    if len(storing) != 1:
        raise SystemExit(f"expected exactly one branch to store the job, found {storing}")
    if default_va not in targets:
        raise SystemExit("the out-of-range branch is not one of the two jump targets")

    return {
        "base": base,
        "count": count,
        "selector_va": selector_va,
        "jump_va": jump_va,
        "repairing_branch": storing[0],
        "type_reader": type_reader,
    }


def _stores_the_job(image: Image, va: int) -> bool:
    """A repairing branch writes the item to agent+0x728 and returns 1."""
    offset = image.offset(va)
    body = image.data[offset : offset + 16]
    stores = body.startswith(b"\x89\xbe" + struct.pack("<I", REPAIR_JOB_OFFSET))
    return stores and b"\xb8\x01\x00\x00\x00" in body


def repairable_types(image: Image, switch: dict) -> list:
    offset = image.offset(switch["selector_va"])
    selector = image.data[offset : offset + switch["count"]]
    if set(selector) != {0, 1}:
        raise SystemExit(f"the selector table holds {sorted(set(selector))}, expected two branches")
    return [
        switch["base"] + index
        for index, branch in enumerate(selector)
        if branch == switch["repairing_branch"]
    ]


def build(root: Path) -> dict:
    exe = root / EXE_REL
    image = Image(exe)
    switch = decode_switch(image)
    types = repairable_types(image, switch)

    definitions = object_action_ids(root)
    unknown = [item_type for item_type in types if item_type not in definitions]
    if unknown:
        raise SystemExit(f"types with no CO_OBJECTS.DAT record: {unknown}")

    return {
        "generated_by": "tools/export_repairable_types.py",
        "source": {
            "exe": str(EXE_REL),
            "size": exe.stat().st_size,
            "sha256": sha256(exe),
            "function": "0x%08x" % FUNCTION_VA,
            "selector_table": "0x%08x" % switch["selector_va"],
            "jump_table": "0x%08x" % switch["jump_va"],
            "first_type": switch["base"],
            "type_span": switch["count"],
            "repair_job_offset": "0x%x" % REPAIR_JOB_OFFSET,
        },
        "types": [
            {"type": item_type, "name": definitions[item_type]["name"]}
            for item_type in types
        ],
    }


def check(root: Path, table: dict) -> int:
    failures = []
    output = root / OUTPUT_REL
    if not output.is_file():
        failures.append(f"{OUTPUT_REL} is missing")
    elif json.loads(output.read_text(encoding="utf-8")) != table:
        failures.append(f"{OUTPUT_REL} is stale")

    types = [entry["type"] for entry in table["types"]]
    if len(types) != 30:
        failures.append(f"{len(types)} repairable types, expected 30")
    if types != sorted(set(types)):
        failures.append("the types are not a sorted, distinct list")
    if table["source"]["first_type"] != 102 or types[:1] != [102]:
        failures.append("the table no longer starts at type 102")

    for failure in failures:
        print(f"FAIL {failure}")
    if failures:
        return 1
    print(f"repairable_types.json matches sacked.exe ({len(types)} types)")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--check", action="store_true", help="Verify the exported table without writing")
    args = parser.parse_args()

    root = args.root.resolve()
    table = build(root)
    if args.check:
        return check(root, table)

    output = root / OUTPUT_REL
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(table, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Wrote {len(table['types'])} repairable item types to {OUTPUT_REL}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
