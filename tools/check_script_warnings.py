#!/usr/bin/env python3
"""Fail when any project script compiles with a GDScript warning.

Godot reports a script's warnings (a local shadowing a property, an integer division, an
unused variable, ...) when it compiles the script, which the editor's debugger lists while the
game runs. tools/load_every_script.gd compiles every script under --debug, where the same
warnings reach stdout; this lists them by file and line and fails if there are any. An
intended one is silenced at its line with @warning_ignore, as an integer division that is
meant to truncate is.

    python3 tools/check_script_warnings.py
"""

import re
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from godot_binary import find_godot_binary  # noqa: E402


ROOT = Path(__file__).resolve().parents[1]
LOCATION = re.compile(r"at: GDScript::reload \((res://[^:]+):(\d+)\)")


def warnings_in(output: str) -> list:
    """(path, line, message) for each compile warning in a --debug run's output."""
    found = []
    lines = output.splitlines()
    for index, line in enumerate(lines[:-1]):
        if not line.startswith("WARNING: "):
            continue
        match = LOCATION.search(lines[index + 1])
        if match:
            found.append((match.group(1), int(match.group(2)), line[len("WARNING: "):].strip()))
    return found


def main() -> int:
    completed = subprocess.run(
        [find_godot_binary(ROOT), "--headless", "--debug", "--path", ".", "--script", "tools/load_every_script.gd"],
        cwd=ROOT,
        # A script error stops at the debugger's prompt; this answers every one with "continue".
        input="c\n" * 500,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=600,
    )
    found = warnings_in(completed.stdout)
    for path, line, message in found:
        print(f"{path.removeprefix('res://')}:{line}: {message}")
    loaded = re.search(r"Loaded (\d+) scripts", completed.stdout)
    if loaded is None:
        print("tools/load_every_script.gd did not finish", file=sys.stderr)
        return 1
    if found:
        print(f"{len(found)} script warning(s) in {loaded.group(1)} scripts", file=sys.stderr)
        return 1
    print(f"No script warnings in {loaded.group(1)} scripts")
    return 0


if __name__ == "__main__":
    sys.exit(main())
