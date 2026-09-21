import unittest
from pathlib import Path

from PIL import Image

from tools.export_gui_assets import slug, specs
from tools.sprite_source import SpriteSource

ROOT = Path(__file__).resolve().parents[1]
EXTRACTION = ROOT / "extract-sacked-assets/extracted/textures"


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
        destinations = [destination for _, _, destination in table]
        self.assertEqual(len(destinations), len(set(destinations)))
        icons = [path for path in destinations if path.startswith("images/gui/acticons/")]
        bubbles = [path for path in destinations if path.startswith("images/effects/bubbles/")]
        # assert "aicon[b] >= 0 && aicon[b] <= 65" allows 66 slots over 64 shipped sprites.
        self.assertEqual(len(icons), 64)
        self.assertEqual(len(bubbles), 10)

    def test_every_exported_file_exists(self):
        for _, sprite, destination in specs(ROOT):
            with self.subTest(sprite=sprite):
                self.assertTrue((ROOT / destination).is_file(), destination)


if __name__ == "__main__":
    unittest.main()
