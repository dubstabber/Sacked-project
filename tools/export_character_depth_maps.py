#!/usr/bin/env python3
import argparse
import json
import pathlib
import re
import struct
import zlib


DIRECTIONS = {
    "000": "up-right",
    "045": "right",
    "090": "down-right",
    "135": "down",
    "180": "down-left",
    "225": "left",
    "270": "up-left",
    "315": "up",
}

SPECS = [
    ("jobless", "JOBLESS_IDLE#1#ATMEN", "jobless-idle1-atmen"),
    ("jobless", "JOBLESS_WALK", "jobless-walk"),
    ("anne", "ANNE_IDLE#1#ATMEN", "anne-idle1-atmen"),
    ("anne", "ANNE_WALK", "anne-walk"),
    ("boss", "CHEF_STAND#IDLE", "boss-stand-idle"),
    ("boss", "CHEF_WALK", "boss-walk"),
]


def png_chunk(kind: bytes, data: bytes) -> bytes:
    return (
        struct.pack(">I", len(data))
        + kind
        + data
        + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)
    )


def write_rgba_png(path: pathlib.Path, width: int, height: int, rgba: bytes) -> None:
    rows = []
    stride = width * 4
    for y in range(height):
        rows.append(b"\x00" + rgba[y * stride : (y + 1) * stride])

    ihdr = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    payload = b"\x89PNG\r\n\x1a\n"
    payload += png_chunk(b"IHDR", ihdr)
    payload += png_chunk(b"IDAT", zlib.compress(b"".join(rows), level=9))
    payload += png_chunk(b"IEND", b"")
    path.write_bytes(payload)


def source_animation_path(root: pathlib.Path, source_prefix: str, angle: str) -> pathlib.Path:
    return (
        root
        / "extract-sacked-assets"
        / "extracted"
        / "animations_godot"
        / f"CO_CHARS_CO_CHARS_{source_prefix}_{angle}_godot.json"
    )


def source_frame_dir(root: pathlib.Path, frame: dict) -> pathlib.Path:
    return root / "extract-sacked-assets" / frame["path"]


def runtime_frame_path(
    root: pathlib.Path,
    character: str,
    runtime_prefix: str,
    direction_name: str,
    sprite_name: str,
) -> pathlib.Path:
    match = re.search(r"#(\d{3})$", sprite_name)
    if match == None:
        raise ValueError(f"Cannot derive frame suffix from {sprite_name}")

    clip_name = f"{runtime_prefix}-{direction_name}"
    frame_name = f"{clip_name}-{match.group(1)}.png"
    return root / "images" / "characters" / character / clip_name / frame_name


def read_frame_depth(frame_dir: pathlib.Path, width: int, height: int) -> tuple[bytes, bytes]:
    depth_path = frame_dir / "SPRITEZB.bin"
    mask_path = frame_dir / "SPRITECB8.bin"
    depth = depth_path.read_bytes()
    mask = mask_path.read_bytes()

    expected_pixels = width * height
    if len(depth) != expected_pixels * 2:
        raise ValueError(f"{depth_path} has {len(depth)} bytes, expected {expected_pixels * 2}")
    if len(mask) != expected_pixels:
        raise ValueError(f"{mask_path} has {len(mask)} bytes, expected {expected_pixels}")

    return depth, mask


def encode_depth_rgba(depth: bytes, mask: bytes, width: int, height: int) -> bytes:
    rgba = bytearray(width * height * 4)
    for index in range(width * height):
        value = depth[index * 2] | (depth[index * 2 + 1] << 8)
        out = index * 4
        rgba[out] = value & 0xFF
        rgba[out + 1] = (value >> 8) & 0xFF
        rgba[out + 2] = 0
        rgba[out + 3] = 0 if mask[index] == 255 else 255
    return bytes(rgba)


def export_spec(root: pathlib.Path, character: str, source_prefix: str, runtime_prefix: str) -> int:
    written = 0
    for angle, direction_name in DIRECTIONS.items():
        animation_path = source_animation_path(root, source_prefix, angle)
        with animation_path.open("r", encoding="utf-8") as f:
            animation = json.load(f)

        for frame in animation["frames"]:
            width = int(frame["w"])
            height = int(frame["h"])
            frame_dir = source_frame_dir(root, frame).parent
            runtime_path = runtime_frame_path(
                root,
                character,
                runtime_prefix,
                direction_name,
                frame["sprite_name"],
            )
            if not runtime_path.is_file():
                raise FileNotFoundError(runtime_path)

            depth, mask = read_frame_depth(frame_dir, width, height)
            depth_path = runtime_path.with_name(f"{runtime_path.stem}-depth.png")
            write_rgba_png(depth_path, width, height, encode_depth_rgba(depth, mask, width, height))
            written += 1

    return written


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Export character SPRITEZB planes as runtime depth PNGs."
    )
    parser.add_argument("--root", default=".", help="Godot project root")
    args = parser.parse_args()

    root = pathlib.Path(args.root).resolve()
    total = 0
    for character, source_prefix, runtime_prefix in SPECS:
        total += export_spec(root, character, source_prefix, runtime_prefix)

    print(f"Wrote {total} character depth maps")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
