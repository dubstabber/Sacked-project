import json
import unittest
from pathlib import Path

from tools.export_action_table import NAME_TABLE_VA, Image
from tools.export_strings import (
    ACTION_SLOTS,
    GENERATED_LANGUAGES,
    GERMAN_LEVEL_TEXT_DIR_REL,
    LEVEL_TEXT_DIR_REL,
    EXE_REL,
    KEYS,
    LANGUAGES,
    LEVEL_COUNT,
    OUTPUT_REL,
    PORT_STRINGS,
    SOURCE_LANGUAGE,
    TEXT_TABLE_COUNT,
    TRANSLATIONS_REL,
    UNUSED_SLOTS,
    build,
    check_translations,
    format_tokens,
    level_text,
)

ROOT = Path(__file__).resolve().parents[1]
ORIGINAL_EXE = ROOT / EXE_REL


@unittest.skipUnless(ORIGINAL_EXE.is_file(), "original sacked.exe is not available")
class TextTableTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.image = Image(ORIGINAL_EXE)
        cls.slots = cls.image.pointers(NAME_TABLE_VA, TEXT_TABLE_COUNT)
        cls.table = build(ROOT)
        cls.strings = cls.table["strings"]

    def test_every_ui_slot_is_claimed_exactly_once(self):
        claimed = []
        for _, indices in KEYS:
            claimed.extend(indices)
        claimed.extend(UNUSED_SLOTS)
        self.assertEqual(len(claimed), len(set(claimed)), "a slot is claimed twice")
        unclaimed = [
            index
            for index in range(ACTION_SLOTS, TEXT_TABLE_COUNT)
            if index not in set(claimed) and self.slots[index]
        ]
        self.assertEqual(unclaimed, [], "a non-NULL UI slot has no key")

    def test_null_slots_close_each_screen_group(self):
        # The NULLs are the table's own punctuation; losing one means the walk has drifted.
        nulls = [index for index in range(ACTION_SLOTS, TEXT_TABLE_COUNT) if not self.slots[index]]
        self.assertEqual(nulls, [189, 192, 199, 208, 212, 220, 224, 232, 254])

    def test_repeated_slots_really_are_the_same_string(self):
        for key, indices in KEYS:
            if len(indices) < 2:
                continue
            texts = {self.image.cstring(self.slots[index]) for index in indices}
            self.assertEqual(len(texts), 1, f"{key} spans slots that differ: {texts}")

    def test_known_values(self):
        self.assertEqual(self.strings["menu.time_game"]["pl"], "Gra na czas")
        self.assertEqual(self.strings["prompt.paused"]["pl"], "Pauza")
        self.assertEqual(self.strings["prompt.quit_answer"]["pl"], "(T)ak lub (N)ie")
        self.assertEqual(self.strings["common.main_menu"]["pl"], "Główne menu")
        # The one string the Polish release left in the original German.
        self.assertEqual(self.strings["app.window_title"]["pl"], "Gefeuert! - Dein letzter Tag")

    def test_level_titles_ascend_with_the_slot(self):
        self.assertEqual(self.strings["level.1.title"]["pl"], "Pierwszy ostatni dzień")
        self.assertEqual(self.strings["level.21.title"]["pl"], "Biuro Paradiso")
        # Four titles run straight into their own description, which is what fixes the
        # direction of the mapping; reversing it would break the sentence.
        for number, opening in ((4, "...i tak ma"), (6, "...tak twoi"), (9, "...niezbędne")):
            self.assertTrue(
                self.strings[f"level.{number}.description"]["pl"].startswith(opening),
                f"level {number}'s description no longer continues its title",
            )

    def test_answer_keys_are_derived_from_the_answer(self):
        answer = self.strings["prompt.quit_answer"]["pl"]
        for key in ("prompt.quit_yes_key", "prompt.quit_no_key"):
            initial = self.strings[key]["pl"]
            self.assertEqual(len(initial), 1)
            self.assertIn(f"({initial})", answer)

    def test_level_texts_all_split_on_their_objective_placeholder(self):
        for number in range(1, LEVEL_COUNT + 1):
            for directory, encoding in (
                (ROOT / LEVEL_TEXT_DIR_REL, "cp1250"),
                (ROOT / GERMAN_LEVEL_TEXT_DIR_REL, "cp1252"),
            ):
                text = level_text(directory, number, encoding)
                self.assertTrue(text["description"], f"level {number} in {directory.name}")
                self.assertTrue(text["hint"], f"level {number} in {directory.name}")

    def test_german_is_generated_not_authored(self):
        generated = [key for key, entry in self.strings.items() if "de" in entry]
        self.assertGreater(len(generated), 240)
        # Only the strings neither build has wording for are left to the authored file.
        gaps = sorted(key for key, entry in self.strings.items() if "de" not in entry)
        self.assertEqual(gaps, sorted(PORT_STRINGS))

    def test_the_two_builds_agree_where_the_translator_missed(self):
        # Two of the action names the port shows stayed German in the Polish release. A third,
        # action 0's "Nullnummer", is never drawn and so carries no key.
        for action_id in (127, 143):
            key = "action.%d.name" % action_id
            self.assertEqual(self.strings[key]["pl"], self.strings[key]["de"], key)

    def test_known_german_values(self):
        self.assertEqual(self.strings["menu.time_game"]["de"], "Zeitmodus")
        self.assertEqual(self.strings["prompt.quit_answer"]["de"], "(J)a oder (N)ein")
        self.assertEqual(self.strings["prompt.quit_yes_key"]["de"], "J")
        self.assertEqual(self.strings["level.1.title"]["de"], "Der erste letzte Tag")
        self.assertEqual(self.strings["level.21.title"]["de"], "Büro Paradiso")

    def test_action_names_come_from_the_records(self):
        actions = json.loads((ROOT / "resources/original/actions.json").read_text(encoding="utf-8"))
        by_id = {action["id"]: action["name"] for action in actions["actions"]}
        named = [key for key in self.strings if key.startswith("action.")]
        self.assertGreater(len(named), 100)
        for key in named:
            action_id = int(key.split(".")[1])
            self.assertEqual(self.strings[key]["pl"], by_id[action_id])

    def test_port_strings_are_declared_with_a_reason(self):
        for key in PORT_STRINGS:
            self.assertIn("reason", self.strings[key])
            self.assertEqual(self.strings[key]["origin"], "port")

    def test_exported_file_is_current(self):
        exported = json.loads((ROOT / OUTPUT_REL).read_text(encoding="utf-8"))
        self.assertEqual(exported, self.table, f"{OUTPUT_REL} is stale")


@unittest.skipUnless(ORIGINAL_EXE.is_file(), "original sacked.exe is not available")
class TranslationTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.table = build(ROOT)
        cls.translations = json.loads((ROOT / TRANSLATIONS_REL).read_text(encoding="utf-8"))

    def test_authored_languages_cover_every_key(self):
        self.assertEqual(check_translations(ROOT, self.table), [])

    def test_nothing_generated_is_also_authored(self):
        # Both retail languages are generated; an authored copy would drift from the builds.
        source = self.table["strings"]
        for key, entry in self.translations.items():
            for language in entry:
                self.assertNotIn(
                    language, source[key], f"{key} authors {language}, which a build provides"
                )

    def test_languages(self):
        self.assertEqual(LANGUAGES, ("pl", "en", "de"))
        self.assertEqual(GENERATED_LANGUAGES, ("pl", "de"))


class FormatTokenTest(unittest.TestCase):
    def test_tokens_are_read_in_order(self):
        self.assertEqual(format_tokens("%d punktów w ciągu %d minut."), ["%d", "%d"])
        self.assertEqual(format_tokens("Najlepszy czas: %02d:%02d"), ["%02d", "%02d"])
        self.assertEqual(format_tokens("Pauza"), [])


@unittest.skipUnless(ORIGINAL_EXE.is_file(), "original sacked.exe is not available")
class TranslationRuleTest(unittest.TestCase):
    """The rules have to reject bad input, or they are not checking anything."""

    @classmethod
    def setUpClass(cls):
        cls.table = build(ROOT)

    def _with(self, root: Path, translations: dict) -> list:
        path = root / TRANSLATIONS_REL
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(translations, ensure_ascii=False), encoding="utf-8")
        return check_translations(root, self.table)

    def test_a_dropped_key_is_reported(self):
        import tempfile

        good = json.loads((ROOT / TRANSLATIONS_REL).read_text(encoding="utf-8"))
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            broken = dict(good)
            broken.pop("menu.quit")
            failures = self._with(root, broken)
            self.assertTrue(any("missing" in failure for failure in failures))

    def test_a_lost_format_token_is_reported(self):
        import tempfile

        good = json.loads((ROOT / TRANSLATIONS_REL).read_text(encoding="utf-8"))
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            broken = dict(good)
            broken["prompt.time_goal_format"] = {"en": "points within minutes.", "de": "%d Punkte in %d Minuten."}
            failures = self._with(root, broken)
            self.assertTrue(any("format tokens" in failure for failure in failures))

    def test_an_answer_key_the_prompt_does_not_name_is_reported(self):
        import tempfile

        good = json.loads((ROOT / TRANSLATIONS_REL).read_text(encoding="utf-8"))
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            broken = dict(good)
            broken["prompt.quit_yes_key"] = {"en": "Z", "de": "J"}
            failures = self._with(root, broken)
            self.assertTrue(any("quit_yes_key" in failure for failure in failures))


if __name__ == "__main__":
    unittest.main()
