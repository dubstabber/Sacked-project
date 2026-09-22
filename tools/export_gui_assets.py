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
    from sprite_source import GERMAN_TEXTURE_ROOT, SpriteSource
except ImportError:  # the tests import this file as tools.export_gui_assets
    from tools.sprite_source import GERMAN_TEXTURE_ROOT, SpriteSource


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
    # Shown for two seconds whenever the office crosses into a higher aggression band.
    ("CO_GUI_CONSOLE_THERMO_UP", "images/gui/hud/thermo-up.png"),
    # The same shape, raised by sub_407990 the moment an agent catches the player, and taken
    # down when the minigame opens two seconds later. See docs/catch-reference.md.
    ("CO_GUI_CONSOLE_AGGRO_UP", "images/gui/hud/aggro-up.png"),
]

SCREENS = [
    ("CO_GUI_SCREENS_WIN", "images/gui/screens/win.png"),
    ("CO_GUI_SCREENS_LOOSE", "images/gui/screens/lose.png"),
    # Re-exported to repair it: the hand-copied file took the pad byte for alpha, so every
    # one of its 640000 pixels was transparent and the main menu drew no background at all.
    ("CO_GUI_SCREENS_MENU_BACKGROUND", "images/gui/screens/menu_background.png"),
]

# The shell between levels. The tree's backdrop has its lattice of linking bars painted in,
# so the screen is that one picture plus 21 node buttons at recovered coordinates; the six
# node faces are the three states in their active and passive halves. The base button face is
# the 160x48 one every shell screen shares. See docs/shell-reference.md.
MENU = [
    ("CO_GUI_SCREENS_LEVELTREE", "images/gui/screens/level-tree.png"),
    ("CO_GUI_MENU_BASE_BG_06", "images/gui/screens/level-description.png"),
    ("CO_GUI_MENU_LEVEL_BACKDROP_DESC", "images/gui/menu/level-backdrop-desc.png"),
    ("CO_GUI_MENU_LEVEL_BACKDROP_INFO", "images/gui/menu/level-backdrop-info.png"),
    ("CO_GUI_MENU_LEVEL_BUTTON_FREE_ACTIVE", "images/gui/menu/level-node-free-active.png"),
    ("CO_GUI_MENU_LEVEL_BUTTON_FREE_PASSIVE", "images/gui/menu/level-node-free-passive.png"),
    ("CO_GUI_MENU_LEVEL_BUTTON_PLAYED_ACTIVE", "images/gui/menu/level-node-played-active.png"),
    ("CO_GUI_MENU_LEVEL_BUTTON_PLAYED_PASSIVE", "images/gui/menu/level-node-played-passive.png"),
    ("CO_GUI_MENU_LEVEL_BUTTON_LOCKED_ACTIVE", "images/gui/menu/level-node-locked-active.png"),
    ("CO_GUI_MENU_LEVEL_BUTTON_LOCKED_PASSIVE", "images/gui/menu/level-node-locked-passive.png"),
    ("CO_GUI_MENU_BASE_BUTTON_ACTIVE", "images/gui/menu/base-button-active.png"),
    ("CO_GUI_MENU_BASE_BUTTON_PASSIVE", "images/gui/menu/base-button-passive.png"),
    # The highscore board and its narrower page-tab button.
    ("CO_GUI_MENU_BASE_BG_04", "images/gui/screens/highscores.png"),
    ("CO_GUI_MENU_HISCORE_BUTTON_ACTIVE", "images/gui/menu/hiscore-button-active.png"),
    ("CO_GUI_MENU_HISCORE_BUTTON_PASSIVE", "images/gui/menu/hiscore-button-passive.png"),
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
MINIGAME_PREFIX = "CO_GUI_MINIGAME_"

# Sprites with words painted into them, which therefore differ per release. The port ships
# both builds' copies and picks by language; English falls back to a drawn label over the
# erased console. See docs/strings-reference.md.
GERMAN_SPRITES = [
    ("CO_GUI_CONSOLE_CONSOLE", "images/gui/hud/console-de.png"),
    ("CO_GUI_MINIGAME_GETREADY", "images/gui/minigame/getready-de.png"),
    ("CO_GUI_MINIGAME_YOURTURN", "images/gui/minigame/yourturn-de.png"),
    ("CO_GUI_MINIGAME_WIN", "images/gui/minigame/win-de.png"),
    ("CO_GUI_MINIGAME_LOOSE", "images/gui/minigame/loose-de.png"),
]

# The console art has the words "czas" and "wynik" painted into it, over the wrong fields --
# the original's own mistake, which the port keeps. They are the only Polish text baked into
# a sprite the port ships, so a second copy is derived with them painted out and the port
# draws Labels there in every other language. The boxes are the lettering's measured bounds
# padded by two pixels, and they contain nothing but the lettering and the frame's flat blue.
# See docs/strings-reference.md.
CONSOLE_LABEL_BOXES = ((91, 72, 134, 88), (236, 67, 293, 98))
CONSOLE_FILL = (74, 109, 230, 255)
UNLABELLED_CONSOLE = "images/gui/hud/console-unlabelled.png"


def unlabelled_console(image):
    """Paint the two words out of the console frame, leaving everything else untouched."""
    result = image.convert("RGBA").copy()
    pixels = result.load()
    for x0, y0, x1, y1 in CONSOLE_LABEL_BOXES:
        for y in range(y0, y1):
            for x in range(x0, x1):
                if pixels[x, y][3] != 0:
                    pixels[x, y] = CONSOLE_FILL
    return result


def slug(name: str) -> str:
    # The archive names are CamelCase runs; split them so the exported files stay readable.
    name = re.sub(r"(?<=[a-z0-9])(?=[A-Z])", "-", name)
    name = re.sub(r"(?<=[A-Z])(?=[A-Z][a-z])", "-", name)
    return re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-")


def acticon_destination(sprite: str) -> str:
    return f"images/gui/acticons/{slug(sprite[len(ACTICON_PREFIX):])}.png"


def specs(root: Path) -> list:
    """Every (archive, sprite, destination, source) this tool owns, in a stable order.

    The fourth element is None for an ordinary sprite, a callable that derives one from the
    decoded image, or a Path naming an alternate extraction to decode it from instead.
    """
    result = []
    for sprite, destination in CONSOLE + SCREENS + MENU:
        result.append((GUI, sprite, destination, None))
    result.append(("CO_GUI", "CO_GUI_CONSOLE_CONSOLE", UNLABELLED_CONSOLE, unlabelled_console))
    for sprite, destination in FONTS:
        result.append((EFFECT, sprite, destination, None))

    for sprite in SpriteSource(root, GUI).names(ACTICON_PREFIX):
        result.append((GUI, sprite, acticon_destination(sprite), None))

    for sprite in SpriteSource(root, EFFECT).names(BUBBLE_PREFIX):
        result.append((EFFECT, sprite, f"images/effects/bubbles/{slug(sprite[len(BUBBLE_PREFIX):])}.png", None))

    for sprite in SpriteSource(root, GUI).names(MINIGAME_PREFIX):
        result.append((GUI, sprite, f"images/gui/minigame/{slug(sprite[len(MINIGAME_PREFIX):])}.png", None))

    for sprite, destination in GERMAN_SPRITES:
        result.append((GUI, sprite, destination, GERMAN_TEXTURE_ROOT))

    destinations = [destination for _, _, destination, _ in result]
    duplicates = {path for path in destinations if destinations.count(path) > 1}
    if duplicates:
        raise SystemExit(f"Destination collision: {sorted(duplicates)}")
    return result


def export(root: Path, check: bool) -> int:
    failures = []
    count = 0
    for archive, sprite, destination, source_or_derive in specs(root):
        textures = source_or_derive if isinstance(source_or_derive, Path) else None
        source = SpriteSource(root, archive, textures)
        image = source.decode(sprite, colour_key=COLOUR_KEYS.get(sprite))
        if callable(source_or_derive):
            image = source_or_derive(image)
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
        for archive, sprite, destination, source_or_derive in specs(root):
            if callable(source_or_derive):
                suffix = "  (derived)"
            elif source_or_derive is not None:
                suffix = "  (German build)"
            else:
                suffix = ""
            print(f"{archive:10} {sprite:44} -> {destination}{suffix}")
        return 0
    return export(root, args.check)


if __name__ == "__main__":
    raise SystemExit(main())
