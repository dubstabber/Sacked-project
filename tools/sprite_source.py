#!/usr/bin/env python3
"""Decode extracted ODIN_ENGINE sprites from their raw chunks.

The extraction keeps each sprite as a folder of raw chunk dumps plus a pile of speculative
decode variants. The chunks are unambiguous, so anything that needs sprite pixels decodes
them here rather than guessing which variant PNG is the right one.
"""

import json
from pathlib import Path

from PIL import Image


TEXTURE_ROOT = Path("extract-sacked-assets/extracted/textures")
# The German retail build's own archives, dumped beside the Polish ones. Only the sprites
# with text painted into them differ, so this is read for those and nothing else.
GERMAN_TEXTURE_ROOT = Path("extract-sacked-assets/extracted-de/textures")
COLOUR_KEY_INDEX = 255  # 8bpp sprites key on palette index 255


class SpriteSource:
    def __init__(self, root: Path, archive: str, textures: Path = None):
        self.root = Path(root)
        self.archive = archive
        self.directory = self.root / (textures or TEXTURE_ROOT) / archive

    def names(self, prefix: str = "") -> list:
        return sorted(
            path.name
            for path in self.directory.iterdir()
            if path.is_dir() and path.name.startswith(prefix) and (path / "SPRITEHDR.json").is_file()
        )

    def header(self, sprite: str) -> dict:
        return json.loads((self.directory / sprite / "SPRITEHDR.json").read_text())

    def decode(self, sprite: str, colour_key: tuple = None) -> Image.Image:
        header = self.header(sprite)
        width, height, bpp = header["width"], header["height"], header["bpp"]
        folder = self.directory / sprite

        if bpp == 8:
            indices = (folder / "SPRITECB8.bin").read_bytes()
            palette = (folder / "SPRITEPAL.bin").read_bytes()
            if len(indices) != width * height:
                raise ValueError(f"{sprite}: SPRITECB8 is {len(indices)} bytes, expected {width * height}")
            if len(palette) != 1024:
                raise ValueError(f"{sprite}: SPRITEPAL is {len(palette)} bytes, expected 1024")
            # Palette quads are [R,G,B,0]; the fourth byte is padding, not alpha.
            image = Image.frombytes("P", (width, height), indices)
            image.putpalette(b"".join(bytes(palette[4 * i : 4 * i + 3]) for i in range(256)))
            image.info["transparency"] = COLOUR_KEY_INDEX
            return image

        if bpp == 32:
            data = (folder / "SPRITECB.bin").read_bytes()
            if len(data) != width * height * 4:
                raise ValueError(f"{sprite}: SPRITECB is {len(data)} bytes, expected {width * height * 4}")
            # Bytes are (R, G, B, A). Proven by CO_EFFECT_FEUER_PALETTE, whose entries run
            # (199,16,4) red -> (252,252,51) yellow -> (254,254,233) white with a rising
            # alpha: any other order turns that fire ramp blue.
            image = Image.frombytes("RGBA", (width, height), data)
            if max(data[3::4]) == 0:
                # The fourth slot is the same unused pad the [R,G,B,0] palette quads carry,
                # so taking it for alpha would make the sprite invisible. Only
                # CO_GUI_CONSOLE_CLOCK_FULL is stored this way.
                image.putalpha(255)
            if colour_key is not None:
                image.putdata(
                    [
                        (r, g, b, 0) if (r, g, b) == colour_key else (r, g, b, a)
                        for r, g, b, a in image.get_flattened_data()
                    ]
                )
            return image

        raise ValueError(f"{sprite}: unsupported bit depth {bpp}")
