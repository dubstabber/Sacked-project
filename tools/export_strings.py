#!/usr/bin/env python3
"""Recover the original UI text into resources/original/strings.json.

Two retail builds are available and both are read, so two of the port's three languages are
generated rather than typed: **Polish** from sacked.exe and **German** from Gefeuert.exe, the
original release the Polish one was localised from. Only English is authored.

Every string a build draws comes out of one `char*` table -- 0x46BD04 in the Polish image and
0x46DD1C in the German one. Each holds 255 slots: 0..155 are the prank action names, 156..253
are the UI strings grouped per screen, and a NULL slot closes each group. The two tables have
their NULLs in the same nine places and three strings the Polish translator missed appear at
the same slots in both, so the slot index is a stable identity across the builds.

Action names are keyed by record id rather than slot, because a record's name pointer is not
always its own slot: thirty of them alias another, and record 154 takes slot 84. That map is
traced out of the Polish initializer by export_action_table.py and applied to both tables.

Level descriptions come from each build's own Levels/Level_XX.txt.

Nothing is transcribed by hand: the tool claims every slot exactly once and refuses to run if
one is left unaccounted for. See docs/strings-reference.md.
"""

import argparse
import hashlib
import json
import re
import struct
import sys
from pathlib import Path

try:
    from export_action_table import (
        Image,
        NAME_TABLE_VA,
        RECORD_STRIDE,
        TABLE_VA,
        trace_records,
    )
except ImportError:  # imported as tools.export_strings by the tests
    from tools.export_action_table import (
        Image,
        NAME_TABLE_VA,
        RECORD_STRIDE,
        TABLE_VA,
        trace_records,
    )


EXE_REL = Path("extract-sacked-assets/sacked/sacked.exe")
LEVEL_TEXT_DIR_REL = Path("extract-sacked-assets/sacked/Levels")
OUTPUT_REL = Path("resources/original/strings.json")
TRANSLATIONS_REL = Path("resources/i18n/translations.json")

# The German retail build the Polish release was localised from.
GERMAN_EXE_REL = Path("extract-sacked-assets/Gefeuert/Gefeuert.exe")
GERMAN_LEVEL_TEXT_DIR_REL = Path("extract-sacked-assets/Gefeuert/Levels")
GERMAN_EXE_SIZE = 487424
GERMAN_EXE_SHA256 = "f1ddc93d9fa17ed9db4199139c58a19aea71e8e77317ed60085a518f1715d05d"
GERMAN_TEXT_TABLE_VA = 0x46DD1C
GERMAN_WINDOW_TITLE_VA = 0x47045C

TEXT_TABLE_COUNT = 255
ACTION_SLOTS = 156  # slots 0..155 belong to the action table
LEVEL_COUNT = 21
# sub_407370's window title, the one string the Polish release left in German.
WINDOW_TITLE_VA = 0x46E004
# Slot 0's own string doubles as the console's idle hover text; 27 action slots point at it.
PLACEHOLDER = "..."

SOURCE_LANGUAGE = "pl"
LANGUAGES = ("pl", "en", "de")
# The two languages the retail builds hand us; English is the only authored column.
GENERATED_LANGUAGES = ("pl", "de")
AUTHORED_LANGUAGES = ("en",)

# Slot -> key. Every slot from ACTION_SLOTS up must appear here, in UNUSED_SLOTS, or be NULL.
# A key listed against several slots is one string the original reuses across screens; the
# exporter asserts they really are identical rather than trusting the layout.
KEYS = [
    ("prompt.quit_question", (156,)),
    ("prompt.quit_answer", (157,)),
    ("prompt.time_goal", (158,)),
    ("prompt.time_goal_format", (159,)),
    ("prompt.points_goal_format", (160,)),
    ("prompt.points_target_format", (161,)),
    ("highscore.best_score_format", (162,)),
    ("highscore.best_score_none", (163,)),
    ("highscore.best_time_format", (164,)),
    ("highscore.best_time_none", (165,)),
    ("hud.thermo_warning", (166,)),
    ("prompt.paused", (167,)),
    ("result.manual", (172,)),
    ("result.quit_game", (173,)),
    ("result.next_level", (175,)),
    ("result.retry", (177,)),
    # sub_407990 picks one of these with rand() & 3, so the order is the index.
    ("catch.exclaim.0", (179,)),
    ("catch.exclaim.1", (180,)),
    ("catch.exclaim.2", (181,)),
    ("catch.exclaim.3", (182,)),
    ("menu.time_game", (183,)),
    ("menu.points_game", (184,)),
    ("menu.highscores", (185,)),
    ("menu.names", (186,)),
    ("menu.sound", (187,)),
    ("menu.quit", (188,)),
    ("level_tree.title", (190,)),
    ("description.best_time", (194,)),
    ("description.best_score", (195,)),
    ("description.size", (196,)),
    ("description.difficulty", (197,)),
    ("description.back", (198,)),
    ("highscore.best_score", (200,)),
    ("highscore.score", (201,)),
    ("highscore.time", (202,)),
    ("highscore.page.0", (203,)),
    ("highscore.page.1", (204,)),
    ("highscore.page.2", (205,)),
    ("highscore.page.3", (206,)),
    ("names.title", (209,)),
    ("character_select.title", (213,)),
    ("character.jobless", (214,)),
    ("character.anne", (215,)),
    ("highscore.name_prompt", (219,)),
    ("sound.title", (221,)),
    ("common.main_menu", (174, 176, 191, 207, 211, 217, 223)),
    ("common.continue", (178, 193, 218)),
    ("common.defaults", (210, 216, 222)),
    ("difficulty.0", (225,)),
    ("difficulty.1", (226,)),
    ("difficulty.2", (227,)),
    ("difficulty.3", (228,)),
    ("difficulty.4", (229,)),
    ("difficulty.5", (230,)),
    ("difficulty.6", (231,)),
] + [("level.%d.title" % n, (232 + n,)) for n in range(1, LEVEL_COUNT + 1)]

# Left over from a press build for a German games magazine; no screen reaches them.
UNUSED_SLOTS = {168: "Rozpocznij poziom 1", 169: "Rozpocznij poziom 2",
                170: "Rozpocznij poziom 3", 171: "Gamestar Redaktion"}

# Text the port has to show that the original has no wording for, with the reason it exists.
PORT_STRINGS = {
    "hud.console.time_label": ("czas", "painted into both builds' console art; only English draws a Label"),
    "hud.console.score_label": ("wynik", "painted into both builds' console art; only English draws a Label"),
    # The four duel banners are painted art in both builds, so only English needs words. The
    # Polish release swapped two of them, and the port shows each build's art as it ships, so
    # these are the roles the sprite names give rather than what the Polish art reads.
    "minigame.banner.get_ready": ("Uwaga!", "painted into both builds' banner art"),
    "minigame.banner.your_turn": ("Twoja odpowiedź!", "painted into both builds' banner art"),
    "minigame.banner.win": ("Tania wymówka!", "painted into both builds' banner art"),
    "minigame.banner.lose": ("Złapany!", "painted into both builds' banner art"),
    # Two rows the port adds to the sound-setup screen. The original ships one language per
    # build and has no display option, so neither has wording in either build.
    "sound.language": ("Język", "the port's language row on screen 11; each build ships one language"),
    "sound.display": ("Ekran", "the port's display row on screen 11; the original has no display option"),
    "sound.windowed": ("W oknie", "the display row's windowed value"),
    "sound.fullscreen": ("Pełny ekran", "the display row's full-screen value"),
    # Each language is named in its own words, so a player can find theirs whatever is showing.
    "language.pl": ("Polski", "the language row names each language in its own words"),
    "language.en": ("English", "the language row names each language in its own words"),
    "language.de": ("Deutsch", "the language row names each language in its own words"),
}

# Godot's % formatting is positional, so a translation has to repeat these in order. The
# space flag is deliberately not accepted: one German action name reads "85% der Menschheit",
# and a printf space flag would read that literal percent as a conversion.
FORMAT_TOKEN = re.compile(r"%[-+#0]*[0-9]*(?:\.[0-9]+)?[a-zA-Z]")
# The initials the quit prompt names, as "(T)ak lub (N)ie".
ANSWER_INITIAL = re.compile(r"\((\w)\)")


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


class GermanImage(Image):
    """Image pins the Polish build, so the German one re-does that check against itself."""

    def __init__(self, path: Path):
        self.data = path.read_bytes()
        self.path = path
        digest = sha256(path)
        if len(self.data) != GERMAN_EXE_SIZE or digest != GERMAN_EXE_SHA256:
            raise SystemExit(
                f"{path} is not the German build these addresses were recovered from "
                f"(size {len(self.data)}, sha256 {digest})."
            )
        self.sections = self._sections()


def text_at(image: Image, va: int, encoding: str) -> str:
    """Image.cstring is fixed to the Polish code page; the German build is cp1252."""
    offset = image.offset(va)
    if offset is None:
        raise SystemExit(f"0x{va:08x} is not mapped in {image.path}")
    end = image.data.find(b"\0", offset)
    return image.data[offset:end].decode(encoding)


def action_name_slots(image: Image) -> dict:
    """Which text slot each action record's name pointer actually points at.

    Thirty of the 156 records alias another record's string -- twenty-seven share the `...`
    placeholder and a handful genuinely reuse a neighbour's wording, record 154 taking slot
    84. Tracing it here means the German names can be read out of the German table by the
    same record id without tracing a second initializer.
    """
    records, _ = trace_records(image)
    slots = image.pointers(NAME_TABLE_VA, TEXT_TABLE_COUNT)
    first_slot = {}
    for index, pointer in enumerate(slots):
        first_slot.setdefault(pointer, index)
    mapping = {}
    for action_id, record in enumerate(records):
        pointer, = struct.unpack_from("<I", record, 0)
        slot = first_slot.get(pointer)
        if slot is None:
            raise SystemExit(f"action {action_id}'s name is not in the text table")
        mapping[action_id] = slot
    return mapping


def level_text(directory: Path, number: int, encoding: str) -> dict:
    """Split one Level_XX.txt into its description and its hint.

    Every file is a description, a lone `%s` the game replaces with the level's objective,
    and a hint, separated by blank lines. The Polish files are always exactly six lines; the
    German ones vary, two of them wrapping the description over two lines and several
    carrying trailing blanks. So the split is made on the `%s` rather than on line numbers.
    """
    path = directory / ("Level_%02d.txt" % (number - 1))
    lines = path.read_bytes().decode(encoding).split("\r\n")
    markers = [index for index, line in enumerate(lines) if line.strip() == "%s"]
    if len(markers) != 1:
        raise SystemExit(f"{path.name} has {len(markers)} objective placeholders, expected 1")
    marker = markers[0]
    description = " ".join(line.strip() for line in lines[:marker] if line.strip())
    hint = " ".join(line.strip() for line in lines[marker + 1 :] if line.strip())
    if not description or not hint:
        raise SystemExit(f"{path.name} is missing its description or its hint")
    return {"description": description, "hint": hint}


def build(root: Path) -> dict:
    polish = Image(root / EXE_REL)
    german = GermanImage(root / GERMAN_EXE_REL)
    tables = {
        "pl": (polish, polish.pointers(NAME_TABLE_VA, TEXT_TABLE_COUNT), "cp1250"),
        "de": (german, german.pointers(GERMAN_TEXT_TABLE_VA, TEXT_TABLE_COUNT), "cp1252"),
    }

    def slot_text(language: str, index: int) -> str:
        image, slots, encoding = tables[language]
        if not slots[index]:
            raise SystemExit(f"{language} slot {index} is NULL")
        return text_at(image, slots[index], encoding)

    strings = {}
    claimed = set()
    for key, indices in KEYS:
        entry = {"slots": list(indices)}
        for language in GENERATED_LANGUAGES:
            texts = [slot_text(language, index) for index in indices]
            if len(set(texts)) != 1:
                raise SystemExit(f"{key} claims {language} slots {indices} but they differ: {texts!r}")
            entry[language] = texts[0]
        strings[key] = entry
        claimed.update(indices)

    for index, expected in UNUSED_SLOTS.items():
        actual = slot_text("pl", index)
        if actual != expected:
            raise SystemExit(f"unused slot {index} is {actual!r}, expected {expected!r}")
        claimed.add(index)

    # Every UI slot must be spoken for, so a build with an extra string fails loudly.
    for language in GENERATED_LANGUAGES:
        _, slots, _ = tables[language]
        for index in range(ACTION_SLOTS, TEXT_TABLE_COUNT):
            if index in claimed:
                continue
            if slots[index]:
                raise SystemExit(
                    f"{language} slot {index} {slot_text(language, index)!r} is not claimed by any key"
                )

    # Action names are keyed by record id, and a record's name is not always its own slot.
    name_slots = action_name_slots(polish)
    for action_id in range(1, len(name_slots)):
        slot = name_slots[action_id]
        polish_name = slot_text("pl", slot)
        if polish_name == PLACEHOLDER:
            continue
        strings["action.%d.name" % action_id] = {
            "pl": polish_name,
            "de": slot_text("de", slot),
            "action": action_id,
            "slots": [slot],
        }

    for number in range(1, LEVEL_COUNT + 1):
        source = "Level_%02d.txt" % (number - 1)
        texts = {
            "pl": level_text(root / LEVEL_TEXT_DIR_REL, number, "cp1250"),
            "de": level_text(root / GERMAN_LEVEL_TEXT_DIR_REL, number, "cp1252"),
        }
        for part in ("description", "hint"):
            strings["level.%d.%s" % (number, part)] = {
                "pl": texts["pl"][part],
                "de": texts["de"][part],
                "file": source,
            }

    strings["app.window_title"] = {
        "pl": text_at(polish, WINDOW_TITLE_VA, "cp1250"),
        "de": text_at(german, GERMAN_WINDOW_TITLE_VA, "cp1252"),
        "va": {"pl": "0x%08x" % WINDOW_TITLE_VA, "de": "0x%08x" % GERMAN_WINDOW_TITLE_VA},
    }

    # The keys the quit prompt answers to are the initials it names, in each language.
    for key, position in (("prompt.quit_yes_key", 0), ("prompt.quit_no_key", 1)):
        entry = {"derived_from": "prompt.quit_answer"}
        for language in GENERATED_LANGUAGES:
            answer = strings["prompt.quit_answer"][language]
            initials = ANSWER_INITIAL.findall(answer)
            if len(initials) != 2:
                raise SystemExit(
                    f"the {language} quit answer names {len(initials)} initials, expected 2: {answer!r}"
                )
            entry[language] = initials[position]
        strings[key] = entry

    for key, (text, reason) in PORT_STRINGS.items():
        strings[key] = {"pl": text, "origin": "port", "reason": reason}

    return {
        "generated_by": "tools/export_strings.py",
        "sources": {
            "pl": {
                "exe": str(EXE_REL),
                "size": (root / EXE_REL).stat().st_size,
                "sha256": sha256(root / EXE_REL),
                "text_table": "0x%08x" % NAME_TABLE_VA,
                "level_texts": str(LEVEL_TEXT_DIR_REL),
            },
            "de": {
                "exe": str(GERMAN_EXE_REL),
                "size": (root / GERMAN_EXE_REL).stat().st_size,
                "sha256": sha256(root / GERMAN_EXE_REL),
                "text_table": "0x%08x" % GERMAN_TEXT_TABLE_VA,
                "level_texts": str(GERMAN_LEVEL_TEXT_DIR_REL),
            },
        },
        "text_table_slots": TEXT_TABLE_COUNT,
        "generated_languages": list(GENERATED_LANGUAGES),
        "authored_languages": list(AUTHORED_LANGUAGES),
        "strings": strings,
    }


def format_tokens(text: str) -> list:
    return FORMAT_TOKEN.findall(text)


def missing_languages(entry: dict) -> list:
    """Which of the port's languages this key still needs from the authored file."""
    return [language for language in LANGUAGES if language not in entry]


def check_translations(root: Path, table: dict) -> list:
    """The authored file must fill exactly the gaps the two retail builds leave."""
    path = root / TRANSLATIONS_REL
    if not path.is_file():
        return [f"{TRANSLATIONS_REL} is missing"]
    translations = json.loads(path.read_text(encoding="utf-8"))
    failures = []

    source = table["strings"]
    missing = sorted(set(source) - set(translations))
    stale = sorted(set(translations) - set(source))
    if missing:
        failures.append(f"{TRANSLATIONS_REL} is missing {len(missing)} keys, first: {missing[:5]}")
    if stale:
        failures.append(f"{TRANSLATIONS_REL} has {len(stale)} keys the exporter does not produce: {stale[:5]}")

    for key in sorted(set(source) & set(translations)):
        entry = translations[key]
        wanted = missing_languages(source[key])
        # Authoring a language the builds already give us would let the two drift apart.
        generated = sorted(set(entry) - set(wanted))
        if generated:
            failures.append(f"{key} authors {generated}, which the retail builds already provide")
        expected = format_tokens(source[key][SOURCE_LANGUAGE])
        for language in wanted:
            text = entry.get(language)
            if not text:
                failures.append(f"{key} has no {language} text")
                continue
            if format_tokens(text) != expected:
                failures.append(
                    f"{key} {language} has format tokens {format_tokens(text)}, expected {expected}"
                )

    # Format tokens have to survive the generated languages too.
    for key, entry in source.items():
        expected = format_tokens(entry[SOURCE_LANGUAGE])
        for language in GENERATED_LANGUAGES:
            if language in entry and format_tokens(entry[language]) != expected:
                failures.append(
                    f"{key} {language} has format tokens {format_tokens(entry[language])}, expected {expected}"
                )

    # Proper nouns the original does not translate either, and the languages' own names.
    for key in ("character.jobless", "character.anne", "language.pl", "language.en", "language.de"):
        expected_name = source[key][SOURCE_LANGUAGE]
        for language in LANGUAGES:
            actual = source[key].get(language, translations.get(key, {}).get(language))
            if actual != expected_name:
                failures.append(f"{key} is a proper noun and must stay {expected_name!r} in {language}")

    # The quit prompt's answer keys are the initials that prompt names, in every language.
    for language in LANGUAGES:
        answer = source["prompt.quit_answer"].get(language) or translations.get("prompt.quit_answer", {}).get(language, "")
        for label in ("yes", "no"):
            key = "prompt.quit_%s_key" % label
            initial = source[key].get(language) or translations.get(key, {}).get(language, "")
            if len(initial) != 1 or not initial.isascii() or not initial.isalpha():
                failures.append(f"{key} in {language} is {initial!r}, expected one ASCII letter")
            elif "(%s)" % initial not in answer:
                failures.append(f"{key} {initial!r} is not named by the {language} answer {answer!r}")
    return failures


def check(root: Path, table: dict) -> int:
    failures = []
    output = root / OUTPUT_REL
    if not output.is_file():
        failures.append(f"{OUTPUT_REL} is missing")
    elif json.loads(output.read_text(encoding="utf-8")) != table:
        failures.append(f"{OUTPUT_REL} is stale")

    strings = table["strings"]
    # A handful of values pinned so a mis-walked table cannot pass quietly.
    pinned = {
        "menu.time_game": ("Gra na czas", "Zeitmodus"),
        "prompt.quit_answer": ("(T)ak lub (N)ie", "(J)a oder (N)ein"),
        "prompt.paused": ("Pauza", "Spiel angehalten"),
        "level.1.title": ("Pierwszy ostatni dzień", "Der erste letzte Tag"),
        "level.21.title": ("Biuro Paradiso", "Büro Paradiso"),
        "level.4.title": ("Tyle pracy...", "So viel zu tun..."),
        # The one string the Polish release left in the original German.
        "app.window_title": ("Gefeuert! - Dein letzter Tag", "Gefeuert! - Dein letzter Tag"),
    }
    for key, (polish, german) in pinned.items():
        entry = strings.get(key, {})
        if entry.get("pl") != polish:
            failures.append(f"{key} pl is {entry.get('pl')!r}, expected {polish!r}")
        if entry.get("de") != german:
            failures.append(f"{key} de is {entry.get('de')!r}, expected {german!r}")

    # Three action names the Polish translator missed are German in both builds.
    for action_id in (0, 127, 143):
        key = "action.%d.name" % action_id
        if key in strings and strings[key]["pl"] != strings[key]["de"]:
            failures.append(f"{key} was untranslated in the Polish build and should match the German")

    # Level 4's title runs straight into its description, which is what proves the titles
    # are slot 232 + n rather than the reverse order.
    if not strings["level.4.description"]["pl"].startswith("...i tak ma"):
        failures.append("level 4's description no longer continues its title")

    if len([key for key in strings if key.startswith("action.")]) < 100:
        failures.append("the action names are missing from the table")

    failures.extend(check_translations(root, table))

    for failure in failures:
        print(f"FAIL {failure}")
    if failures:
        return 1
    print(f"strings.json matches sacked.exe ({len(strings)} keys, {len(LANGUAGES)} languages)")
    return 0


def review(root: Path, table: dict, language: str) -> int:
    """Print the authored text beside the original's, for a reading pass."""
    path = root / TRANSLATIONS_REL
    translations = json.loads(path.read_text(encoding="utf-8")) if path.is_file() else {}
    languages = [language] if language else [l for l in LANGUAGES if l != SOURCE_LANGUAGE]
    print("| key | pl | " + " | ".join(languages) + " |")
    print("| --- | --- | " + " | ".join("---" for _ in languages) + " |")
    for key, entry in table["strings"].items():
        row = [key, entry["pl"]] + [translations.get(key, {}).get(l, "") for l in languages]
        print("| " + " | ".join(cell.replace("|", "\\|") for cell in row) + " |")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--check", action="store_true", help="Verify the exported table without writing")
    parser.add_argument("--review", action="store_true", help="Print key/pl/en/de as a markdown table")
    parser.add_argument("--lang", default="", help="Restrict --review to one language")
    args = parser.parse_args()

    root = args.root.resolve()
    table = build(root)

    if args.review:
        return review(root, table, args.lang)
    if args.check:
        return check(root, table)

    output = root / OUTPUT_REL
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(table, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Wrote {len(table['strings'])} strings to {OUTPUT_REL}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
