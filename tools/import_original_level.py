#!/usr/bin/env python3
import argparse
import filecmp
import json
import os
import re
import shutil
import struct
import subprocess
import sys
import tempfile
import unicodedata
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, Iterable, List, Optional, Tuple


SOURCE_ID = 3
TILE_SIZE = (94, 48)
PLAYABLE_LEVEL_NUMBER = 1
ORIGINAL_LEVEL_INDEX = PLAYABLE_LEVEL_NUMBER - 1
LEVEL_SOURCE_REL = Path("extract-sacked-assets/sacked/Levels/LEVEL_00.col")
LEVEL_TEXT_REL = Path("extract-sacked-assets/sacked/Levels/Level_00.txt")
OBJECT_DB_REL = Path("extract-sacked-assets/sacked/CO_OBJECTS.DAT")
OBJECT_TEXTURE_LOG_REL = Path("extract-sacked-assets/extracted/textures/CO_OBJECTS/png_conversion_log.json")
OBJECT_TEXTURE_ROOT_REL = Path("extract-sacked-assets/extracted/textures/CO_OBJECTS")
OBJECT_IMAGE_DIR_REL = Path("images/objects")
TILE_ATLAS_MANIFEST_REL = Path("resources/tilemaps/sacked-tile-atlases.json")
LEVEL_MANIFEST_REL = Path("resources/levels/level_1.json")
LEVEL_SCENE_REL = Path("scenes/level_1.tscn")


@dataclass(frozen=True)
class ChunkRecord:
    name: str
    payload: bytes
    sequence: int
    flags: int
    offset: int


@dataclass(frozen=True)
class ObjectDefinition:
    object_id: int
    name: str
    sprite_name: str


@dataclass(frozen=True)
class TextureCandidate:
    sprite: str
    angle: int
    source_rel: Path
    width: int
    height: int
    pivot_x: int
    pivot_y: int


@dataclass(frozen=True)
class ResolvedTexture:
    candidate: TextureCandidate
    dest_rel: Path


def repo_root() -> Path:
    return Path(__file__).resolve().parents[1]


def read_u16(data: bytes, offset: int) -> int:
    return struct.unpack_from("<H", data, offset)[0]


def read_s16(data: bytes, offset: int) -> int:
    return struct.unpack_from("<h", data, offset)[0]


def read_u32(data: bytes, offset: int) -> int:
    return struct.unpack_from("<I", data, offset)[0]


def read_f32(data: bytes, offset: int) -> float:
    return struct.unpack_from("<f", data, offset)[0]


def read_cstr(data: bytes, start: int, max_len: int) -> str:
    end = data.find(b"\x00", start, min(start + max_len, len(data)))
    if end < 0:
        end = min(start + max_len, len(data))
    return data[start:end].decode("latin-1", errors="replace").strip()


def parse_chunk_at(data: bytes, tag_offset: int) -> Optional[ChunkRecord]:
    if tag_offset < 6:
        return None
    name_len = read_u16(data, tag_offset - 6)
    payload_len = read_u32(data, tag_offset - 4)
    if name_len <= 1 or payload_len < 0:
        return None
    name_end = tag_offset + name_len
    payload_start = name_end
    payload_end = payload_start + payload_len
    trailer_end = payload_end + 8
    if name_end > len(data) or payload_end > len(data) or trailer_end > len(data):
        return None
    if data[name_end - 1] != 0:
        return None
    name = data[tag_offset:name_end - 1].decode("latin-1", errors="replace")
    sequence = read_u32(data, payload_end)
    flags = read_u32(data, payload_end + 4)
    return ChunkRecord(name, data[payload_start:payload_end], sequence, flags, tag_offset)


def find_chunk(data: bytes, name: str) -> ChunkRecord:
    needle = name.encode("latin-1") + b"\x00"
    offset = data.find(needle)
    if offset < 0:
        raise ValueError(f"Missing chunk {name}")
    record = parse_chunk_at(data, offset)
    if record is None or record.name != name:
        raise ValueError(f"Invalid chunk header for {name}")
    return record


def find_numbered_chunks(data: bytes, prefix: str) -> List[ChunkRecord]:
    chunks: List[ChunkRecord] = []
    pattern = re.compile(rb"%s\d+\x00" % prefix.encode("ascii"))
    for match in pattern.finditer(data):
        record = parse_chunk_at(data, match.start())
        if record is not None and record.name.startswith(prefix):
            chunks.append(record)
    chunks.sort(key=lambda chunk: int(chunk.name[len(prefix):]))
    return chunks


def find_named_chunks(data: bytes, name: str) -> List[ChunkRecord]:
    chunks: List[ChunkRecord] = []
    needle = name.encode("latin-1") + b"\x00"
    start = 0
    while True:
        offset = data.find(needle, start)
        if offset < 0:
            break
        record = parse_chunk_at(data, offset)
        if record is not None and record.name == name:
            chunks.append(record)
        start = offset + 1
    return chunks


def parse_layer(payload: bytes, expected_count: int) -> List[int]:
    if len(payload) != expected_count * 2:
        raise ValueError(f"Layer has {len(payload)} bytes, expected {expected_count * 2}")
    return [read_u16(payload, offset) for offset in range(0, len(payload), 2)]


def parse_level_file(path: Path) -> Dict[str, object]:
    data = path.read_bytes()
    if not data.startswith(b"#ODIN_ENGINE"):
        raise ValueError(f"Invalid level signature: {path}")

    mapinfo = find_chunk(data, "MAPINFO")
    if len(mapinfo.payload) < 6:
        raise ValueError("MAPINFO payload is too short")
    width = read_u16(mapinfo.payload, 0)
    height = read_u16(mapinfo.payload, 2)
    layer_count = read_u16(mapinfo.payload, 4)
    expected_count = width * height

    layer0 = parse_layer(find_chunk(data, "LAYER0").payload, expected_count)
    layer1 = parse_layer(find_chunk(data, "LAYER1").payload, expected_count)
    layer2 = parse_layer(find_chunk(data, "LAYER2").payload, expected_count)

    items = []
    for record in find_numbered_chunks(data, "ITEM"):
        if len(record.payload) != 16:
            raise ValueError(f"{record.name} has {len(record.payload)} payload bytes, expected 16")
        kind = read_u32(record.payload, 0)
        items.append(
            {
                "record_name": record.name,
                "kind": kind,
                "x": read_f32(record.payload, 4),
                "z": read_f32(record.payload, 8),
                "y": read_f32(record.payload, 12),
                "instance_id": record.sequence,
                "flags": record.flags,
            }
        )

    spawns = []
    for index, record in enumerate(find_named_chunks(data, "SPAWN")):
        if len(record.payload) != 16:
            raise ValueError(f"SPAWN {index} has {len(record.payload)} payload bytes, expected 16")
        spawns.append(
            {
                "record_name": "SPAWN",
                "spawn_id": read_u32(record.payload, 0),
                "x": read_f32(record.payload, 4),
                "z": read_f32(record.payload, 8),
                "y": read_f32(record.payload, 12),
                "instance_id": record.sequence,
                "flags": record.flags,
            }
        )

    return {
        "width": width,
        "height": height,
        "layer_count": layer_count,
        "layers": {
            "LAYER0": layer0,
            "LAYER1": layer1,
            "LAYER2": layer2,
        },
        "items": items,
        "spawns": spawns,
    }


def parse_object_database(path: Path) -> Dict[int, ObjectDefinition]:
    data = path.read_bytes()
    if not data.startswith(b"#ODIN_ENGINE"):
        raise ValueError(f"Invalid object database signature: {path}")

    definitions: Dict[int, ObjectDefinition] = {}
    start = 0
    while True:
        offset = data.find(b"ITEM\x00", start)
        if offset < 0:
            break
        record = parse_chunk_at(data, offset)
        start = offset + 1
        if record is None or record.name != "ITEM" or len(record.payload) < 320:
            continue
        object_id = read_u32(record.payload, 0)
        if object_id in (0, 0xFFFFFFFF):
            continue
        name = read_cstr(record.payload, 8, 128)
        sprite_name = read_cstr(record.payload, 264, 64)
        if sprite_name == "":
            continue
        definitions[object_id] = ObjectDefinition(object_id, name, sprite_name)

    if not definitions:
        raise ValueError(f"No object definitions parsed from {path}")
    return definitions


def slugify(value: str) -> str:
    normalized = unicodedata.normalize("NFKD", value).encode("ascii", "ignore").decode("ascii")
    normalized = normalized.lower()
    normalized = re.sub(r"[^a-z0-9]+", "-", normalized).strip("-")
    return re.sub(r"-+", "-", normalized) or "object"


def delimiter_normalized(value: str) -> str:
    value = value.upper()
    value = value.replace("&", "_").replace("#", "_")
    value = re.sub(r"[^A-Z0-9_]+", "_", value)
    return re.sub(r"_+", "_", value).strip("_")


def compact_normalized(value: str) -> str:
    value = value.upper()
    replacements = {
        "Ä": "A",
        "Ö": "O",
        "Ü": "U",
        "ä": "A",
        "ö": "O",
        "ü": "U",
        "ß": "SS",
    }
    for source, target in replacements.items():
        value = value.replace(source, target)
    value = unicodedata.normalize("NFKD", value).encode("ascii", "ignore").decode("ascii")
    return re.sub(r"[^A-Z0-9]+", "", value)


def sprite_aliases(sprite_name: str) -> List[Tuple[str, str]]:
    replacements = [
        {},
        {"Ä": "AE", "Ö": "OE", "Ü": "UE", "ä": "AE", "ö": "OE", "ü": "UE", "ß": "SS"},
        {"Ä": "A", "Ö": "O", "Ü": "U", "ä": "A", "ö": "O", "ü": "U", "ß": "SS"},
        {"Ä": "", "Ö": "", "Ü": "", "ä": "", "ö": "", "ü": "", "ß": "SS"},
    ]
    aliases: List[Tuple[str, str]] = []
    seen = set()
    for mapping in replacements:
        value = sprite_name
        for source, target in mapping.items():
            value = value.replace(source, target)
        delimited = delimiter_normalized(value)
        compact = compact_normalized(value)
        key = (delimited, compact)
        if compact and key not in seen:
            aliases.append(key)
            seen.add(key)
    return aliases


def load_texture_candidates(root: Path) -> List[TextureCandidate]:
    log_path = root / OBJECT_TEXTURE_LOG_REL
    texture_root = root / OBJECT_TEXTURE_ROOT_REL
    data = json.loads(log_path.read_text(encoding="utf-8"))
    entries = data.get("entries", [])
    candidates: List[TextureCandidate] = []
    for entry in entries:
        if entry.get("status") != "ok":
            continue
        sprite = str(entry.get("sprite", ""))
        match = re.search(r"_IDLE_(\d{3})_", sprite)
        if match is None:
            continue
        source_rel = OBJECT_TEXTURE_ROOT_REL / sprite / f"{sprite}.png"
        if not (root / source_rel).is_file():
            continue
        pivot_x, pivot_y = read_sprite_pivot(
            root / OBJECT_TEXTURE_ROOT_REL / sprite,
            int(entry.get("width", 0)),
            int(entry.get("height", 0)),
        )
        candidates.append(
            TextureCandidate(
                sprite=sprite,
                angle=int(match.group(1)),
                source_rel=source_rel,
                width=int(entry.get("width", 0)),
                height=int(entry.get("height", 0)),
                pivot_x=pivot_x,
                pivot_y=pivot_y,
            )
        )
    return candidates


def read_sprite_pivot(sprite_dir: Path, width: int, height: int) -> Tuple[int, int]:
    header_path = sprite_dir / "SPRITEHDR.bin"
    if header_path.is_file():
        header = header_path.read_bytes()
        if len(header) >= 0x208:
            return read_s16(header, 0x204), read_s16(header, 0x206)
    return width // 2, height


def domain_hints(definition: ObjectDefinition) -> List[str]:
    name = definition.name.upper()
    sprite = definition.sprite_name.upper()
    object_id = definition.object_id
    hints: List[str] = []

    if "KÜCH" in name or "KUCH" in name or sprite.startswith("KÜCH") or sprite.startswith("KUCH"):
        hints.append("K_CHE")
    if 0x00000530 <= object_id <= 0x08000630:
        hints.append("K_CHE")
    if "EDEL" in name or 0x000907B0 <= object_id <= 0x07000780:
        hints.append("CHEF")
    if "MEETING" in name or sprite in {"LEINWAND", "REDNERPULT"}:
        hints.append("MEETING")
    if sprite in {"BESEN", "HANDTUCHHAKEN", "PUTZWAGEN", "TOIKABINE", "TOIKABINE&EIMER"}:
        hints.append("WC")
    if object_id in {
        0x000203A0,
        0x000203B0,
        0x020003C0,
        0x020003D0,
        0x020003E0,
        0x020003F0,
        0x02000400,
        0x01000480,
        0x01000490,
        0x010004A0,
    } or sprite.startswith("SCHREIBTISCH") or sprite.startswith("STUHL"):
        hints.append("B_RO")
    if sprite.startswith(("SCHRANK", "PFLANZE", "REGAL", "KOMODE")):
        hints.append("ALLGEMEIN")
    hints.append("AKTIV")
    return dedupe(hints)


def dedupe(values: Iterable[str]) -> List[str]:
    result: List[str] = []
    seen = set()
    for value in values:
        if value not in seen:
            result.append(value)
            seen.add(value)
    return result


def source_prefix(candidate: TextureCandidate) -> str:
    match = re.search(r"^CO_OBJECTS_(.+)_IDLE_\d{3}_", candidate.sprite)
    if match:
        return match.group(1)
    return candidate.sprite


def candidate_score(candidate: TextureCandidate, definition: ObjectDefinition, desired_angle: int) -> int:
    if candidate.angle != desired_angle:
        return -1_000_000

    prefix = source_prefix(candidate)
    delimited_prefix = delimiter_normalized(prefix)
    compact_prefix = compact_normalized(prefix)
    score = 0

    alias_scores: List[int] = []
    for delimited_alias, compact_alias in sprite_aliases(definition.sprite_name):
        alias_score = -1_000_000
        token = "_%s" % delimited_alias
        if delimited_prefix == delimited_alias or delimited_prefix.endswith(token):
            alias_score = max(alias_score, 220)
        if compact_prefix.endswith(compact_alias):
            alias_score = max(alias_score, 180)
        if compact_alias in compact_prefix:
            alias_score = max(alias_score, 80)
        alias_scores.append(alias_score)
    score += max(alias_scores)

    for index, hint in enumerate(domain_hints(definition)):
        if delimiter_normalized(prefix).startswith(delimiter_normalized(hint) + "_") or delimiter_normalized(prefix) == delimiter_normalized(hint):
            score += 60 - index
            break

    definition_compact = compact_normalized(definition.sprite_name)
    prefix_compact = compact_normalized(prefix)
    if "HOCH" in prefix_compact and "HOCH" not in definition_compact:
        score -= 30
    if "DREH" in prefix_compact and "DREH" not in definition_compact:
        score -= 30
    if "EIMER" in prefix_compact and "EIMER" not in definition_compact and "EIMER" not in definition.name.upper():
        score -= 30
    score -= len(prefix_compact) // 8
    return score


def resolve_texture(
    definition: ObjectDefinition,
    variant: int,
    candidates: List[TextureCandidate],
) -> TextureCandidate:
    desired_angle = variant * 90
    scored = [
        (candidate_score(candidate, definition, desired_angle), candidate)
        for candidate in candidates
        if candidate.angle == desired_angle
    ]
    scored = [item for item in scored if item[0] > 0]
    if not scored:
        raise ValueError(
            "No idle texture for object 0x%08x %s variant %d"
            % (definition.object_id, definition.sprite_name, variant)
        )
    scored.sort(key=lambda item: (-item[0], item[1].sprite))
    return scored[0][1]


def atlas_index_to_coords(index: int, columns: int, tile_count: int, atlas_name: str) -> List[int]:
    if index < 0 or index >= tile_count:
        raise ValueError(f"{atlas_name} tile index {index} outside 0..{tile_count - 1}")
    return [index % columns, index // columns]


def build_tile_cells(
    tiles: List[int],
    width: int,
    visible_width: int,
    visible_height: int,
    source_id: int,
    columns: int,
    tile_count: int,
    atlas_name: str,
    value_offset: int = 0,
) -> List[Dict[str, object]]:
    cells: List[Dict[str, object]] = []
    for index, tile_id in enumerate(tiles):
        cell_x = index % width
        cell_y = index // width
        if cell_x >= visible_width or cell_y >= visible_height:
            continue
        if tile_id == 0 and value_offset != 0:
            continue
        atlas_index = tile_id + value_offset
        cells.append(
            {
                "cell": [cell_x, cell_y],
                "source_id": source_id,
                "atlas_coords": atlas_index_to_coords(atlas_index, columns, tile_count, atlas_name),
                "tile_id": tile_id,
            }
        )
    return cells


def object_texture_slug(candidate: TextureCandidate) -> str:
    prefix = source_prefix(candidate)
    return slugify("%s-%03d" % (prefix, candidate.angle))


def destination_for_texture(candidate: TextureCandidate) -> Path:
    return OBJECT_IMAGE_DIR_REL / f"{object_texture_slug(candidate)}.png"


def round_float(value: float) -> float:
    return round(value, 6)


def build_manifest(root: Path) -> Tuple[Dict[str, object], Dict[Path, Path]]:
    level = parse_level_file(root / LEVEL_SOURCE_REL)
    object_db = parse_object_database(root / OBJECT_DB_REL)
    texture_candidates = load_texture_candidates(root)
    tile_manifest = json.loads((root / TILE_ATLAS_MANIFEST_REL).read_text(encoding="utf-8"))
    atlases = tile_manifest["atlases"]

    width = int(level["width"])
    height = int(level["height"])
    # The original tile renderer iterates with exclusive max bounds at width - 1 and height - 1.
    visible_width = max(width - 1, 0)
    visible_height = max(height - 1, 0)
    layers = level["layers"]
    floor_tiles = layers["LAYER0"]
    wall_tiles = layers["LAYER1"]
    duplicate_wall_tiles = layers["LAYER2"]
    if wall_tiles != duplicate_wall_tiles:
        raise ValueError(f"{LEVEL_SOURCE_REL.name} LAYER2 no longer matches LAYER1; importer needs a separate mapping")

    floor_atlas = atlases["floor"]
    wall_atlas = atlases["walls"]

    source_to_dest: Dict[Path, Path] = {}
    resolved_by_source: Dict[str, ResolvedTexture] = {}
    objects: List[Dict[str, object]] = []
    for item in level["items"]:
        kind = int(item["kind"])
        object_id = kind & 0xFFFFFFF0
        definition = object_db.get(kind) or object_db.get(object_id)
        if definition is None:
            raise ValueError("No object definition for kind 0x%08x" % kind)
        variant = kind & 0xF
        texture = resolve_texture(definition, variant, texture_candidates)
        if texture.sprite not in resolved_by_source:
            dest_rel = destination_for_texture(texture)
            resolved_by_source[texture.sprite] = ResolvedTexture(texture, dest_rel)
            source_to_dest[texture.source_rel] = dest_rel
        else:
            dest_rel = resolved_by_source[texture.sprite].dest_rel

        node_slug = slugify("%03d-%s" % (int(item["instance_id"]), definition.sprite_name))
        objects.append(
            {
                "record_name": item["record_name"],
                "node_name": "Object%s" % node_slug.title().replace("-", ""),
                "kind": "0x%08x" % kind,
                "object_id": "0x%08x" % object_id,
                "variant": variant,
                "display_name": definition.name,
                "sprite_name": definition.sprite_name,
                "source_sprite": texture.sprite,
                "texture": "res://%s" % dest_rel.as_posix(),
                "texture_size": [texture.width, texture.height],
                "pivot": [texture.pivot_x, texture.pivot_y],
                "tile_position": [round_float(float(item["x"])), round_float(float(item["y"]))],
                "height": round_float(float(item["z"])),
                "instance_id": int(item["instance_id"]),
                "flags": int(item["flags"]),
            }
        )

    spawns = []
    for spawn in level["spawns"]:
        spawns.append(
            {
                "spawn_id": int(spawn["spawn_id"]),
                "tile_position": [round_float(float(spawn["x"])), round_float(float(spawn["y"]))],
                "height": round_float(float(spawn["z"])),
                "instance_id": int(spawn["instance_id"]),
                "flags": int(spawn["flags"]),
            }
        )

    manifest = {
        "generated_by": "tools/import_original_level.py",
        "source": LEVEL_SOURCE_REL.as_posix(),
        "original_level_index": ORIGINAL_LEVEL_INDEX,
        "playable_level_number": PLAYABLE_LEVEL_NUMBER,
        "original_level_text": LEVEL_TEXT_REL.as_posix(),
        "object_database": OBJECT_DB_REL.as_posix(),
        "tile_atlas_manifest": TILE_ATLAS_MANIFEST_REL.as_posix(),
        "tile_size": list(TILE_SIZE),
        "source_id": SOURCE_ID,
        "map": {
            "width": width,
            "height": height,
            "visible_width": visible_width,
            "visible_height": visible_height,
            "layer_count": int(level["layer_count"]),
        },
        "tile_layers": [
            {
                "name": "FloorTileMapLayer",
                "tileset": floor_atlas["tileset"],
                "z_index": -20,
                "cells": build_tile_cells(
                    floor_tiles,
                    width,
                    visible_width,
                    visible_height,
                    SOURCE_ID,
                    int(floor_atlas["columns"]),
                    len(floor_atlas["tiles"]),
                    "floor",
                ),
            },
            {
                "name": "WallTileMapLayer",
                "tileset": wall_atlas["tileset"],
                "z_index": -5,
                "cells": build_tile_cells(
                    wall_tiles,
                    width,
                    visible_width,
                    visible_height,
                    SOURCE_ID,
                    int(wall_atlas["columns"]),
                    len(wall_atlas["tiles"]),
                    "walls",
                    -1,
                ),
            },
            {
                "name": "GlassTileMapLayer",
                "tileset": atlases["glass"]["tileset"],
                "z_index": -4,
                "cells": [],
            },
        ],
        "objects": objects,
        "spawns": spawns,
        "player_spawn_id": 0,
        "ignored_layers": {
            "LAYER2": f"matches LAYER1 for {LEVEL_SOURCE_REL.name} and is not rendered twice",
        },
    }
    return manifest, source_to_dest


def write_atomic_text(text: str, target: Path) -> None:
    target.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile("w", delete=False, encoding="utf-8", dir=str(target.parent)) as handle:
        handle.write(text)
        temp_path = Path(handle.name)
    try:
        os.replace(temp_path, target)
    finally:
        temp_path.unlink(missing_ok=True)


def copy_atomic(source: Path, target: Path) -> None:
    target.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(delete=False, suffix=target.suffix, dir=str(target.parent)) as handle:
        temp_path = Path(handle.name)
    try:
        shutil.copy2(source, temp_path)
        os.replace(temp_path, target)
    finally:
        temp_path.unlink(missing_ok=True)


def write_outputs(root: Path, manifest: Dict[str, object], source_to_dest: Dict[Path, Path]) -> None:
    manifest_text = json.dumps(manifest, indent=2, sort_keys=True, ensure_ascii=False) + "\n"
    write_atomic_text(manifest_text, root / LEVEL_MANIFEST_REL)
    remove_stale_object_textures(root, source_to_dest.values())
    for source_rel, dest_rel in sorted(source_to_dest.items(), key=lambda item: item[1].as_posix()):
        copy_atomic(root / source_rel, root / dest_rel)


def remove_stale_object_textures(root: Path, expected_dest_rels: Iterable[Path]) -> None:
    object_dir = root / OBJECT_IMAGE_DIR_REL
    if not object_dir.is_dir():
        return
    expected = {root / dest_rel for dest_rel in expected_dest_rels}
    for path in object_dir.glob("*.png"):
        if path not in expected:
            path.unlink()
    expected_imports = {Path(str(path) + ".import") for path in expected}
    for path in object_dir.glob("*.png.import"):
        if path not in expected_imports:
            path.unlink()


def compare_outputs(root: Path, manifest: Dict[str, object], source_to_dest: Dict[Path, Path]) -> int:
    expected_manifest = json.dumps(manifest, indent=2, sort_keys=True, ensure_ascii=False) + "\n"
    manifest_path = root / LEVEL_MANIFEST_REL
    failures: List[str] = []
    if not manifest_path.is_file():
        failures.append(f"missing {LEVEL_MANIFEST_REL}")
    elif manifest_path.read_text(encoding="utf-8") != expected_manifest:
        failures.append(f"stale {LEVEL_MANIFEST_REL}")

    for source_rel, dest_rel in sorted(source_to_dest.items(), key=lambda item: item[1].as_posix()):
        source = root / source_rel
        target = root / dest_rel
        if not target.is_file():
            failures.append(f"missing {dest_rel}")
        elif not filecmp.cmp(source, target, shallow=False):
            failures.append(f"stale {dest_rel}")

    expected_dest_rels = set(source_to_dest.values())
    object_dir = root / OBJECT_IMAGE_DIR_REL
    if object_dir.is_dir():
        for path in sorted(object_dir.glob("*.png")):
            rel = path.relative_to(root)
            if rel not in expected_dest_rels:
                failures.append(f"stale {rel}")

    if failures:
        print("Level 1 import outputs are stale:", file=sys.stderr)
        for failure in failures:
            print(f"  {failure}", file=sys.stderr)
        return 1
    print("Level 1 import data is up to date.")
    return 0


def run_godot_scene_builder(root: Path, godot_binary: str) -> None:
    env = os.environ.copy()
    env.setdefault("HOME", "/tmp/sacked-godot-home")
    env.setdefault("XDG_CONFIG_HOME", "/tmp/sacked-godot-config")
    env.setdefault("XDG_DATA_HOME", "/tmp/sacked-godot-xdg")

    subprocess.run([godot_binary, "--headless", "--path", ".", "--import"], cwd=root, env=env, check=True)
    subprocess.run(
        [
            godot_binary,
            "--headless",
            "--path",
            ".",
            "--script",
            "tools/build_level_scene.gd",
            "--",
            "res://%s" % LEVEL_MANIFEST_REL.as_posix(),
            "res://%s" % LEVEL_SCENE_REL.as_posix(),
        ],
        cwd=root,
        env=env,
        check=True,
    )
    normalize_scene_file(root / LEVEL_SCENE_REL)


def normalize_scene_file(path: Path) -> None:
    text = path.read_text(encoding="utf-8")
    lines = text.splitlines()
    if not lines:
        return

    ext_resources: List[Dict[str, str]] = []
    rest: List[str] = []
    header = re.sub(r' uid="[^"]+"', "", lines[0])
    for line in lines[1:]:
        if line.startswith("[ext_resource "):
            attrs = dict(re.findall(r'(\w+)="([^"]*)"', line))
            old_id = attrs.get("id")
            if old_id:
                ext_resources.append(
                    {
                        "old_id": old_id,
                        "type": attrs.get("type", ""),
                        "path": attrs.get("path", ""),
                    }
                )
            continue
        rest.append(re.sub(r" unique_id=\d+", "", line))

    ext_resources.sort(key=lambda item: (item["type"], item["path"], item["old_id"]))
    id_map = {item["old_id"]: str(index + 1) for index, item in enumerate(ext_resources)}
    normalized_ext_lines = [
        '[ext_resource type="%s" path="%s" id="%s"]' % (item["type"], item["path"], id_map[item["old_id"]])
        for item in ext_resources
    ]

    normalized_rest: List[str] = []
    ext_ref_pattern = re.compile(r'ExtResource\("([^"]+)"\)')
    for line in rest:
        def replace_ext_ref(match) -> str:
            old_id = match.group(1)
            return 'ExtResource("%s")' % id_map.get(old_id, old_id)

        normalized_rest.append(ext_ref_pattern.sub(replace_ext_ref, line))

    while normalized_rest and normalized_rest[0] == "":
        normalized_rest.pop(0)

    output_lines = [header, ""] + normalized_ext_lines + [""] + normalized_rest
    write_atomic_text("\n".join(output_lines).rstrip() + "\n", path)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Import original Sacked first playable level data into the Godot project.")
    parser.add_argument("--check", action="store_true", help="Verify copied object textures and level manifest are current.")
    parser.add_argument("--skip-godot", action="store_true", help="Write manifest and object textures without regenerating the scene.")
    parser.add_argument("--godot-binary", default="./Godot_v4.6.2-stable_linux.x86_64", help="Godot binary used to serialize the level scene.")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    root = repo_root()
    manifest, source_to_dest = build_manifest(root)
    if args.check:
        return compare_outputs(root, manifest, source_to_dest)

    write_outputs(root, manifest, source_to_dest)
    if not args.skip_godot:
        run_godot_scene_builder(root, args.godot_binary)
    return 0


if __name__ == "__main__":
    sys.exit(main())
