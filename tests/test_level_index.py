import json
import unittest
from pathlib import Path

from tools.export_level_index import (
    LEVEL_COUNT,
    TREE_ENTRY_COUNT,
    build,
    node_position,
    unlocked_by,
)

ROOT = Path(__file__).resolve().parents[1]
EXE = ROOT / "extract-sacked-assets/sacked/sacked.exe"
INDEX = ROOT / "resources/levels/index.json"


class TreeShapeTest(unittest.TestCase):
    """The triangle, checked without touching the executable."""

    def test_a_column_holds_as_many_entries_as_its_number(self):
        # Columns 1..6 hold 1+2+3+4+5+6 = 21 entries, which is every level; column 7 is the
        # empty tail that explains the 28-record highscore table.
        self.assertEqual(sum(range(1, 7)), LEVEL_COUNT)
        self.assertEqual(sum(range(1, 8)), TREE_ENTRY_COUNT)

    def test_clearing_an_entry_opens_the_two_below_it(self):
        # sub_421F80: entry i in column c opens i + c and i + c + 1.
        self.assertEqual(unlocked_by(0, 1), [2, 3])
        self.assertEqual(unlocked_by(1, 2), [4, 5])
        self.assertEqual(unlocked_by(2, 2), [5, 6])

    def test_the_last_column_of_levels_opens_nothing(self):
        # Column 6's children land in column 7, which has no levels.
        for index in range(15, 21):
            self.assertEqual(unlocked_by(index, 6), [])

    def test_the_root_sits_where_sub_421f30_puts_it(self):
        self.assertEqual(node_position(1, 0), [40, 256])
        self.assertEqual(node_position(2, 0), [152, 216])
        self.assertEqual(node_position(2, 1), [152, 296])
        # The bottom of column 6, the lowest node on the screen.
        self.assertEqual(node_position(6, 5), [600, 456])


class ExportedIndexTest(unittest.TestCase):
    def setUp(self):
        if not INDEX.is_file():
            self.skipTest("resources/levels/index.json has not been exported")
        self.index = json.loads(INDEX.read_text(encoding="utf-8"))
        self.levels = self.index["levels"]

    def test_every_level_is_present_once_and_in_order(self):
        self.assertEqual([level["number"] for level in self.levels], list(range(1, LEVEL_COUNT + 1)))

    def test_level_one_matches_its_own_file(self):
        first = self.levels[0]
        self.assertEqual((first["width"], first["height"]), (16, 16))
        self.assertEqual(first["time_game"], {"time_limit_seconds": 360.0, "score_target": 4000})
        self.assertEqual(first["difficulty"], 0)

    def test_the_points_game_reads_the_s_file(self):
        # Level 1's S file is a shorter, cheaper run than its plain file.
        first = self.levels[0]
        self.assertNotEqual(first["time_game"], first["points_game"])
        self.assertEqual(first["points_game"], {"time_limit_seconds": 300.0, "score_target": 3000})

    def test_difficulty_is_the_tree_column_minus_one(self):
        for level in self.levels:
            self.assertEqual(level["difficulty"], level["column"] - 1)

    def test_no_level_shows_the_seventh_difficulty(self):
        # difficulty.6 belongs to the empty column, so it is unreachable in a shipped game.
        self.assertNotIn(6, [level["difficulty"] for level in self.levels])

    def test_every_level_but_the_first_is_reachable(self):
        reached = set()
        for level in self.levels:
            reached.update(level["unlocks"])
        self.assertEqual(reached, set(range(2, LEVEL_COUNT + 1)))

    def test_no_level_opens_the_root(self):
        self.assertFalse(any(1 in level["unlocks"] for level in self.levels))

    def test_every_node_fits_on_the_original_screen(self):
        width, height = self.index["tree"]["node_size"]
        for level in self.levels:
            x, y = level["node_position"]
            self.assertGreaterEqual(x, 0)
            self.assertGreaterEqual(y, 0)
            self.assertLessEqual(x + width, 800)
            self.assertLessEqual(y + height, 600)


@unittest.skipUnless(EXE.is_file(), "sacked.exe is not available")
class RebuildTest(unittest.TestCase):
    def test_the_exported_file_matches_a_fresh_build(self):
        if not INDEX.is_file():
            self.skipTest("resources/levels/index.json has not been exported")
        self.assertEqual(build(ROOT), json.loads(INDEX.read_text(encoding="utf-8")))


if __name__ == "__main__":
    unittest.main()
