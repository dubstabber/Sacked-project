#!/usr/bin/env python3
"""Copy the original's sound effects and music into the project.

SOUND\\SOUNDS.TXT is the index: sub_42A2D0 reads each line as "%d %s", keeping the number
as the entry's already-loaded flag and building the path as SOUND\\FX\\<name>.wav. An entry
whose flag is 1 is never handed to the loader, so those play straight from the file; Godot
decides that per import, so the flag is carried in the manifest and otherwise unused.

Twenty-two listed ids ship no file at all. They are listed below rather than silently
skipped, so a name that stops resolving is a failure instead of a shrug.
"""

import argparse
import json
import shutil
from pathlib import Path


SOUNDS_INDEX_REL = Path("extract-sacked-assets/sacked/Sound/sounds.txt")
FX_SOURCE_REL = Path("extract-sacked-assets/extracted/sounds/FX")
MUSIC_SOURCE_REL = Path("extract-sacked-assets/extracted/sounds/Musik")
FX_DEST_REL = Path("audio/sfx")
MUSIC_DEST_REL = Path("audio/music")
MANIFEST_REL = Path("resources/original/sounds.json")

# Named by the index but absent from the shipped FX folder.
MISSING_FROM_DISK = {
    "S0005", "S0007", "S0008", "S0009", "S0011", "S0018", "S0019", "S0021", "S0022",
    "S0026", "S0027", "S0028", "S0031", "S0032", "S0036", "S0039", "S0043", "S0045",
    "S0053", "S0603", "S0604", "S0605",
}
# sub_406AF0 picks one of these at random when a level starts; Menu1 is the shell's.
MUSIC = ["Menu1", "Menu2", "Theme1", "Theme2", "Theme3"]


def read_index(root: Path) -> list:
    entries = []
    for line in (root / SOUNDS_INDEX_REL).read_text().splitlines():
        parts = line.split()
        if len(parts) != 2:
            raise ValueError(f"sounds.txt line is not '<flag> <name>': {line!r}")
        entries.append({"id": parts[1], "preloaded": parts[0] != "0"})
    return entries


def source_for(folder: Path, stem: str, suffix: str):
    for candidate in (folder / f"{stem}{suffix}", folder / f"{stem}{suffix.upper()}"):
        if candidate.is_file():
            return candidate
    return None


def export(root: Path, check: bool) -> int:
    entries = read_index(root)
    failures = []
    copied = 0

    absent = {entry["id"] for entry in entries if source_for(root / FX_SOURCE_REL, entry["id"], ".wav") is None}
    if absent != MISSING_FROM_DISK:
        for name in sorted(absent - MISSING_FROM_DISK):
            failures.append(f"{name} is indexed but its file has gone missing")
        for name in sorted(MISSING_FROM_DISK - absent):
            failures.append(f"{name} is listed as absent but now ships a file")

    for entry in entries:
        source = source_for(root / FX_SOURCE_REL, entry["id"], ".wav")
        if source is None:
            entry["stream"] = ""
            continue
        destination = root / FX_DEST_REL / f"{entry['id'].lower()}.wav"
        entry["stream"] = f"res://{destination.relative_to(root).as_posix()}"
        copied += 1
        if check:
            if not destination.is_file() or destination.read_bytes() != source.read_bytes():
                failures.append(str(destination.relative_to(root)))
        else:
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source, destination)

    music = {}
    for name in MUSIC:
        source = source_for(root / MUSIC_SOURCE_REL, name, ".ogg")
        if source is None:
            failures.append(f"{name}.ogg is missing")
            continue
        destination = root / MUSIC_DEST_REL / f"{name.lower()}.ogg"
        music[name] = f"res://{destination.relative_to(root).as_posix()}"
        copied += 1
        if check:
            if not destination.is_file() or destination.read_bytes() != source.read_bytes():
                failures.append(str(destination.relative_to(root)))
        else:
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source, destination)

    manifest = {
        "generated_by": "tools/export_sounds.py",
        "source": str(SOUNDS_INDEX_REL),
        "effects": entries,
        "music": music,
        "missing_from_disk": sorted(MISSING_FROM_DISK),
    }
    text = json.dumps(manifest, indent=2, sort_keys=True) + "\n"
    path = root / MANIFEST_REL
    if check:
        if not path.is_file() or path.read_text() != text:
            failures.append(f"{path.relative_to(root)} is stale")
    else:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)

    if failures:
        print("Sounds out of date:\n" + "\n".join(f"  {line}" for line in failures[:20]))
        return 1
    print(
        f"{'Verified' if check else 'Exported'} {copied} files for {len(entries)} indexed effects "
        f"and {len(music)} music tracks; {len(MISSING_FROM_DISK)} indexed effects ship no file."
    )
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--check", action="store_true", help="Verify the copied sounds without writing")
    args = parser.parse_args()
    return export(args.root.resolve(), args.check)


if __name__ == "__main__":
    raise SystemExit(main())
