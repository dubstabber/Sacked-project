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
plays. `loop` goes straight to the buffer's `Play(0, 0, loop != 0)` at vtable offset 48,
so a looping sound is `DSBPLAY_LOOPING` over the whole clip (`sub_45E7E0` → `sub_45EE60` →
`sub_45F9B0`). `quiet` starts that slot at **0.1** of the effects volume; everything else
plays at the full effects volume from `handler+3892`. The last flag is really positional:
`sub_42A970` recomputes the volume of flagged slots from their distance to a listener it is
handed. That listener was not traced, and nothing on the duel or result path sets the flag.
`sub_42A7C0(slot, 0)` stops one again.

The handler is the game object's own, `game+15136`, and it outlives every screen. Only its
shutdown (`sub_42A180` → `sub_42AA40`) stops all its slots. Otherwise a slot stops when its
sound ends or when something stops it by name: the warning slot, and the player's own four
held slots (`player+1108`–`1120`, stopped by the player's destructor `0x41AE90`). So a
one-shot that is still playing when the level ends plays on into the next screen.

## What a level plays

- **Theme.** `sub_406AF0` ends a level's setup with `rand() % 3` over `Theme1`, `Theme2`
  and `Theme3`. The shell has two tracks: `sub_407370` asks for one on four cases only,
  `Menu1` on the loading and menu screens and `Menu2` on the coworker-names and highscore
  screens. Every other screen keeps whatever is already playing, which is why the level
  tree, the description screen and character select ask for no music. After the menu they
  run under `Menu1`. After a win they run under the level's theme, because `Następny poziom`
  goes straight to the tree (screen 15) and nothing stops the theme on the way. The port
  mirrors the requests with a per-screen stream map in `ScreenManager`; the names screen is
  not built yet, so `Menu2` is reached only from the highscore board. See
  docs/shell-reference.md.
- **Warning.** `sub_403780` starts `S1012` looping once `limit - elapsed <= 10`, keeping the
  slot in `game+19056` so it is only started once.
- **Win and loss.** `sub_407370` case 7 stops the warning slot (`sub_42A7C0` at `0x4075E3`,
  then `game+19056 = -1`). It then plays `S1100` through the handler at `0x407601`, before
  `sub_406E70` records the win and builds the win screen. Case 8 stops the same slot at
  `0x407639` and plays nothing. Neither case stops another effect or the music.
  `sub_42AC30`'s only caller is case 5. `sub_42AA60` changes the track only in cases 2, 3,
  13 and 14 and in `sub_406AF0`, and it ignores a request for the track already playing
  (`0x42AA7A`). So the theme plays on under both result screens.
- **Actions.** Each action record names its sound at `+0x44` and says at `+0x48` whether it
  plays when the action starts or when it applies. All 32 sounds level 1's actions name
  resolve to a shipped file.
- **Pause and the quit prompt.** Both only set `game+12740` bit `0x20` (the quit prompt at
  `0x4075AF`), and no sound code reads it: `sub_402590` runs the channel update `sub_42A970`
  at `0x4025AB`, before its own pause test at `0x4025B0`, and the music streams on its own
  thread (`sub_42AA60` → `sub_45E420` → `sub_45F450`, `_beginthreadex`). So the theme, the
  warning loop and any effect still sounding play on behind either one.
- **The duel.** `sub_407370` case 5 pauses only the music stream (`sub_42AC30` at
  `0x407571` → `sub_45F4F0`, the buffer's `Stop`). It touches no effect slot, so a warning
  that has started loops on through the duel. `sub_4027B0` calls `sub_42A970(0)` only to reap
  finished slots, and it resumes the music (`sub_42AC40` → `sub_45F530`) after either outcome:
  at `0x402839` when the duel is won and at `0x40284D` when it is lost. The duel's own sounds
  are in [minigame-reference.md](minigame-reference.md).

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

### What a level plays

`scenes/level/level_audio.gd` picks the theme, starts the warning loop and plays each action's
sound at the end the record asks for. Every one-shot goes through `ScreenManager.play_effect`,
the port's copy of the game's handler. Its players are children of the autoload, which
always processes, so a sound plays on under a pause and over a scene change, as the lost
duel's `S1001` does into the lose screen. Each player frees itself when its sound ends.
`LevelAudio` plays a one-shot itself only when there is no `ScreenManager` autoload. The
warning loop stays in `LevelAudio`, which stops it when the level ends, as cases 7 and 8 do.
The imported clips carry no loop points, and Godot never starts a forward loop that ends at
sample 0, so `LevelAudio` loops the whole clip itself. Until it did, the warning was never
heard. `LevelAudio`'s own players also run with the tree paused, so the pause key and the
quit prompt leave them playing. Only its `_process`, which starts the warning, stops with
the level. `ScreenManager.report_level_finished` plays `S1100` on a win before it changes
screen. `CatchWatch` holds the theme for the duel and lets it go on a win; the warning keeps
looping.

**One port decision.** `LevelAudio` stops the theme when the level ends, and the tree then
starts `Menu1`. The original stops nothing there. Its theme plays on under the result screen
and, after a win, under the tree and the description screen until a screen asks for another
track.
