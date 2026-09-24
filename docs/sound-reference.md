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

## The two volumes

Verified on 2026-09-22. The two fields are, in this order:

| field | registry value | default | applied by | what it sets |
|---|---|---:|---|---|
| `game+20690` | `SOUNDVOLUME` | **75** | `sub_42A8D0(v / 100)` | `handler+3892`, the effects volume every new sound plays at |
| `game+20692` | `MUSICVOLUME` | **65** | `sub_42A860(v / 100)` | `handler+3888`, and the playing music stream through `sub_45E490` |

So **effects default to 75 and music to 65**. Earlier notes, and the port's store, had the
two the other way round. `sub_4261A0` reads both at start-up. `sub_4262B0` writes them, each
stored as **value + 1**, so that a missing value (read back as 0) falls back to the
default. `sub_405430` applies both before the first screen, and case 2 applies the music one
again right after it starts `Menu1`. A music change reaches the playing track at once. An
effects change only affects sounds started after it.

## The sound setup screen, 11

`CSoundSetup`. `sub_407370`'s case 11 calls `sub_407A90`, which builds it with `sub_425050`
and fills the two value boxes from the handler's live volumes (`sub_42A940` effects,
`sub_42A930` music, each × 100). It starts no track, so `Menu1` keeps playing. The background
is `CO_GUI_SCREENS_MENU_BACKGROUND`, the main menu's own picture. The title is slot 221, drawn
the way every menu screen draws its title (see [shell-reference.md](shell-reference.md)).

Every rect comes from the table at `0x4710F8` (German `0x473550`, identical). Effects are
on the left and music on the right:

| id | element | art | x | y | w | h |
|---:|---|---|---:|---:|---:|---:|
| — | title | slot 221 `Konfiguracja dźwięku i muzyki` | 64 | 16 | 672 | 64 |
| — | effects symbol | `CO_GUI_MENU_SOUND_SOUND_SYMBOL` | 32 | 128 | 336 | 208 |
| — | music symbol | `CO_GUI_MENU_SOUND_MUSIK_SYMBOL` | 432 | 128 | 336 | 208 |
| 1 | effects − 5 | `CO_GUI_MENU_BASE_LARROW_{ACTIVE,PASSIVE}` | 32 | 368 | 64 | 48 |
| — | effects value | `CO_GUI_MENU_BASE_TEXTINPUT_VOLUME` | 112 | 368 | 176 | 48 |
| 2 | effects + 5 | `CO_GUI_MENU_BASE_RARROW_{ACTIVE,PASSIVE}` | 305 | 368 | 64 | 48 |
| 3 | music − 5 | `…_LARROW_*` | 432 | 368 | 64 | 48 |
| — | music value | `…_TEXTINPUT_VOLUME` | 512 | 368 | 176 | 48 |
| 4 | music + 5 | `…_RARROW_*` | 705 | 368 | 64 | 48 |
| 6 | slot 223 `Główne menu` | `CO_GUI_MENU_BASE_BUTTON_*` | 16 | 536 | 160 | 48 |
| 5 | slot 222 `Domyślne` | `CO_GUI_MENU_BASE_BUTTON_*` | 624 | 536 | 160 | 48 |

The right arrows' x is 305 and 705 as stored, one pixel off symmetry. `305 = 32 + 273` and
`705 = 432 + 273`, so the two rows do match each other.

**The value boxes are display only.** They are the same `CGUIInput` class as the name boxes
on screen 13, with the caret turned off (`+420 = 0`). The handler never reads their text back,
and `sub_425A10` rewrites both as `"%d"`, a bare number with no percent sign, after every
change. The text is the menu's Arial 32 (`+1168`): white, a `(32, 32, 32)` copy two pixels
right and down behind it, centred both ways in the box.

`sub_403F20` case 11 handles the buttons:

| id | effect |
|---:|---|
| 1 / 2 | effects −5 / +5 |
| 3 / 4 | music −5 / +5 |
| 5 | effects = 75, music = 65 |
| 6 | screen 3 |

Every id except 6 then clamps both to 0–100, applies both (`sub_42A8D0`, `sub_42A860`),
refreshes both boxes and writes both registry values. The switch at `0x4088E2` sends a frame
with **no** button press to the same `default:` branch, because `0 − 1` compares above 5
unsigned. So while the screen is open, all four steps run every frame. That is harmless,
because nothing changes between presses. The port writes on change, which reaches the same
state.

## In the port

`tools/export_sounds.py --check` copies the 94 shipped effects and all five music tracks
into `audio/`, writing `resources/original/sounds.json` beside them. The menu music and the
footsteps sit on the Music and SFX buses along with everything else.

### The two volumes

`autoloads/settings_store.gd` keeps the two volumes and the step-5, clamp-0–100 rule in
`user://settings.cfg` rather than the registry, and applies them to the two buses as
`linear_to_db(value / 100)`. `default_bus_layout.tres` carries the defaults in decibels,
which is what plays for the instant before the store is ready. From then on the store is
the source of truth.

**It currently has the defaults backwards**: music 75 and effects 65, in the store's
constants, in the bus layout (Music −2.5 dB, SFX −3.7 dB) and in
`tests/check_settings_store.gd`. The original's are effects 75 and music 65 (above). Task T6
swaps them.

**One port decision.** `linear_to_db(0)` is negative infinity, so a volume of 0 mutes its
bus instead of being handed to it. The original's own mixer is not recovered; silence at
the bottom of a slider the screen lets you take all the way down is this port's reading.

The store also holds the language the player picked and whether the window is full screen.
Neither is the original's: it ships one language per build and has no display option. So
the sound-setup screen's `Domyślne` puts only the two volumes back, and deliberately leaves
those two rows alone.
`scenes/level/level_audio.gd` picks the theme, starts the warning loop, plays the win cue and
plays each action's sound at the end the record asks for.
