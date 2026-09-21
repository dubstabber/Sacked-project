#!/usr/bin/env python3
"""Recover the original prank action table from sacked.exe into resources/original/actions.json.

The 156 action records are not a static array in the data section: the compiler emits one
straight-line initializer that stores every field through registers (sub_40A600, 3779
instructions, no branches and no calls). Replaying those stores is the only way to read the
table without transcribing it by hand, so this tool implements a tiny whitelist-only x86
interpreter and refuses to run if the function contains anything outside that whitelist.

Field meanings come from the consumers in sacked.exe; see docs/prank-reference.md.
"""

import argparse
import hashlib
import json
import struct
import sys
from pathlib import Path


EXE_REL = Path("extract-sacked-assets/sacked/sacked.exe")
SOUND_DIR_REL = Path("extract-sacked-assets/sacked/Sound/FX")
ACTICON_DIR_REL = Path("extract-sacked-assets/extracted/textures/CO_GUI")
OBJECT_DB_REL = Path("extract-sacked-assets/sacked/CO_OBJECTS.DAT")
OUTPUT_REL = Path("resources/original/actions.json")

# The build this project targets. Every address below is only meaningful for this image.
EXE_SIZE = 479232
EXE_SHA256 = "6404096cc74e1c954daa2033a7d7d7826429a27deaa679f1ff7103027f614a86"

INITIALIZER_START = 0x40A600  # sub_40A5F0 is a five-byte jmp thunk to here
TABLE_VA = 0x474C00
RECORD_STRIDE = 0x4C  # sub_4103E0: 76 * action_id + 0x474C00
ACTION_COUNT = 156  # assert "m_action[p_set] >= 0 && m_action[p_set] <= 155"

NAME_TABLE_VA = 0x46BD04
ICON_TABLE_VA = 0x46C100
ICON_COUNT = 66  # assert "aicon[b] >= 0 && aicon[b] <= 65"
ITEM_STATE_TABLE_VA = 0x46DD54
ITEM_STATE_COUNT = 16  # sub_40FDA0 clamps the state to 0..15
BUBBLE_TABLE_VA = 0x46E7A8
BUBBLE_COUNT = 10

# sub_41D820 ignores a required-item slot whose value is >= 31, so those are not prerequisites.
REQUIRED_ITEM_LIMIT = 0x1F
PICKUP_RESULT_STATE = 17  # sub_41B240 skips the item state change entirely
IN_USE_RESULT_STATE = 18  # sets item+232 while the action runs


class Image:
    """The pinned executable, addressable by virtual address."""

    def __init__(self, path: Path):
        self.data = path.read_bytes()
        self.path = path
        digest = hashlib.sha256(self.data).hexdigest()
        if len(self.data) != EXE_SIZE or digest != EXE_SHA256:
            raise SystemExit(
                f"{path} is not the build these addresses were recovered from "
                f"(size {len(self.data)}, sha256 {digest})."
            )
        self.sections = self._sections()

    def _sections(self) -> list:
        pe = struct.unpack_from("<I", self.data, 0x3C)[0]
        if self.data[pe : pe + 4] != b"PE\0\0":
            raise SystemExit("Not a PE image")
        section_count, = struct.unpack_from("<H", self.data, pe + 6)
        optional_size, = struct.unpack_from("<H", self.data, pe + 20)
        self.image_base, = struct.unpack_from("<I", self.data, pe + 24 + 28)
        table = pe + 24 + optional_size
        sections = []
        for index in range(section_count):
            entry = table + 40 * index
            virtual_size, virtual_address, raw_size, raw_offset = struct.unpack_from(
                "<IIII", self.data, entry + 8
            )
            sections.append((virtual_address, max(virtual_size, raw_size), raw_offset, raw_size))
        return sections

    def offset(self, va: int):
        rva = va - self.image_base
        for virtual_address, virtual_size, raw_offset, raw_size in self.sections:
            if virtual_address <= rva < virtual_address + virtual_size:
                delta = rva - virtual_address
                return raw_offset + delta if delta < raw_size else None
        return None

    def byte(self, va: int) -> int:
        offset = self.offset(va)
        return self.data[offset] if offset is not None else 0

    def cstring(self, va: int):
        offset = self.offset(va)
        if offset is None:
            return None
        end = self.data.find(b"\0", offset)
        return self.data[offset:end].decode("cp1250")

    def pointers(self, va: int, count: int) -> list:
        return [
            struct.unpack_from("<I", self.data, self.offset(va) + 4 * index)[0]
            for index in range(count)
        ]


class Interpreter:
    """Replays the initializer's stores. Anything outside the whitelist is a hard error."""

    def __init__(self, image: Image):
        self.image = image
        self.regs = [0] * 8
        self.memory = {}
        self.stores = 0
        self.loads = 0
        self.instructions = 0

    def _load(self, va: int, size: int) -> int:
        value = 0
        for index in range(size):
            byte = self.memory.get(va + index)
            value |= (self.image.byte(va + index) if byte is None else byte) << (8 * index)
        return value

    def _store(self, va: int, size: int, value: int) -> None:
        for index in range(size):
            self.memory[va + index] = (value >> (8 * index)) & 0xFF
        self.stores += 1

    def _get(self, reg: int, size: int) -> int:
        if size == 4:
            return self.regs[reg]
        if size == 2:
            return self.regs[reg] & 0xFFFF
        # 8-bit register ids 4..7 are ah/ch/dh/bh, the high byte of eax..ebx.
        return (self.regs[reg - 4] >> 8) & 0xFF if reg >= 4 else self.regs[reg] & 0xFF

    def _set(self, reg: int, size: int, value: int) -> None:
        if size == 4:
            self.regs[reg] = value & 0xFFFFFFFF
        elif size == 2:
            self.regs[reg] = (self.regs[reg] & 0xFFFF0000) | (value & 0xFFFF)
        elif reg >= 4:
            self.regs[reg - 4] = (self.regs[reg - 4] & 0xFFFF00FF) | ((value & 0xFF) << 8)
        else:
            self.regs[reg] = (self.regs[reg] & 0xFFFFFF00) | (value & 0xFF)

    def run(self, start_va: int) -> None:
        va = start_va
        while True:
            self.instructions += 1
            size = 4
            op = self.image.byte(va)
            if op == 0x66:  # operand-size prefix
                size = 2
                va += 1
                op = self.image.byte(va)

            if op == 0xA1:  # mov eax/ax, [imm32]
                self._set(0, size, self._load(self._load(va + 1, 4), size))
                va += 5
            elif op == 0xA3:  # mov [imm32], eax/ax
                self._store(self._load(va + 1, 4), size, self._get(0, size))
                va += 5
            elif op == 0xA0:  # mov al, [imm32]
                self._set(0, 1, self._load(self._load(va + 1, 4), 1))
                va += 5
            elif op == 0xA2:  # mov [imm32], al
                self._store(self._load(va + 1, 4), 1, self._get(0, 1))
                va += 5
            elif op == 0xC7 and self.image.byte(va + 1) == 0x05:  # mov [imm32], imm
                self._store(self._load(va + 2, 4), size, self._load(va + 6, size))
                va += 6 + size
            elif op == 0xC6 and self.image.byte(va + 1) == 0x05:  # mov byte [imm32], imm8
                self._store(self._load(va + 2, 4), 1, self._load(va + 6, 1))
                va += 7
            elif op in (0x88, 0x89, 0x8A, 0x8B) and self.image.byte(va + 1) & 0xC7 == 0x05:
                reg = (self.image.byte(va + 1) >> 3) & 7
                addr = self._load(va + 2, 4)
                width = size if op in (0x89, 0x8B) else 1
                if op in (0x88, 0x89):  # mov [imm32], reg
                    self._store(addr, width, self._get(reg, width))
                else:  # mov reg, [imm32]
                    self._set(reg, width, self._load(addr, width))
                    self.loads += 1
                va += 6
            elif 0xB8 <= op <= 0xBF:  # mov reg, imm
                self._set(op - 0xB8, size, self._load(va + 1, size))
                va += 1 + size
            elif 0xB0 <= op <= 0xB7:  # mov reg8, imm8
                self._set(op - 0xB0, 1, self.image.byte(va + 1))
                va += 2
            elif op in (0x31, 0x33) and self.image.byte(va + 1) & 0xC0 == 0xC0:  # xor reg, reg
                modrm = self.image.byte(va + 1)
                if (modrm >> 3) & 7 != modrm & 7:
                    raise SystemExit(f"Unexpected xor of two different registers at {va:#x}")
                self._set(modrm & 7, size, 0)
                va += 2
            elif 0x50 <= op <= 0x5F or op == 0x90:  # push/pop/nop: no effect on the table
                va += 1
            elif op == 0xC3:  # ret
                return
            else:
                raise SystemExit(
                    f"{self.image.path.name}: unexpected opcode {op:#04x} at {va:#x}; "
                    "the initializer is not the straight-line form this tool can replay."
                )


def trace_records(image: Image) -> tuple:
    interpreter = Interpreter(image)
    interpreter.run(INITIALIZER_START)

    table_end = TABLE_VA + ACTION_COUNT * RECORD_STRIDE
    outside = [va for va in interpreter.memory if not TABLE_VA <= va < table_end]
    if outside:
        raise SystemExit(
            f"{len(outside)} stores landed outside the action table, first at {min(outside):#x}"
        )
    records = [
        bytes(interpreter.memory.get(TABLE_VA + index * RECORD_STRIDE + k, 0) for k in range(RECORD_STRIDE))
        for index in range(ACTION_COUNT)
    ]
    return records, interpreter


def decode(image: Image, index: int, raw: bytes, icons: list, states: list) -> dict:
    u8 = lambda offset: raw[offset]
    u16 = lambda offset: struct.unpack_from("<H", raw, offset)[0]
    u32 = lambda offset: struct.unpack_from("<I", raw, offset)[0]
    ids = lambda offset: [value for value in struct.unpack_from("<4I", raw, offset) if value]

    icon = u8(0x04)
    result_state = u16(0x40)
    sound = image.cstring(u32(0x44)) if u32(0x44) else ""
    required = [value for value in (u8(0x1B), u8(0x1C)) if 0 < value < REQUIRED_ITEM_LIMIT]

    return {
        "id": index,
        "name": image.cstring(u32(0x00)),
        "icon": icon,
        "icon_sprite": icons[icon] if icon < len(icons) else None,
        "score": u32(0x08),
        "duration_tenths": u32(0x0C),
        "player_animation": u8(0x18),
        "grants_item": u8(0x19),
        "removes_item": bool(u8(0x1A)),
        "requires_items": required,
        "unlocks": ids(0x20),
        "disables": ids(0x30),
        "result_state": result_state,
        "result_state_name": states[result_state] if result_state < len(states) else None,
        "state_at_start": bool(u8(0x42)),
        "sound": sound,
        "sound_at_start": bool(u8(0x48)),
        # Written by the initializer but read by nothing: sub_4103E0's only caller,
        # sub_41B240, never touches these offsets.
        "unknown_0x10": u32(0x10),
        "unknown_0x14": u32(0x14),
    }


def build(root: Path) -> dict:
    image = Image(root / EXE_REL)
    records, interpreter = trace_records(image)

    icons = [image.cstring(va) for va in image.pointers(ICON_TABLE_VA, ICON_COUNT)]
    states = [image.cstring(va) for va in image.pointers(ITEM_STATE_TABLE_VA, ITEM_STATE_COUNT)]
    bubbles = [image.cstring(va) for va in image.pointers(BUBBLE_TABLE_VA, BUBBLE_COUNT)]

    return {
        "generated_by": "tools/export_action_table.py",
        "source": {
            "file": EXE_REL.name,
            "size": EXE_SIZE,
            "sha256": EXE_SHA256,
            "initializer": f"{INITIALIZER_START:#x}",
            "table": f"{TABLE_VA:#x}",
            "stride": RECORD_STRIDE,
            "instructions_replayed": interpreter.instructions,
            "stores_replayed": interpreter.stores,
        },
        "icons": icons,
        "item_states": states,
        "bubbles": bubbles,
        "actions": [decode(image, index, raw, icons, states) for index, raw in enumerate(records)],
    }


def object_action_ids(root: Path) -> dict:
    """Read each object definition's eight action ids from CO_OBJECTS.DAT (+528)."""
    data = (root / OBJECT_DB_REL).read_bytes()
    result = {}
    cursor = data.find(b"ITEM\0")
    index = 0
    while cursor > 0:
        name_length, payload_length = struct.unpack_from("<HI", data, cursor - 6)
        payload = data[cursor + name_length : cursor + name_length + payload_length]
        if payload_length == 544:
            kind, = struct.unpack_from("<I", payload, 0)
            result[(kind >> 4) & 0xFFF] = {
                "record": index,
                "name": payload[8:264].split(b"\0")[0].decode("latin-1"),
                "sprite": payload[264:520].split(b"\0")[0].decode("latin-1"),
                "action_ids": [value for value in payload[528:536] if value],
            }
            index += 1
        cursor = data.find(b"ITEM\0", cursor + 1)
    return result


def check(root: Path, table: dict) -> int:
    failures = []
    output = root / OUTPUT_REL
    if not output.is_file():
        failures.append(f"{OUTPUT_REL} is missing")
    elif json.loads(output.read_text()) != table:
        failures.append(f"{OUTPUT_REL} is stale")

    actions = {action["id"]: action for action in table["actions"]}
    if actions[0]["name"] != "Nullnummer":
        failures.append("action 0 is not the Nullnummer placeholder")
    if actions[1]["name"] != "Zrestrukturyzuj pliki":
        failures.append("action 1 is not Zrestrukturyzuj pliki")

    acticons = {
        path.name.lower(): path.name
        for path in (root / ACTICON_DIR_REL).iterdir()
        if path.is_dir() and path.name.startswith("CO_GUI_ACTICON_")
    }
    for index, name in enumerate(table["icons"]):
        if name and name.lower() not in acticons:
            failures.append(f"icon {index} {name} has no sprite folder")

    sounds = {path.stem.upper() for path in (root / SOUND_DIR_REL).iterdir()}
    used = set()
    for definition in object_action_ids(root).values():
        used.update(definition["action_ids"])
    for action_id in sorted(used):
        action = actions[action_id]
        if action["score"] <= 0:
            failures.append(f"action {action_id} {action['name']!r} has no score")
        if action["icon"] > ICON_COUNT - 1:
            failures.append(f"action {action_id} icon {action['icon']} is out of range")
        if action["sound"] and action["sound"].upper() not in sounds:
            failures.append(f"action {action_id} sound {action['sound']} has no wav")

    if failures:
        print("Action table check failed:\n" + "\n".join(f"  {line}" for line in failures))
        return 1
    print(
        f"Verified {len(table['actions'])} action records "
        f"({len(used)} used by CO_OBJECTS.DAT), {len(table['icons'])} icons, "
        f"{len(table['item_states'])} item states."
    )
    return 0


def report(root: Path, table: dict, level: int) -> int:
    """Summarise, per prerequisite class, what a level's placed objects are worth."""
    manifest_path = root / f"resources/levels/level_{level}.json"
    manifest = json.loads(manifest_path.read_text())
    definitions = object_action_ids(root)
    actions = {action["id"]: action for action in table["actions"]}

    placed = []
    for item in manifest["objects"]:
        item_type = (int(item["kind"], 16) >> 4) & 0xFFF
        definition = definitions.get(item_type)
        if not definition:
            continue
        for action_id in definition["action_ids"]:
            placed.append((item["node_name"], definition["name"], actions[action_id]))

    unlocked_later = {
        unlocked for _, _, action in placed for unlocked in action["unlocks"]
    }

    classes = {
        "free": [],
        "pickup": [],
        "needs item": [],
        "locked until another action": [],
    }
    for node, item_name, action in placed:
        if action["id"] in unlocked_later:
            key = "locked until another action"
        elif action["requires_items"]:
            key = "needs item"
        elif action["grants_item"]:
            key = "pickup"
        else:
            key = "free"
        classes[key].append((node, item_name, action))

    target = manifest.get("conditions", {}).get("base", {}).get("score_target")
    print(f"level {level}: {len(placed)} placed action rows on {len(manifest['objects'])} objects")
    for key, rows in classes.items():
        total = sum(action["score"] for _, _, action in rows)
        best_per_object = {}
        for node, _, action in rows:
            best_per_object[node] = max(best_per_object.get(node, 0), action["score"])
        print(f"  {key:28} {len(rows):3} rows  {total:6} pts  ({sum(best_per_object.values())} if one per object)")
    if target:
        print(f"  score target from CONDITION: {target}")

    free_and_pickup = classes["free"] + classes["pickup"]
    print("\n  free + pickup rows, highest first:")
    for node, item_name, action in sorted(free_and_pickup, key=lambda row: -row[2]["score"])[:20]:
        needs = f" grants item {action['grants_item']}" if action["grants_item"] else ""
        print(
            f"    {action['score']:5}  {action['name'][:44]:44} "
            f"{item_name[:22]:22} -> {action['result_state_name']}{needs}"
        )
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--check", action="store_true", help="Verify the exported table without writing")
    parser.add_argument("--report", action="store_true", help="Print a level's prank scope by prerequisite class")
    parser.add_argument("--level", type=int, default=1, help="Level number for --report")
    args = parser.parse_args()

    root = args.root.resolve()
    table = build(root)

    if args.report:
        return report(root, table, args.level)
    if args.check:
        return check(root, table)

    output = root / OUTPUT_REL
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(table, ensure_ascii=False, indent=2, sort_keys=True) + "\n")
    print(f"Wrote {len(table['actions'])} action records to {OUTPUT_REL}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
