import json
import unittest
from pathlib import Path

from PIL import Image

from tools.export_gui_assets import (
    CONSOLE_FILL,
    CONSOLE_LABEL_BOXES,
    STRINGS_ANIMATION,
    STRINGS_TIMING,
    LOADING_BACKGROUND_STRIP,
    UNLABELLED_CONSOLE,
    UNTITLED_LOADING,
    slug,
    specs,
    strings_timing,
)
from tools.sprite_source import SpriteSource

ROOT = Path(__file__).resolve().parents[1]
EXTRACTION = ROOT / "extract-sacked-assets/extracted/textures"
STRINGS_FRAMES = [f"images/effects/strings/strings-{number:03d}.png" for number in range(1, 17)]


@unittest.skipUnless(EXTRACTION.is_dir(), "extracted textures are not available")
class SpriteDecodeTest(unittest.TestCase):
    def test_palette_decode_reproduces_the_hand_copied_cursors(self):
        # These were copied out by hand before the exporter existed, so they are an
        # independent check that the 8bpp palette + index-255 colour key rule is right.
        source = SpriteSource(ROOT, "CO_GUI")
        pairs = [
            ("CO_GUI_Cursor_Pointer_Pointer", "images/gui/cursors/pointer.png"),
            ("CO_GUI_Cursor_Active_090#000", "images/gui/cursors/active/active-090.png"),
            ("CO_GUI_Cursor_Walk_315#000", "images/gui/cursors/walking/walk-315.png"),
            ("CO_GUI_MENU_PLAYER_PORTAIT_JO_ACTIVE", "images/gui/screens/character_select_jobless_active.png"),
        ]
        for sprite, shipped in pairs:
            with self.subTest(sprite=sprite):
                decoded = source.decode(sprite).convert("RGBA")
                with Image.open(ROOT / shipped) as existing:
                    self.assertEqual(decoded.size, existing.size)
                    self.assertEqual(decoded.tobytes(), existing.convert("RGBA").tobytes())

    def test_colour_key_marks_only_index_255(self):
        source = SpriteSource(ROOT, "CO_GUI")
        folder = EXTRACTION / "CO_GUI" / "CO_GUI_Cursor_Pointer_Pointer"
        indices = (folder / "SPRITECB8.bin").read_bytes()
        decoded = source.decode("CO_GUI_Cursor_Pointer_Pointer").convert("RGBA")
        for position, pixel in enumerate(decoded.get_flattened_data()):
            self.assertEqual(pixel[3] == 0, indices[position] == 255)

    def test_true_colour_byte_order_is_rgba(self):
        # The fire ramp is the proof: read in any other order it turns blue.
        ramp = SpriteSource(ROOT, "CO_EFFECT").decode("CO_EFFECT_FEUER_PALETTE")
        self.assertEqual(ramp.getpixel((0, 0)), (0, 0, 0, 0))
        self.assertEqual(ramp.getpixel((128, 0)), (199, 16, 4, 173))
        self.assertEqual(ramp.getpixel((224, 0)), (252, 252, 51, 241))
        self.assertEqual(ramp.getpixel((255, 0)), (254, 254, 233, 255))

    def test_graded_alpha_survives(self):
        # A soft shadow is black with a fade-out tail; clamping it would flatten the fade.
        shadow = SpriteSource(ROOT, "CO_EFFECT").decode("CO_EFFECT_Shadow_Shadow")
        alphas = {pixel[3] for pixel in shadow.get_flattened_data()}
        self.assertGreater(len(alphas), 2)
        self.assertEqual(max(alphas), 223)
        self.assertEqual({pixel[:3] for pixel in shadow.get_flattened_data()}, {(0, 0, 0)})

    def test_unused_pad_becomes_opaque(self):
        # CO_GUI_CONSOLE_CLOCK_FULL stores no alpha at all; taking its pad byte for alpha
        # would make the whole overlay invisible.
        clock = SpriteSource(ROOT, "CO_GUI").decode("CO_GUI_CONSOLE_CLOCK_FULL")
        self.assertEqual({pixel[3] for pixel in clock.get_flattened_data()}, {255})
        self.assertEqual(clock.getpixel((0, 0)), (74, 109, 231, 255))

    def test_menu_background_is_opaque(self):
        # The hand-copied file took the pad byte for alpha, so the main menu drew nothing.
        decoded = SpriteSource(ROOT, "CO_GUI").decode("CO_GUI_SCREENS_MENU_BACKGROUND")
        self.assertEqual({pixel[3] for pixel in decoded.get_flattened_data()}, {255})
        self.assertEqual(decoded.getpixel((0, 0))[:3], (0, 43, 149))

    def test_strings_frames_are_black_and_white_under_a_graded_alpha(self):
        # The smoke texture's shape is all in its alpha; its colour bytes are only ever 0 or
        # 255, so a decode that dropped the fourth byte would leave nothing recognisable.
        frame = SpriteSource(ROOT, "CO_EFFECT").decode("CO_EFFECT_Strings_strings_001_alpha")
        pixels = list(frame.get_flattened_data())
        self.assertEqual(frame.size, (64, 64))
        self.assertEqual({pixel[:3] for pixel in pixels}, {(0, 0, 0), (255, 255, 255)})
        self.assertGreater(len({pixel[3] for pixel in pixels}), 100)

    def test_colour_key_applies_when_given(self):
        source = SpriteSource(ROOT, "CO_GUI")
        keyed = source.decode("CO_GUI_CONSOLE_CLOCK_FULL", colour_key=(74, 109, 231))
        self.assertEqual(keyed.getpixel((0, 0)), (74, 109, 231, 0))

    def test_font_strips_have_the_geometry_the_hud_will_slice(self):
        source = SpriteSource(ROOT, "CO_GUI")
        numbers = source.decode("CO_GUI_CONSOLE_NUMBERS").convert("RGBA")
        self.assertEqual(numbers.size, (14, 280))
        rows = [
            y
            for y in range(numbers.height)
            if any(numbers.getpixel((x, y))[3] for x in range(numbers.width))
        ]
        runs = [y for y in rows if y - 1 not in rows]
        # Eleven glyphs, not ten: the strip carries a second zero for the odometer roll,
        # and the pitch is uneven (24-26 px), so the HUD cannot slice it into equal cells.
        self.assertEqual(len(runs), 11)
        self.assertEqual(runs[0], 1)
        self.assertNotEqual(len({b - a for a, b in zip(runs, runs[1:])}), 1)

        score = SpriteSource(ROOT, "CO_EFFECT").decode("CO_EFFECT_FONT_SCORE").convert("RGBA")
        self.assertEqual(score.size, (312, 32))
        columns = [
            x
            for x in range(score.width)
            if any(score.getpixel((x, y))[3] for y in range(score.height))
        ]
        starts = [x for x in columns if x - 1 not in columns]
        # 13 cells of 24px indexed from '-' (0x2D), so '.' and '/' are the blank pair.
        self.assertEqual(score.width // 13, 24)
        self.assertEqual(len(starts), 11)
        self.assertEqual(starts[0] // 24, 0)
        self.assertEqual(starts[1] // 24, 3)


@unittest.skipUnless(EXTRACTION.is_dir(), "extracted textures are not available")
class ExportTableTest(unittest.TestCase):
    def test_slugs(self):
        self.assertEqual(slug("AbstraktNehmen"), "abstrakt-nehmen")
        self.assertEqual(slug("BrokenCD"), "broken-cd")
        self.assertEqual(slug("Handy_Notruf"), "handy-notruf")
        self.assertEqual(slug("Papier-Porno"), "papier-porno")

    def test_table_covers_every_icon_and_bubble(self):
        table = specs(ROOT)
        destinations = [destination for _, _, destination, _ in table]
        self.assertEqual(len(destinations), len(set(destinations)))
        icons = [path for path in destinations if path.startswith("images/gui/acticons/")]
        bubbles = [path for path in destinations if path.startswith("images/effects/bubbles/")]
        # assert "aicon[b] >= 0 && aicon[b] <= 65" allows 66 slots over 64 shipped sprites.
        self.assertEqual(len(icons), 64)
        self.assertEqual(len(bubbles), 10)

    def test_table_covers_the_sixteen_strings_frames(self):
        destinations = [destination for _, _, destination, _ in specs(ROOT)]
        strings = [path for path in destinations if path.startswith("images/effects/strings/")]
        self.assertEqual(strings, STRINGS_FRAMES)

    def test_every_exported_file_exists(self):
        for _, sprite, destination, _ in specs(ROOT):
            with self.subTest(sprite=sprite):
                self.assertTrue((ROOT / destination).is_file(), destination)

    def test_the_console_variant_only_erases_the_two_painted_words(self):
        """The erased copy exists so the other languages can draw their own labels."""
        from PIL import Image

        painted = Image.open(ROOT / "images/gui/hud/console.png").convert("RGBA")
        erased = Image.open(ROOT / UNLABELLED_CONSOLE).convert("RGBA")
        self.assertEqual(painted.size, erased.size)

        boxes = CONSOLE_LABEL_BOXES
        before, after = painted.load(), erased.load()
        changed = 0
        for y in range(painted.size[1]):
            for x in range(painted.size[0]):
                inside = any(x0 <= x < x1 and y0 <= y < y1 for x0, y0, x1, y1 in boxes)
                if not inside:
                    self.assertEqual(before[x, y], after[x, y], f"pixel {(x, y)} changed outside a word box")
                elif before[x, y] != after[x, y]:
                    changed += 1
                    self.assertEqual(after[x, y], CONSOLE_FILL)
        # If nothing changed the words are still there, which is the failure that matters.
        self.assertGreater(changed, 500)


    def test_the_untitled_still_erases_the_title_and_nothing_else(self):
        """English draws the game's title itself, over a still with the painted one removed."""
        painted = Image.open(ROOT / "images/gui/screens/loading.png").convert("RGB")
        erased = Image.open(ROOT / UNTITLED_LOADING).convert("RGB")
        self.assertEqual(painted.size, erased.size)
        before, after = painted.load(), erased.load()
        x0, x1 = LOADING_BACKGROUND_STRIP

        def background(y):
            row = sorted(before[x, y] for x in range(x0, x1))
            return row[len(row) // 2]

        def off_background(pixel, y):
            return max(abs(a - b) for a, b in zip(pixel, background(y))) > 2

        # The painted title's bounds, measured on the Polish still.
        left, top, right, bottom = 12, 14, 347, 183
        changed = 0
        kept_character = 0
        for y in range(painted.size[1]):
            for x in range(painted.size[0]):
                inside = left <= x <= right and top <= y <= bottom
                if before[x, y] != after[x, y]:
                    changed += 1
                    self.assertTrue(inside, f"pixel {(x, y)} changed outside the title")
                    self.assertFalse(off_background(after[x, y], y), f"pixel {(x, y)} is not the backdrop")
                elif inside and off_background(after[x, y], y):
                    # Only the character reaches into the title's bounds, from x 318.
                    self.assertGreaterEqual(x, 318, f"pixel {(x, y)} of the title survived")
                    kept_character += 1
        self.assertGreater(changed, 40000)
        self.assertGreater(kept_character, 0, "the character's ear and shoulder are untouched")


class StringsTimingTest(unittest.TestCase):
    """resources/effects/strings.json is the port's copy of the CO_EFFECT_Strings ANIM record."""

    def setUp(self):
        self.timing = json.loads((ROOT / STRINGS_TIMING).read_text())

    def test_the_record_is_the_one_the_executable_names(self):
        # sub_41BC50 compares with _stricmp, so the upper-case spelling finds this record.
        self.assertEqual(self.timing["source"], "CO_EFFECT_Strings")
        self.assertEqual(self.timing["source"].upper(), "CO_EFFECT_STRINGS")

    def test_sixteen_frames_at_eight_per_second_looping(self):
        frames = self.timing["frames"]
        self.assertEqual([frame["texture"] for frame in frames], ["res://" + path for path in STRINGS_FRAMES])
        self.assertEqual(self.timing["fps"], 8.0)
        self.assertEqual({frame["duration"] for frame in frames}, {0.125})
        self.assertEqual(sum(frame["duration"] for frame in frames), 2.0)
        # The ANIM payload stores no loop flag, so the record keeps the allocator's default.
        self.assertIs(self.timing["loop"], True)

    def test_every_frame_is_pivoted_on_its_centre(self):
        for frame in self.timing["frames"]:
            with self.subTest(texture=frame["texture"]):
                path = ROOT / frame["texture"].removeprefix("res://")
                with Image.open(path) as image:
                    self.assertEqual(image.size, (64, 64))
                    self.assertEqual(frame["offset"], [-image.width // 2, -image.height // 2])

    @unittest.skipUnless((ROOT / STRINGS_ANIMATION).is_file(), "CO_EFFECT animation JSON is not available")
    def test_the_committed_file_is_what_the_exporter_writes(self):
        self.assertEqual((ROOT / STRINGS_TIMING).read_bytes(), strings_timing(ROOT).encode())

    @unittest.skipUnless((ROOT / STRINGS_ANIMATION).is_file(), "CO_EFFECT animation JSON is not available")
    def test_frame_order_is_the_animcells_order(self):
        source = json.loads((ROOT / STRINGS_ANIMATION).read_text())
        names = [frame["sprite_name"] for frame in source["frames"]]
        self.assertEqual(names, [f"CO_EFFECT_Strings_strings_{number:03d}_alpha" for number in range(1, 17)])
        ids = [frame["sprite_id"] for frame in source["frames"]]
        self.assertEqual(ids, list(range(ids[0], ids[0] + 16)))


if __name__ == "__main__":
    unittest.main()
