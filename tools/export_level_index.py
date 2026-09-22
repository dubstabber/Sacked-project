#!/usr/bin/env python3
"""Recover the level tree and every level's headline facts into resources/levels/index.json.

The shell needs four things about each of the 21 levels before it can draw the tree or the
description screen: where its node sits, which levels clearing it opens, how hard it is, and
what its win condition is. The first three come out of two byte tables in sacked.exe and the
last out of the level files themselves, so none of it is transcribed.

`byte_470BB4` gives each of 28 entries a 1-based tree column and `byte_470BD0` its row within
that column, which makes the tree a triangle: column c holds exactly c entries, so columns 1
to 6 hold the 21 levels and column 7 is an empty tail. `sub_421F80` opens entry `i + c` and
`i + c + 1` when entry `i` in column `c` is cleared, and `sub_421F30` places its button at
`(112 * (c - 1) + 40, 40 * (2 * row - (c - 1)) + 256)`.

`byte_465270` is the per-level difficulty index the description screen shows. It is not an
independent table -- it is the column minus one -- and this tool asserts that rather than
assuming it, so a build where they diverge fails instead of exporting a guess.

Conditions are read twice per level, from the plain file the time game loads and the S file
the points game loads. See docs/shell-reference.md.
"""

import argparse
import hashlib
import json
from pathlib import Path

try:
    from export_action_table import Image
    from import_original_level import find_chunk, parse_condition, read_u16
except ImportError:  # imported as tools.export_level_index by the tests
    from tools.export_action_table import Image
    from tools.import_original_level import find_chunk, parse_condition, read_u16


EXE_REL = Path("extract-sacked-assets/sacked/sacked.exe")
LEVELS_DIR_REL = Path("extract-sacked-assets/sacked/Levels")
OUTPUT_REL = Path("resources/levels/index.json")

LEVEL_COUNT = 21
# The tree's own tables are 28 entries: columns 1..6 hold the 21 levels, column 7 is empty.
TREE_ENTRY_COUNT = 28
COLUMN_TABLE_VA = 0x470BB4
ROW_TABLE_VA = 0x470BD0
DIFFICULTY_TABLE_VA = 0x465270

# sub_421F30's placement, and the 48x48 node art it places.
NODE_SIZE = (48, 48)
NODE_ORIGIN = (40, 256)
NODE_COLUMN_STEP = 112
NODE_ROW_STEP = 40
# sub_421FE0 puts the back button here, on the 160x48 shared button face.
BACK_BUTTON_POSITION = (16, 536)
BACK_BUTTON_ID = 29

# The highest column that has children; column 7 is the empty tail sub_421F80 skips.
LAST_PARENT_COLUMN = 6


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def tree_tables(image: Image) -> tuple:
    """The column and row of each of the 28 tree entries, plus the difficulty column."""
    columns = [image.byte(COLUMN_TABLE_VA + index) for index in range(TREE_ENTRY_COUNT)]
    rows = [image.byte(ROW_TABLE_VA + index) for index in range(TREE_ENTRY_COUNT)]
    difficulties = [image.byte(DIFFICULTY_TABLE_VA + index) for index in range(TREE_ENTRY_COUNT)]

    # A triangle: the entries are grouped by column, each column one longer than the last,
    # and every row runs 0..c-1. Anything else means these are not the tables we think.
    expected_columns = []
    expected_rows = []
    column = 1
    while len(expected_columns) < TREE_ENTRY_COUNT:
        for row in range(column):
            expected_columns.append(column)
            expected_rows.append(row)
        column += 1
    if columns != expected_columns[:TREE_ENTRY_COUNT]:
        raise SystemExit(f"{COLUMN_TABLE_VA:#x} is not the triangular column table: {columns}")
    if rows != expected_rows[:TREE_ENTRY_COUNT]:
        raise SystemExit(f"{ROW_TABLE_VA:#x} is not the triangular row table: {rows}")
    if difficulties != [value - 1 for value in columns]:
        raise SystemExit(
            f"{DIFFICULTY_TABLE_VA:#x} is no longer the column minus one: {difficulties}"
        )
    return columns, rows, difficulties


def node_position(column: int, row: int) -> list:
    return [
        NODE_COLUMN_STEP * (column - 1) + NODE_ORIGIN[0],
        NODE_ROW_STEP * (2 * row - (column - 1)) + NODE_ORIGIN[1],
    ]


def unlocked_by(index: int, column: int) -> list:
    """The 1-based levels clearing this entry opens, dropping any past the 21 that exist."""
    if column > LAST_PARENT_COLUMN:
        return []
    children = (index + column, index + column + 1)
    return [child + 1 for child in children if child < LEVEL_COUNT]


def map_size(data: bytes) -> tuple:
    mapinfo = find_chunk(data, "MAPINFO")
    if len(mapinfo.payload) < 4:
        raise ValueError("MAPINFO payload is too short")
    return read_u16(mapinfo.payload, 0), read_u16(mapinfo.payload, 2)


def build(root: Path) -> dict:
    exe = root / EXE_REL
    image = Image(exe)
    columns, rows, difficulties = tree_tables(image)

    levels = []
    for number in range(1, LEVEL_COUNT + 1):
        index = number - 1
        # sub_408D00 formats the index, not the number, so level 1 is LEVEL_00.
        plain = root / LEVELS_DIR_REL / ("LEVEL_%02d.col" % index)
        points = root / LEVELS_DIR_REL / ("LEVEL_%02ds.col" % index)
        plain_data = plain.read_bytes()
        width, height = map_size(plain_data)
        column = columns[index]
        levels.append(
            {
                "number": number,
                "index": index,
                "width": width,
                "height": height,
                "time_game": parse_condition(plain_data),
                "points_game": parse_condition(points.read_bytes()),
                "column": column,
                "row": rows[index],
                "difficulty": difficulties[index],
                "node_position": node_position(column, rows[index]),
                "unlocks": unlocked_by(index, column),
            }
        )

    return {
        "generated_by": "tools/export_level_index.py",
        "sources": {
            "exe": {
                "path": str(EXE_REL).replace("\\", "/"),
                "size": len(image.data),
                "sha256": sha256(exe),
                "column_table": "0x%08x" % COLUMN_TABLE_VA,
                "row_table": "0x%08x" % ROW_TABLE_VA,
                "difficulty_table": "0x%08x" % DIFFICULTY_TABLE_VA,
            },
            "levels_dir": str(LEVELS_DIR_REL).replace("\\", "/"),
        },
        "tree": {
            "entry_count": TREE_ENTRY_COUNT,
            "node_size": list(NODE_SIZE),
            "back_button_position": list(BACK_BUTTON_POSITION),
            "back_button_id": BACK_BUTTON_ID,
        },
        "levels": levels,
    }


def check(root: Path, index: dict) -> int:
    failures = []
    output = root / OUTPUT_REL
    if not output.is_file():
        failures.append(f"{OUTPUT_REL} is missing")
    elif json.loads(output.read_text(encoding="utf-8")) != index:
        failures.append(f"{OUTPUT_REL} is stale")

    levels = index["levels"]
    if len(levels) != LEVEL_COUNT:
        failures.append(f"{len(levels)} levels, expected {LEVEL_COUNT}")

    # Every level bar the root is reachable, and the root is reachable from nowhere.
    reached = set()
    for level in levels:
        reached.update(level["unlocks"])
    missing = sorted(set(range(2, LEVEL_COUNT + 1)) - reached)
    if missing:
        failures.append(f"levels unreachable from any other: {missing}")
    if 1 in reached:
        failures.append("level 1 is opened by another level, but it is the root")

    if [level["difficulty"] for level in levels] != [level["column"] - 1 for level in levels]:
        failures.append("difficulty is no longer the tree column minus one")

    positions = [tuple(level["node_position"]) for level in levels]
    if len(set(positions)) != len(positions):
        failures.append("two levels share a node position")
    for level in levels:
        x, y = level["node_position"]
        if not 0 <= x <= 800 - NODE_SIZE[0] or not 0 <= y <= 600 - NODE_SIZE[1]:
            failures.append(f"level {level['number']} sits outside the 800x600 screen at {x},{y}")

    for failure in failures:
        print(f"FAIL {failure}")
    if failures:
        return 1
    print(f"index.json matches sacked.exe and the level files ({len(levels)} levels)")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--check", action="store_true", help="Verify the exported index without writing")
    args = parser.parse_args()

    root = args.root.resolve()
    index = build(root)
    if args.check:
        return check(root, index)

    output = root / OUTPUT_REL
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(index, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Wrote {len(index['levels'])} levels to {OUTPUT_REL}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
