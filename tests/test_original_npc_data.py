import json
import struct
import unittest
from pathlib import Path

from tools.import_original_level import (
    ObjectDefinition,
    build_npcs,
    find_startup_item,
    oriented_interaction_offset,
    parse_object_database,
)


ROOT = Path(__file__).resolve().parents[1]
ORIGINAL_LEVEL = ROOT / "extract-sacked-assets/sacked/Levels/LEVEL_00.col"
ORIGINAL_OBJECTS = ROOT / "extract-sacked-assets/sacked/CO_OBJECTS.DAT"


def item(instance_id, item_type, x, y):
    return {"instance_id": instance_id, "kind": item_type << 4, "x": x, "y": y}


def spawn(instance_id, spawn_id, x, y):
    return {"instance_id": instance_id, "spawn_id": spawn_id, "x": x, "y": y, "z": 0.0}


class OriginalNpcDataTests(unittest.TestCase):
    def test_interaction_offsets_follow_original_axis_swaps_and_signs(self):
        self.assertEqual(
            [oriented_interaction_offset((2.0, 3.0), variant) for variant in range(4)],
            [(2.0, 3.0), (3.0, 2.0), (-2.0, -3.0), (-3.0, -2.0)],
        )

    def test_workstation_search_uses_first_item_within_expanding_strict_radius(self):
        first = item(1, 152, 0.49, 0.0)
        nearest = item(2, 153, 0.1, 0.0)
        boundary = item(3, 154, 0.5, 0.0)
        items = [boundary, first, nearest]
        self.assertIs(find_startup_item(items, (152, 153, 154), set(), (0.0, 0.0), (0.5, 1.0)), first)
        self.assertIs(find_startup_item(items, (152, 153, 154), {1}, (0.0, 0.0), (0.5, 1.0)), nearest)
        self.assertIsNone(find_startup_item([boundary], (154,), set(), (0.0, 0.0), (0.5,)))

    def test_spawn_type_order_and_temporary_claims_determine_assignments(self):
        level = {
            "spawns": [spawn(3, 6, 0.0, 0.0), spawn(2, 4, 0.0, 0.0), spawn(1, 1, 0.0, 0.0)],
            "items": [item(10, 152, 0.2, 0.0), item(11, 153, 0.3, 0.0), item(12, 68, 0.0, 0.0), item(13, 70, 0.0, 0.0)],
        }
        definitions = {item_type << 4: ObjectDefinition(item_type << 4, category, "", "")
                       for item_type, category in ((152, 5), (153, 5), (68, 1), (70, 1))}
        npcs = build_npcs(level, definitions)
        self.assertEqual([npc["spawn_id"] for npc in npcs], [1, 4, 6])
        self.assertEqual([npc["assigned_workstation_instance_id"] for npc in npcs], [None, 10, 11])
        self.assertEqual([npc["assigned_chair_instance_id"] for npc in npcs], [None, 12, 13])

    def test_singleton_roles_and_repeatable_coworker_spawns(self):
        level = {"spawns": [spawn(index, kind, 0.0, 0.0) for index, kind in enumerate((0, 1, 1, 2, 2, 3, 3, 4, 4))], "items": []}
        self.assertEqual([npc["spawn_id"] for npc in build_npcs(level, {})], [1, 2, 3, 4, 4])

    def test_committed_level_has_original_three_npcs_and_workstations(self):
        manifest = json.loads((ROOT / "resources/levels/level_1.json").read_text())
        npcs = manifest["npcs"]
        self.assertEqual([npc["profile_id"] for npc in npcs], ["boss", "male-employee-1", "female-employee-1"])
        self.assertEqual([npc["tile_position"] for npc in npcs], [[1.0, 12.0], [3.0, 2.0], [6.0, 1.0]])
        self.assertEqual([npc["assigned_workstation_instance_id"] for npc in npcs], [None, 10, 14])
        self.assertEqual([npc["assigned_chair_instance_id"] for npc in npcs], [None, 9, 13])
        self.assertTrue(all(npc["initial_direction_index"] == 0 for npc in npcs))
        for npc in npcs:
            self.assertTrue((ROOT / npc["profile"].removeprefix("res://")).is_file())
        objects = {entry["instance_id"]: entry for entry in manifest["objects"]}
        self.assertEqual(objects[9]["interaction_tile_position"], [3.0, 2.0])
        self.assertEqual(objects[13]["interaction_tile_position"], [6.083333, 1.333333])
        self.assertEqual(objects[14]["interaction_tile_position"], [7.0, 1.333333])

    @unittest.skipUnless(ORIGINAL_LEVEL.is_file() and ORIGINAL_OBJECTS.is_file(), "Original game is a local, untracked reference")
    def test_spawn_coordinates_and_dat_offsets_match_binary_fields(self):
        manifest = json.loads((ROOT / "resources/levels/level_1.json").read_text())
        original = ORIGINAL_LEVEL.read_bytes()
        cursor = 0
        source_spawns = {}
        while (cursor := original.find(b"SPAWN\x00", cursor)) >= 0:
            kind, x, height, y, instance_id = struct.unpack_from("<IfffI", original, cursor + 6)
            source_spawns[instance_id] = (kind, [x, y], height)
            cursor += 6
        for npc in manifest["npcs"]:
            self.assertEqual((npc["spawn_id"], npc["tile_position"], npc["height"]), source_spawns[npc["instance_id"]])
        definitions = parse_object_database(ORIGINAL_OBJECTS)
        self.assertEqual(definitions[0x00060980].interaction_offset, (1.0, 0.0))
        self.assertEqual(definitions[0x01000480].interaction_offset, (-1.0, 0.0))
        self.assertAlmostEqual(definitions[0x03090130].interaction_offset[0], 0.7)


if __name__ == "__main__":
    unittest.main()
