#!/usr/bin/env python3
"""Recover the seven NPC character profiles from sacked.exe into resources/original/npc_profiles.json.

`sub_4184B0` loads each agent's constants out of one static table of floats at 0x46E7D8,
eleven per character. The first three it stores twice, once into the live field and once
into a saved base that the per-tick functions add the aggression band to:

    column 0  speed, tiles/s      -> agent+56    (base kept at agent+1852)
    column 1  notice radius       -> agent+1068  (base kept at agent+1856)
    column 2  notice cone, deg    -> agent+1072  (base kept at agent+1860)
    columns 3..10  the eight goal decay rates -> agent+940 onwards

The room masks are compiled-in immediates rather than table columns, so they stay documented
constants in scenes/npc/npc_brain.gd. See docs/npc-reference.md and docs/catch-reference.md.
"""

import argparse
import hashlib
import json
import struct
import sys
from pathlib import Path


EXE_REL = Path("extract-sacked-assets/sacked/sacked.exe")
OUTPUT_REL = Path("resources/original/npc_profiles.json")

# The build this project targets. The address below is only meaningful for this image.
EXE_SIZE = 479232
EXE_SHA256 = "6404096cc74e1c954daa2033a7d7d7826429a27deaa679f1ff7103027f614a86"
IMAGE_BASE = 0x400000  # RVA == file offset in this image

PROFILE_TABLE_VA = 0x46E7D8
PROFILE_FLOATS = 11
GOAL_COUNT = 8

# sub_4184B0 is reached with the agent's own type, and sub_404B90 and friends set +1740.
SPAWN_IDS = {
    1: "boss",
    2: "secretary",
    3: "janitor",
    4: "male-employee-1",
    5: "male-employee-2",
    6: "female-employee-1",
    7: "female-employee-2",
}

# sub_415D50 seeds every agent before its profile overwrites these.
DEFAULT_NOTICE_RADIUS = 5.0
DEFAULT_NOTICE_CONE = 60.0

# The three tick functions that apply the band; sub_419740, the boss, applies none of them.
BAND_SPEED_STEP = 0.15
BAND_RADIUS_STEP = 0.2
BAND_CONE_STEP = 5.0


def repo_root() -> Path:
    return Path(__file__).resolve().parents[1]


def read_exe(root: Path) -> bytes:
    data = (root / EXE_REL).read_bytes()
    if len(data) != EXE_SIZE:
        raise SystemExit(f"{EXE_REL} is {len(data)} bytes, expected {EXE_SIZE}")
    digest = hashlib.sha256(data).hexdigest()
    if digest != EXE_SHA256:
        raise SystemExit(f"{EXE_REL} sha256 {digest}, expected {EXE_SHA256}")
    return data


def build_table(data: bytes) -> dict:
    profiles = {}
    for spawn_id, name in sorted(SPAWN_IDS.items()):
        offset = PROFILE_TABLE_VA - IMAGE_BASE + (spawn_id - 1) * PROFILE_FLOATS * 4
        values = struct.unpack_from("<%df" % PROFILE_FLOATS, data, offset)
        profiles[name] = {
            "spawn_id": spawn_id,
            "speed_tiles": round(values[0], 6),
            "notice_radius_tiles": round(values[1], 6),
            "notice_cone_degrees": round(values[2], 6),
            "rates": [round(value, 6) for value in values[3:]],
        }
    return {
        "generated_by": "tools/export_npc_profiles.py",
        "source": EXE_REL.as_posix(),
        "source_sha256": EXE_SHA256,
        "table_address": "0x%06X" % PROFILE_TABLE_VA,
        "defaults": {
            "notice_radius_tiles": DEFAULT_NOTICE_RADIUS,
            "notice_cone_degrees": DEFAULT_NOTICE_CONE,
        },
        "aggression_band": {
            "speed_tiles": BAND_SPEED_STEP,
            "notice_radius_tiles": BAND_RADIUS_STEP,
            "notice_cone_degrees": BAND_CONE_STEP,
            "exempt": ["boss"],
        },
        "profiles": profiles,
    }


def validate(table: dict) -> list:
    failures = []
    for name, profile in sorted(table["profiles"].items()):
        if len(profile["rates"]) != GOAL_COUNT:
            failures.append(f"{name} has {len(profile['rates'])} decay rates, expected {GOAL_COUNT}")
        if not 0.5 <= profile["speed_tiles"] <= 5.0:
            failures.append(f"{name} speed {profile['speed_tiles']} is not a plausible walking speed")
        if not 1.0 <= profile["notice_radius_tiles"] <= 8.0:
            # sub_418310 rejects anything past 8 tiles on each axis before it measures.
            failures.append(f"{name} notice radius {profile['notice_radius_tiles']} is outside the 8-tile box")
        if not 0.0 <= profile["notice_cone_degrees"] <= 360.0:
            failures.append(f"{name} notice cone {profile['notice_cone_degrees']} is not an angle")
        for rate in profile["rates"]:
            if rate < 0.0 or rate > 100.0:
                failures.append(f"{name} has decay rate {rate} outside 0..100")
    return failures


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=repo_root())
    parser.add_argument("--check", action="store_true", help="Verify the exported table without writing")
    args = parser.parse_args()

    table = build_table(read_exe(args.root))
    failures = validate(table)
    output = args.root / OUTPUT_REL
    text = json.dumps(table, indent=2, sort_keys=True, ensure_ascii=False) + "\n"

    if args.check:
        if not output.is_file():
            failures.append(f"{OUTPUT_REL} is missing")
        elif output.read_text(encoding="utf-8") != text:
            failures.append(f"{OUTPUT_REL} is stale")
        if failures:
            print("NPC profile check failed:\n" + "\n".join(f"  {line}" for line in failures))
            return 1
        print(f"Verified {len(table['profiles'])} NPC profiles from {table['table_address']}.")
        return 0

    if failures:
        print("NPC profile export failed:\n" + "\n".join(f"  {line}" for line in failures))
        return 1
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(text, encoding="utf-8")
    print(f"Wrote {OUTPUT_REL} with {len(table['profiles'])} profiles.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
