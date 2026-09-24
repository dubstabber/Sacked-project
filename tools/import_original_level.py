#!/usr/bin/env python3
import argparse
import filecmp
import json
import math
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
from typing import Dict, Iterable, Iterator, List, Optional, Tuple


SOURCE_ID = 3
TILE_SIZE = (96, 48)
# The level tree accepts 21 levels; sub_408D00 turns button n into original index n - 1.
LEVEL_COUNT = 21
LEVELS_DIR_REL = Path("extract-sacked-assets/sacked/Levels")
OBJECT_DB_REL = Path("extract-sacked-assets/sacked/CO_OBJECTS.DAT")
OBJECT_TEXTURE_LOG_REL = Path("extract-sacked-assets/extracted/textures/CO_OBJECTS/png_conversion_log.json")
OBJECT_TEXTURE_ROOT_REL = Path("extract-sacked-assets/extracted/textures/CO_OBJECTS")
OBJECT_IMAGE_DIR_REL = Path("images/objects")
TILE_ATLAS_MANIFEST_REL = Path("resources/tilemaps/sacked-tile-atlases.json")
LEVEL_MANIFEST_DIR_REL = Path("resources/levels")
OBJECT_PREFAB_DIR_REL = Path("scenes/objects")
NPC_PROFILES = {
    1: "boss",
    2: "secretary",
    3: "janitor",
    4: "male-employee-1",
    5: "male-employee-2",
    6: "female-employee-1",
    7: "female-employee-2",
}
WORKSTATION_TYPES = (152, 153, 154, 155)
CHAIR_TYPES = (68, 69, 70, 71, 72, 73, 74, 86, 93, 94, 121, 122)


@dataclass(frozen=True)
class LevelPaths:
    """Every path that depends on which level is being imported."""

    number: int
    index: int
    points: bool
    source_rel: Path
    points_source_rel: Path
    text_rel: Path
    manifest_rel: Path
    scene_rel: Path

    @property
    def label(self) -> str:
        """How this build is named in messages: "5" for the level, "5s" for its variant."""
        return "%d%s" % (self.number, "s" if self.points else "")


def level_paths(number: int, points: bool = False) -> LevelPaths:
    """Where one build reads from and writes to.

    sub_408D00 picks the plain file for the time game and the S file for the points game.
    Where the two differ only in CONDITION one scene serves both, so only the divergent
    levels get a second, "s"-suffixed build whose layout comes from the S file.
    """
    if not 1 <= number <= LEVEL_COUNT:
        raise ValueError(f"level {number} is outside the original's 1..{LEVEL_COUNT} range")
    index = number - 1
    points_source_rel = LEVELS_DIR_REL / ("LEVEL_%02ds.col" % index)
    suffix = "s" if points else ""
    return LevelPaths(
        number=number,
        index=index,
        points=points,
        source_rel=points_source_rel if points else LEVELS_DIR_REL / ("LEVEL_%02d.col" % index),
        points_source_rel=points_source_rel,
        text_rel=LEVELS_DIR_REL / ("Level_%02d.txt" % index),
        manifest_rel=LEVEL_MANIFEST_DIR_REL / ("level_%d%s.json" % (number, suffix)),
        scene_rel=Path("scenes/level_%d%s.tscn" % (number, suffix)),
    )


def imported_level_numbers(root: Path) -> List[int]:
    """The levels this checkout has already imported, in numeric order.

    Points-mode variants are named level_<n>s.json and are deliberately not matched: they
    belong to a level rather than being one.
    """
    numbers = []
    for path in (root / LEVEL_MANIFEST_DIR_REL).glob("level_*.json"):
        match = re.fullmatch(r"level_(\d+)", path.stem)
        if match:
            number = int(match.group(1))
            if 1 <= number <= LEVEL_COUNT:
                numbers.append(number)
    return sorted(numbers) or [1]


def imported_manifest_paths(root: Path) -> List[Path]:
    """Every imported manifest, each level followed by its points variant if it has one.

    The order is fixed so the exporters that read manifests can never reshuffle which
    level a shared texture is first seen in.
    """
    paths: List[Path] = []
    for number in imported_level_numbers(root):
        for points in (False, True):
            manifest_rel = level_paths(number, points=points).manifest_rel
            if (root / manifest_rel).is_file():
                paths.append(manifest_rel)
    return paths


@dataclass(frozen=True)
class LevelBuild:
    """One build's computed manifest, before anything is written."""

    paths: LevelPaths
    manifest: Dict[str, object]
    source_to_dest: Dict[Path, Path]
    points_variant: Optional["LevelBuild"] = None


def every_build(builds: Dict[int, "LevelBuild"]) -> Iterator["LevelBuild"]:
    """Every build in a fixed order: each level, then the points variant it may have."""
    for number in sorted(builds):
        build = builds[number]
        yield build
        if build.points_variant is not None:
            yield build.points_variant


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
    category: int
    name: str
    sprite_name: str
    interaction_offset: Tuple[float, float] = (0.0, 0.0)
    action_ids: Tuple[int, ...] = ()


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


def parse_info_data(payload: bytes, expected_count: int) -> List[int]:
    if len(payload) != expected_count * 4:
        raise ValueError(f"INFODATA has {len(payload)} bytes, expected {expected_count * 4}")
    return [read_u32(payload, offset) for offset in range(0, len(payload), 4)]


def build_collision_grid(info_data: List[int], width: int, height: int) -> Dict[str, object]:
    if width <= 0 or height <= 0 or len(info_data) != width * height:
        raise ValueError("INFODATA cell count does not match the map dimensions")
    # sub_412AE0 reads these bits independently; see docs/collision-reference.md.
    return {
        "source_chunk": "INFODATA",
        "width": width,
        "height": height,
        "blocked_cells": [[index % width, index // width] for index, value in enumerate(info_data) if value & 1],
        "sight_blocked_cells": [[index % width, index // width] for index, value in enumerate(info_data) if value & 2],
        "room_ids": [(value >> 16) & 0xFF for value in info_data],
    }


# sub_412FB0 accepts a CONDITION half only inside these ranges and otherwise keeps the
# value it already had; see docs/game-rules-reference.md.
CONDITION_TIME_RANGE = (1.0, 3600.0)
CONDITION_SCORE_RANGE = (1, 99999)


def parse_condition(data: bytes) -> Dict[str, object]:
    record = find_chunk(data, "CONDITION")
    if len(record.payload) != 8:
        raise ValueError(f"CONDITION has {len(record.payload)} payload bytes, expected 8")
    time_limit = read_f32(record.payload, 0)
    score_target = read_u32(record.payload, 4)
    if not CONDITION_TIME_RANGE[0] <= time_limit <= CONDITION_TIME_RANGE[1]:
        raise ValueError(f"CONDITION time limit {time_limit} is outside the range the engine accepts")
    if not CONDITION_SCORE_RANGE[0] <= score_target <= CONDITION_SCORE_RANGE[1]:
        raise ValueError(f"CONDITION score target {score_target} is outside the range the engine accepts")
    return {"time_limit_seconds": round_float(time_limit), "score_target": score_target}


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
    info_data = parse_info_data(find_chunk(data, "INFODATA").payload, expected_count)

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
        "condition": parse_condition(data),
        "info_data": info_data,
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
        if record is None or record.name != "ITEM" or len(record.payload) != 544:
            continue
        object_id = read_u32(record.payload, 0)
        if object_id in (0, 0xFFFFFFFF):
            continue
        category = read_u32(record.payload, 4)
        name = read_cstr(record.payload, 8, 128)
        sprite_name = read_cstr(record.payload, 264, 64)
        if sprite_name == "":
            continue
        interaction_offset = (read_f32(record.payload, 536), read_f32(record.payload, 540))
        # item_crazyoffice.cpp keeps eight prank action ids per object; see docs/prank-reference.md.
        action_ids = tuple(value for value in record.payload[528:536] if value)
        definitions[object_id] = ObjectDefinition(
            object_id, category, name, sprite_name, interaction_offset, action_ids
        )

    if not definitions:
        raise ValueError(f"No object definitions parsed from {path}")
    return definitions


def oriented_interaction_offset(offset: Tuple[float, float], variant: int) -> Tuple[float, float]:
    # sub_410550 swaps axes for odd variants; this is not a conventional rotation.
    x, y = offset
    return ((x, y), (y, x), (-x, -y), (-y, -x))[variant & 3]


def find_startup_item(
    items: List[Dict[str, object]],
    item_types: Tuple[int, ...],
    claimed: set,
    origin: Tuple[float, float],
    radii: Iterable[float],
) -> Optional[Dict[str, object]]:
    # sub_418230 returns the first item inside each search radius, not the nearest.
    for radius in radii:
        for item in items:
            if int(item["instance_id"]) in claimed or ((int(item["kind"]) >> 4) & 0xFFF) not in item_types:
                continue
            if math.hypot(float(item["x"]) - origin[0], float(item["y"]) - origin[1]) < radius:
                return item
    return None


def build_npcs(level: Dict[str, object], object_db: Dict[int, ObjectDefinition]) -> List[Dict[str, object]]:
    npcs = []
    claimed = set()
    unique_spawns = set()
    for spawn in sorted(level["spawns"], key=lambda entry: int(entry["spawn_id"])):
        spawn_id = int(spawn["spawn_id"])
        if spawn_id == 0:
            continue
        if spawn_id not in NPC_PROFILES:
            raise ValueError(f"Unknown NPC spawn type {spawn_id}")
        if spawn_id <= 3 and spawn_id in unique_spawns:
            continue
        unique_spawns.add(spawn_id)
        profile_id = NPC_PROFILES[spawn_id]
        origin = (float(spawn["x"]), float(spawn["y"]))
        workstation = None
        chair = None
        if spawn_id not in (1, 3):
            workstation = find_startup_item(level["items"], WORKSTATION_TYPES, claimed, origin, (index * 0.5 for index in range(1, 21)))
            if workstation is not None:
                if object_db[int(workstation["kind"]) & ~3].category == 5:
                    claimed.add(int(workstation["instance_id"]))
                    origin = (float(workstation["x"]), float(workstation["y"]))
                else:
                    workstation = None
            chair = find_startup_item(level["items"], CHAIR_TYPES, claimed, origin, (1.0, 2.0, 3.0))
            if chair is not None:
                if object_db[int(chair["kind"]) & ~3].category != 5:
                    claimed.add(int(chair["instance_id"]))
                else:
                    chair = None
        npcs.append({
            "node_name": "Npc%03d%s" % (int(spawn["instance_id"]), profile_id.title().replace("-", "")),
            "spawn_id": spawn_id,
            "instance_id": int(spawn["instance_id"]),
            "profile_id": profile_id,
            "profile": f"res://scenes/npc/profiles/{profile_id}.tres",
            "tile_position": [round_float(float(spawn["x"])), round_float(float(spawn["y"]))],
            "height": round_float(float(spawn["z"])),
            "initial_direction_index": 0,
            "assigned_workstation_instance_id": int(workstation["instance_id"]) if workstation else None,
            "assigned_chair_instance_id": int(chair["instance_id"]) if chair else None,
        })
    return npcs


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
    category_hints = {
        0: "ALLGEMEIN",
        1: "B_RO",
        2: "K_CHE",
        3: "WC",
        4: "CHEF",
        5: "AKTIV",
        6: "AUFENTHALT",
        7: "FOYER",
        8: "HAUSMEISTER",
        9: "MEETING",
    }
    name = definition.name.upper()
    sprite = definition.sprite_name.upper()
    hints: List[str] = []

    if definition.category in category_hints:
        return [category_hints[definition.category]]
    if "KÜCH" in name or "KUCH" in name or sprite.startswith("KÜCH") or sprite.startswith("KUCH"):
        hints.append("K_CHE")
    if "EDEL" in name:
        hints.append("CHEF")
    if "MEETING" in name or sprite in {"LEINWAND", "REDNERPULT"}:
        hints.append("MEETING")
    if sprite in {"BESEN", "HANDTUCHHAKEN", "PUTZWAGEN", "TOIKABINE", "TOIKABINE&EIMER"}:
        hints.append("WC")
    if definition.object_id in {
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


@dataclass(frozen=True)
class ImportContext:
    """The level-independent inputs, loaded once and shared by every level."""

    object_db: Dict[int, "ObjectDefinition"]
    texture_candidates: List["TextureCandidate"]
    atlases: Dict[str, object]


def load_import_context(root: Path) -> ImportContext:
    tile_manifest = json.loads((root / TILE_ATLAS_MANIFEST_REL).read_text(encoding="utf-8"))
    return ImportContext(
        object_db=parse_object_database(root / OBJECT_DB_REL),
        texture_candidates=load_texture_candidates(root),
        atlases=tile_manifest["atlases"],
    )


def points_file_differences(level: Dict[str, object], points_level: Dict[str, object]) -> List[str]:
    """Which chunks the points-mode S file changes beyond CONDITION.

    Most levels change nothing else, and one scene then serves both game modes because it
    carries both CONDITIONs. Six of the campaign's levels (5, 8, 11, 12, 19 and 20) also
    move items or floor tiles, and those get a second scene built from the S file rather
    than quietly rendering the time game's layout in the points game.
    """
    return [key for key in sorted(level) if key != "condition" and level[key] != points_level.get(key)]


# ITEM records the original loads but never lets the player see, left out of the scene. Keyed
# by (level file, record) to the kind and tile position the record must still have.
#
# The original keeps an item wherever it sits: sub_412FB0 hands every ITEM chunk to sub_412AB0,
# whose sub_410550 / sub_42B330 take the raw position with no bounds test, and sub_411E20 /
# sub_41A2D0 / sub_40FCE0 cull only against the camera rect (item+232, the one hide flag, is set
# only during actions). That rect is 800 x 600, centred on the player's ground position with no
# clamp (sub_405750 0x405870-0x405885, CIsoCamera 0x409240, sub_402590 0x402771-0x4027A3,
# sub_403780 0x4037B0). Level 3's spare monitor stands five tiles off the map, and from the
# closest spot the player can reach at most a ~10 px sliver of its transparent-tapered keyboard
# tip enters that rect; the port's wider canvas would show all of it floating in the void.
# LEVEL_02s.col repeats the record and matters only if level 3 ever earns a points build.
# LEVEL_10s.col ITEM132, the only other record off the map, is fully visible at 4:3 and stays.
# See docs/widescreen.md.
PARKED_RECORDS: Dict[Tuple[str, str], Tuple[int, float, float]] = {
    ("LEVEL_02.col", "ITEM22"): (0x00060980, -5.0, 16.0),
    ("LEVEL_02s.col", "ITEM22"): (0x00060980, -5.0, 16.0),
}


def parked_record_names(source_name: str, items: List[Dict[str, object]]) -> set:
    """The records of one level file that PARKED_RECORDS leaves out of its scene.

    Every entry for the file must still match its record exactly, so a changed level file
    fails the import instead of quietly dropping, or keeping, the wrong item.
    """
    by_name = {item["record_name"]: item for item in items}
    parked = set()
    for (source, record_name), expected in PARKED_RECORDS.items():
        if source != source_name:
            continue
        item = by_name.get(record_name)
        if item is None or (int(item["kind"]), float(item["x"]), float(item["y"])) != expected:
            raise ValueError(f"{source_name} {record_name} no longer matches its PARKED_RECORDS entry {expected}")
        parked.add(record_name)
    return parked


def build_level(root: Path, number: int, context: ImportContext) -> LevelBuild:
    """One level, plus the second build its points-mode file earns when it diverges."""
    paths = level_paths(number)
    level = parse_level_file(root / paths.source_rel)
    points_level = parse_level_file(root / paths.points_source_rel)
    # Both builds carry both CONDITIONs, so LevelSession picks by mode either way and a
    # restart in the points game keeps its own target.
    conditions = {"time": level["condition"], "points": points_level["condition"]}
    manifest, source_to_dest = manifest_from_level(paths, level, conditions, context)
    variant: Optional[LevelBuild] = None
    if points_file_differences(level, points_level):
        variant_paths = level_paths(number, points=True)
        variant_manifest, variant_sources = manifest_from_level(variant_paths, points_level, conditions, context)
        variant = LevelBuild(paths=variant_paths, manifest=variant_manifest, source_to_dest=variant_sources)
    return LevelBuild(paths=paths, manifest=manifest, source_to_dest=source_to_dest, points_variant=variant)


def manifest_from_level(
    paths: LevelPaths,
    level: Dict[str, object],
    conditions: Dict[str, object],
    context: ImportContext,
) -> Tuple[Dict[str, object], Dict[Path, Path]]:
    object_db = context.object_db
    texture_candidates = context.texture_candidates
    atlases = context.atlases

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
        raise ValueError(f"{paths.source_rel.name} LAYER2 no longer matches LAYER1; importer needs a separate mapping")

    floor_atlas = atlases["floor"]
    wall_atlas = atlases["walls"]

    source_to_dest: Dict[Path, Path] = {}
    resolved_by_source: Dict[str, ResolvedTexture] = {}
    objects: List[Dict[str, object]] = []
    parked_names = parked_record_names(paths.source_rel.name, level["items"])
    parked_items: List[Dict[str, object]] = []
    for item in level["items"]:
        kind = int(item["kind"])
        object_id = kind & 0xFFFFFFF0
        definition = object_db.get(kind) or object_db.get(object_id)
        if definition is None:
            raise ValueError("No object definition for kind 0x%08x" % kind)
        if item["record_name"] in parked_names:
            parked_items.append(
                {
                    "record_name": item["record_name"],
                    "instance_id": int(item["instance_id"]),
                    "kind": "0x%08x" % kind,
                    "sprite_name": definition.sprite_name,
                    "tile_position": [round_float(float(item["x"])), round_float(float(item["y"]))],
                }
            )
            continue
        variant = kind & 0xF
        interaction_offset = oriented_interaction_offset(definition.interaction_offset, variant)
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
                "object_category": int(definition.category),
                "variant": variant,
                "action_ids": list(definition.action_ids),
                "display_name": definition.name,
                "sprite_name": definition.sprite_name,
                "source_sprite": texture.sprite,
                "texture": "res://%s" % dest_rel.as_posix(),
                "texture_size": [texture.width, texture.height],
                "pivot": [texture.pivot_x, texture.pivot_y],
                "tile_position": [round_float(float(item["x"])), round_float(float(item["y"]))],
                "interaction_tile_position": [
                    round_float(float(item["x"]) + interaction_offset[0]),
                    round_float(float(item["y"]) + interaction_offset[1]),
                ],
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

    # sub_4185B0's startup search sees every item, parked or not, but a parked item has no
    # node for build_level_scene.gd to point an assignment at.
    npcs = build_npcs(level, object_db)
    parked_ids = {entry["instance_id"] for entry in parked_items}
    for npc in npcs:
        for field in ("assigned_workstation_instance_id", "assigned_chair_instance_id"):
            if npc[field] in parked_ids:
                raise ValueError(f"{paths.source_rel.name} {npc['node_name']} is assigned parked item {npc[field]}")

    manifest = {
        "generated_by": "tools/import_original_level.py",
        "source": paths.source_rel.as_posix(),
        # Only a points-mode variant carries this, so a level's own manifest is unchanged.
        **({"game_mode": "points"} if paths.points else {}),
        "original_level_index": paths.index,
        "playable_level_number": paths.number,
        "original_level_text": paths.text_rel.as_posix(),
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
        "conditions": conditions,
        "collision_grid": build_collision_grid(level["info_data"], width, height),
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
        # Only a level that parks something carries this, so every other manifest is unchanged.
        **({"parked_items": parked_items} if parked_items else {}),
        "npcs": npcs,
        "spawns": spawns,
        "player_spawn_id": 0,
        "ignored_layers": {
            "LAYER2": f"matches LAYER1 for {paths.source_rel.name} and is not rendered twice",
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


def manifest_text(manifest: Dict[str, object]) -> str:
    return json.dumps(manifest, indent=2, sort_keys=True, ensure_ascii=False) + "\n"


def check_texture_union(builds: Dict[int, "LevelBuild"]) -> None:
    """One slug must mean one sprite at one pivot across every level.

    build_level_scene.gd keys its prefab cache on (texture, pivot) but names the file after
    the texture alone, so two levels disagreeing here would silently overwrite each other's
    prefab. Its own -pivot-X-Y fallback only sees one level per process, which is why this
    has to be caught here.
    """
    seen: Dict[str, Tuple[str, Tuple[object, ...]]] = {}
    conflicts: List[str] = []
    for build in every_build(builds):
        for entry in build.manifest["objects"]:
            slug = Path(str(entry["texture"])).stem
            signature = (entry["source_sprite"], tuple(entry["pivot"]), tuple(entry["texture_size"]))
            first = seen.get(slug)
            if first is None:
                seen[slug] = (build.paths.label, signature)
            elif first[1] != signature:
                conflicts.append(
                    "%s: level %s has %s but level %s has %s"
                    % (slug, first[0], first[1], build.paths.label, signature)
                )
    if conflicts:
        raise ValueError("object texture slugs disagree between levels:\n  " + "\n  ".join(sorted(set(conflicts))))


def write_outputs(root: Path, builds: Dict[int, "LevelBuild"], targets: Iterable[int]) -> None:
    union = union_destinations(builds)
    for number in sorted(targets):
        build = builds[number]
        write_atomic_text(manifest_text(build.manifest), root / build.paths.manifest_rel)
        if build.points_variant is not None:
            variant = build.points_variant
            write_atomic_text(manifest_text(variant.manifest), root / variant.paths.manifest_rel)
        else:
            # A level whose S file has stopped diverging must not keep a second build.
            remove_points_variant_outputs(root, number)
    remove_stale_object_textures(root, union)
    for build in every_build(builds):
        for source_rel, dest_rel in sorted(build.source_to_dest.items(), key=lambda item: item[1].as_posix()):
            source = root / source_rel
            target = root / dest_rel
            # Copying an identical file would only churn its mtime and force a Godot reimport.
            if target.is_file() and filecmp.cmp(source, target, shallow=False):
                continue
            copy_atomic(source, target)


def union_destinations(builds: Dict[int, "LevelBuild"]) -> Dict[Path, Path]:
    union: Dict[Path, Path] = {}
    for build in every_build(builds):
        union.update(build.source_to_dest)
    return union


def remove_points_variant_outputs(root: Path, number: int) -> None:
    variant = level_paths(number, points=True)
    for rel in (variant.manifest_rel, variant.scene_rel):
        (root / rel).unlink(missing_ok=True)


def remove_stale_object_textures(root: Path, union: Dict[Path, Path]) -> None:
    """Prune against the union of every imported level, never one level's manifest alone.

    The glob stays non-recursive on purpose: images/objects/states/ holds the per-state
    frames that export_object_state_assets.py owns, and they are not named here.
    """
    object_dir = root / OBJECT_IMAGE_DIR_REL
    if not object_dir.is_dir():
        return
    expected = {root / dest_rel for dest_rel in union.values()}
    expected |= {path.with_name(path.stem + "-depth.png") for path in expected}
    for path in object_dir.glob("*.png"):
        if path not in expected:
            path.unlink()
    expected_imports = {Path(str(path) + ".import") for path in expected}
    for path in object_dir.glob("*.png.import"):
        if path not in expected_imports:
            path.unlink()


def compare_outputs(root: Path, builds: Dict[int, "LevelBuild"]) -> int:
    failures: List[str] = []
    expected_variants: set = set()
    for build in every_build(builds):
        manifest_path = root / build.paths.manifest_rel
        if not manifest_path.is_file():
            failures.append(f"missing {build.paths.manifest_rel}")
        elif manifest_path.read_text(encoding="utf-8") != manifest_text(build.manifest):
            failures.append(f"stale {build.paths.manifest_rel}")
        if not (root / build.paths.scene_rel).is_file():
            failures.append(f"missing {build.paths.scene_rel}")
        if build.paths.points:
            expected_variants |= {build.paths.manifest_rel, build.paths.scene_rel}

    # A variant on disk for a level whose S file matches is as stale as a missing one.
    for pattern_dir, pattern in ((LEVEL_MANIFEST_DIR_REL, "level_*s.json"), (Path("scenes"), "level_*s.tscn")):
        directory = root / pattern_dir
        if not directory.is_dir():
            continue
        for path in sorted(directory.glob(pattern)):
            rel = path.relative_to(root)
            if rel not in expected_variants:
                failures.append(f"stale {rel}")

    union = union_destinations(builds)
    for source_rel, dest_rel in sorted(union.items(), key=lambda item: item[1].as_posix()):
        source = root / source_rel
        target = root / dest_rel
        if not target.is_file():
            failures.append(f"missing {dest_rel}")
        elif not filecmp.cmp(source, target, shallow=False):
            failures.append(f"stale {dest_rel}")

    expected_dest_rels = set(union.values())
    expected_dest_rels |= {path.with_name(path.stem + "-depth.png") for path in expected_dest_rels}
    object_dir = root / OBJECT_IMAGE_DIR_REL
    if object_dir.is_dir():
        for path in sorted(object_dir.glob("*.png")):
            rel = path.relative_to(root)
            if rel not in expected_dest_rels:
                failures.append(f"stale {rel}")

    # --check cannot run Godot, so the prefabs are verified as a file set only.
    prefab_dir = root / OBJECT_PREFAB_DIR_REL
    if prefab_dir.is_dir():
        expected_prefabs = {dest_rel.stem for dest_rel in union.values()}
        actual_prefabs = {path.stem for path in prefab_dir.glob("*.tscn")}
        for stem in sorted(expected_prefabs - actual_prefabs):
            failures.append(f"missing {OBJECT_PREFAB_DIR_REL / (stem + '.tscn')}")
        for stem in sorted(actual_prefabs - expected_prefabs):
            failures.append(f"stale {OBJECT_PREFAB_DIR_REL / (stem + '.tscn')}")

    levels = ", ".join(build.paths.label for build in every_build(builds))
    if failures:
        print(f"Level import outputs are stale (levels {levels}):", file=sys.stderr)
        for failure in failures:
            print(f"  {failure}", file=sys.stderr)
        return 1
    print(f"Level import data is up to date (levels {levels}).")
    return 0


def run_godot_scene_builder(root: Path, godot_binary: str, builds: Dict[int, "LevelBuild"], targets: Iterable[int]) -> None:
    env = os.environ.copy()
    env.setdefault("HOME", "/tmp/sacked-godot-home")
    env.setdefault("XDG_CONFIG_HOME", "/tmp/sacked-godot-config")
    env.setdefault("XDG_DATA_HOME", "/tmp/sacked-godot-xdg")

    subprocess.run([godot_binary, "--headless", "--path", ".", "--import"], cwd=root, env=env, check=True)
    for number in sorted(targets):
        build = builds[number]
        for target in (build, build.points_variant):
            if target is None:
                continue
            paths = target.paths
            subprocess.run(
                [
                    godot_binary,
                    "--headless",
                    "--path",
                    ".",
                    "--script",
                    "tools/build_level_scene.gd",
                    "--",
                    "res://%s" % paths.manifest_rel.as_posix(),
                    "res://%s" % paths.scene_rel.as_posix(),
                ],
                cwd=root,
                env=env,
                check=True,
            )
            normalize_scene_file(root / paths.scene_rel)
    remove_stale_object_prefabs(root, union_destinations(builds))
    # The builder re-saves every object prefab with a fresh random unique_id, so without
    # the same normalization each regeneration churns all of scenes/objects/.
    for prefab in sorted((root / OBJECT_PREFAB_DIR_REL).glob("*.tscn")):
        normalize_scene_file(prefab)


def remove_stale_object_prefabs(root: Path, union: Dict[Path, Path]) -> None:
    prefab_dir = root / OBJECT_PREFAB_DIR_REL
    if not prefab_dir.is_dir():
        return
    expected = {dest_rel.stem for dest_rel in union.values()}
    for path in prefab_dir.glob("*.tscn"):
        if path.stem not in expected:
            path.unlink()


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
    parser = argparse.ArgumentParser(description="Import original Sacked level data into the Godot project.")
    parser.add_argument("--check", action="store_true", help="Verify copied object textures and level manifests are current.")
    parser.add_argument("--skip-godot", action="store_true", help="Write manifests and object textures without regenerating the scenes.")
    parser.add_argument("--godot-binary", default=None, help="Godot binary used to serialize the level scenes.")
    parser.add_argument(
        "--level",
        type=int,
        action="append",
        dest="levels",
        metavar="N",
        help=f"Playable level 1..{LEVEL_COUNT} to import or refresh; repeatable. Defaults to every imported level.",
    )
    parser.add_argument(
        "--all",
        action="store_true",
        help="Refresh every already-imported level. This never imports a level for the first time; use --level for that.",
    )
    return parser.parse_args()


def build_levels(root: Path, numbers: Iterable[int]) -> Dict[int, LevelBuild]:
    context = load_import_context(root)
    builds: Dict[int, LevelBuild] = {}
    for number in sorted(set(numbers)):
        builds[number] = build_level(root, number, context)
    check_texture_union(builds)
    return builds


def main() -> int:
    args = parse_args()
    root = repo_root()
    known = imported_level_numbers(root)
    targets = list(known) if args.all or not args.levels else sorted(set(args.levels))
    for number in targets:
        level_paths(number)
    # Every imported level is rebuilt in memory, because pruning and the slug guard are only
    # correct against the whole set, not against the levels this run happens to write.
    builds = build_levels(root, set(known) | set(targets))

    if args.check:
        return compare_outputs(root, builds)

    write_outputs(root, builds, targets)
    if not args.skip_godot:
        # Imported here, not at module scope: the tests import this file as
        # tools.import_original_level, where sibling modules are not on sys.path.
        from godot_binary import find_godot_binary

        run_godot_scene_builder(root, args.godot_binary or find_godot_binary(root), builds, targets)
    return 0


if __name__ == "__main__":
    sys.exit(main())
