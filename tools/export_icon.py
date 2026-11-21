#!/usr/bin/env python3
"""Export the original game's icon as the Godot project icon.

sacked.exe carries one icon group (RT_GROUP_ICON 101) holding the same 32x32 picture twice, at
16 and at 256 colours; Gefeuert.exe carries a byte-identical group. The 256-colour image is
written to images/icon.png, its AND mask becoming the alpha channel.

Run with --check to verify the exported file without writing.
"""

import argparse
import io
import struct
from pathlib import Path

from PIL import Image

try:
    from original_exe import read_exe
except ImportError:  # the tests import this file as tools.export_icon
    from tools.original_exe import read_exe


DESTINATION = "images/icon.png"

RT_ICON = 3
RT_GROUP_ICON = 14
RESOURCE_DIRECTORY = 2


def _section_offset(data: bytes, rva: int) -> int:
    """The file offset of a relative virtual address, through the PE section table."""
    pe = struct.unpack_from("<I", data, 0x3C)[0]
    sections, optional_size = struct.unpack_from("<H12xH", data, pe + 6)
    table = pe + 24 + optional_size
    for index in range(sections):
        virtual_size, virtual_address, raw_size, raw_pointer = struct.unpack_from("<4I", data, table + 40 * index + 8)
        if virtual_address <= rva < virtual_address + max(virtual_size, raw_size):
            return raw_pointer + rva - virtual_address
    raise SystemExit(f"RVA 0x{rva:X} lies in no section")


def _resources(data: bytes) -> dict:
    """{(type, id): bytes} for every resource with a numeric type and id, first language only."""
    pe = struct.unpack_from("<I", data, 0x3C)[0]
    directory_rva = struct.unpack_from("<I", data, pe + 24 + 96 + 8 * RESOURCE_DIRECTORY)[0]
    base = _section_offset(data, directory_rva)

    def entries(offset: int) -> list:
        named, numbered = struct.unpack_from("<HH", data, base + offset + 12)
        return [struct.unpack_from("<II", data, base + offset + 16 + 8 * index) for index in range(named + numbered)]

    found = {}
    for type_id, type_offset in entries(0):
        if type_id & 0x80000000:
            continue
        for resource_id, resource_offset in entries(type_offset & 0x7FFFFFFF):
            if resource_id & 0x80000000:
                continue
            _, leaf = entries(resource_offset & 0x7FFFFFFF)[0]
            data_rva, size = struct.unpack_from("<II", data, base + leaf)
            start = _section_offset(data, data_rva)
            found[(type_id, resource_id)] = data[start : start + size]
    return found


def icon_image(data: bytes) -> Image.Image:
    """The deepest image of the executable's one icon group, decoded to RGBA."""
    resources = _resources(data)
    groups = [key for key in resources if key[0] == RT_GROUP_ICON]
    if len(groups) != 1:
        raise SystemExit(f"Expected one icon group, found {len(groups)}")
    group = resources[groups[0]]
    count = struct.unpack_from("<H", group, 4)[0]
    # GRPICONDIRENTRY: width, height, colours, reserved, planes, bit count, bytes, icon id.
    members = [struct.unpack_from("<BBBBHHIH", group, 6 + 14 * index) for index in range(count)]
    width, height, colours, reserved, planes, bits, _, icon_id = max(
        members, key=lambda member: ((member[0] or 256) * (member[1] or 256), member[5])
    )
    picture = resources[(RT_ICON, icon_id)]
    # An .ico file holding that one image: the group header, then ICONDIRENTRY with the image's
    # offset where the group entry has its resource id.
    ico = struct.pack("<HHH", 0, 1, 1) + struct.pack("<BBBBHHII", width, height, colours, reserved, planes, bits, len(picture), 22) + picture
    with Image.open(io.BytesIO(ico)) as image:
        return image.convert("RGBA")


def export(root: Path, check: bool) -> int:
    image = icon_image(read_exe(root))
    path = root / DESTINATION
    if check:
        if not path.is_file():
            print(f"Icon check failed: {DESTINATION} is missing")
            return 1
        with Image.open(path) as existing:
            if existing.size != image.size or existing.convert("RGBA").tobytes() != image.tobytes():
                print(f"Icon check failed: {DESTINATION} is stale")
                return 1
        print(f"Verified {DESTINATION} ({image.width}x{image.height}).")
        return 0
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path, optimize=True)
    print(f"Exported {DESTINATION} ({image.width}x{image.height}).")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--check", action="store_true", help="Verify the exported icon without writing")
    args = parser.parse_args()
    return export(args.root.resolve(), args.check)


if __name__ == "__main__":
    raise SystemExit(main())
