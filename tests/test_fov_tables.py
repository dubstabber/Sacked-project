import hashlib
import json
import unittest
from pathlib import Path

from tools.export_fov_tables import (
    ENTRY_COUNT,
    EXE_REL,
    OUTPUT_REL,
    SAMPLE_COUNT,
    TABLES_SHA1,
    build_tables,
    builder_constants,
    intersect,
    parse,
    read_exe,
    render,
    serialise,
    view_constants,
)


ROOT = Path(__file__).resolve().parents[1]


class FieldOfViewTableTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tables = parse((ROOT / OUTPUT_REL).read_text(encoding="utf-8"))

    def spans(self, r, j):
        _r, _j, start, count = self.tables["samples"][r * (r - 1) // 2 + j]
        return self.tables["entries"][start : start + count]

    def test_the_checked_in_tables_are_the_ones_the_reference_hashed(self):
        # The file alone rebuilds the original's four tables byte for byte, so this holds
        # without the executable.
        self.assertEqual(len(self.tables["samples"]), SAMPLE_COUNT)
        self.assertEqual(len(self.tables["entries"]), ENTRY_COUNT)
        self.assertEqual(hashlib.sha1(serialise(self.tables)).hexdigest(), TABLES_SHA1)

    def test_a_blocking_own_cell_shadows_the_whole_octant(self):
        # Sample 0 covers every minor texel on every row, which is why a selected agent
        # standing in a sight-blocking cell draws no tint at all.
        self.assertEqual(self.spans(1, 0), [(0, 56, k) for k in range(56)])

    def test_neighbouring_squares_leave_no_gap_between_their_shadows(self):
        # scenes/shared/field_of_view_mask.gd stamps a run of blocked samples on one row r as
        # one span per row k, from the first sample's a to the last one's b. That is exact
        # only because no span is empty and, along j, both ends never go back and the next
        # span starts no later than this one ends.
        for r in range(1, 57):
            rows = [self.spans(r, j) for j in range(r)]
            for offset in range(57 - r):
                for j in range(r):
                    a, b, _k = rows[j][offset]
                    self.assertLess(a, b, f"sample ({r}, {j}) row {offset + r - 1} is empty")
                    if j + 1 < r:
                        next_a, next_b, _k = rows[j + 1][offset]
                        self.assertLessEqual(a, next_a)
                        self.assertLessEqual(b, next_b)
                        self.assertLessEqual(next_a, b, f"a gap after sample ({r}, {j}) on row {offset + r - 1}")

    def test_farther_squares_shadow_no_more_and_leave_no_gap(self):
        # A blocked stretch of several rows r is stamped as one span per row k too, from the a
        # of the farthest row that reaches k to the b of the nearest. That is exact only because,
        # at the same j, the farther sample's a and b never lie past the nearer one's and the two
        # spans overlap. Sample (r + 1, j) covers rows r to 55, sample (r, j) rows r - 1 to 55.
        for r in range(1, 56):
            for j in range(r):
                near = self.spans(r, j)[1:]
                far = self.spans(r + 1, j)
                for (a, b, k), (far_a, far_b, far_k) in zip(near, far):
                    self.assertEqual(k, far_k)
                    self.assertLessEqual(far_a, a, f"sample ({r + 1}, {j}) starts past ({r}, {j}) on row {k}")
                    self.assertLessEqual(far_b, b, f"sample ({r + 1}, {j}) ends past ({r}, {j}) on row {k}")
                    self.assertLessEqual(a, far_b, f"a gap between samples ({r}, {j}) and ({r + 1}, {j}) on row {k}")

    def test_parallel_lines_answer_the_sentinel(self):
        self.assertEqual(intersect((0.0, 1.0), (10.0, 1.0), (0.0, 2.0), (5.0, 2.0), -1000.0), (-1000.0, -1000.0))

    @unittest.skipUnless((ROOT / EXE_REL).is_file(), f"{EXE_REL} is absent")
    def test_the_replay_writes_the_checked_in_file(self):
        data = read_exe(ROOT)
        tables = build_tables(builder_constants(data))
        self.assertEqual(render(tables, view_constants(data)), (ROOT / OUTPUT_REL).read_text(encoding="utf-8"))

    def test_the_file_carries_the_constants_beside_the_tables(self):
        # The gate, the diamond's reach, the sector constant, the texel scale and the shadow
        # walk's step, as float32 widened to double.
        data = json.loads((ROOT / OUTPUT_REL).read_text(encoding="utf-8"))
        self.assertEqual(data["gate_tiles"], 12.0)
        self.assertEqual(data["reach_tiles"], 7.0)
        self.assertEqual(data["sector_scale"], 0.022221999242901802)
        self.assertEqual(data["texels_per_tile"], 8.0)
        self.assertEqual(data["sample_step"], 0.125)


if __name__ == "__main__":
    unittest.main()
