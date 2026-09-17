import json
import struct
import unittest
from pathlib import Path

from tools.import_original_level import build_collision_grid, parse_info_data, parse_level_file


ROOT = Path(__file__).resolve().parents[1]
ORIGINAL_LEVEL = ROOT / "extract-sacked-assets/sacked/Levels/LEVEL_00.col"


class CollisionDataTests(unittest.TestCase):
    def test_rectangular_grid_keeps_movement_sight_and_room_flags_separate(self):
        payload = struct.pack("<6I", 0, 0x00070002, 0x00020001, 3, 0xC0090000, 1)
        grid = build_collision_grid(parse_info_data(payload, 6), 3, 2)
        self.assertEqual(grid["blocked_cells"], [[2, 0], [0, 1], [2, 1]])
        self.assertEqual(grid["sight_blocked_cells"], [[1, 0], [0, 1]])
        self.assertEqual(grid["room_ids"], [0, 7, 2, 0, 9, 0])

    def test_incomplete_or_oversized_chunks_are_rejected(self):
        for size in (0, 3, 7, 9, 12):
            with self.subTest(size=size), self.assertRaisesRegex(ValueError, "INFODATA"):
                parse_info_data(bytes(size), 2)

    def test_grid_rejects_inconsistent_dimensions(self):
        for width, height in ((0, 1), (1, 0), (-1, -1), (2, 2)):
            with self.subTest(width=width, height=height), self.assertRaises(ValueError):
                build_collision_grid([1], width, height)

    def test_committed_map_preserves_original_passages_and_decorative_exceptions(self):
        manifest = json.loads((ROOT / "resources/levels/level_1.json").read_text())
        grid = manifest["collision_grid"]
        blocked = {tuple(cell) for cell in grid["blocked_cells"]}
        sight_blocked = {tuple(cell) for cell in grid["sight_blocked_cells"]}
        self.assertEqual((grid["width"], grid["height"]), (16, 16))
        self.assertEqual(grid["source_chunk"], "INFODATA")
        self.assertEqual(len(blocked), 117)
        self.assertEqual(len(sight_blocked), 92)
        self.assertEqual(len(grid["room_ids"]), 256)
        self.assertTrue({(1, 1), (5, 4), (15, 6), (15, 8)} <= blocked)
        self.assertTrue({(1, 5), (1, 8), (3, 4), (4, 4), (8, 3), (12, 9)}.isdisjoint(blocked))
        self.assertIn((8, 3), sight_blocked)
        self.assertEqual(grid["room_ids"][8 * 16 + 1], 8)

    @unittest.skipUnless(ORIGINAL_LEVEL.is_file(), "Original game is a local, untracked reference")
    def test_manifest_matches_original_binary_and_blocks_every_original_wall(self):
        original = ORIGINAL_LEVEL.read_bytes()
        payload_start = original.index(b"INFODATA\x00") + len(b"INFODATA\x00")
        flags = struct.unpack_from("<256I", original, payload_start)
        expected = {(index % 16, index // 16) for index, value in enumerate(flags) if value & 1}
        manifest = json.loads((ROOT / "resources/levels/level_1.json").read_text())
        self.assertEqual({tuple(cell) for cell in manifest["collision_grid"]["blocked_cells"]}, expected)
        level = parse_level_file(ORIGINAL_LEVEL)
        self.assertEqual(level["info_data"], list(flags))
        walls = {(index % 16, index // 16) for index, value in enumerate(level["layers"]["LAYER1"]) if value}
        self.assertEqual(len(walls), 88)
        self.assertTrue(walls <= expected)
        self.assertEqual(len(expected - walls), 29)


if __name__ == "__main__":
    unittest.main()
