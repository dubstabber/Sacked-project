#!/usr/bin/env python3
"""Recover the coworkers' default names into resources/original/names.json.

The original keeps fifteen names in one table (`dword_473CE8`, source npc_names.cpp), each
record a u16 type, a u16 used flag and an 18-byte name that every copy cuts to 16
characters. Three copies of those records exist, and this tool reads all three and refuses to
run unless they agree:

  NAMES.DAT        334 bytes: a u32 count, then the 330 bytes of records, as sub_415980 reads
                   them. The Polish release ships it; the German one does not.
  sacked.exe       the embedded defaults sub_415630 falls back to, at 0x46E5C0, fifteen
                   records and an all-zero terminator.
  Gefeuert.exe     the same 352 bytes at 0x470A18.

The pool a record belongs to is its fixed position, not its type column: record 0 is the
boss, 1 the secretary, 2 the janitor, then three each for the two male and two female
coworker variants. The tool asserts the type column matches that, so nothing downstream has
to trust it. The portrait each type shows on screen 13 comes from the char*[7] table at
0x470518, and the literal an exhausted pool hands out from 0x46E724 (German 0x470B7C).

The extraction's own notes decode NAMES.DAT without its count and are wrong; see
docs/names-reference.md.
"""

import argparse
import hashlib
import json
import struct
from pathlib import Path

try:
    from export_action_table import EXE_REL, Image
    from export_strings import GERMAN_EXE_REL, GermanImage, text_at
    from import_original_level import NPC_PROFILES
except ImportError:  # imported as tools.export_names by the tests
    from tools.export_action_table import EXE_REL, Image
    from tools.export_strings import GERMAN_EXE_REL, GermanImage, text_at
    from tools.import_original_level import NPC_PROFILES


NAMES_REL = Path("extract-sacked-assets/sacked/NAMES.DAT")
NAMES_SIZE = 334
NAMES_SHA256 = "7536017a4d2055811a13229c9958097d05af67a0254549a9ea7e66dd91cdbd14"
OUTPUT_REL = Path("resources/original/names.json")

RECORD_COUNT = 15
RECORD_SIZE = 22
NAME_OFFSET = 4
# Every copy in or out of a record is strncpy(..., 16), and screen 13's boxes cap at 16 too.
NAME_MAX_LENGTH = 16

DEFAULTS_VA = 0x46E5C0
GERMAN_DEFAULTS_VA = 0x470A18
PLACEHOLDER_VA = 0x46E724
GERMAN_PLACEHOLDER_VA = 0x470B7C
PORTRAIT_TABLE_VA = 0x470518

# How many records each type's pool holds, in pool order. sub_4156E0 addresses the pools by
# these fixed positions.
POOL_SIZES = {1: 1, 2: 1, 3: 1, 4: 3, 5: 3, 6: 3, 7: 3}


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def pool_types() -> list:
    """The type each record position belongs to: [1, 2, 3, 4, 4, 4, 5, ...]."""
    types = []
    for pool, size in POOL_SIZES.items():
        types.extend([pool] * size)
    return types


def decode_records(blob: bytes, encoding: str) -> list:
    records = []
    for index in range(len(blob) // RECORD_SIZE):
        base = index * RECORD_SIZE
        record_type, used = struct.unpack_from("<HH", blob, base)
        raw = blob[base + NAME_OFFSET : base + RECORD_SIZE].split(b"\0", 1)[0]
        records.append((record_type, used, raw.decode(encoding)))
    return records


def read_file(root: Path) -> list:
    data = (root / NAMES_REL).read_bytes()
    if len(data) != NAMES_SIZE or sha256(data) != NAMES_SHA256:
        raise SystemExit(
            f"{NAMES_REL} is not the file this layout was recovered from "
            f"(size {len(data)}, sha256 {sha256(data)})."
        )
    count, = struct.unpack_from("<I", data, 0)
    if count != RECORD_COUNT:
        raise SystemExit(f"{NAMES_REL} holds {count} records, expected {RECORD_COUNT}")
    return decode_records(data[4:], "cp1250")


def read_defaults(image: Image, va: int, encoding: str) -> list:
    offset = image.offset(va)
    if offset is None:
        raise SystemExit(f"0x{va:08x} is not mapped in {image.path}")
    blob = image.data[offset : offset + RECORD_SIZE * (RECORD_COUNT + 1)]
    records = decode_records(blob, encoding)
    # sub_415630 copies records until it reads type 0.
    if records[RECORD_COUNT] != (0, 0, "") or any(record[0] == 0 for record in records[:RECORD_COUNT]):
        raise SystemExit(f"the defaults at 0x{va:08x} in {image.path} do not end after {RECORD_COUNT} records")
    return records[:RECORD_COUNT]


def build(root: Path) -> dict:
    polish = Image(root / EXE_REL)
    german = GermanImage(root / GERMAN_EXE_REL)
    shipped = read_file(root)
    polish_defaults = read_defaults(polish, DEFAULTS_VA, "cp1250")
    german_defaults = read_defaults(german, GERMAN_DEFAULTS_VA, "cp1252")

    if not (shipped == polish_defaults == german_defaults):
        raise SystemExit("NAMES.DAT and the two builds' embedded defaults disagree")
    expected_types = pool_types()
    if len(expected_types) != RECORD_COUNT:
        raise SystemExit(f"the pools hold {len(expected_types)} records, expected {RECORD_COUNT}")
    for index, (record_type, used, name) in enumerate(shipped):
        if record_type != expected_types[index]:
            raise SystemExit(f"record {index} has type {record_type}, but its position is pool {expected_types[index]}")
        if used != 0:
            raise SystemExit(f"record {index} ships with its used flag set")
        if not name or len(name) > NAME_MAX_LENGTH:
            raise SystemExit(f"record {index} name {name!r} is empty or longer than {NAME_MAX_LENGTH}")

    placeholder = text_at(polish, PLACEHOLDER_VA, "cp1250")
    if text_at(german, GERMAN_PLACEHOLDER_VA, "cp1252") != placeholder:
        raise SystemExit("the two builds hand out different placeholders")

    portraits = polish.pointers(PORTRAIT_TABLE_VA, len(POOL_SIZES))
    types = []
    for position, pool in enumerate(POOL_SIZES):
        first = expected_types.index(pool)
        types.append({
            "type": pool,
            "profile_id": NPC_PROFILES[pool],
            "portrait": polish.cstring(portraits[position]),
            "records": list(range(first, first + POOL_SIZES[pool])),
        })

    return {
        "generated_by": "tools/export_names.py",
        "sources": {
            "file": {"path": str(NAMES_REL), "size": NAMES_SIZE, "sha256": NAMES_SHA256},
            "pl": {
                "exe": str(EXE_REL),
                "defaults": "0x%08x" % DEFAULTS_VA,
                "placeholder": "0x%08x" % PLACEHOLDER_VA,
                "portraits": "0x%08x" % PORTRAIT_TABLE_VA,
            },
            "de": {
                "exe": str(GERMAN_EXE_REL),
                "defaults": "0x%08x" % GERMAN_DEFAULTS_VA,
                "placeholder": "0x%08x" % GERMAN_PLACEHOLDER_VA,
            },
        },
        "max_length": NAME_MAX_LENGTH,
        "placeholder": placeholder,
        "types": types,
        "records": [
            {"index": index, "type": record_type, "profile_id": NPC_PROFILES[record_type], "name": name}
            for index, (record_type, _, name) in enumerate(shipped)
        ],
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--check", action="store_true", help="Verify names.json without writing")
    args = parser.parse_args()

    root = args.root.resolve()
    table = build(root)
    output = root / OUTPUT_REL
    if args.check:
        if not output.is_file():
            print(f"{OUTPUT_REL} is missing")
            return 1
        if json.loads(output.read_text(encoding="utf-8")) != table:
            print(f"{OUTPUT_REL} is stale")
            return 1
        print(f"names.json matches NAMES.DAT and both builds ({RECORD_COUNT} names)")
        return 0
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(table, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Wrote {RECORD_COUNT} names to {OUTPUT_REL}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
