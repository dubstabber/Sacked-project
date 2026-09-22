# Original sound handling

Verified on 2026-09-21 against a disposable copy of `sacked.exe.i64` and the shipped
`sacked.exe` (479232 bytes, SHA-256 `6404096c…`). Addresses are virtual addresses in that
build, where RVA equals file offset.

## The index

`sub_406AB0` points the sound handler at `SOUND\FX`, `SOUND\MUSIK` and `SOUND\SOUNDS.TXT`,
then `sub_42A2D0` reads the index. Each line is `sscanf(line, "%d %s", &flag, name)` and
becomes a three-field entry:

| Field | Value |
| --- | --- |
| `+0` | `flag != 0` — the entry's **already-loaded** flag |
| `+4` | the name, e.g. `S0067` |
| `+8` | `SOUND\FX\<name>.wav` |

`sub_42A6A0` hands `+8` to the loader only when `+0` is still zero, so an entry that starts
flagged is never preloaded and plays straight from its path. Twelve of the 116 entries are
flagged — `S1000`, `S0600`–`S0605`, `S1012`–`S1015`, `S1100` — all of them long cues. Godot
decides streaming at import time, so the port carries the flag in the manifest and
otherwise leaves it alone.

**Twenty-two indexed names ship no file at all**: `S0005 S0007 S0008 S0009 S0011 S0018
S0019 S0021 S0022 S0026 S0027 S0028 S0031 S0032 S0036 S0039 S0043 S0045 S0053 S0603 S0604
S0605`. `tools/export_sounds.py` lists them so a name that stops resolving fails instead of
being skipped quietly. None of them is named by an action record.

## Playing one

`sub_42A6A0(handler, name, loop, quiet)` takes a free slot out of 128
(`slot >= 0 && slot < 128`), matches the name case-insensitively, loads on first use, and
plays. `loop` goes straight to the player. `quiet` scales the effects volume by **0.1** for
that slot; everything else plays at the full effects volume from `handler+3892`.
`sub_42A7C0(slot, 0)` stops one again.

## What a level plays

- **Theme.** `sub_406AF0` ends a level's setup with `rand() % 3` over `Theme1`, `Theme2`
  and `Theme3`. The shell has two tracks: `sub_407370` asks for one on four cases only,
  `Menu1` on the loading and menu screens and `Menu2` on the coworker-names and highscore
  screens. Every other screen keeps whatever is already playing, which is why the level
  tree, the description screen and character select are silent about music and still run
  under `Menu1` — every route to them passes through the menu. The port mirrors this with a
  per-screen stream map in `ScreenManager`; the names screen is not built yet, so `Menu2` is
  reached only from the highscore board. See docs/shell-reference.md.
- **Warning.** `sub_403780` starts `S1012` looping once `limit - elapsed <= 10`, keeping the
  slot in `game+19056` so it is only started once.
- **Win.** Screen 7 plays `S1100`.
- **Actions.** Each action record names its sound at `+0x44` and says at `+0x48` whether it
  plays when the action starts or when it applies. All 32 sounds level 1's actions name
  resolve to a shipped file.

## In the port

`tools/export_sounds.py --check` copies the 94 shipped effects and all five music tracks
into `audio/`, writing `resources/original/sounds.json` beside them. The menu music and the
footsteps sit on the Music and SFX buses along with everything else.

### The two volumes

`sub_4261A0` restores the original's music and effects volumes from the registry
(`game+20690`, `game+20692`), and its sound-setup screen moves each by 5 and clamps it to
0..100, starting from 75 and 65. `autoloads/settings_store.gd` keeps those numbers and that
rule, in `user://settings.cfg` rather than the registry, and applies them to the two buses
as `linear_to_db(value / 100)`. `default_bus_layout.tres` still carries 75 and 65 in
decibels, which is what plays for the instant before the store is ready; from then on the
store is the source of truth.

**One port decision.** `linear_to_db(0)` is negative infinity, so a volume of 0 mutes its
bus instead of being handed to it. The original's own mixer is not recovered; silence at
the bottom of a slider the screen lets you take all the way down is this port's reading.

The store also holds the language the player picked and whether the window is full screen.
Neither is the original's: it ships one language per build and has no display option. So
the sound-setup screen's `Domyślne` puts only the two volumes back, and deliberately leaves
those two rows alone.
`scenes/level/level_audio.gd` picks the theme, starts the warning loop, plays the win cue and
plays each action's sound at the end the record asks for.
