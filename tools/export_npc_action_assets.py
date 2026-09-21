#!/usr/bin/env python3
"""Copy the first level's sitting animations and their original pixel depth masks."""

import argparse
import json
import shutil
from pathlib import Path

from PIL import Image

from export_character_depth_maps import (
    DIRECTIONS,
    encode_depth_rgba,
    read_frame_depth,
    runtime_frame_path,
    source_animation_path,
    source_frame_dir,
    write_rgba_png,
)


# Seated clips only exist for the four diagonal views; standing ones have all eight.
SEATED_ANGLES = ("000", "090", "180", "270")
STANDING_ANGLES = ("000", "045", "090", "135", "180", "225", "270", "315")

SPECS = [
    ("boss", "CHEF_SIT#IDLE", "boss-sit-idle", SEATED_ANGLES),
    ("boss", "CHEF_SIT#EASY", "boss-sit-easy", SEATED_ANGLES),
    ("male-employee-1", "ANGESTELLTER#1_SIT#IDLE", "male-employee-1-sit-idle", SEATED_ANGLES),
    ("male-employee-1", "ANGESTELLTER#1_SIT#USE", "male-employee-1-sit-use", SEATED_ANGLES),
    ("male-employee-1", "ANGESTELLTER#1_SIT#EASY", "male-employee-1-sit-easy", SEATED_ANGLES),
    ("male-employee-1", "ANGESTELLTER#1_SPECIAL#1", "male-employee-1-special-1", STANDING_ANGLES),
    ("female-employee-1", "ANGESTELLTE#1_SIT#IDLE", "female-employee-1-sit-idle", SEATED_ANGLES),
    ("female-employee-1", "ANGESTELLTE#1_SIT#USE", "female-employee-1-sit-use", SEATED_ANGLES),
    ("female-employee-1", "ANGESTELLTE#1_SIT#EASY", "female-employee-1-sit-easy", SEATED_ANGLES),
    ("female-employee-1", "ANGESTELLTE#1_SPECIAL#1", "female-employee-1-special-1", STANDING_ANGLES),
]


def export_assets(root: Path, check: bool) -> int:
    failures = []
    count = 0
    clips = 0
    for character, source_prefix, runtime_prefix, angles in SPECS:
        for angle in angles:
            clips += 1
            animation = json.loads(source_animation_path(root, source_prefix, angle).read_text())
            if animation["frame_count"] != len(animation["frames"]):
                raise ValueError(f"Unexpected source frame count: {animation['name']}")
            for frame in animation["frames"]:
                source = source_frame_dir(root, frame)
                destination = runtime_frame_path(root, character, runtime_prefix, DIRECTIONS[angle], frame["sprite_name"])
                width, height = int(frame["w"]), int(frame["h"])
                depth_path = destination.with_name(destination.stem + "-depth.png")
                if not (source.parent / "SPRITEZB.bin").is_file():
                    # A handful of original frames ship no Z plane; the engine blits those
                    # without a depth test, which the runtime reproduces when the mask is absent.
                    if check:
                        if not destination.is_file() or destination.read_bytes() != source.read_bytes():
                            failures.append(str(destination.relative_to(root)))
                        if depth_path.is_file():
                            failures.append(f"{depth_path.relative_to(root)} (source has no Z plane)")
                    else:
                        destination.parent.mkdir(parents=True, exist_ok=True)
                        shutil.copy2(source, destination)
                        depth_path.unlink(missing_ok=True)
                    count += 1
                    continue
                depth, mask = read_frame_depth(source.parent, width, height)
                rgba = encode_depth_rgba(depth, mask, width, height)
                if check:
                    if not destination.is_file() or destination.read_bytes() != source.read_bytes():
                        failures.append(str(destination.relative_to(root)))
                    if not depth_path.is_file():
                        failures.append(str(depth_path.relative_to(root)))
                    else:
                        with Image.open(depth_path) as actual:
                            if actual.size != (width, height) or actual.convert("RGBA").tobytes() != rgba:
                                failures.append(str(depth_path.relative_to(root)))
                else:
                    destination.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copy2(source, destination)
                    write_rgba_png(depth_path, width, height, rgba)
                count += 1
    if failures:
        print("Missing or stale NPC action assets:\n" + "\n".join(failures))
        return 1
    print(f"{'Verified' if check else 'Exported'} {count} NPC action frames and depth masks in {clips} clips.")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--check", action="store_true", help="Verify copied images and decoded depth pixels without writing files")
    args = parser.parse_args()
    return export_assets(args.root.resolve(), args.check)


if __name__ == "__main__":
    raise SystemExit(main())
