#!/usr/bin/env python3
"""Copy the animation frames the port needs, with their original pixel depth masks.

Which clips those are lives in tools/character_action_clips.json, shared with
tools/import_npc_action_animations.gd so the frames on disk and the AnimationLibraries
built from them can never drift apart. The player's rows come from the animation slot
table at 0x46EC04; see docs/player-action-reference.md.

The spec's "effects" rows are CO_CHARS records the executable names outright rather than
through a character's slot table, such as the puddle sub_41D630 gives both characters
(0x41D716). They have one view, so their frames are numbered in play order under
images/effects/<name>/.
"""

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


SPEC_REL = Path("tools/character_action_clips.json")


def load_specs(root: Path) -> list:
    """(character, source prefix, runtime prefix, angles) per clip, from the shared spec."""
    spec = json.loads((root / SPEC_REL).read_text())
    return [
        (row["character"], row["source"], "%s-%s" % (row["character"], row["action"]), tuple(row["angles"]))
        for row in spec["clips"]
    ]


def load_effects(root: Path) -> list:
    """(runtime name, CO_CHARS record name) per effect, from the shared spec."""
    spec = json.loads((root / SPEC_REL).read_text())
    return [(row["name"], row["record"]) for row in spec.get("effects", [])]


def effect_animation_path(root: Path, record: str) -> Path:
    return root / "extract-sacked-assets" / "extracted" / "animations_godot" / f"CO_CHARS_{record}_godot.json"


def effect_frame_path(root: Path, name: str, index: int) -> Path:
    return root / "images" / "effects" / name / f"{name}-{index:03d}.png"


def read_animation(path: Path, record: str = "") -> dict:
    animation = json.loads(path.read_text())
    if animation["frame_count"] != len(animation["frames"]):
        raise ValueError(f"Unexpected source frame count: {animation['name']}")
    if record and (animation["container"] != "CO_CHARS" or animation["name"] != record):
        raise ValueError(f"{path} holds {animation['container']}/{animation['name']}, not CO_CHARS/{record}")
    return animation


def export_frame(root: Path, frame: dict, destination: Path, check: bool, failures: list) -> None:
    source = source_frame_dir(root, frame)
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
        return
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


def export_assets(root: Path, check: bool) -> int:
    failures = []
    count = 0
    clips = 0
    for character, source_prefix, runtime_prefix, angles in load_specs(root):
        for angle in angles:
            clips += 1
            animation = read_animation(source_animation_path(root, source_prefix, angle))
            for frame in animation["frames"]:
                destination = runtime_frame_path(root, character, runtime_prefix, DIRECTIONS[angle], frame["sprite_name"])
                export_frame(root, frame, destination, check, failures)
                count += 1
    effect_frames = 0
    effects = load_effects(root)
    for name, record in effects:
        animation = read_animation(effect_animation_path(root, record), record)
        for index, frame in enumerate(animation["frames"]):
            export_frame(root, frame, effect_frame_path(root, name, index), check, failures)
            effect_frames += 1
    if failures:
        print("Missing or stale NPC action assets:\n" + "\n".join(failures))
        return 1
    print(
        f"{'Verified' if check else 'Exported'} {count} NPC action frames and depth masks in {clips} clips, "
        f"and {effect_frames} frames in {len(effects)} effects."
    )
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--check", action="store_true", help="Verify copied images and decoded depth pixels without writing files")
    args = parser.parse_args()
    return export_assets(args.root.resolve(), args.check)


if __name__ == "__main__":
    raise SystemExit(main())
