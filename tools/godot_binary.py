#!/usr/bin/env python3
"""Locate the Godot binary the project is currently built against."""

import os
from pathlib import Path


PATTERN = "Godot_v*-stable_linux.x86_64"


def find_godot_binary(root: Path) -> str:
    """Return $GODOT_BIN, else the newest checked-out Godot binary in the project root.

    The binary is gitignored and its version changes, so no default may be hardcoded.
    """
    override = os.environ.get("GODOT_BIN")
    if override:
        return override

    candidates = sorted(path for path in root.glob(PATTERN) if os.access(path, os.X_OK))
    if not candidates:
        raise FileNotFoundError(
            f"No {PATTERN} in {root}; download the editor binary or set GODOT_BIN."
        )
    return f"./{candidates[-1].name}"
