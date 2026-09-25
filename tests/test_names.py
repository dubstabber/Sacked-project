import json
import unittest
from pathlib import Path

from tools.export_gui_assets import specs
from tools.export_names import (
    NAME_MAX_LENGTH,
    NAMES_REL,
    OUTPUT_REL,
    POOL_SIZES,
    RECORD_COUNT,
    build,
    pool_types,
)

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless((ROOT / NAMES_REL).is_file(), "the original NAMES.DAT is not available")
class NamesExportTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        # build() refuses to run unless NAMES.DAT and both builds' defaults agree.
        cls.table = build(ROOT)
        cls.names = [record["name"] for record in cls.table["records"]]

    def test_the_checked_in_table_is_current(self):
        shipped = json.loads((ROOT / OUTPUT_REL).read_text(encoding="utf-8"))
        self.assertEqual(shipped, self.table)

    def test_fifteen_records_in_seven_fixed_pools(self):
        self.assertEqual(len(self.table["records"]), RECORD_COUNT)
        self.assertEqual(pool_types(), [1, 2, 3, 4, 4, 4, 5, 5, 5, 6, 6, 6, 7, 7, 7])
        self.assertEqual([record["type"] for record in self.table["records"]], pool_types())
        for entry in self.table["types"]:
            self.assertEqual(len(entry["records"]), POOL_SIZES[entry["type"]])
            for index in entry["records"]:
                self.assertEqual(self.table["records"][index]["type"], entry["type"])

    def test_known_names(self):
        # The boss is record 0, and Klara Fall is the name a reference screenshot shows in
        # yellow over a coworker. Hanne Büchen carries the one non-ASCII byte, 0xFC.
        self.assertEqual(self.table["records"][0]["name"], "Roy Behr")
        self.assertEqual(self.table["records"][0]["profile_id"], "boss")
        self.assertEqual(self.table["records"][13]["name"], "Klara Fall")
        self.assertEqual(self.table["records"][13]["profile_id"], "female-employee-2")
        self.assertEqual(self.table["records"][11]["name"], "Hanne Büchen")
        self.assertEqual(len(set(self.names)), RECORD_COUNT, "every default name is distinct")
        self.assertTrue(all(0 < len(name) <= NAME_MAX_LENGTH for name in self.names))

    def test_the_placeholder_is_read_from_both_builds(self):
        self.assertEqual(self.table["placeholder"], "DEFAULT NAME")

    def test_each_type_shows_its_own_portrait(self):
        portraits = [entry["portrait"] for entry in self.table["types"]]
        self.assertEqual(portraits[0], "CO_GUI_MENU_COWORKER_PORTAIT_CHEF")
        self.assertEqual(portraits[6], "CO_GUI_MENU_COWORKER_PORTAIT_KW2")
        exported = {sprite: destination for _, sprite, destination, _ in specs(ROOT)}
        for entry in self.table["types"]:
            self.assertEqual(
                exported.get(entry["portrait"]),
                "images/gui/menu/portrait-%s.png" % entry["profile_id"],
                "screen 13 finds type %d's portrait by its profile id" % entry["type"],
            )


if __name__ == "__main__":
    unittest.main()
