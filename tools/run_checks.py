#!/usr/bin/env python3
"""Run every headless GDScript check, the Python unit tests and each exporter's --check."""

import argparse
import subprocess
import sys
import time
from pathlib import Path

from godot_binary import find_godot_binary


ROOT = Path(__file__).resolve().parents[1]
EXTRACTION_REL = Path("extract-sacked-assets")

# Exporters and importers whose --check mode re-derives their outputs from the reference
# extraction and compares them against the checked-in files. They are skipped without it.
REFERENCE_CHECKS = [
    ["tools/export_action_table.py", "--check"],
    ["tools/export_character_depth_maps.py", "--check"],
    ["tools/export_npc_action_assets.py", "--check"],
    ["tools/export_world_depth_maps.py", "--check"],
    ["tools/build_tilemap_atlases.py", "--check"],
    ["tools/import_original_level.py", "--check"],
]


def run(label: str, command: list, verbose: bool) -> tuple:
    start = time.monotonic()
    completed = subprocess.run(
        command,
        cwd=ROOT,
        capture_output=not verbose,
        text=True,
    )
    elapsed = time.monotonic() - start
    ok = completed.returncode == 0
    print(f"{'PASS' if ok else 'FAIL'}  {label}  ({elapsed:.1f}s)")
    if not ok and not verbose:
        output = (completed.stdout or "") + (completed.stderr or "")
        print("\n".join(f"      {line}" for line in output.strip().splitlines()[-40:]))
    return ok, elapsed


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--skip-import", action="store_true", help="Do not reimport Godot assets first")
    parser.add_argument("--filter", default="", help="Only run steps whose label contains this text")
    parser.add_argument("--verbose", action="store_true", help="Stream each step's output instead of capturing it")
    args = parser.parse_args()

    godot = find_godot_binary(ROOT)
    steps = []

    # Freshly exported PNGs have no .import sidecar until Godot reimports them, and the
    # GDScript checks load them through res:// paths.
    if not args.skip_import:
        steps.append(("godot --import", [godot, "--headless", "--path", ".", "--import"]))

    for script in sorted((ROOT / "tests").glob("check_*.gd")):
        steps.append((script.name, [godot, "--headless", "--script", f"tests/{script.name}"]))

    # Discovery roots at tests/ because it is not a package; cwd still puts tools/ on sys.path.
    steps.append(("python unittest", [sys.executable, "-m", "unittest", "discover", "-s", "tests", "-t", "tests"]))

    if (ROOT / EXTRACTION_REL).is_dir():
        for command in REFERENCE_CHECKS:
            steps.append((f"{Path(command[0]).name} --check", [sys.executable] + command))
    else:
        print(f"SKIP  reference exporter checks ({EXTRACTION_REL} is absent)")

    if args.filter:
        steps = [step for step in steps if args.filter in step[0]]

    failures = []
    total = 0.0
    for label, command in steps:
        ok, elapsed = run(label, command, args.verbose)
        total += elapsed
        if not ok:
            failures.append(label)

    print(f"\n{len(steps) - len(failures)}/{len(steps)} steps passed in {total:.1f}s")
    if failures:
        print("Failed: " + ", ".join(failures))
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
