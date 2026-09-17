#!/usr/bin/env python3
import argparse
import filecmp
import json
import os
import re
import shutil
import struct
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Callable, Dict, List, Tuple

from PIL import Image


SOURCE_ID = 3
TILE_SIZE = (96, 48)
MANIFEST_REL = Path("resources/tilemaps/sacked-tile-atlases.json")


@dataclass(frozen=True)
class AtlasSpec:
    name: str
    image_rel: Path
    tileset_rel: Path
    cell_size: Tuple[int, int]
    texture_origin: Tuple[int, int]
    columns: int
    include: Callable[[str], bool]
    order: Tuple[str, ...] = ()


SPECS: Tuple[AtlasSpec, ...] = (
    AtlasSpec(
        name="floor",
        image_rel=Path("images/floor/sacked-floors.png"),
        tileset_rel=Path("resources/tilemaps/sacked-floor.tres"),
        cell_size=(94, 48),
        texture_origin=(0, 0),
        columns=10,
        include=lambda sprite: "_FLOOR_" in sprite,
    ),
    AtlasSpec(
        name="walls",
        image_rel=Path("images/tilemaps/sacked-walls.png"),
        tileset_rel=Path("resources/tilemaps/sacked-walls.tres"),
        cell_size=(96, 176),
        texture_origin=(0, 73),
        columns=8,
        include=lambda sprite: "_WALLS_" in sprite,
        order=(
            "CO_BACKGROUND_OFFICE_WALLS_WALL#VERT",
            "CO_BACKGROUND_OFFICE_WALLS_WALL#HORZ",
            "CO_BACKGROUND_OFFICE_WALLS_CORNER#TOP#LEFT",
            "CO_BACKGROUND_OFFICE_WALLS_CORNER#TOP#RIGHT",
            "CO_BACKGROUND_OFFICE_WALLS_CORNER#BOTTOM#LEFT",
            "CO_BACKGROUND_OFFICE_WALLS_CORNER#BOTTOM#RIGHT",
            "CO_BACKGROUND_OFFICE_WALLS_TJ#LEFT",
            "CO_BACKGROUND_OFFICE_WALLS_TJ#RIGHT",
            "CO_BACKGROUND_OFFICE_WALLS_TJ#TOP",
            "CO_BACKGROUND_OFFICE_WALLS_TJ#BOTTOM",
            "CO_BACKGROUND_OFFICE_WALLS_CROSS",
            "CO_BACKGROUND_OFFICE_WALLS_WALL#THICK#LEFT",
            "CO_BACKGROUND_OFFICE_WALLS_WALL#THICK#RIGHT",
            "CO_BACKGROUND_OFFICE_WALLS_WALL#THICK#TOP",
            "CO_BACKGROUND_OFFICE_WALLS_WALL#THICK#BOTTOM",
            "CO_BACKGROUND_OFFICE_WALLS_CORNER#THICK#TOP#LEFT",
            "CO_BACKGROUND_OFFICE_WALLS_CORNER#THICK#TOP#RIGHT",
            "CO_BACKGROUND_OFFICE_WALLS_CORNER#THICK#BOTTOM#LEFT",
            "CO_BACKGROUND_OFFICE_WALLS_CORNER#THICK#BOTTOM#RIGHT",
            "CO_BACKGROUND_OFFICE_WALLS_TJ#THICK#LEFT",
            "CO_BACKGROUND_OFFICE_WALLS_TJ#THICK#RIGHT",
            "CO_BACKGROUND_OFFICE_WALLS_TJ#THICK#TOP",
            "CO_BACKGROUND_OFFICE_WALLS_TJ#THICK#BOTTOM",
        ),
    ),
    AtlasSpec(
        name="glass",
        image_rel=Path("images/tilemaps/sacked-glass.png"),
        tileset_rel=Path("resources/tilemaps/sacked-glass.tres"),
        cell_size=(94, 96),
        texture_origin=(0, 95),
        columns=8,
        include=lambda sprite: "_GLASS_" in sprite,
    ),
)


def repo_root() -> Path:
    return Path(__file__).resolve().parents[1]


def source_root(root: Path) -> Path:
    return root / "extract-sacked-assets" / "extracted" / "textures" / "CO_BACKGROUND"


def read_s16(data: bytes, offset: int) -> int:
    return struct.unpack_from("<h", data, offset)[0]


def load_conversion_log(root: Path) -> List[Dict[str, object]]:
    log_path = source_root(root) / "png_conversion_log.json"
    with log_path.open("r", encoding="utf-8") as handle:
        data = json.load(handle)
    entries = data.get("entries", [])
    if not isinstance(entries, list):
        raise ValueError(f"{log_path} does not contain an entries list")
    return entries


def atlas_entries(entries: List[Dict[str, object]], spec: AtlasSpec) -> List[Dict[str, object]]:
    selected = [entry for entry in entries if spec.include(str(entry.get("sprite", "")))]
    if not selected:
        raise ValueError(f"No CO_BACKGROUND entries matched atlas '{spec.name}'")
    if spec.order:
        by_sprite = {str(entry.get("sprite", "")): entry for entry in selected}
        missing = [sprite for sprite in spec.order if sprite not in by_sprite]
        extra = [str(entry.get("sprite", "")) for entry in selected if str(entry.get("sprite", "")) not in spec.order]
        if missing or extra:
            raise ValueError(f"Atlas '{spec.name}' order mismatch: missing={missing} extra={extra}")
        return [by_sprite[sprite] for sprite in spec.order]
    return selected


def sprite_png_path(root: Path, sprite: str) -> Path:
    return source_root(root) / sprite / f"{sprite}.png"


def tile_key(sprite: str) -> str:
    key = sprite.lower()
    key = key.replace("co_background_office_", "")
    key = re.sub(r"[^a-z0-9]+", "-", key).strip("-")
    return re.sub(r"-+", "-", key)


def paste_offset(cell_size: Tuple[int, int], image_size: Tuple[int, int]) -> Tuple[int, int]:
    cell_w, cell_h = cell_size
    image_w, image_h = image_size
    if image_w > cell_w or image_h > cell_h:
        raise ValueError(f"Sprite {image_w}x{image_h} does not fit cell {cell_w}x{cell_h}")
    return ((cell_w - image_w) // 2, cell_h - image_h)


def read_sprite_pivot(root: Path, sprite: str, image_size: Tuple[int, int]) -> Tuple[int, int]:
    header_path = source_root(root) / sprite / "SPRITEHDR.bin"
    if header_path.is_file():
        header = header_path.read_bytes()
        if len(header) >= 0x208:
            return read_s16(header, 0x204), read_s16(header, 0x206)
    return image_size[0] // 2, image_size[1]


def texture_origin_for_sprite(
    pivot: Tuple[int, int], offset: Tuple[int, int], cell_size: Tuple[int, int]
) -> Tuple[int, int]:
    return (pivot[0] + offset[0] - cell_size[0] // 2, pivot[1] + offset[1] - cell_size[1] // 2)


def write_atomic_image(image: Image.Image, target: Path) -> None:
    target.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(delete=False, suffix=".png", dir=str(target.parent)) as handle:
        temp_path = Path(handle.name)
    try:
        image.save(temp_path)
        os.replace(temp_path, target)
    finally:
        temp_path.unlink(missing_ok=True)


def write_atomic_text(text: str, target: Path) -> None:
    target.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile("w", delete=False, encoding="utf-8", dir=str(target.parent)) as handle:
        handle.write(text)
        temp_path = Path(handle.name)
    try:
        os.replace(temp_path, target)
    finally:
        temp_path.unlink(missing_ok=True)


def build_atlas(root: Path, output_root: Path, spec: AtlasSpec, entries: List[Dict[str, object]]) -> Dict[str, object]:
    cell_w, cell_h = spec.cell_size
    rows = (len(entries) + spec.columns - 1) // spec.columns
    atlas = Image.new("RGBA", (cell_w * spec.columns, cell_h * rows), (0, 0, 0, 0))
    tiles: List[Dict[str, object]] = []

    for index, entry in enumerate(entries):
        sprite = str(entry["sprite"])
        png_path = sprite_png_path(root, sprite)
        if not png_path.is_file():
            raise FileNotFoundError(png_path)

        with Image.open(png_path) as source:
            image = source.convert("RGBA")
            source_size = (image.width, image.height)
            offset = paste_offset(spec.cell_size, source_size)
            pivot = read_sprite_pivot(root, sprite, source_size)
            texture_origin = texture_origin_for_sprite(pivot, offset, spec.cell_size)
            atlas_coords = (index % spec.columns, index // spec.columns)
            atlas.paste(image, (atlas_coords[0] * cell_w + offset[0], atlas_coords[1] * cell_h + offset[1]))

        z_path = source_root(root) / sprite / "SPRITEZB.bin"
        tiles.append(
            {
                "tile_key": tile_key(sprite),
                "sprite": sprite,
                "atlas_coords": list(atlas_coords),
                "source_size": [int(source_size[0]), int(source_size[1])],
                "paste_offset": [int(offset[0]), int(offset[1])],
                "pivot": [int(pivot[0]), int(pivot[1])],
                "texture_origin": [int(texture_origin[0]), int(texture_origin[1])],
                "has_z": z_path.is_file(),
            }
        )

    target = output_root / spec.image_rel
    write_atomic_image(atlas, target)

    return {
        "image": "res://%s" % spec.image_rel.as_posix(),
        "tileset": "res://%s" % spec.tileset_rel.as_posix(),
        "cell_size": list(spec.cell_size),
        "tile_size": list(TILE_SIZE),
        "texture_origin": list(spec.texture_origin),
        "columns": spec.columns,
        "source_id": SOURCE_ID,
        "tiles": tiles,
    }


def build_outputs(root: Path, output_root: Path) -> Dict[str, object]:
    entries = load_conversion_log(root)
    atlases: Dict[str, object] = {}
    for spec in SPECS:
        atlases[spec.name] = build_atlas(root, output_root, spec, atlas_entries(entries, spec))

    manifest = {
        "generated_by": "tools/build_tilemap_atlases.py",
        "source": "extract-sacked-assets/extracted/textures/CO_BACKGROUND/png_conversion_log.json",
        "tile_size": list(TILE_SIZE),
        "source_id": SOURCE_ID,
        "atlases": atlases,
    }
    manifest_text = json.dumps(manifest, indent=2, sort_keys=True) + "\n"
    write_atomic_text(manifest_text, output_root / MANIFEST_REL)
    return manifest


def compare_generated(root: Path, generated_root: Path) -> int:
    rels = [spec.image_rel for spec in SPECS] + [MANIFEST_REL]
    mismatches: List[Path] = []
    missing: List[Path] = []
    for rel in rels:
        expected = root / rel
        actual = generated_root / rel
        if not expected.exists():
            missing.append(rel)
        elif not filecmp.cmp(expected, actual, shallow=False):
            mismatches.append(rel)

    if missing:
        print("Missing generated outputs:", file=sys.stderr)
        for rel in missing:
            print(f"  {rel}", file=sys.stderr)
    if mismatches:
        print("Generated outputs are stale:", file=sys.stderr)
        for rel in mismatches:
            print(f"  {rel}", file=sys.stderr)
    if missing or mismatches:
        return 1

    print("Tilemap atlases are up to date.")
    return 0


def run_godot_tileset_builder(root: Path, godot_binary: str) -> None:
    env = os.environ.copy()
    env.setdefault("HOME", "/tmp/sacked-godot-home")
    env.setdefault("XDG_CONFIG_HOME", "/tmp/sacked-godot-config")
    env.setdefault("XDG_DATA_HOME", "/tmp/sacked-godot-xdg")
    import_command = [
        godot_binary,
        "--headless",
        "--path",
        ".",
        "--import",
    ]
    subprocess.run(import_command, cwd=root, env=env, check=True)

    command = [
        godot_binary,
        "--headless",
        "--path",
        ".",
        "--script",
        "tools/build_tilemap_tilesets.gd",
        "--",
        "res://%s" % MANIFEST_REL.as_posix(),
    ]
    subprocess.run(command, cwd=root, env=env, check=True)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Build deterministic TileMap atlases from extracted Sacked CO_BACKGROUND sprites.")
    parser.add_argument("--check", action="store_true", help="Build into a temporary directory and verify checked-in generated outputs are current.")
    parser.add_argument("--skip-godot", action="store_true", help="Only write atlas PNGs and manifest; do not regenerate TileSet resources.")
    parser.add_argument("--godot-binary", default="./Godot_v4.6.2-stable_linux.x86_64", help="Godot binary used to serialize TileSet resources.")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    root = repo_root()

    if args.check:
        with tempfile.TemporaryDirectory(prefix="sacked-tilemap-atlases-") as temp_dir:
            generated_root = Path(temp_dir)
            build_outputs(root, generated_root)
            return compare_generated(root, generated_root)

    build_outputs(root, root)
    if not args.skip_godot:
        run_godot_tileset_builder(root, args.godot_binary)
    return 0


if __name__ == "__main__":
    sys.exit(main())
