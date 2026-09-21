#!/usr/bin/env python3
"""Export original GUI and effect sprites into the port's images/ tree.

The extraction writes about eighteen speculative decode variants next to every sprite
because the channel order was unknown at the time. Rather than pick one of those guesses,
this tool decodes the raw chunks the way the engine does, which is fully determined for the
8bpp sprites that make up almost all of the GUI:

  8bpp  SPRITECB8.bin holds one palette index per pixel and SPRITEPAL.bin holds 256 [R,G,B,0]
        quads. Index 255 is the colour key. Verified by reproducing all 33 GUI images that
        were previously copied out by hand, pixel for pixel.
  32bpp SPRITECB.bin holds four bytes per pixel as (pad, R, G, B). The pad byte is not alpha
        (see extract-sacked-assets/docs/formats/image_format.md), so transparency, where a
        sprite needs it, comes from a colour key named in the table below.

Run with --check to verify the exported files without writing.
"""

import argparse
import re
from pathlib import Path

from PIL import Image

try:
    from sprite_source import SpriteSource
except ImportError:  # the tests import this file as tools.export_gui_assets
    from tools.sprite_source import SpriteSource


GUI = "CO_GUI"
EFFECT = "CO_EFFECT"

# The HUD console and its overlays, as laid out in the original screenshot.
CONSOLE = [
    ("CO_GUI_CONSOLE_CONSOLE", "images/gui/hud/console.png"),
    ("CO_GUI_CONSOLE_NUMBERS", "images/gui/hud/numbers.png"),
    ("CO_GUI_CONSOLE_AGGRO_FULL", "images/gui/hud/aggro-full.png"),
    ("CO_GUI_CONSOLE_CLOCK_FULL", "images/gui/hud/clock-full.png"),
    # sacked.exe references only these three lamps; EDDING_ACT and FIRE_ACT ship unused.
    ("CO_GUI_CONSOLE_SMOKE_ACT", "images/gui/hud/lamp-smoke.png"),
    ("CO_GUI_CONSOLE_PISS_ACT", "images/gui/hud/lamp-piss.png"),
    ("CO_GUI_CONSOLE_MATRIX_ACT", "images/gui/hud/lamp-matrix.png"),
]

SCREENS = [
    ("CO_GUI_SCREENS_WIN", "images/gui/screens/win.png"),
    ("CO_GUI_SCREENS_LOOSE", "images/gui/screens/lose.png"),
    # Re-exported to repair it: the hand-copied file took the pad byte for alpha, so every
    # one of its 640000 pixels was transparent and the main menu drew no background at all.
    ("CO_GUI_SCREENS_MENU_BACKGROUND", "images/gui/screens/menu_background.png"),
]

FONTS = [
    ("CO_EFFECT_FONT_SCORE", "images/gui/fonts/score-digits.png"),
]

# The pad byte of a 32bpp pixel is not alpha, so a true-colour sprite that needs
# transparency has to name its colour key here. None do yet: CLOCK_FULL's black pixels are
# dial markings rather than background, and how the original masks that overlay is a
# question for whoever reverse-engineers the round bar that draws it.
COLOUR_KEYS = {}


ACTICON_PREFIX = "CO_GUI_ACTICON_"
BUBBLE_PREFIX = "CO_EFFECT_Bubbles_"


def slug(name: str) -> str:
    # The archive names are CamelCase runs; split them so the exported files stay readable.
    name = re.sub(r"(?<=[a-z0-9])(?=[A-Z])", "-", name)
    name = re.sub(r"(?<=[A-Z])(?=[A-Z][a-z])", "-", name)
    return re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-")


def acticon_destination(sprite: str) -> str:
    return f"images/gui/acticons/{slug(sprite[len(ACTICON_PREFIX):])}.png"


def specs(root: Path) -> list:
    """Every (archive, sprite, destination) this tool owns, in a stable order."""
    result = []
    for sprite, destination in CONSOLE + SCREENS:
        result.append((GUI, sprite, destination))
    for sprite, destination in FONTS:
        result.append((EFFECT, sprite, destination))

    for sprite in SpriteSource(root, GUI).names(ACTICON_PREFIX):
        result.append((GUI, sprite, acticon_destination(sprite)))

    for sprite in SpriteSource(root, EFFECT).names(BUBBLE_PREFIX):
        result.append((EFFECT, sprite, f"images/effects/bubbles/{slug(sprite[len(BUBBLE_PREFIX):])}.png"))

    destinations = [destination for _, _, destination in result]
    duplicates = {path for path in destinations if destinations.count(path) > 1}
    if duplicates:
        raise SystemExit(f"Destination collision: {sorted(duplicates)}")
    return result


def export(root: Path, check: bool) -> int:
    failures = []
    count = 0
    for archive, sprite, destination in specs(root):
        source = SpriteSource(root, archive)
        image = source.decode(sprite, colour_key=COLOUR_KEYS.get(sprite))
        path = root / destination
        count += 1
        if check:
            if not path.is_file():
                failures.append(f"{destination} is missing")
                continue
            with Image.open(path) as existing:
                if existing.size != image.size:
                    failures.append(f"{destination} is {existing.size}, expected {image.size}")
                elif existing.convert("RGBA").tobytes() != image.convert("RGBA").tobytes():
                    failures.append(f"{destination} is stale")
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            image.save(path, optimize=True)

    if failures:
        print("GUI asset check failed:\n" + "\n".join(f"  {line}" for line in failures))
        return 1
    print(f"{'Verified' if check else 'Exported'} {count} GUI and effect sprites.")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--check", action="store_true", help="Verify exported images without writing")
    parser.add_argument("--list", action="store_true", help="Print the source-to-destination table")
    args = parser.parse_args()

    root = args.root.resolve()
    if args.list:
        for archive, sprite, destination in specs(root):
            print(f"{archive:10} {sprite:44} -> {destination}")
        return 0
    return export(root, args.check)


if __name__ == "__main__":
    raise SystemExit(main())
