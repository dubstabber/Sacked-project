import json
import struct
import unittest
from pathlib import Path

from tools.export_npc_profiles import (
    CANDIDATE_SCAN_VA,
    EXE_REL,
    IMAGE_BASE,
    OUTPUT_REL,
    PROFILE_LOADER_VA,
    build_table,
    read_exe,
    replay_room_masks,
    room_masks,
)
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
ORIGINAL_EXE = ROOT / EXE_REL


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
        # sub_406AF0 drains the SPAWN list by type in ascending order -- one call each for
        # types 0..3, then a loop per type for 4..7 -- and sub_413320 returns the first
        # record still carrying that type, so file order only breaks ties inside a type.
        # Records are listed here out of type order to prove the sort, not the file.
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
        # sub_406AF0 gives types 1, 2 and 3 a bare `if` and types 4..7 a while loop, so a
        # second boss, secretary or janitor record is never consumed. Level 7 ships two
        # secretary records and the original creates one secretary.
        level = {"spawns": [spawn(index, kind, 0.0, 0.0) for index, kind in enumerate((0, 1, 1, 2, 2, 3, 3, 4, 4))], "items": []}
        self.assertEqual([npc["spawn_id"] for npc in build_npcs(level, {})], [1, 2, 3, 4, 4])

    def test_the_boss_and_the_janitor_are_given_no_desk(self):
        # CObj_Boss (sub_404B90) and CObj_Housekeeper (sub_404D20) call sub_418790, which
        # zeroes both the workstation and the chair, where every other agent calls
        # sub_4185B0 and claims one.
        level = {
            "spawns": [spawn(index, kind, 0.0, 0.0) for index, kind in enumerate((1, 2, 3, 4))],
            "items": [item(10, 152, 0.1, 0.0), item(11, 153, 0.2, 0.0),
                      item(12, 68, 0.0, 0.0), item(13, 70, 0.0, 0.0)],
        }
        definitions = {item_type << 4: ObjectDefinition(item_type << 4, category, "", "")
                       for item_type, category in ((152, 5), (153, 5), (68, 1), (70, 1))}
        npcs = {npc["spawn_id"]: npc for npc in build_npcs(level, definitions)}
        for spawn_id in (1, 3):
            self.assertIsNone(npcs[spawn_id]["assigned_workstation_instance_id"])
            self.assertIsNone(npcs[spawn_id]["assigned_chair_instance_id"])
        # The desks the two of them skipped are still there for the agents that do claim.
        self.assertEqual(npcs[2]["assigned_workstation_instance_id"], 10)
        self.assertEqual(npcs[4]["assigned_workstation_instance_id"], 11)

    def test_level_7_ships_two_secretaries_and_only_one_is_created(self):
        from tools.import_original_level import level_paths, parse_level_file

        level = parse_level_file(ROOT / level_paths(7).source_rel)
        secretaries = [entry for entry in level["spawns"] if int(entry["spawn_id"]) == 2]
        self.assertEqual(len(secretaries), 2)
        built = [npc for npc in build_npcs(level, parse_object_database(ORIGINAL_OBJECTS)) if npc["spawn_id"] == 2]
        self.assertEqual(len(built), 1)
        # The one that survives is the first in the file, which is what sub_413320 returns.
        self.assertEqual(built[0]["instance_id"], int(secretaries[0]["instance_id"]))

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


def initialiser(body: bytes, start: int = 0x401000) -> bytes:
    """A fake image whose code at `start` calls sub_4184B0, runs `body`, then calls sub_4187F0."""
    code = bytearray()

    def call(target: int) -> None:
        code.extend(b"\xE8" + struct.pack("<i", target - (start + len(code) + 5)))

    code.extend(b"\x53\x8B\xD9")  # push ebx; mov ebx, ecx
    call(PROFILE_LOADER_VA)
    code.extend(body)
    call(CANDIDATE_SCAN_VA)
    image = bytearray(start - IMAGE_BASE)
    image.extend(code)
    return bytes(image)


def store(offset: int, value: int) -> bytes:
    return b"\xC7\x83" + struct.pack("<II", offset, value)


class RoomMaskReplayTests(unittest.TestCase):
    # sub_41A830's own sequence: eax carries 11 into the first two masks.
    JANITOR = (b"\xB8" + struct.pack("<I", 11) + b"\x8B\xCB"
               + b"\x89\x83" + struct.pack("<I", 1864) + b"\x89\x83" + struct.pack("<I", 1868)
               + store(1872, 76) + store(1876, 22) + store(1880, 128) + store(1884, 92)
               + store(1888, 12) + store(1892, 72))

    def test_replays_the_three_mov_forms_between_the_two_calls(self):
        self.assertEqual(replay_room_masks(initialiser(self.JANITOR), 0x401000), [11, 11, 76, 22, 128, 92, 12, 72])

    def test_refuses_anything_outside_the_whitelist(self):
        with self.assertRaises(SystemExit):
            replay_room_masks(initialiser(b"\x90" + self.JANITOR), 0x401000)

    def test_refuses_a_mask_left_unwritten(self):
        with self.assertRaises(SystemExit):
            replay_room_masks(initialiser(self.JANITOR[: -len(store(1892, 72))]), 0x401000)


@unittest.skipUnless(ORIGINAL_EXE.is_file(), "Original game is a local, untracked reference")
class OriginalRoomMaskTests(unittest.TestCase):
    def test_each_archetype_has_its_own_initialisers_masks(self):
        # sub_41E2C0 and sub_41A830 differ from the coworkers' sub_419C10 in goals 3 and 5.
        masks = {archetype: (hex(address), rooms) for archetype, (address, rooms) in room_masks(read_exe(ROOT)).items()}
        self.assertEqual(masks, {
            "boss": ("0x4196a0", [10, 266, 328, 256, 128, 76, 264, 72]),
            "secretary": ("0x41e2c0", [11, 11, 76, 4, 128, 332, 12, 72]),
            "janitor": ("0x41a830", [11, 11, 76, 22, 128, 92, 12, 72]),
            "coworker": ("0x419c10", [11, 11, 76, 5, 128, 76, 12, 72]),
        })

    def test_committed_profile_table_is_current(self):
        committed = json.loads((ROOT / OUTPUT_REL).read_text(encoding="utf-8"))
        self.assertEqual(committed, build_table(read_exe(ROOT)))


if __name__ == "__main__":
    unittest.main()
