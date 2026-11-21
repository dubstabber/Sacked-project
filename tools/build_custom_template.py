#!/usr/bin/env python3
"""Build scenes/custom_level_template.tscn, the starting point for a custom map.

The template is level 1's office as the original built it: its floor, walls, movement cells,
rooms and sight blockers, and the player's spawn. It keeps one furnished desk, the cola machine
and the windows, and one coworker with no desk assigned, which the level start's search
(scenes/npc/npc_startup.gd) gives one at run time. Everything else is left for the designer;
see docs/map-authoring.md.

    python3 tools/build_custom_template.py           # write the spec and build the scene
    python3 tools/build_custom_template.py --check   # the spec matches level 1, the scene exists

The spec, resources/templates/custom_level.json, is a level manifest cut down from
resources/levels/level_1.json, which tools/build_level_scene.gd builds like any other.
"""

import argparse
import json
import os
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from godot_binary import find_godot_binary  # noqa: E402
from import_original_level import OBJECT_PREFAB_DIR_REL, normalize_scene_file  # noqa: E402


ROOT = Path(__file__).resolve().parents[1]
SOURCE_REL = Path("resources/levels/level_1.json")
SPEC_REL = Path("resources/templates/custom_level.json")
SCENE_REL = Path("scenes/custom_level_template.tscn")
# The desk the male coworker works at in level 1 (desk, swivel chair, monitor, PC tower) and
# the cola machine; the windows are kept by name, as they belong to the walls.
KEPT_RECORDS = {"ITEM0", "ITEM1", "ITEM2", "ITEM3", "ITEM28"}
KEPT_NAME_PREFIXES = ("Fenster",)
# Male employee 1, who sits at that desk in level 1.
KEPT_NPC = "Npc079MaleEmployee1"


def build_spec(level: dict) -> dict:
    spec = {key: value for key, value in level.items() if key not in ("objects", "npcs", "parked_items")}
    spec["generated_by"] = "tools/build_custom_template.py"
    spec["source"] = SOURCE_REL.as_posix()
    spec["objects"] = [
        entry for entry in level["objects"]
        if entry["record_name"] in KEPT_RECORDS or str(entry["display_name"]).startswith(KEPT_NAME_PREFIXES)
    ]
    npcs = []
    for npc in level["npcs"]:
        if npc["node_name"] != KEPT_NPC:
            continue
        npc = dict(npc)
        # Left to the level start's search, as for any agent a designer drops in.
        npc["assigned_workstation_instance_id"] = None
        npc["assigned_chair_instance_id"] = None
        npc["runtime_desk"] = True
        npcs.append(npc)
    spec["npcs"] = npcs
    return spec


def spec_text(spec: dict) -> str:
    return json.dumps(spec, indent=2, sort_keys=True, ensure_ascii=False) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--check", action="store_true", help="verify instead of writing")
    args = parser.parse_args()

    spec = build_spec(json.loads((ROOT / SOURCE_REL).read_text(encoding="utf-8")))
    text = spec_text(spec)
    spec_path = ROOT / SPEC_REL
    if args.check:
        failures = []
        if not spec_path.is_file() or spec_path.read_text(encoding="utf-8") != text:
            failures.append(f"stale {SPEC_REL}")
        if not (ROOT / SCENE_REL).is_file():
            failures.append(f"missing {SCENE_REL}")
        for failure in failures:
            print(failure, file=sys.stderr)
        if not failures:
            print(f"Custom level template is up to date ({len(spec['objects'])} objects, {len(spec['npcs'])} coworker)")
        return 1 if failures else 0

    spec_path.parent.mkdir(parents=True, exist_ok=True)
    spec_path.write_text(text, encoding="utf-8")
    env = os.environ.copy()
    env.setdefault("HOME", "/tmp/sacked-godot-home")
    env.setdefault("XDG_CONFIG_HOME", "/tmp/sacked-godot-config")
    env.setdefault("XDG_DATA_HOME", "/tmp/sacked-godot-xdg")
    subprocess.run(
        [find_godot_binary(ROOT), "--headless", "--path", ".", "--script", "tools/build_level_scene.gd", "--",
         "res://%s" % SPEC_REL.as_posix(), "res://%s" % SCENE_REL.as_posix()],
        cwd=ROOT, env=env, check=True,
    )
    normalize_scene_file(ROOT / SCENE_REL)
    # The builder saves every prefab it places again; normalised, they come out unchanged.
    for prefab in sorted((ROOT / OBJECT_PREFAB_DIR_REL).glob("*.tscn")):
        normalize_scene_file(prefab)
    return 0


if __name__ == "__main__":
    sys.exit(main())
