#!/usr/bin/env python3
"""Run every headless GDScript check, the Python unit tests and each exporter's --check."""

import argparse
import re
import subprocess
import sys
import time
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
EXTRACTION_REL = Path("extract-sacked-assets")

# Exporters and importers whose --check mode re-derives their outputs from the reference
# extraction and compares them against the checked-in files. They are skipped without it.
REFERENCE_CHECKS = [
    ["tools/export_action_table.py", "--check"],
    ["tools/export_strings.py", "--check"],
    ["tools/export_names.py", "--check"],
    ["tools/export_repairable_types.py", "--check"],
    ["tools/export_level_index.py", "--check"],
    ["tools/export_npc_profiles.py", "--check"],
    ["tools/export_gui_assets.py", "--check"],
    ["tools/export_sounds.py", "--check"],
    ["tools/export_object_state_assets.py", "--check"],
    ["tools/export_character_depth_maps.py", "--check"],
    ["tools/export_npc_action_assets.py", "--check"],
    ["tools/export_world_depth_maps.py", "--check"],
    ["tools/build_tilemap_atlases.py", "--check"],
    ["tools/import_original_level.py", "--check"],
]

# A GDScript runtime or compile error, or a signal or deferred call Godot could not dispatch,
# leaves a --script run's exit code at 0: a check whose preloaded game script no longer
# parses still prints its "passed" line and quits cleanly, so this line is the only trace.
# Searched rather than anchored so that a colour-coded SCRIPT ERROR still counts.
FAILURE_LINE = re.compile(r"SCRIPT ERROR:|^ERROR: Error calling ")
# A check whose _init or _run itself errors never reaches quit() and would hold the run.
CHECK_TIMEOUT = 600
TAIL_LINES = 40


def _decode(part) -> str:
    # TimeoutExpired carries the output read so far as bytes, even under text=True.
    return part.decode(errors="replace") if isinstance(part, bytes) else (part or "")


def _print_indented(lines: list) -> None:
    for line in lines:
        print(f"      {line}")


def run(label: str, command: list, verbose: bool, script_check: bool = False) -> tuple:
    start = time.monotonic()
    timeout = CHECK_TIMEOUT if script_check else None
    try:
        completed = subprocess.run(
            command,
            cwd=ROOT,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=timeout,
        )
        returncode, output = completed.returncode, completed.stdout or ""
    except subprocess.TimeoutExpired as expired:
        returncode, output = None, _decode(expired.stdout)
    elapsed = time.monotonic() - start
    lines = output.strip().splitlines()
    errors = [i for i, line in enumerate(lines) if FAILURE_LINE.search(line)] if script_check else []
    ok = returncode == 0 and not errors
    print(f"{'PASS' if ok else 'FAIL'}  {label}  ({elapsed:.1f}s)")
    if not verbose and ok:
        return ok, elapsed

    first_shown = 0 if verbose else max(0, len(lines) - TAIL_LINES)
    # An error above the tail is listed with its location first; one inside it is not repeated.
    for i in errors:
        if i < first_shown:
            location = [line for line in lines[i + 1 : i + 2] if line.lstrip().startswith("at:")]
            _print_indented([lines[i]] + location)
    if first_shown:
        _print_indented(["..."])
    _print_indented(lines[first_shown:])
    if returncode is None:
        _print_indented([f"timed out after {timeout}s without quitting"])
    elif errors:
        _print_indented([f"exited {returncode}, but logged {len(errors)} error line(s)"])
    return ok, elapsed


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--skip-import", action="store_true", help="Do not reimport Godot assets first")
    parser.add_argument("--filter", default="", help="Only run steps whose label contains this text")
    parser.add_argument("--verbose", action="store_true", help="Print each step's full output once it finishes")
    args = parser.parse_args()

    # Imported here, not at module scope: tests/test_run_checks.py imports this file as
    # tools.run_checks, where sibling modules are not on sys.path.
    from godot_binary import find_godot_binary

    godot = find_godot_binary(ROOT)
    steps = []

    # Freshly exported PNGs have no .import sidecar until Godot reimports them, and the
    # GDScript checks load them through res:// paths.
    if not args.skip_import:
        steps.append(("godot --import", [godot, "--headless", "--path", ".", "--import"], False))

    for script in sorted((ROOT / "tests").glob("check_*.gd")):
        command = [godot, "--headless"]
        # A check that simulates an office advances on the wall clock, so two simulated
        # minutes cost two real ones. A fixed 10 fps frame still runs six 1/60 physics
        # ticks, under max_physics_steps_per_frame, so every decision is unchanged while
        # the run takes seconds. Verified identical on check_npc_level_2_runtime.gd, down
        # to the secretary's 292 and the janitor's 1143 navigation retries.
        if "runtime" in script.name:
            command += ["--fixed-fps", "10"]
        steps.append((script.name, command + ["--script", f"tests/{script.name}"], True))

    # Discovery roots at tests/ because it is not a package; cwd still puts tools/ on sys.path.
    steps.append(("python unittest", [sys.executable, "-m", "unittest", "discover", "-s", "tests", "-t", "tests"], False))

    if (ROOT / EXTRACTION_REL).is_dir():
        for command in REFERENCE_CHECKS:
            steps.append((f"{Path(command[0]).name} --check", [sys.executable] + command, False))
    else:
        print(f"SKIP  reference exporter checks ({EXTRACTION_REL} is absent)")

    if args.filter:
        steps = [step for step in steps if args.filter in step[0]]

    failures = []
    total = 0.0
    for label, command, script_check in steps:
        ok, elapsed = run(label, command, args.verbose, script_check)
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
