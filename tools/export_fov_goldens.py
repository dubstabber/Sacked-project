#!/usr/bin/env python3
"""Record the original's own field-of-view masks as goldens for tests/check_field_of_view.gd.

The executable itself is run under emulation (unicorn): sub_427DC0 builds the shadow tables,
then for every case below sub_428270 answers the octant bits and sub_428BC0 builds the whole
mask -- the cone, the shadows through sub_412AE0, the radius disc (sub_429770), the OR
(sub_429800) and the texels (sub_429830) -- exactly as the game does each frame. The masks
and texels it leaves in memory go to tests/fixtures/fov_golden_masks.json.

Run by hand when the cases change; tools/run_checks.py does not run it, because it needs the
unicorn package. It skips cleanly when unicorn or the executable is missing. See "The mask"
in docs/field-of-view-reference.md.
"""

import argparse
import json
import random
import struct
import sys
from pathlib import Path

try:
    from original_exe import EXE_REL, EXE_SHA256, IMAGE_BASE, f32, read_exe, repo_root
except ImportError:  # imported as tools.export_fov_goldens
    from tools.original_exe import EXE_REL, EXE_SHA256, IMAGE_BASE, f32, read_exe, repo_root


OUTPUT_REL = Path("tests/fixtures/fov_golden_masks.json")
PROFILES_REL = Path("resources/original/npc_profiles.json")

IMAGE_SIZE = 0x92000

TABLE_BUILDER_VA = 0x427DC0
CONE_VA = 0x428270
BUILD_VA = 0x428BC0
RADIUS_MASK_VA = 0x429770
# f32(0.022222), which sub_428270 multiplies lo and hi by to find their sectors; its negation
# at 0x4667D0 serves a negative lo. See "The cone" in docs/field-of-view-reference.md.
SECTOR_SCALE_VA = 0x4667D4
# The C runtime's 53-bit precision, which no game code changes (__setdefaultprecision, 0x461CEE).
FPU_CONTROL = 0x27F

# Imports and runtime helpers the build reaches, by the address of their IAT slot or entry.
NEW_VA = 0x4618AE
DELETE_VA = 0x461880
MALLOC_IAT = 0x465110
FREE_IAT = 0x4650F0
REALLOC_IAT = 0x46510C
CEIL_IAT = 0x465104
FTOL_IAT = 0x4650DC

# The field-of-view object embedded at agent+1128, as far as the build reads it.
OBJECT_SIZE = 0x250
OBJECT_IMAGE_PIXELS = 0x4
OBJECT_CONE_MASK = 0x240
OBJECT_RADIUS_MASK = 0x244
OBJECT_MAP = 0x248
OBJECT_RADIUS_CACHE = 0x24C
MASK_ALLOCATION = 0x35E1
# The level map as sub_412AE0 reads it: u16 width and height at +4, the INFODATA dwords at +36.
MAP_SIZE_OFFSET = 4
MAP_INFODATA_OFFSET = 36
SIGHT_BIT = 0x2

SIDE = 113
AGGRESSION_BANDS = range(4)  # the band never passes 3: the janitor's 70 + 15 is the widest cone, 85

STUB = 0x10000000
STACK = 0x20000000
STACK_SIZE = 0x100000
HEAP = 0x30000000
HEAP_SIZE = 0x4000000
# x87 bodies for the two MSVCRT helpers: ceil rounds up (RC = 10), _ftol truncates (RC = 11).
CEIL_CODE = "83EC04D93C24668B04246625FFF3660D00086689442402D96C2402DD442408D9FCD92C2483C404C3"
FTOL_CODE = "83EC0CD93C24668B0424660D000C6689442402D96C2402DF7C2404D92C248B4424048B54240883C40CC3"


def f32_bits(value: float) -> int:
    return struct.unpack("<I", struct.pack("<f", value))[0]


def from_f32_bits(bits: int) -> float:
    return struct.unpack("<f", struct.pack("<I", bits))[0]


def sector_start(sector: int, scale: float) -> float:
    """The least positive float32 whose product with the scale reaches the sector.

    A float32 times a float32 is exact in the x87's 53 bits, and so in a Python float.
    """
    below = f32_bits(45.0 * sector * 0.999)
    above = f32_bits(45.0 * sector * 1.001)
    if not from_f32_bits(below) * scale < sector <= from_f32_bits(above) * scale:
        raise SystemExit(f"sector {sector} does not start near {45 * sector} degrees")
    while above - below > 1:
        middle = (below + above) // 2
        if from_f32_bits(middle) * scale >= sector:
            above = middle
        else:
            below = middle
    return from_f32_bits(above)


def heading_for(end: str, angle: float, cone: float) -> float:
    """The float32 heading whose lo (or hi) sub_428270 computes as exactly this angle."""
    half = f32(cone) * 0.5
    heading = f32(angle + half if end == "lo" else angle - half)
    landed = f32(heading - half if end == "lo" else heading + half)
    if landed != f32(angle):
        raise SystemExit(f"no float32 heading puts {end} on {angle!r} with a cone of {cone}")
    return heading


def sector_edge_cases(scale: float) -> list:
    """lo or hi on a multiple of 45, which lands one sector low, and on either side of where a
    sector really starts, at multiples of 45.00045 degrees."""
    result = []
    for end, angle, cone in (("lo", 90.0, 60.0), ("hi", 135.0, 70.0), ("lo", 0.0, 80.0), ("hi", 360.0, 55.0), ("lo", -45.0, 85.0), ("hi", 45.0, 65.0)):
        result.append((f"{end} exactly {angle:g}", end, angle, cone))
    for end, sector, cone in (("lo", 4, 60.0), ("hi", 2, 75.0), ("hi", 8, 85.0), ("lo", -1, 55.0)):
        start = sector_start(abs(sector), scale)
        before = from_f32_bits(f32_bits(start) - 1)
        # A negative lo is sectored by its magnitude: -1 - trunc(-lo * 0.022222).
        for label, angle in (("on", start), ("one float32 short of", before)):
            angle = -angle if sector < 0 else angle
            result.append((f"{end} {label} a sector start ({angle:.9g})", end, angle, cone))
    return [(f"sector edge, {name}, cone {cone:g}", "near", 10.0, 10.0, 5.0, heading_for(end, angle, cone), cone) for name, end, angle, cone in result]


class Original:
    """sacked.exe mapped into unicorn with just enough of its runtime to build the mask."""

    def __init__(self, unicorn, data: bytes):
        from unicorn import x86_const

        self.x86 = x86_const
        self.mu = unicorn.Uc(unicorn.UC_ARCH_X86, unicorn.UC_MODE_32)
        mu = self.mu
        mu.mem_map(IMAGE_BASE, IMAGE_SIZE)
        mu.mem_write(IMAGE_BASE, data[:0x1000])
        pe = struct.unpack_from("<I", data, 0x3C)[0]
        sections = struct.unpack_from("<H", data, pe + 6)[0]
        header = pe + 24 + struct.unpack_from("<H", data, pe + 20)[0]
        for index in range(sections):
            virtual_size, virtual_address, raw_size, raw_offset = struct.unpack_from("<IIII", data, header + 40 * index + 8)
            mu.mem_write(IMAGE_BASE + virtual_address, data[raw_offset : raw_offset + min(raw_size, max(virtual_size, raw_size))])
        mu.mem_map(STUB, 0x1000)
        mu.mem_map(STACK, STACK_SIZE)
        mu.mem_map(HEAP, HEAP_SIZE)
        self.heap = HEAP
        self.sizes = {}
        self.stubs = {}
        for slot, name in enumerate(("new", "delete", "malloc", "free", "realloc")):
            address = STUB + slot * 0x40
            mu.mem_write(address, b"\xc3")
            self.stubs[address] = name
        ceil = STUB + 5 * 0x40
        ftol = STUB + 6 * 0x40
        mu.mem_write(ceil, bytes.fromhex(CEIL_CODE))
        mu.mem_write(ftol, bytes.fromhex(FTOL_CODE))
        self.sentinel = STUB + 0x800
        mu.mem_write(self.sentinel, b"\xf4")
        for source, target in ((NEW_VA, STUB), (DELETE_VA, STUB + 0x40)):
            mu.mem_write(source, b"\xe9" + struct.pack("<i", target - (source + 5)))
        for slot, target in ((MALLOC_IAT, STUB + 0x80), (FREE_IAT, STUB + 0xC0), (REALLOC_IAT, STUB + 0x100), (CEIL_IAT, ceil), (FTOL_IAT, ftol)):
            mu.mem_write(slot, struct.pack("<I", target))
        mu.hook_add(unicorn.UC_HOOK_CODE, self._runtime, begin=STUB, end=STUB + 5 * 0x40 - 1)
        mu.reg_write(x86_const.UC_X86_REG_FPCW, FPU_CONTROL)

    def alloc(self, size: int, fill: int = 0xCD) -> int:
        address = (self.heap + 15) & ~15
        self.heap = address + size
        self.sizes[address] = size
        self.mu.mem_write(address, bytes([fill]) * size)
        return address

    def _runtime(self, mu, address, _size, _user):
        name = self.stubs.get(address)
        if name is None:
            return
        esp = mu.reg_read(self.x86.UC_X86_REG_ESP)
        back = struct.unpack("<I", mu.mem_read(esp, 4))[0]
        first, second = struct.unpack("<II", mu.mem_read(esp + 4, 8))
        result = 0
        if name in ("new", "malloc"):
            result = self.alloc(first)
        elif name == "realloc":
            result = self.alloc(second)
            if first:
                mu.mem_write(result, bytes(mu.mem_read(first, min(self.sizes.get(first, second), second))))
        mu.reg_write(self.x86.UC_X86_REG_EAX, result)
        mu.reg_write(self.x86.UC_X86_REG_ESP, esp + 4)
        mu.reg_write(self.x86.UC_X86_REG_EIP, back)

    def call(self, function: int, args=(), this=None) -> int:
        esp = STACK + STACK_SIZE - 0x1000
        pushed = b"".join(struct.pack("<f", value) if isinstance(value, float) else struct.pack("<I", value & 0xFFFFFFFF) for value in args)
        esp -= len(pushed)
        self.mu.mem_write(esp, pushed)
        esp -= 4
        self.mu.mem_write(esp, struct.pack("<I", self.sentinel))
        self.mu.reg_write(self.x86.UC_X86_REG_ESP, esp)
        if this is not None:
            self.mu.reg_write(self.x86.UC_X86_REG_ECX, this)
        self.mu.emu_start(function, self.sentinel, count=2_000_000_000)
        return self.mu.reg_read(self.x86.UC_X86_REG_EAX)

    def read(self, address: int, size: int) -> bytes:
        return bytes(self.mu.mem_read(address, size))


class FieldOfView:
    """One agent's field-of-view object, set up as sub_428140 leaves it."""

    def __init__(self, original: Original):
        self.original = original
        self.object = original.alloc(OBJECT_SIZE, 0)
        self.texels = original.alloc(SIDE * SIDE * 4, 0)
        self.cone_mask = original.alloc(MASK_ALLOCATION)
        self.radius_mask = original.alloc(MASK_ALLOCATION)
        original.mu.mem_write(self.object + OBJECT_IMAGE_PIXELS, struct.pack("<I", self.texels))
        original.mu.mem_write(self.object + OBJECT_CONE_MASK, struct.pack("<II", self.cone_mask, self.radius_mask))
        original.mu.mem_write(self.object + OBJECT_RADIUS_CACHE, struct.pack("<f", 5.0))
        original.call(RADIUS_MASK_VA, [5.0], this=self.object)
        self.maps = {}

    def use_map(self, name: str, level_map: dict) -> None:
        if name not in self.maps:
            width, height = level_map["width"], level_map["height"]
            info = [0] * (width * height)
            for x, z in level_map["sight"]:
                info[x + width * z] |= SIGHT_BIT
            address = self.original.alloc(64, 0)
            cells = self.original.alloc(4 * width * height, 0)
            self.original.mu.mem_write(cells, struct.pack("<%dI" % len(info), *info))
            self.original.mu.mem_write(address + MAP_SIZE_OFFSET, struct.pack("<HH", width, height))
            self.original.mu.mem_write(address + MAP_INFODATA_OFFSET, struct.pack("<I", cells))
            self.maps[name] = address
        self.original.mu.mem_write(self.object + OBJECT_MAP, struct.pack("<I", self.maps[name]))

    def build(self, x, z, radius, heading, cone):
        octants = self.original.call(CONE_VA, [heading, cone], this=self.object) & 0xFF
        self.original.call(BUILD_VA, [x, z, radius, heading, cone], this=self.object)
        mask = self.original.read(self.cone_mask, SIDE * SIDE)
        words = struct.unpack("<%dI" % (SIDE * SIDE), self.original.read(self.texels, SIDE * SIDE * 4))
        if any(word & 0xFF00FFFF for word in words):
            raise SystemExit("a texel has a byte other than byte 2 set, which the reference rules out")
        return octants, mask, [(word >> 16) & 0xFF for word in words]


def load_profiles(root: Path) -> list:
    """Every notice radius and cone an agent can hold, as the float32 fields agent+1068/+1072 keep."""
    data = json.loads((root / PROFILES_REL).read_text(encoding="utf-8"))
    band = data["aggression_band"]
    combos = []
    for name, profile in sorted(data["profiles"].items()):
        bands = [0] if name in band["exempt"] else list(AGGRESSION_BANDS)
        for level in bands:
            radius = f32(f32(profile["notice_radius_tiles"]) + band["notice_radius_tiles"] * level)
            cone = f32(f32(profile["notice_cone_degrees"]) + band["notice_cone_degrees"] * level)
            combos.append((f"{name}-band-{level}", radius, cone))
    return combos


def level_map(root: Path, level: str) -> dict:
    grid = json.loads((root / "resources/levels" / f"{level}.json").read_text(encoding="utf-8"))["collision_grid"]
    return {
        "from": f"resources/levels/{level}.json collision_grid.sight_blocked_cells",
        "width": grid["width"],
        "height": grid["height"],
        "sight": sorted([int(x), int(z)] for x, z in grid["sight_blocked_cells"]),
    }


def synthetic_maps() -> dict:
    scatter = random.Random(1128)
    return {
        "open": {"from": "synthetic: no sight-blocking cell", "width": 20, "height": 20, "sight": []},
        "near": {
            "from": "synthetic: sight-blocking cells beside the agent's cell (10, 10)",
            "width": 20,
            "height": 20,
            "sight": sorted([[11, 10], [10, 8], [8, 9], [12, 12], [9, 11], [13, 7], [7, 13], [10, 14], [15, 10]]),
        },
        "own-cell": {"from": "synthetic: the agent's own cell (10, 10) blocks sight", "width": 20, "height": 20, "sight": [[10, 10]]},
        "edges": {
            "from": "synthetic: sight-blocking cells along every edge of a 12 x 9 map",
            "width": 12,
            "height": 9,
            "sight": sorted([[x, 0] for x in range(0, 12, 2)] + [[x, 8] for x in range(1, 12, 3)] + [[0, z] for z in range(3, 9, 2)] + [[11, z] for z in range(0, 9, 3)]),
        },
        "scatter": {
            "from": "synthetic: a seeded scatter of sight-blocking cells, one in six",
            "width": 24,
            "height": 24,
            "sight": sorted([x, z] for z in range(24) for x in range(24) if scatter.random() < 1.0 / 6.0),
        },
    }


def cases(root: Path, scale: float) -> list:
    # (name, map, x, z, radius, heading, cone); every value becomes the float32 the original holds.
    result = []
    headings = [3.0, 41.5, 88.0, 133.25, 177.0, 222.5, 268.0, 301.75, 344.0, 359.5]
    for index, (label, radius, cone) in enumerate(load_profiles(root)):
        map_name = ("near", "scatter", "open")[index % 3]
        position = ((10.0, 10.0), (11.62, 12.37), (9.3, 8.85))[index % 3]
        result.append((f"profile {label}", map_name, position[0], position[1], radius, headings[index % len(headings)], cone))
    # Headings around the circle, a lo below 0 and a hi past 360, and headings the eased heading
    # never holds but the build accepts: negative and past a full turn.
    for heading in (0.0, 0.01, 22.5, 27.5, 45.0, 90.0, 135.0, 180.0, 225.0, 270.0, 315.0, 337.5, 352.0, 359.99, -10.0, -45.0, -200.0, 365.0, 720.5):
        result.append((f"heading {heading:g}", "near", 10.0, 10.0, 5.0, heading, 60.0))
    result += sector_edge_cases(scale)
    result += [
        ("own cell blocks", "own-cell", 10.25, 10.1, 5.8, 75.0, 75.0),
        ("own cell, other side of the round", "own-cell", 9.6, 9.55, 5.9, 200.0, 85.0),
        ("edge, west", "edges", 0.4, 4.2, 5.9, 270.0, 85.0),
        ("edge, north-east corner", "edges", 10.6, 1.3, 5.5, 45.0, 70.0),
        ("edge, south", "edges", 6.0, 8.45, 5.0, 180.0, 60.0),
        ("off the map to the west", "edges", -3.2, 4.0, 5.3, 90.0, 55.0),
        ("off the map, x + 0.5 in (-1, 0)", "edges", -0.7, 3.3, 5.2, 100.0, 65.0),
        ("off the map, z + 0.5 in (-1, 0)", "edges", 5.0, -0.6, 5.1, 170.0, 80.0),
        ("off the map past the far corner", "edges", 13.5, 10.8, 5.9, 315.0, 85.0),
        ("level 1, the boss at his spawn", "level_1", 1.0, 12.0, 5.8, 45.0, 75.0),
        ("level 1, the boss turned", "level_1", 1.0, 12.0, 5.8, 135.0, 75.0),
        ("level 1, the coworker at his spawn", "level_1", 3.0, 2.0, 5.2, 180.0, 60.0),
        ("level 1, the corridor", "level_1", 7.3, 5.4, 5.6, 263.0, 70.0),
        ("level 1, a doorway", "level_1", 8.6, 7.9, 5.9, 331.0, 85.0),
        ("level 13, the boss at his spawn", "level_13", 4.0, 1.0, 5.8, 135.0, 75.0),
        ("level 13, the corridor", "level_13", 12.2, 7.2, 5.5, 95.0, 80.0),
        ("level 13, the janitor at his spawn", "level_13", 3.0, 10.0, 5.6, 12.0, 85.0),
        ("level 13, a coworker at a desk", "level_13", 18.0, 15.0, 5.2, 290.0, 60.0),
    ]
    return result


def encode_mask_row(row: bytes) -> str:
    """Run lengths, alternating, starting with visible (0): "12,5,96" is 12 zeros, 5 ones, 96 zeros."""
    runs = []
    value = 0
    count = 0
    for byte in row:
        if byte not in (0, 1):
            raise SystemExit(f"a mask byte of {byte}")
        if byte == value:
            count += 1
        else:
            runs.append(count)
            value = byte
            count = 1
    runs.append(count)
    return ",".join(str(run) for run in runs)


def encode_texel_row(row: list) -> str:
    """Runs of blue values: "0*12 64*3 40 0*97"; a run of one has no count."""
    tokens = []
    start = 0
    while start < len(row):
        end = start
        while end < len(row) and row[end] == row[start]:
            end += 1
        tokens.append(str(row[start]) if end - start == 1 else f"{row[start]}*{end - start}")
        start = end
    return " ".join(tokens)


def encode_rows(rows: list) -> str:
    """The 113 rows joined by "/", with "=" for a row that repeats the one above it."""
    return "/".join("=" if index and row == rows[index - 1] else row for index, row in enumerate(rows))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=repo_root())
    args = parser.parse_args()

    try:
        import unicorn
    except ImportError:
        print("SKIP  unicorn is not installed (pip install unicorn); the goldens were not rebuilt")
        return 0
    exe = args.root / EXE_REL
    if not exe.is_file():
        print(f"SKIP  {EXE_REL} is absent; the goldens were not rebuilt")
        return 0
    data = read_exe(args.root)

    original = Original(unicorn, data)
    original.call(TABLE_BUILDER_VA)
    view = FieldOfView(original)
    maps = synthetic_maps()
    maps["level_1"] = level_map(args.root, "level_1")
    maps["level_13"] = level_map(args.root, "level_13")

    recorded = []
    scale = struct.unpack("<f", original.read(SECTOR_SCALE_VA, 4))[0]
    for name, map_name, x, z, radius, heading, cone in cases(args.root, scale):
        values = [f32(value) for value in (x, z, radius, heading, cone)]
        view.use_map(map_name, maps[map_name])
        octants, mask, texels = view.build(*values)
        recorded.append({
            "name": name,
            "map": map_name,
            "x": values[0],
            "z": values[1],
            "radius": values[2],
            "heading": values[3],
            "cone": values[4],
            "float32_bits": [f32_bits(value) for value in values],
            "octants": octants,
            "visible_texels": mask.count(0),
            "mask": encode_rows([encode_mask_row(mask[row * SIDE : (row + 1) * SIDE]) for row in range(SIDE)]),
            "texels": encode_rows([encode_texel_row(texels[row * SIDE : (row + 1) * SIDE]) for row in range(SIDE)]),
        })

    document = {
        "generated_by": "tools/export_fov_goldens.py",
        "source": EXE_REL.as_posix(),
        "source_sha256": EXE_SHA256,
        "emulated": (
            "sub_427DC0 once, then per case sub_428270 (the octants) and sub_428BC0 (the whole "
            "build), under unicorn with the x87 control word 0x27F"
        ),
        "encoding": {
            "inputs": "x, z, radius, heading and cone are the float32 values passed, float32_bits their bit patterns",
            "rows": "113 rows joined by '/', where '=' repeats the row above",
            "mask": "113 bytes a row, 1 = hidden; each row is alternating run lengths starting with 0s",
            "texels": "byte 2 (blue) of each image dword, 113 a row; runs of value*count, a lone value has no count",
            "map": "sight lists the cells with INFODATA bit 1 set, as [x, z]; every other cell, and every cell off the map, is clear",
        },
        "maps": maps,
        "cases": recorded,
    }
    output = args.root / OUTPUT_REL
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(document, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"Wrote {OUTPUT_REL}: {len(recorded)} cases from the emulated original.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
