"""The sacked.exe build every executable reader in tools/ is pinned to, and how they read it.

The addresses the exporters read only mean something in this one image, so reading refuses
any other file. The image's sections sit at their file offsets (RVA == file offset), so a
virtual address is read at va - IMAGE_BASE.
"""

import hashlib
import struct
from pathlib import Path


EXE_REL = Path("extract-sacked-assets/sacked/sacked.exe")
EXE_SIZE = 479232
EXE_SHA256 = "6404096cc74e1c954daa2033a7d7d7826429a27deaa679f1ff7103027f614a86"
IMAGE_BASE = 0x400000


def repo_root() -> Path:
    return Path(__file__).resolve().parents[1]


def f32(value: float) -> float:
    """The double a value widens to once stored as a float32, which is what the x87 reads."""
    return struct.unpack("<f", struct.pack("<f", value))[0]


def read_exe(root: Path) -> bytes:
    path = root / EXE_REL
    data = path.read_bytes()
    digest = hashlib.sha256(data).hexdigest()
    if len(data) != EXE_SIZE or digest != EXE_SHA256:
        raise SystemExit(
            f"{path} is not the build these addresses were recovered from "
            f"(size {len(data)}, sha256 {digest}); expected size {EXE_SIZE}, sha256 {EXE_SHA256}."
        )
    return data


def at(data: bytes, va: int, fmt: str):
    """One little-endian value of struct format `fmt` at virtual address `va`."""
    return struct.unpack_from("<" + fmt, data, va - IMAGE_BASE)[0]


def bytes_at(data: bytes, va: int, count: int) -> bytes:
    return data[va - IMAGE_BASE : va - IMAGE_BASE + count]


# The x87 instructions that read a constant from an absolute address: the opcode and ModR/M
# bytes, then the address as a 32-bit operand.
FLD = bytes([0xD9, 0x05])  # fld dword ptr [addr]
FADD = bytes([0xD8, 0x05])  # fadd dword ptr [addr]
FMUL = bytes([0xD8, 0x0D])  # fmul dword ptr [addr]
FCOM = bytes([0xD8, 0x15])  # fcom dword ptr [addr]
FCOMP = bytes([0xD8, 0x1D])  # fcomp dword ptr [addr]
FSUB = bytes([0xD8, 0x25])  # fsub dword ptr [addr]
FSUBR = bytes([0xD8, 0x2D])  # fsubr dword ptr [addr]
FMUL_QWORD = bytes([0xDC, 0x0D])  # fmul qword ptr [addr]
FILD = bytes([0xDB, 0x05])  # fild dword ptr [addr]


def pin_readers(data: bytes, name: str, va: int, readers, failures: list) -> None:
    """Check that each (instruction, opcode) in `readers` is that instruction reading `name` at
    `va`, and add a line to `failures` for each one that is not."""
    for instruction, opcode in readers:
        if bytes_at(data, instruction, len(opcode)) != opcode:
            failures.append(f"0x{instruction:X} is not {opcode.hex(' ')}, the read of {name}")
        elif at(data, instruction + len(opcode), "I") != va:
            failures.append(f"the instruction at 0x{instruction:X} does not read {name} at 0x{va:X}")
