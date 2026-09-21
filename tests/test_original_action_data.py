import json
import unittest
from pathlib import Path

from tools.export_action_table import (
    ACTION_COUNT,
    EXE_REL,
    ICON_COUNT,
    OUTPUT_REL,
    RECORD_STRIDE,
    TABLE_VA,
    Image,
    build,
    object_action_ids,
    trace_records,
)

ROOT = Path(__file__).resolve().parents[1]
ORIGINAL_EXE = ROOT / EXE_REL


@unittest.skipUnless(ORIGINAL_EXE.is_file(), "original sacked.exe is not available")
class TraceActionTableTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.image = Image(ORIGINAL_EXE)
        cls.records, cls.interpreter = trace_records(cls.image)
        cls.table = build(ROOT)
        cls.actions = {action["id"]: action for action in cls.table["actions"]}

    def test_initializer_is_pure_straight_line_stores(self):
        # Every store must land inside the table, or the replay is reading the wrong function.
        self.assertEqual(len(self.records), ACTION_COUNT)
        self.assertEqual(self.interpreter.stores, 3588)
        self.assertEqual(self.interpreter.instructions, 3779)
        written = self.interpreter.memory.keys()
        self.assertGreaterEqual(min(written), TABLE_VA)
        self.assertLess(max(written), TABLE_VA + ACTION_COUNT * RECORD_STRIDE)

    def test_known_action_names(self):
        self.assertEqual(self.actions[0]["name"], "Nullnummer")
        self.assertEqual(self.actions[1]["name"], "Zrestrukturyzuj pliki")
        # Record 154's name is copied from string slot 84, not slot 154.
        self.assertEqual(self.actions[154]["name"], "Napełnij pęcherz")

    def test_item_state_table(self):
        states = self.table["item_states"]
        self.assertEqual(states[0], "IDLE")
        self.assertEqual(states[1], "USE")
        self.assertEqual(states[2], "DESTROY_1")
        self.assertEqual(states[9], "DESTROYED_1")
        self.assertEqual(len(states), 16)

    def test_icons_are_in_range(self):
        self.assertEqual(len(self.table["icons"]), ICON_COUNT)
        for action in self.table["actions"]:
            self.assertLess(action["icon"], ICON_COUNT, action["name"])

    def test_copier_chain(self):
        # sub_410450: the continuous-copy action unlocks the breakage that then disables it.
        self.assertIn(82, self.actions[28]["unlocks"])
        self.assertIn(126, self.actions[82]["disables"])

    def test_item_prerequisites_pair_with_the_pickup_that_grants_them(self):
        lighter = self.actions[19]
        self.assertEqual(lighter["name"], "Zabierz zapalniczkę")
        self.assertEqual(lighter["requires_items"], [])
        granted = lighter["grants_item"]
        self.assertTrue(granted)
        self.assertIn(granted, self.actions[145]["requires_items"])

    def test_object_database_action_ids(self):
        definitions = object_action_ids(ROOT)
        by_name = {definition["name"]: definition for definition in definitions.values()}
        self.assertEqual(by_name["Kopierer"]["action_ids"], [28, 29, 126, 82])
        self.assertEqual(by_name["Server-Tower"]["action_ids"], [96, 97, 98, 99])
        self.assertEqual(
            by_name["Toilettenkabine"]["action_ids"], [43, 44, 109, 110, 112, 113]
        )

    def test_every_referenced_action_exists_and_scores(self):
        used = set()
        for definition in object_action_ids(ROOT).values():
            used.update(definition["action_ids"])
        self.assertEqual(len(used), 127)
        for action_id in used:
            self.assertGreater(self.actions[action_id]["score"], 0)

    def test_exported_json_is_current(self):
        exported = json.loads((ROOT / OUTPUT_REL).read_text())
        self.assertEqual(exported, self.table)


if __name__ == "__main__":
    unittest.main()
