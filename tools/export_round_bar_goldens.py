#!/usr/bin/env python3
"""Record what the original's stopwatch sweep draws, as goldens for tests/check_round_bar.gd.

The executable's own CGUIRoundBarTex::Draw (sub_45AEE0) runs under emulation (unicorn), fan,
vertex truncation, the triangle filler sub_457400 and its texture interpolation included, set
up as sub_405930 builds the console's stopwatch: centre (662, 536), radius 38.0, step 15,
start angle 0.5. Every texel of a stand-in for CO_GUI_CONSOLE_CLOCK_FULL holds its own index
plus one, so the surface it draws into says which texel landed on each pixel. The results go
to tests/fixtures/round_bar_goldens.json.

Run by hand when the cases change; tools/run_checks.py does not run it, because it needs the
unicorn package. See "How the stopwatch is swept" in docs/hud-reference.md.
"""

import argparse
import json
import struct
import sys
from pathlib import Path

try:
    from export_fov_goldens import Original
    from original_exe import EXE_SHA256, f32, read_exe, repo_root
except ImportError:  # imported as tools.export_round_bar_goldens
    from tools.export_fov_goldens import Original
    from tools.original_exe import EXE_SHA256, f32, read_exe, repo_root


OUTPUT_REL = Path("tests/fixtures/round_bar_goldens.json")

DRAW_VA = 0x45AEE0
TEXTURE_LOOKUP_VA = 0x459680
RENDER_SINGLETON_VA = 0x474BF8

# sub_405930 (0x405A03-0x405A66) and the CGUIRoundBar constructor sub_45A960 (0x45A983).
CENTRE = (0x296, 0x218)
RADIUS = 38.0
STEP = 15
START_ANGLE = 0.5
TEXTURE_SIZE = (75, 77)
SURFACE_SIZE = (800, 600)

# Where sub_45AEE0 reads the element (offsets into CGUIRoundBarTex).
FIELD_X = 0x8
FIELD_Y = 0xC
FIELD_Z = 0x10
FIELD_SURFACE = 0x34
FIELD_RADIUS = 0x60
FIELD_STEP = 0x64
FIELD_PROGRESS = 0x70
FIELD_START = 0x474
ELEMENT_SIZE = 0x478
# A surface as sub_42C900 reads one: pixels at +4, the Z plane at +8, width +20, height +24.
SURFACE_PIXELS = 0x4
SURFACE_DEPTH = 0x8
SURFACE_WIDTH = 0x14
SURFACE_HEIGHT = 0x18
# The renderer's clip rectangle, which sub_45AEE0 copies from the singleton's +56..+68.
SINGLETON_CLIP = 0x38

# The drawn texel index is stored plus one, so a delta string never needs more than this.
DELTA_BASE = ord("a") + 4


def progress_cases(step: float) -> list:
    """Whole and partial sweeps, with both sides of the steps where a triangle turns full."""
    cases = [0.0, 0.001, 0.003, 0.01, 0.05, 0.1, 0.25, 0.3333, 0.5, 0.6667, 0.75, 0.9, 0.99, 0.999, 1.0]
    for k in (1, 7, 15):
        edge = ((k + 1) * step - f32(0.009999999776482582)) / 6.28
        cases += [edge - 0.0005, edge + 0.0005]
    return sorted({f32(value) for value in cases if 0.0 <= value <= 1.0})


def encode_rows(pixels: dict) -> list:
    """Each row as [y, x, first index, deltas]: consecutive pixels in a run, delta per pixel."""
    rows = []
    for y in sorted({y for _x, y in pixels}):
        xs = sorted(x for x, row in pixels if row == y)
        start = 0
        while start < len(xs):
            end = start
            while end + 1 < len(xs) and xs[end + 1] == xs[end] + 1:
                end += 1
            run = [pixels[(x, y)] for x in xs[start : end + 1]]
            deltas = "".join(chr(DELTA_BASE + b - a) for a, b in zip(run, run[1:]))
            rows.append([y, xs[start], run[0], deltas])
            start = end + 1
    return rows


class Stopwatch:
    def __init__(self, unicorn, data: bytes):
        self.original = Original(unicorn, data)
        mu = self.original.mu
        width, height = TEXTURE_SIZE
        self.texture = self._surface(width, height, b"".join(struct.pack("<I", index + 1) for index in range(width * height)))
        self.screen_width, self.screen_height = SURFACE_SIZE
        self.screen = self._surface(self.screen_width, self.screen_height, bytes(4 * self.screen_width * self.screen_height))
        # sub_459680 looks the texture up by name; hand back the stand-in instead (thiscall, 3 args).
        mu.mem_write(TEXTURE_LOOKUP_VA, b"\xb8" + struct.pack("<I", self.texture) + b"\xc2\x0c\x00")
        singleton = self.original.alloc(0x400, 0)
        mu.mem_write(singleton + SINGLETON_CLIP, struct.pack("<iiii", 0, 0, self.screen_width, self.screen_height))
        mu.mem_write(RENDER_SINGLETON_VA, struct.pack("<I", singleton))
        self.element = self.original.alloc(ELEMENT_SIZE, 0)
        mu.mem_write(self.element + FIELD_X, struct.pack("<iii", CENTRE[0], CENTRE[1], 0x8000))
        mu.mem_write(self.element + FIELD_SURFACE, struct.pack("<I", self.screen))
        mu.mem_write(self.element + FIELD_RADIUS, struct.pack("<fi", RADIUS, STEP))
        mu.mem_write(self.element + FIELD_START, struct.pack("<f", START_ANGLE))

    def _surface(self, width: int, height: int, pixels: bytes) -> int:
        surface = self.original.alloc(0x40, 0)
        buffer = self.original.alloc(len(pixels), 0)
        depth = self.original.alloc(2 * width * height, 0)
        self.original.mu.mem_write(buffer, pixels)
        mu = self.original.mu
        mu.mem_write(surface + SURFACE_PIXELS, struct.pack("<II", buffer, depth))
        mu.mem_write(surface + SURFACE_WIDTH, struct.pack("<ii", width, height))
        return surface

    def draw(self, progress: float) -> dict:
        mu = self.original.mu
        pixels = struct.unpack_from("<I", self.original.read(self.screen + SURFACE_PIXELS, 4))[0]
        mu.mem_write(pixels, bytes(4 * self.screen_width * self.screen_height))
        mu.mem_write(self.element + FIELD_PROGRESS, struct.pack("<f", progress))
        self.original.call(DRAW_VA, (0,), this=self.element)
        cx, cy = CENTRE
        left, top = cx - 48, cy - 48
        drawn = {}
        window = self.original.read(pixels + 4 * (top * self.screen_width), 4 * 96 * self.screen_width)
        for y in range(96):
            for x in range(96):
                value = struct.unpack_from("<I", window, 4 * (y * self.screen_width + left + x))[0]
                if value:
                    drawn[(left + x, top + y)] = value - 1
        return drawn


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--check", action="store_true", help="fail if the goldens are stale")
    arguments = parser.parse_args()
    root = repo_root()
    try:
        import unicorn
    except ImportError:
        print("unicorn is not installed; skipping the stopwatch goldens")
        return 0
    data = read_exe(root)
    stopwatch = Stopwatch(unicorn, data)
    step = f32(12.56 / (RADIUS * 12.56) * STEP)
    cases = []
    for progress in progress_cases(step):
        cases.append({"progress": progress, "rows": encode_rows(stopwatch.draw(progress))})
    text = json.dumps(
        {
            "generated_by": "tools/export_round_bar_goldens.py",
            "exe_sha256": EXE_SHA256,
            "centre": list(CENTRE),
            "radius": RADIUS,
            "step": STEP,
            "start_angle": START_ANGLE,
            "texture_size": list(TEXTURE_SIZE),
            "delta_base": DELTA_BASE,
            "cases": cases,
        },
        indent=1,
    ) + "\n"
    path = root / OUTPUT_REL
    if arguments.check:
        if not path.is_file() or path.read_text() != text:
            print(f"{OUTPUT_REL} is stale")
            return 1
        print(f"Verified {len(cases)} stopwatch sweeps")
        return 0
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)
    print(f"Wrote {len(cases)} stopwatch sweeps to {OUTPUT_REL}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
