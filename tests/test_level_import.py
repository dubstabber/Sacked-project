import tempfile
import unittest
from pathlib import Path
from unittest import mock

from tools.import_original_level import (
    LEVEL_COUNT,
    PARKED_RECORDS,
    LevelBuild,
    LevelPaths,
    build_level,
    build_npcs,
    check_texture_union,
    every_build,
    imported_level_numbers,
    imported_manifest_paths,
    level_paths,
    load_import_context,
    parked_record_names,
    parse_level_file,
    points_file_differences,
    remove_stale_object_prefabs,
    remove_stale_object_textures,
    union_destinations,
)


ROOT = Path(__file__).resolve().parents[1]

# The S files of these levels move items, spawns or layers as well as CONDITION, so one
# scene cannot serve both game modes and each gets a second build from its S file.
# Numbers are playable levels, not original indices, and the values are the chunks that
# differ, measured from the shipped files.
DIVERGENT_POINTS_LEVELS = (5, 8, 11, 12, 19, 20)
DIVERGENT_POINTS_KEYS = {
    5: ["items"],
    8: ["layers"],
    11: ["items", "spawns"],
    12: ["items"],
    19: ["items", "spawns"],
    20: ["items"],
}
# Only two of the six change how many objects the map holds; the rest move them.
DIVERGENT_OBJECT_COUNTS = {11: (190, 191), 19: (407, 406)}


def build(number: int, context) -> LevelBuild:
    return build_level(ROOT, number, context)


_CAMPAIGN = None


def campaign():
    """Every level built once: resolving 21 levels' textures is far too slow to repeat."""
    global _CAMPAIGN
    if _CAMPAIGN is None:
        context = load_import_context(ROOT)
        builds = {number: build(number, context) for number in range(1, LEVEL_COUNT + 1)}
        divergent = tuple(number for number in sorted(builds) if builds[number].points_variant is not None)
        _CAMPAIGN = (builds, divergent)
    return _CAMPAIGN


class LevelPathTests(unittest.TestCase):
    def test_maps_a_playable_level_onto_its_original_index(self):
        paths = level_paths(1)
        self.assertEqual(paths.index, 0)
        self.assertFalse(paths.points)
        self.assertEqual(paths.label, "1")
        self.assertEqual(paths.source_rel.name, "LEVEL_00.col")
        self.assertEqual(paths.points_source_rel.name, "LEVEL_00s.col")
        self.assertEqual(paths.text_rel.name, "Level_00.txt")
        self.assertEqual(paths.manifest_rel.as_posix(), "resources/levels/level_1.json")
        self.assertEqual(paths.scene_rel.as_posix(), "scenes/level_1.tscn")

    def test_a_points_variant_reads_the_s_file_and_writes_beside_its_level(self):
        paths = level_paths(5, points=True)
        self.assertEqual(paths.index, 4)
        self.assertTrue(paths.points)
        self.assertEqual(paths.label, "5s")
        # The variant's layout comes from the S file, which is also where its own
        # CONDITION comes from.
        self.assertEqual(paths.source_rel.name, "LEVEL_04s.col")
        self.assertEqual(paths.points_source_rel.name, "LEVEL_04s.col")
        self.assertEqual(paths.text_rel.name, "Level_04.txt")
        self.assertEqual(paths.manifest_rel.as_posix(), "resources/levels/level_5s.json")
        self.assertEqual(paths.scene_rel.as_posix(), "scenes/level_5s.tscn")

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

    def test_a_points_variant_belongs_to_a_level_rather_than_being_one(self):
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            (root / "resources/levels").mkdir(parents=True)
            for leaf in ("level_1.json", "level_5.json", "level_5s.json"):
                (root / "resources/levels" / leaf).write_text("{}")
            self.assertEqual(imported_level_numbers(root), [1, 5])
            self.assertEqual(
                [path.name for path in imported_manifest_paths(root)],
                ["level_1.json", "level_5.json", "level_5s.json"],
            )

    def test_falls_back_to_level_one_when_nothing_is_imported(self):
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            (root / "resources/levels").mkdir(parents=True)
            self.assertEqual(imported_level_numbers(root), [1])


class PointsVariantTests(unittest.TestCase):
    """A level whose S file moves the map gets a second build, and no other level does."""

    @classmethod
    def setUpClass(cls):
        cls.context = load_import_context(ROOT)

    def test_a_level_whose_s_file_only_changes_condition_keeps_one_build(self):
        for number in (1, 2):
            with self.subTest(number=number):
                built = build(number, self.context)
                self.assertIsNone(built.points_variant)
                self.assertNotIn("game_mode", built.manifest)
                self.assertNotEqual(built.manifest["conditions"]["time"], built.manifest["conditions"]["points"])

    def test_only_the_six_measured_levels_diverge(self):
        self.assertEqual(campaign()[1], DIVERGENT_POINTS_LEVELS)

    def test_each_divergent_level_names_the_chunks_it_moves(self):
        builds = campaign()[0]
        for number, keys in DIVERGENT_POINTS_KEYS.items():
            with self.subTest(number=number):
                paths = builds[number].paths
                from tools.import_original_level import parse_level_file

                level = parse_level_file(ROOT / paths.source_rel)
                points = parse_level_file(ROOT / paths.points_source_rel)
                self.assertEqual(points_file_differences(level, points), keys)

    def test_a_variant_is_built_from_the_s_file_and_shares_its_level_conditions(self):
        builds = campaign()[0]
        for number in DIVERGENT_POINTS_LEVELS:
            with self.subTest(number=number):
                built = builds[number]
                variant = built.points_variant
                self.assertIsNotNone(variant)
                self.assertEqual(variant.manifest["game_mode"], "points")
                self.assertEqual(Path(variant.manifest["source"]).name, "LEVEL_%02ds.col" % (number - 1))
                # Both builds carry both CONDITIONs, so a restart keeps the mode's target.
                self.assertEqual(variant.manifest["conditions"], built.manifest["conditions"])
                self.assertEqual(variant.paths.manifest_rel.name, "level_%ds.json" % number)
                # The map really differs, which is the whole reason for the second scene.
                # Level 8 moves floor tiles and the other five move objects.
                self.assertNotEqual(
                    (variant.manifest["objects"], variant.manifest["tile_layers"]),
                    (built.manifest["objects"], built.manifest["tile_layers"]),
                )

    def test_the_two_levels_that_change_their_object_count(self):
        builds = campaign()[0]
        for number, (plain, points) in DIVERGENT_OBJECT_COUNTS.items():
            with self.subTest(number=number):
                self.assertEqual(len(builds[number].manifest["objects"]), plain)
                self.assertEqual(len(builds[number].points_variant.manifest["objects"]), points)

    def test_level_8_moves_floor_tiles_rather_than_objects(self):
        built = campaign()[0][8]
        variant = built.points_variant
        self.assertEqual(len(variant.manifest["objects"]), len(built.manifest["objects"]))
        floors = [layer for layer in built.manifest["tile_layers"] if layer["name"] == "FloorTileMapLayer"]
        variant_floors = [layer for layer in variant.manifest["tile_layers"] if layer["name"] == "FloorTileMapLayer"]
        self.assertNotEqual(floors[0]["cells"], variant_floors[0]["cells"])

    def test_every_build_yields_each_level_then_its_variant(self):
        builds = campaign()[0]
        labels = [built.paths.label for built in every_build(builds)]
        self.assertEqual(labels[:3], ["1", "2", "3"])
        for number in DIVERGENT_POINTS_LEVELS:
            index = labels.index(str(number))
            self.assertEqual(labels[index + 1], "%ds" % number)


def on_the_original_map(item, width: int, height: int) -> bool:
    """The original's own map-membership test for an item.

    sub_4187F0 looks an item up with sub_412AE0((int16)_ftol(x + 0.5), (int16)_ftol(y + 0.5)),
    which answers 0 outside [0, w) x [0, h) (0x412AE9, 0x412B0F). int() truncates toward zero
    like _ftol.
    """
    return 0 <= int(item["x"] + 0.5) < width and 0 <= int(item["y"] + 0.5) < height


class ParkedRecordTests(unittest.TestCase):
    """The original keeps every ITEM wherever it stands; the port leaves out only what the
    original's 4:3 view never shows."""

    @classmethod
    def setUpClass(cls):
        cls.context = load_import_context(ROOT)
        cls.files = {}
        for number in range(1, LEVEL_COUNT + 1):
            for points in (False, True):
                paths = level_paths(number, points=points)
                cls.files[paths.label] = (paths, parse_level_file(ROOT / paths.source_rel))

    def test_only_three_records_in_the_campaign_stand_off_the_map(self):
        # Every one of the other 224 records past an edge is wall-hung and overhangs by at
        # most a third of a tile, which the original's lookup still rounds onto the map.
        off_map = {
            (label, item["record_name"])
            for label, (_, level) in self.files.items()
            for item in level["items"]
            if not on_the_original_map(item, level["width"], level["height"])
        }
        self.assertEqual(off_map, {("3", "ITEM22"), ("3s", "ITEM22"), ("11s", "ITEM132")})

    def test_only_level_3s_spare_monitor_is_parked(self):
        self.assertEqual(set(PARKED_RECORDS), {("LEVEL_02.col", "ITEM22"), ("LEVEL_02s.col", "ITEM22")})
        for label in ("3", "3s"):
            with self.subTest(label=label):
                paths, level = self.files[label]
                self.assertEqual(parked_record_names(paths.source_rel.name, level["items"]), {"ITEM22"})
        # LEVEL_10s.col's cigarettes are off the map too, but the original shows them whole at
        # 4:3, so they stay.
        paths, level = self.files["11s"]
        self.assertEqual(parked_record_names(paths.source_rel.name, level["items"]), set())
        variant = campaign()[0][11].points_variant.manifest
        self.assertIn(140, [entry["instance_id"] for entry in variant["objects"]])
        self.assertNotIn("parked_items", variant)

    def test_a_parked_record_that_no_longer_matches_fails_the_import(self):
        paths, level = self.files["3"]
        for field, value in (("x", -4.0), ("y", 15.0), ("kind", 0x00060990)):
            with self.subTest(field=field):
                items = [dict(item, **{field: value}) if item["record_name"] == "ITEM22" else item for item in level["items"]]
                with self.assertRaisesRegex(ValueError, "PARKED_RECORDS"):
                    parked_record_names(paths.source_rel.name, items)
        without = [item for item in level["items"] if item["record_name"] != "ITEM22"]
        with self.assertRaisesRegex(ValueError, "PARKED_RECORDS"):
            parked_record_names(paths.source_rel.name, without)

    def test_level_3_leaves_the_monitor_out_of_its_scene_but_not_out_of_the_npc_search(self):
        manifest = campaign()[0][3].manifest
        self.assertEqual(len(manifest["objects"]), 122)
        self.assertNotIn(30, [entry["instance_id"] for entry in manifest["objects"]])
        self.assertEqual(
            manifest["parked_items"],
            [
                {
                    "record_name": "ITEM22",
                    "instance_id": 30,
                    "kind": "0x00060980",
                    "sprite_name": "MONITOR&TASTATUR#FRONTAL",
                    "tile_position": [-5.0, 16.0],
                }
            ],
        )
        # sub_4185B0's startup search runs over every item, and still hands out the desks
        # and chairs it did before the monitor was parked.
        self.assertEqual(manifest["npcs"], build_npcs(self.files["3"][1], self.context.object_db))
        self.assertEqual(
            [(npc["assigned_workstation_instance_id"], npc["assigned_chair_instance_id"]) for npc in manifest["npcs"]],
            [(118, 112), (33, 29), (117, 111), (31, 26), (32, 25)],
        )

    def test_no_other_build_parks_anything(self):
        for built in every_build(campaign()[0]):
            with self.subTest(label=built.paths.label):
                self.assertEqual("parked_items" in built.manifest, built.paths.label == "3")

    def test_wall_hung_items_that_overhang_the_edge_stay(self):
        builds = campaign()[0]
        for number, instance_id, sprite_name in (
            (1, 21, "FENSTER01"),  # ITEM13 at (-0.052, 5.885)
            (11, 8, "EINGANG"),  # ITEM0 at (-0.333, 10.083)
            (15, 114, "BILD01"),  # ITEM106 at (-0.333, 8.458)
            (20, 83, "FAHRSTUHL"),  # ITEM75 at (6.094, -0.260)
        ):
            with self.subTest(number=number):
                objects = {entry["instance_id"]: entry for entry in builds[number].manifest["objects"]}
                self.assertEqual(objects[instance_id]["sprite_name"], sprite_name)

    def test_an_npc_assigned_a_parked_item_fails_the_import(self):
        # Level 1's ITEM2 is the desk Npc079 sits at; parking it would leave the builder an
        # assignment with no node to point at.
        desk = next(item for item in self.files["1"][1]["items"] if item["record_name"] == "ITEM2")
        entry = {("LEVEL_00.col", "ITEM2"): (int(desk["kind"]), float(desk["x"]), float(desk["y"]))}
        with mock.patch.dict(PARKED_RECORDS, entry):
            with self.assertRaisesRegex(ValueError, "assigned parked item 10"):
                build(1, self.context)


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
