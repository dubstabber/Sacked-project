#!/usr/bin/env python3
"""Copy extracted object/wall Z planes into the runtime PNG mask convention."""

import argparse
import json
from pathlib import Path

from PIL import Image

from export_character_depth_maps import encode_depth_rgba, read_frame_depth

try:
    from tools.import_original_level import imported_level_numbers, level_paths
except ImportError:
    from import_original_level import imported_level_numbers, level_paths


def depth_image(folder: Path, size: tuple[int, int]) -> Image.Image:
    depth, mask = read_frame_depth(folder, *size)
    return Image.frombytes("RGBA", size, encode_depth_rgba(depth, mask, *size))


def level_manifests(root: Path):
    """Every imported level, in numeric order so first-seen fields never reshuffle."""
    for number in imported_level_numbers(root):
        path = root / level_paths(number).manifest_rel
        if path.is_file():
            yield json.loads(path.read_text())


def outputs(root: Path):
    texture_root = root / "extract-sacked-assets/extracted/textures"
    seen = set()
    for manifest in level_manifests(root):
        for item in manifest["objects"]:
            color_path = root / item["texture"].removeprefix("res://")
            destination = color_path.with_stem(color_path.stem + "-depth")
            if destination in seen:
                continue
            seen.add(destination)
            yield destination, depth_image(
                texture_root / "CO_OBJECTS" / item["source_sprite"],
                tuple(item["texture_size"]),
            )

    atlases = json.loads((root / "resources/tilemaps/sacked-tile-atlases.json").read_text())
    for name in ("walls",):
        atlas = atlases["atlases"][name]
        color_path = root / atlas["image"].removeprefix("res://")
        with Image.open(color_path) as color:
            result = Image.new("RGBA", color.size)
        for tile in atlas["tiles"]:
            sprite = depth_image(texture_root / "CO_BACKGROUND" / tile["sprite"], tuple(tile["source_size"]))
            position = tuple(
                tile["atlas_coords"][axis] * atlas["cell_size"][axis] + tile["paste_offset"][axis]
                for axis in range(2)
            )
            result.paste(sprite, position)
        yield color_path.with_stem(color_path.stem + "-depth"), result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--check", action="store_true", help="Verify masks without writing files")
    args = parser.parse_args()
    count = 0
    failures = []
    for path, expected in outputs(args.root):
        count += 1
        current = None
        if path.is_file():
            with Image.open(path) as actual:
                if actual.size == expected.size:
                    current = actual.convert("RGBA").tobytes()
        matches = current is not None and current == expected.tobytes()
        if args.check:
            if not matches:
                failures.append(str(path))
        elif not matches:
            # Only rewrite a mask whose pixels actually changed. PIL does not reproduce the
            # encoder the committed files were written with, so saving an unchanged mask
            # would churn its LFS object for identical pixels.
            expected.save(path)
    if failures:
        print("Missing or stale depth masks:\n" + "\n".join(failures))
        return 1
    print(f"{'Verified' if args.check else 'Exported'} {count} world depth masks.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
