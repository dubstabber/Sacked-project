import tempfile
import unittest
from pathlib import Path

from tools.import_original_level import (
    LEVEL_COUNT,
    LevelBuild,
    LevelPaths,
    build_manifest,
    check_texture_union,
    imported_level_numbers,
    level_paths,
    load_import_context,
    remove_stale_object_prefabs,
    remove_stale_object_textures,
    union_destinations,
)


ROOT = Path(__file__).resolve().parents[1]

# The S files of these levels move items, spawns or layers as well as CONDITION, so one
# scene cannot serve both game modes. Numbers are playable levels, not original indices.
DIVERGENT_POINTS_LEVELS = (5, 8, 11, 12, 19, 20)


def build(number: int, context) -> LevelBuild:
    paths = level_paths(number)
    manifest, source_to_dest = build_manifest(ROOT, paths, context)
    return LevelBuild(paths=paths, manifest=manifest, source_to_dest=source_to_dest)


_CAMPAIGN = None


def campaign():
    """Every level built once: resolving 21 levels' textures is far too slow to repeat."""
    global _CAMPAIGN
    if _CAMPAIGN is None:
        context = load_import_context(ROOT)
        builds, refused = {}, []
        for number in range(1, LEVEL_COUNT + 1):
            try:
                builds[number] = build(number, context)
            except ValueError:
                refused.append(number)
        _CAMPAIGN = (builds, tuple(refused))
    return _CAMPAIGN


class LevelPathTests(unittest.TestCase):
    def test_maps_a_playable_level_onto_its_original_index(self):
        paths = level_paths(1)
        self.assertEqual(paths.index, 0)
        self.assertEqual(paths.source_rel.name, "LEVEL_00.col")
        self.assertEqual(paths.points_source_rel.name, "LEVEL_00s.col")
        self.assertEqual(paths.text_rel.name, "Level_00.txt")
        self.assertEqual(paths.manifest_rel.as_posix(), "resources/levels/level_1.json")
        self.assertEqual(paths.scene_rel.as_posix(), "scenes/level_1.tscn")

    def test_every_level_the_tree_accepts_exists_on_disk(self):
        for number in range(1, LEVEL_COUNT + 1):
            with self.subTest(number=number):
                paths = level_paths(number)
                self.assertTrue((ROOT / paths.source_rel).is_file())
                self.assertTrue((ROOT / paths.points_source_rel).is_file())
                self.assertTrue((ROOT / paths.text_rel).is_file())

    def test_rejects_levels_outside_the_original_range(self):
        for number in (-1, 0, LEVEL_COUNT + 1, 99):
            with self.subTest(number=number):
                with self.assertRaisesRegex(ValueError, "1..%d" % LEVEL_COUNT):
                    level_paths(number)


class ImportedLevelDiscoveryTests(unittest.TestCase):
    def test_orders_numerically_rather_than_lexically(self):
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            (root / "resources/levels").mkdir(parents=True)
            for number in (10, 2, 1, 21):
                (root / "resources/levels" / ("level_%d.json" % number)).write_text("{}")
            self.assertEqual(imported_level_numbers(root), [1, 2, 10, 21])

    def test_ignores_files_that_are_not_levels(self):
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            (root / "resources/levels").mkdir(parents=True)
            (root / "resources/levels/level_1.json").write_text("{}")
            for noise in ("level_0.json", "level_22.json", "level_x.json", "notes.json"):
                (root / "resources/levels" / noise).write_text("{}")
            self.assertEqual(imported_level_numbers(root), [1])

    def test_falls_back_to_level_one_when_nothing_is_imported(self):
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            (root / "resources/levels").mkdir(parents=True)
            self.assertEqual(imported_level_numbers(root), [1])


class PointsFileGuardTests(unittest.TestCase):
    """The importer takes only CONDITION from the S file, so the rest has to agree."""

    @classmethod
    def setUpClass(cls):
        cls.context = load_import_context(ROOT)

    def test_accepts_the_levels_whose_s_file_only_changes_condition(self):
        for number in (1, 2):
            with self.subTest(number=number):
                manifest, _ = build_manifest(ROOT, level_paths(number), self.context)
                self.assertNotEqual(manifest["conditions"]["time"], manifest["conditions"]["points"])

    def test_refuses_every_level_whose_s_file_moves_more_than_condition(self):
        for number in DIVERGENT_POINTS_LEVELS:
            with self.subTest(number=number):
                with self.assertRaisesRegex(ValueError, "beyond CONDITION"):
                    build_manifest(ROOT, level_paths(number), self.context)

    def test_refuses_no_other_level(self):
        self.assertEqual(campaign()[1], DIVERGENT_POINTS_LEVELS)


class TextureUnionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.context = load_import_context(ROOT)

    def test_every_importable_level_agrees_on_what_each_slug_means(self):
        builds = campaign()[0]
        self.assertGreater(len(builds), 1)
        check_texture_union(builds)

    def test_reports_a_slug_that_two_levels_disagree_about(self):
        one = build(1, self.context)
        entry = dict(one.manifest["objects"][0])
        entry["pivot"] = [entry["pivot"][0] + 1, entry["pivot"][1]]
        forged = LevelBuild(
            paths=level_paths(2),
            manifest={"objects": [entry]},
            source_to_dest={},
        )
        with self.assertRaisesRegex(ValueError, "disagree between levels"):
            check_texture_union({1: one, 2: forged})


class PruningTests(unittest.TestCase):
    """Pruning runs against the union of every imported level, never one manifest alone."""

    def make_root(self):
        root = Path(tempfile.mkdtemp())
        (root / "images/objects/states").mkdir(parents=True)
        (root / "scenes/objects").mkdir(parents=True)
        return root

    def union_of(self, *names):
        return {Path("src/%s.png" % name): Path("images/objects/%s.png" % name) for name in names}

    def test_keeps_a_texture_only_another_level_needs(self):
        root = self.make_root()
        for name in ("desk", "fridge", "gone"):
            (root / "images/objects" / (name + ".png")).write_text("x")
            (root / "images/objects" / (name + "-depth.png")).write_text("x")
        remove_stale_object_textures(root, self.union_of("desk", "fridge"))
        self.assertTrue((root / "images/objects/desk.png").is_file())
        self.assertTrue((root / "images/objects/fridge.png").is_file())
        self.assertTrue((root / "images/objects/fridge-depth.png").is_file())
        self.assertFalse((root / "images/objects/gone.png").is_file())
        self.assertFalse((root / "images/objects/gone-depth.png").is_file())

    def test_never_touches_the_state_frames_another_tool_owns(self):
        root = self.make_root()
        (root / "images/objects/desk.png").write_text("x")
        frame = root / "images/objects/states/desk-destroy-1-000.png"
        frame.write_text("x")
        remove_stale_object_textures(root, self.union_of("desk"))
        self.assertTrue(frame.is_file())

    def test_prunes_prefabs_against_the_same_union(self):
        root = self.make_root()
        for name in ("desk", "gone"):
            (root / "scenes/objects" / (name + ".tscn")).write_text("x")
        remove_stale_object_prefabs(root, self.union_of("desk"))
        self.assertTrue((root / "scenes/objects/desk.tscn").is_file())
        self.assertFalse((root / "scenes/objects/gone.tscn").is_file())

    def test_union_prefers_nothing_and_merges_every_level(self):
        a = LevelBuild(level_paths(1), {"objects": []}, self.union_of("desk"))
        b = LevelBuild(level_paths(2), {"objects": []}, self.union_of("fridge"))
        self.assertEqual(
            sorted(path.name for path in union_destinations({1: a, 2: b}).values()),
            ["desk.png", "fridge.png"],
        )


if __name__ == "__main__":
    unittest.main()
