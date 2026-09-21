import json
import struct
import unittest
from pathlib import Path

from tools.import_original_level import (
    CONDITION_SCORE_RANGE,
    CONDITION_TIME_RANGE,
    parse_condition,
)


ROOT = Path(__file__).resolve().parents[1]
LEVELS = ROOT / "extract-sacked-assets/sacked/Levels"
LEVEL_COUNT = 21


def condition_file(payload: bytes) -> bytes:
    """A container holding one CONDITION chunk, laid out as parse_chunk_at expects."""
    name = b"CONDITION\x00"
    return struct.pack("<HI", len(name), len(payload)) + name + payload + struct.pack("<II", 0, 0)


class ConditionChunkTests(unittest.TestCase):
    def test_accepts_the_range_the_engine_accepts(self):
        for time_limit, target in (CONDITION_TIME_RANGE[0], 1), (CONDITION_TIME_RANGE[1], 99999):
            with self.subTest(time_limit=time_limit, target=target):
                parsed = parse_condition(condition_file(struct.pack("<fI", time_limit, target)))
                self.assertEqual(parsed, {"time_limit_seconds": time_limit, "score_target": target})

    def test_rejects_values_the_engine_would_have_ignored(self):
        # sub_412FB0 keeps the value it already had rather than storing one of these; the
        # importer has no previous value to keep, so it refuses the file instead.
        for time_limit, target in (0.5, 4000), (3600.5, 4000), (360.0, 0), (360.0, 100000):
            with self.subTest(time_limit=time_limit, target=target):
                with self.assertRaisesRegex(ValueError, "CONDITION"):
                    parse_condition(condition_file(struct.pack("<fI", time_limit, target)))

    def test_rejects_a_payload_that_is_not_eight_bytes(self):
        for size in (0, 4, 7, 9, 12):
            with self.subTest(size=size), self.assertRaisesRegex(ValueError, "CONDITION"):
                parse_condition(condition_file(bytes(size)))

    def test_rejects_a_file_without_the_chunk(self):
        with self.assertRaisesRegex(ValueError, "CONDITION"):
            parse_condition(b"#ODIN_ENGINE" + bytes(64))


@unittest.skipUnless(LEVELS.is_dir(), "Original game is a local, untracked reference")
class OriginalLevelConditionTests(unittest.TestCase):
    """Every shipped level, not just the one the port imports.

    sub_408D00 builds the path from the game mode: the plain file is the time game and the
    S file the points game. See docs/game-rules-reference.md.
    """

    def level_files(self):
        for index in range(LEVEL_COUNT):
            yield index, LEVELS / f"LEVEL_{index:02d}.col", LEVELS / f"LEVEL_{index:02d}s.col"

    def test_every_level_ships_a_file_for_both_modes(self):
        for index, time_file, points_file in self.level_files():
            with self.subTest(level=index):
                self.assertTrue(time_file.is_file(), f"{time_file.name} is missing")
                self.assertTrue(points_file.is_file(), f"{points_file.name} is missing")
        self.assertEqual(len(list(LEVELS.glob("*.col"))), LEVEL_COUNT * 2)

    def test_every_condition_parses_inside_the_accepted_range(self):
        for index, time_file, points_file in self.level_files():
            for path in (time_file, points_file):
                with self.subTest(level=index, file=path.name):
                    condition = parse_condition(path.read_bytes())
                    self.assertGreaterEqual(condition["time_limit_seconds"], CONDITION_TIME_RANGE[0])
                    self.assertLessEqual(condition["time_limit_seconds"], CONDITION_TIME_RANGE[1])
                    self.assertGreaterEqual(condition["score_target"], CONDITION_SCORE_RANGE[0])
                    self.assertLessEqual(condition["score_target"], CONDITION_SCORE_RANGE[1])

    def test_the_two_modes_never_carry_the_same_condition(self):
        # The S file is a second CONDITION for the same map rather than a second campaign,
        # and no level leaves the two identical.
        for index, time_file, points_file in self.level_files():
            with self.subTest(level=index):
                self.assertNotEqual(
                    parse_condition(time_file.read_bytes()),
                    parse_condition(points_file.read_bytes()),
                )

    def test_the_imported_level_keeps_both_of_its_conditions(self):
        manifest = json.loads((ROOT / "resources/levels/level_1.json").read_text())
        index = manifest["original_level_index"]
        _, time_file, points_file = list(self.level_files())[index]
        self.assertEqual(manifest["conditions"]["time"], parse_condition(time_file.read_bytes()))
        self.assertEqual(manifest["conditions"]["points"], parse_condition(points_file.read_bytes()))
        self.assertEqual(manifest["conditions"]["time"], {"time_limit_seconds": 360.0, "score_target": 4000})
        self.assertEqual(manifest["conditions"]["points"], {"time_limit_seconds": 300.0, "score_target": 3000})


if __name__ == "__main__":
    unittest.main()
