#!/usr/bin/env python3
"""Export the damaged states of the objects a level can prank.

Every interactive object ships one sprite set per state -- IDLE, USE, DESTROY_1..7 and
DESTROYED_1..7 -- but the level importer only ever copied out the IDLE frame, so nothing
in the port could show an object after it had been sabotaged.

An action names a DESTROY_n state; the engine plays that clip once and then advances the
object to the matching DESTROYED_n, which loops. Plenty of objects ship no DESTROY_n at
all and jump straight to their damaged art. See docs/prank-reference.md.

Timing comes from the container's own ANIM chunks. The loop flag there is not authoritative
for DESTROY_n, because the runtime forces those to play once regardless.
"""

import argparse
import json
import sys
from pathlib import Path

from PIL import Image

try:
    from export_character_depth_maps import encode_depth_rgba, read_frame_depth, write_rgba_png
    from import_original_level import imported_level_numbers, level_paths
except ImportError:  # imported as tools.export_object_state_assets by the tests
    from tools.export_character_depth_maps import encode_depth_rgba, read_frame_depth, write_rgba_png
    from tools.import_original_level import imported_level_numbers, level_paths


def level_manifests(root: Path):
    """Every imported level, in numeric order so first-seen fields never reshuffle."""
    for number in imported_level_numbers(root):
        path = root / level_paths(number).manifest_rel
        if path.is_file():
            yield json.loads(path.read_text())


EXTRACTION_TOOLS_REL = Path("extract-sacked-assets/tools")
CONTAINER_REL = Path("extract-sacked-assets/sacked/CO_OBJECTS.OGD")
TEXTURE_ROOT_REL = Path("extract-sacked-assets/extracted/textures/CO_OBJECTS")
ACTIONS_REL = Path("resources/original/actions.json")
STATE_IMAGE_DIR_REL = Path("images/objects/states")
STATE_MANIFEST_DIR_REL = Path("resources/objects")

# sub_40FDA0 clamps an item state to 0..15; DESTROY_n advances to DESTROYED_n.
DESTROYED_OFFSET = 7
FIRST_TRANSITION_STATE = 2
LAST_TRANSITION_STATE = 8

# sub_41DC80: three action ids reach past their own object and put something else into
# DESTROYED_1. Those targets carry no action ids of their own -- the projector screen action
# 116 switches on has none at all -- so their art has to be pulled in by what points at them
# rather than by what they offer. See docs/prank-reference.md.
CONSEQUENCE_STATE = 9  # DESTROYED_1
GLOBAL_CONSEQUENCE_TARGETS = {
    79: {"item_type": 253},   # every air conditioner
    116: {"item_type": 265},  # the nearest projector screen within +/-5 tiles
    118: {"category": 9},     # every meeting-room item
}
# No sprite in the container is anywhere near this far from its own frame, so a pivot past
# it means the field was read unsigned again; an off-frame sprite drags the world's static
# composite bounds out with it.
PIVOT_SANITY_LIMIT = 4096

# States a level can ask an object for that ship no art at all. sub_40FDA0 stores the state
# regardless and keeps the previous clip, so the object reaches its damaged look without a
# transition; the port settles an unplayable DESTROY_n on its DESTROYED_n instead. Listing
# them keeps the gap from growing silently -- a state that stops resolving fails the check.
KNOWN_MISSING_STATES = {
    "aktiv-aktenablage-180 DESTROY_1 (no clip in the container)",
    "aktiv-aquarium-000 DESTROY_2 (no clip in the container)",
    "aktiv-aushang-090 DESTROY_1 (no clip in the container)",
    "aktiv-aushang2-000 DESTROY_1 (no clip in the container)",
    "aktiv-beamer-270 DESTROYED_1 (no clip in the container)",
    "aktiv-beamer-270 DESTROY_1 (no clip in the container)",
    "aktiv-chefbild01-090 DESTROY_1 (no clip in the container)",
    "aktiv-chefbild02-090 DESTROY_1 (no clip in the container)",
    "aktiv-chefbild03-000 DESTROY_1 (no clip in the container)",
    "aktiv-chefvitrine-000 DESTROY_1 (no clip in the container)",
    "aktiv-coffeemat-090 DESTROY_1 (no clip in the container)",
    "aktiv-coffeemat-090 DESTROY_4 (no clip in the container)",
    "aktiv-colamat-000 DESTROY_1 (no clip in the container)",
    "aktiv-colamat-000 DESTROY_4 (no clip in the container)",
    "aktiv-disketten-000 DESTROY_1 (no clip in the container)",
    "aktiv-drucker01-000 DESTROY_1 (no clip in the container)",
    "aktiv-drucker01-180 DESTROY_1 (no clip in the container)",
    "aktiv-fenster01-000 DESTROY_1 (no clip in the container)",
    "aktiv-fenster01-090 DESTROY_1 (no clip in the container)",
    "aktiv-fenster02-000 DESTROY_1 (no clip in the container)",
    "aktiv-fenster02-090 DESTROY_1 (no clip in the container)",
    "aktiv-fenster03-000 DESTROY_1 (no clip in the container)",
    "aktiv-fenster03-090 DESTROY_1 (no clip in the container)",
    "aktiv-flipchart-000 DESTROY_1 (no clip in the container)",
    "aktiv-flipchart-090 DESTROY_1 (no clip in the container)",
    "aktiv-handtuchspender-000 DESTROY_1 (no clip in the container)",
    "aktiv-handy-000 DESTROY_1 (no clip in the container)",
    "aktiv-heizungssteuerung-090 DESTROYED_1 (no clip in the container)",
    "aktiv-heizungssteuerung-090 DESTROY_1 (no clip in the container)",
    "aktiv-k-hlschrank-000 DESTROYED_1 (no clip in the container)",
    "aktiv-k-hlschrank-000 DESTROYED_2 (no clip in the container)",
    "aktiv-k-hlschrank-000 DESTROYED_3 (no clip in the container)",
    "aktiv-k-hlschrank-000 DESTROY_1 (no clip in the container)",
    "aktiv-k-hlschrank-000 DESTROY_2 (no clip in the container)",
    "aktiv-k-hlschrank-000 DESTROY_3 (no clip in the container)",
    "aktiv-kaffeemaschi-270 DESTROYED_2 (no clip in the container)",
    "aktiv-kaffeemaschi-270 DESTROY_1 (no clip in the container)",
    "aktiv-kopierer-000 DESTROY_1 (no clip in the container)",
    "aktiv-kopierer-000 DESTROY_2 (no clip in the container)",
    "aktiv-monitor-kaffee-000 DESTROYED_1 (no clip in the container)",
    "aktiv-monitor-kaffee-000 DESTROYED_2 (no clip in the container)",
    "aktiv-monitor-kaffee-000 DESTROYED_3 (no clip in the container)",
    "aktiv-monitor-kaffee-000 DESTROYED_4 (no clip in the container)",
    "aktiv-monitor-kaffee-000 DESTROY_1 (no clip in the container)",
    "aktiv-monitor-kaffee-000 DESTROY_2 (no clip in the container)",
    "aktiv-monitor-kaffee-000 DESTROY_3 (no clip in the container)",
    "aktiv-monitor-kaffee-000 DESTROY_4 (no clip in the container)",
    "aktiv-monitor-tastatur-frontal-000 DESTROYED_1 (no clip in the container)",
    "aktiv-monitor-tastatur-frontal-000 DESTROYED_2 (no clip in the container)",
    "aktiv-monitor-tastatur-frontal-000 DESTROYED_3 (no clip in the container)",
    "aktiv-monitor-tastatur-frontal-000 DESTROY_1 (no clip in the container)",
    "aktiv-monitor-tastatur-frontal-000 DESTROY_2 (no clip in the container)",
    "aktiv-monitor-tastatur-frontal-000 DESTROY_3 (no clip in the container)",
    "aktiv-monitor-tastatur-links-000 DESTROYED_1 (no clip in the container)",
    "aktiv-monitor-tastatur-links-000 DESTROYED_2 (no clip in the container)",
    "aktiv-monitor-tastatur-links-000 DESTROYED_3 (no clip in the container)",
    "aktiv-monitor-tastatur-links-000 DESTROY_1 (no clip in the container)",
    "aktiv-monitor-tastatur-links-000 DESTROY_2 (no clip in the container)",
    "aktiv-monitor-tastatur-links-000 DESTROY_3 (no clip in the container)",
    "aktiv-monitor-tastatur-links-180 DESTROYED_1 (no clip in the container)",
    "aktiv-monitor-tastatur-links-180 DESTROYED_2 (no clip in the container)",
    "aktiv-monitor-tastatur-links-180 DESTROYED_3 (no clip in the container)",
    "aktiv-monitor-tastatur-links-180 DESTROY_1 (no clip in the container)",
    "aktiv-monitor-tastatur-links-180 DESTROY_2 (no clip in the container)",
    "aktiv-monitor-tastatur-links-180 DESTROY_3 (no clip in the container)",
    "aktiv-monitor-tastatur-rechts-000 DESTROYED_1 (no clip in the container)",
    "aktiv-monitor-tastatur-rechts-000 DESTROYED_2 (no clip in the container)",
    "aktiv-monitor-tastatur-rechts-000 DESTROYED_3 (no clip in the container)",
    "aktiv-monitor-tastatur-rechts-000 DESTROY_1 (no clip in the container)",
    "aktiv-monitor-tastatur-rechts-000 DESTROY_2 (no clip in the container)",
    "aktiv-monitor-tastatur-rechts-000 DESTROY_3 (no clip in the container)",
    "aktiv-poster01-090 DESTROY_1 (no clip in the container)",
    "aktiv-poster03-000 DESTROY_1 (no clip in the container)",
    "aktiv-poster04-090 DESTROY_1 (no clip in the container)",
    "aktiv-putzeimer-000 DESTROY_1 (no clip in the container)",
    "aktiv-salz-zucker-090 DESTROYED_1 (no clip in the container)",
    "aktiv-salz-zucker-090 DESTROY_1 (no clip in the container)",
    "aktiv-schwarzbrett-000 DESTROY_1 (no clip in the container)",
    "aktiv-schwarzbrett-000 DESTROY_2 (no clip in the container)",
    "aktiv-schwarzbrett-000 DESTROY_3 (no clip in the container)",
    "aktiv-server-000 DESTROY_1 (no clip in the container)",
    "aktiv-server-000 DESTROY_6 (no clip in the container)",
    "aktiv-spiegel-000 DESTROY_1 (no clip in the container)",
    "aktiv-spiegel-090 DESTROY_1 (no clip in the container)",
    "aktiv-spuele-000 DESTROYED_1 (frames missing on disk)",
    "aktiv-spuele-000 DESTROY_1 (no clip in the container)",
    "aktiv-spuele-090 DESTROYED_1 (frames missing on disk)",
    "aktiv-spuele-090 DESTROY_1 (no clip in the container)",
    "aktiv-spuelmaschine-000 DESTROYED_1 (frames missing on disk)",
    "aktiv-spuelmaschine-000 DESTROY_1 (no clip in the container)",
    "aktiv-stifthalter01-000 DESTROY_1 (no clip in the container)",
    "aktiv-tafel-090 DESTROY_1 (no clip in the container)",
    "aktiv-teddy-180 DESTROY_1 (no clip in the container)",
    "aktiv-telefon01-180 DESTROYED_1 (no clip in the container)",
    "aktiv-telefon01-180 DESTROY_2 (no clip in the container)",
    "aktiv-tischlampe2-270 DESTROY_1 (no clip in the container)",
    "aktiv-toikabine-000 DESTROY_1 (no clip in the container)",
    "aktiv-toikabine-000 DESTROY_2 (no clip in the container)",
    "aktiv-toikabine-000 DESTROY_3 (no clip in the container)",
    "aktiv-toikabine-090 DESTROY_1 (no clip in the container)",
    "aktiv-toikabine-090 DESTROY_2 (no clip in the container)",
    "aktiv-toikabine-090 DESTROY_3 (no clip in the container)",
    "aktiv-waschbecken-000 DESTROY_1 (no clip in the container)",
    "aktiv-waschbecken-090 DESTROY_1 (no clip in the container)",
}


def load_container(root: Path):
    sys.path.insert(0, str(root / EXTRACTION_TOOLS_REL))
    import animation_exporter
    import extract_animations

    data = (root / CONTAINER_REL).read_bytes()
    animations = {anim.name: anim for anim in extract_animations.parse_animations(str(root / CONTAINER_REL))}
    sprites = animation_exporter.collect_sprite_info(data)
    return animations, sprites


def slug(text: str) -> str:
    return "".join(character if character.isalnum() else "-" for character in text.lower()).strip("-")


def signed16(value: int) -> int:
    """SPRITEHDR pivots are signed, and a sprite anchored left of its own frame has a
    negative one. The extraction helper reads the field unsigned, so -6 arrives as 65530;
    import_original_level.py reads the same field with read_s16 for the IDLE sprite."""
    return value - 0x10000 if value >= 0x8000 else value


def wanted_states(actions: dict, action_ids: list) -> list:
    """The states a level can actually put an object into, in a stable order."""
    states = []
    for action_id in action_ids:
        result = actions["actions"][action_id]["result_state"]
        if result >= len(actions["item_states"]):
            continue  # 17 and 18 are markers, not states
        for state in (result, result + DESTROYED_OFFSET):
            if state < len(actions["item_states"]) and state not in states:
                states.append(state)
    return states


def item_type(entry: dict) -> int:
    return (int(entry["kind"], 16) >> 4) & 0xFFF


def consequence_states(manifest: dict, entry: dict) -> list:
    """DESTROYED_1, when some action placed on this level reaches this object from another."""
    for action_id, target in GLOBAL_CONSEQUENCE_TARGETS.items():
        if not any(action_id in other["action_ids"] for other in manifest["objects"]):
            continue
        if target.get("item_type") == item_type(entry) or target.get("category") == entry["object_category"]:
            return [CONSEQUENCE_STATE]
    return []


def object_specs(root: Path) -> list:
    """One entry per (object texture, needed states), derived from the level manifests."""
    actions = json.loads((root / ACTIONS_REL).read_text())
    specs = {}
    for manifest in level_manifests(root):
        for item in manifest["objects"]:
            states = wanted_states(actions, item["action_ids"]) + consequence_states(manifest, item)
            if not states:
                continue
            source = item["source_sprite"]
            if "_IDLE_" not in source:
                continue
            prefix, rest = source.rsplit("_IDLE_", 1)
            angle = rest.split("_")[0]
            key = Path(item["texture"]).stem
            specs.setdefault(key, {"prefix": prefix, "angle": angle, "states": [], "sprite": item["sprite_name"]})
            for state in states:
                if state not in specs[key]["states"]:
                    specs[key]["states"].append(state)
    return [(key, value) for key, value in sorted(specs.items())]


def frame_paths(root: Path, sprites: dict, frame_ids: list) -> list:
    result = []
    for frame_id in frame_ids:
        info = sprites.get(frame_id)
        if info is None:
            return []
        folder = root / TEXTURE_ROOT_REL / info.name
        if not (folder / f"{info.name}.png").is_file():
            return []
        result.append((info, folder))
    return result


def export(root: Path, check: bool) -> int:
    actions = json.loads((root / ACTIONS_REL).read_text())
    state_names = actions["item_states"]
    animations, sprites = load_container(root)

    failures = []
    unresolved = []
    written = clips = 0

    for key, spec in object_specs(root):
        states = {}
        for state in spec["states"]:
            name = f"{spec['prefix']}_{state_names[state]}_{spec['angle']}"
            anim = animations.get(name)
            if anim is None:
                unresolved.append(f"{key} {state_names[state]} (no clip in the container)")
                continue
            frames = frame_paths(root, sprites, anim.frames)
            if not frames:
                unresolved.append(f"{key} {state_names[state]} (frames missing on disk)")
                continue
            clips += 1
            entries = []
            for index, (info, folder) in enumerate(frames):
                stem = f"{key}-{slug(state_names[state])}-{index:03d}"
                destination = root / STATE_IMAGE_DIR_REL / key / f"{stem}.png"
                depth_destination = destination.with_name(f"{stem}-depth.png")
                source = folder / f"{info.name}.png"
                written += 1
                pivot = [signed16(info.pivot_x), signed16(info.pivot_y)]
                if max(abs(pivot[0]), abs(pivot[1])) > PIVOT_SANITY_LIMIT:
                    failures.append(f"{key} {state_names[state]} frame {index} has pivot {pivot}")
                entries.append(
                    {
                        "texture": f"res://{destination.relative_to(root).as_posix()}",
                        "pivot": pivot,
                        "size": [info.w, info.h],
                    }
                )
                if check:
                    if not destination.is_file() or destination.read_bytes() != source.read_bytes():
                        failures.append(str(destination.relative_to(root)))
                    _check_depth(root, folder, info, depth_destination, failures)
                else:
                    destination.parent.mkdir(parents=True, exist_ok=True)
                    destination.write_bytes(source.read_bytes())
                    _write_depth(folder, info, depth_destination)
            states[state_names[state]] = {
                "state": state,
                "fps": float(anim.fps),
                # The runtime forces DESTROY_n to play once whatever the container says.
                "loop": not (FIRST_TRANSITION_STATE <= state <= LAST_TRANSITION_STATE),
                "advances_to": state + DESTROYED_OFFSET
                if FIRST_TRANSITION_STATE <= state <= LAST_TRANSITION_STATE
                else None,
                "frames": entries,
            }

        manifest = {
            "generated_by": "tools/export_object_state_assets.py",
            "sprite": spec["sprite"],
            "angle": spec["angle"],
            "states": states,
        }
        path = root / STATE_MANIFEST_DIR_REL / f"{key}.json"
        text = json.dumps(manifest, ensure_ascii=False, indent=2, sort_keys=True) + "\n"
        if check:
            if not path.is_file():
                failures.append(f"{path.relative_to(root)} is missing")
            elif path.read_text() != text:
                failures.append(f"{path.relative_to(root)} is stale")
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text)

    if failures:
        print("Object state assets out of date:\n" + "\n".join(f"  {line}" for line in failures[:20]))
        return 1

    appeared = sorted(set(unresolved) - KNOWN_MISSING_STATES)
    resolved = sorted(KNOWN_MISSING_STATES - set(unresolved))
    if appeared or resolved:
        print("KNOWN_MISSING_STATES no longer matches the container:")
        for line in appeared:
            print(f"  now missing, not listed: {line}")
        for line in resolved:
            print(f"  listed, but resolves now: {line}")
        return 1

    print(
        f"{'Verified' if check else 'Exported'} {written} frames across {clips} state clips. "
        f"{len(unresolved)} states have no art and settle on the object's damaged state instead."
    )
    return 0


def _write_depth(folder: Path, info, destination: Path) -> None:
    if not (folder / "SPRITEZB.bin").is_file():
        destination.unlink(missing_ok=True)
        return
    depth, mask = read_frame_depth(folder, info.w, info.h)
    write_rgba_png(destination, info.w, info.h, encode_depth_rgba(depth, mask, info.w, info.h))


def _check_depth(root: Path, folder: Path, info, destination: Path, failures: list) -> None:
    if not (folder / "SPRITEZB.bin").is_file():
        if destination.is_file():
            failures.append(f"{destination.relative_to(root)} (source has no Z plane)")
        return
    if not destination.is_file():
        failures.append(str(destination.relative_to(root)))
        return
    depth, mask = read_frame_depth(folder, info.w, info.h)
    expected = encode_depth_rgba(depth, mask, info.w, info.h)
    with Image.open(destination) as actual:
        if actual.size != (info.w, info.h) or actual.convert("RGBA").tobytes() != expected:
            failures.append(str(destination.relative_to(root)))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--check", action="store_true", help="Verify exported state assets without writing")
    args = parser.parse_args()
    return export(args.root.resolve(), args.check)


if __name__ == "__main__":
    raise SystemExit(main())
