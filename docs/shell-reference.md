# The shell: level tree, description, results, highscores

Everything the original does between levels. Recovered from `sacked.exe`; the compilation
unit is `D:\Projects\CrazyOffice\crazyoffice.cpp` and the GUI classes carry their own RTTI
names (`CLevelTree`, `CLevelDesc`, `CWinScreen`, `CLooseScreen`, `CHighscore`), which this
document uses.

Screen ids and the transition function `sub_407370` are in
[game-rules-reference.md](game-rules-reference.md); the strings are generated per
[strings-reference.md](strings-reference.md).

## Where progress lives

Two stores, and neither is a save file in the usual sense.

**The registry** holds the profile: which levels are open, who you are, and the volumes.
`sub_426260` writes it and `sub_426120` reads it, both under the same four value names:

| value | type | game field | meaning |
|---|---|---|---|
| `GENDER` | dword | `game+20686` | 0 = Jo Bless, 1 = Anne Employed |
| `NAME` | binary | `game+20668` | the typed player name, 16 bytes |
| `STATUS` | dword | `game+20660` | unlock bitmask, **time game** |
| `CHECK` | dword | `game+20664` | unlock bitmask, **points game** |

The read happens once at start-up, from `sub_405430` at `0x4056db`, into exactly those four
fields. A missing `NAME` zeroes 17 bytes rather than failing. Two neighbours are read the
same way: `sub_4261A0` restores music and effects volume (`game+20690`, `game+20692`) and
`sub_426230`/`sub_426310` keep a run counter that is incremented every start.

The masks are written on **every win**, and also whenever the character-select screen
commits a name or a character — `sub_403F20`'s case 12 re-saves the whole profile on
buttons 1, 2 and 5. So the profile is flushed eagerly, never at exit.

**`HIGHSCORE.DAT`** holds the per-level records, and only those. `sub_408A20` reads it and
`sub_408AC0` writes it, both moving **1092 bytes** into `game+19196`.

### The record

`sub_401000`'s tail initialises the table, which pins every field:

| offset | type | initial | meaning |
|---:|---|---|---|
| `+0` | f32 | `1.0` … `28.0` | the level number, 1-based |
| `+4` | char[20] | `"---"` | name that holds the best **score** |
| `+24` | f32 | `0.0` | best score |
| `+28` | char[20] | `"---"` | name that holds the best **time** |
| `+48` | f32 | `12345.0` | best time in seconds |

52 bytes each. The `12345.0` at `+48` is the "never played" sentinel and the description
screen renders it as `--:--`; a score of `0` renders as `---`.

**The table has 28 records in memory but only 21 on disk.** The initialiser loops 28 times
(records numbered 1.0 to 28.0), while both file calls move 1092 = 21 × 52 bytes. Records 21
to 27 therefore exist, stay at their initial values forever, and never persist. They are the
tail of the tree's seventh column, below.

### What a win writes

`sub_406E70` (`m_Screen_Win`) is the only writer. It sets the unlock bit, saves the profile,
updates at most one record field pair, writes the file, and only then builds the screen:

```c
if (game+20700)  game+20664 |= 1 << game+20656;   // points game
else             game+20660 |= 1 << game+20656;   // time game
sub_426260(gender, name, game+20660, game+20664); // flush the registry

if (mode == 1) {                                  // points game -> best score
    score = level->score;                         // *(game+14676) + 984
    if (score >= (int)record[+24]) { record[+24] = score; strncpy(record+4, name, 16); }
} else {                                          // time game -> best time
    if (game+14708 <= (int)record[+48]) { record[+48] = elapsed; strncpy(record+28, name, 16); }
}
sub_408AC0(game);                                 // flush HIGHSCORE.DAT
```

Three things worth keeping:

- **A loss writes nothing.** `sub_4070A0` (`m_Screen_Loss`) only tears the level down. No
  unlock bit, no record, no file.
- **Each mode writes only its own field.** The points game never touches the best time and
  the time game never touches the best score, but the description screen shows both.
- **Ties overwrite.** `>=` on score and `<=` on time, so an equal result replaces the name.
- `game+14708` is the level's own time counter. That it holds **elapsed** rather than
  remaining seconds is inferred from the `<=`, which would otherwise rank a slow run above a
  fast one; it was not read at its writer.

The name is copied with `strncpy(..., 16)` into a 20-byte field after the field is zeroed,
so it is NUL-terminated in practice but not guaranteed by the copy.

**There is no post-level name prompt.** The name comes straight from `game+20668`, typed once
on the character-select screen, so beating a record never asks who you are. Slot 219
(`Imię do tabeli najlepszych wyników`) is that screen's own caption rather than a prompt
raised here: the original draws it over two lines to the left of the name box, which a
reference screenshot of screen 12 settles.

## The level tree, screen 15

`CLevelTree`, background `CO_GUI_SCREENS_LEVELTREE`, title rect `(16, 16, 512, 48)` holding
slot 190. `sub_407CB0` builds it with **one argument**: the unlock mask for the current mode
(`game+20664` for the points game, `game+20660` for the time game). Nothing else reaches it,
so the mask alone decides every button.

### The shape

Two parallel byte tables describe a triangle. `byte_470BB4[i]` is the column `c` (1-based)
and `byte_470BD0[i]` the row `r` within it, for 28 entries:

```
column   1  2   3    4     5      6       7
entries  1  2   3    4     5      6       7      = 28
levels   1  2-3 4-6  7-10  11-15  16-21   (none)
```

Columns 1 to 6 hold exactly 21 entries, which is every level. **Column 7 has no levels** —
it is the tail that also explains the 28-record table and the unreachable fourth highscore
page.

### The unlock predicate

`sub_421F80(states, mask)` derives one state per entry, and it is the whole rule:

```c
memset(states, 0, 21 * 4);                  // note: 21, while the loop writes up to 28
for (i = 0; i < 28; i++)
    if (mask >> i & 1) {
        states[i] = 2;                      // cleared
        if (byte_470BB4[i] < 7) {           // columns 1..6 have children
            states[i + byte_470BB4[i]]     = 1;
            states[i + byte_470BB4[i] + 1] = 1;
        }
    }
if (!states[0]) states[0] = 1;              // level 1 is always at least playable
```

So **clearing entry `i` in column `c` opens `i + c` and `i + c + 1`** — the two entries
directly beneath it in the next column, standard triangle indexing. A cleared level always
ends up in state 2 even when it is also somebody's child, because its own `= 2` runs at a
later iteration than any parent's `= 1`.

The state picks the button art and whether the button is live at all:

| state | art | button id | screenshot |
|---:|---|---:|---|
| 0 | `CO_GUI_MENU_LEVEL_BUTTON_LOCKED_{ACTIVE,PASSIVE}` | **0** — dead | red |
| 1 | `..._PLAYED_{ACTIVE,PASSIVE}` | `i + 1` | yellow |
| 2 | `..._FREE_{ACTIVE,PASSIVE}` | `i + 1` | green |

The art names run counter to the meaning: **`FREE` is a level you have cleared** and
`PLAYED` is one you may play now. The screenshot settles it — green where the mask bit is
set, yellow on the frontier, red beyond.

A locked button is still built and drawn, with id 0. `sub_403F20`'s case 15 acts only on ids
1 to 21 and on 29, so id 0 is inert; there is no separate enabled flag.

### Coordinates

`sub_421F30(i, &x, &y)` reuses the same two tables:

```c
v3 = byte_470BB4[i] - 1;                 // column, 0-based
x  = 16 * (7 * v3) + 40;                 // = 112 * v3 + 40
y  = 40 * (2 * byte_470BD0[i] - v3) + 256;
```

Buttons are 48 × 48, so the node centre is the listed point plus (24, 24). The back button
(id 29, slot 191, `CO_GUI_MENU_BASE_BUTTON_*`) sits at `(16, 536)`.

| level | col | row | x | y | difficulty | clearing it opens |
|---:|---:|---:|---:|---:|---:|---|
| 1 | 1 | 0 | 40 | 256 | 0 | 2, 3 |
| 2 | 2 | 0 | 152 | 216 | 1 | 4, 5 |
| 3 | 2 | 1 | 152 | 296 | 1 | 5, 6 |
| 4 | 3 | 0 | 264 | 176 | 2 | 7, 8 |
| 5 | 3 | 1 | 264 | 256 | 2 | 8, 9 |
| 6 | 3 | 2 | 264 | 336 | 2 | 9, 10 |
| 7 | 4 | 0 | 376 | 136 | 3 | 11, 12 |
| 8 | 4 | 1 | 376 | 216 | 3 | 12, 13 |
| 9 | 4 | 2 | 376 | 296 | 3 | 13, 14 |
| 10 | 4 | 3 | 376 | 376 | 3 | 14, 15 |
| 11 | 5 | 0 | 488 | 96 | 4 | 16, 17 |
| 12 | 5 | 1 | 488 | 176 | 4 | 17, 18 |
| 13 | 5 | 2 | 488 | 256 | 4 | 18, 19 |
| 14 | 5 | 3 | 488 | 336 | 4 | 19, 20 |
| 15 | 5 | 4 | 488 | 416 | 4 | 20, 21 |
| 16 | 6 | 0 | 600 | 56 | 5 | — |
| 17 | 6 | 1 | 600 | 136 | 5 | — |
| 18 | 6 | 2 | 600 | 216 | 5 | — |
| 19 | 6 | 3 | 600 | 296 | 5 | — |
| 20 | 6 | 4 | 600 | 376 | 5 | — |
| 21 | 6 | 5 | 600 | 456 | 5 | — |

Checked against the 800 × 600 tree screenshot (`sacked-reference-images/`, gitignored and
local): every node centre lands on the computed point, and its green/yellow/red pattern is
exactly the predicate's output for levels 1–3 cleared — green on 1, 2, 3 and yellow on
4, 5, 6, which is `{1+1, 1+2} ∪ {2+2, 2+3} ∪ {3+2, 3+3}`.

### Difficulty

`byte_465270[i]`, read in `sub_408D00` into `game+20688`, is the per-level difficulty index
for slots 225–231. It is **the tree column minus one** — `byte_465270[i] == byte_470BB4[i] - 1`
for all 28 entries — so it is derived, not an independent table. Difficulty 6
(`Ekstremalny` / `Mach dein Testament`) belongs to column 7 and **no level ever shows it**.

## Choosing a level: `sub_408D00`

The tree's button handler calls `sub_408D00(game, n - 1)` before switching to screen 16.
Given the 0-based index it:

1. Reads `LEVELS\LEVEL_%02d.TXT` — the index is **0-based**, so level 1 is `LEVEL_00.TXT`,
   matching the `.col` naming. If the file is missing it falls back to the literal
   `"Blah blah\n\n%s\n\nBlah Blah"`.
2. Builds the level path into `p_p_Destination`: `LEVELS\LEVEL_%02dS.col` when
   `game+20700` is set (points game), else `LEVELS\LEVEL_%02d.COL`. This is the global the
   loader reads at screen 1 and again on restart.
3. Caches `record[+24]` into `game+19060` and `record[+48]` into `game+19064`.
4. Sets `game+20688` = difficulty and `game+20656` = the level index.

### What fills the `%s`

`sub_408B60` composes it, and the answer is **the goal sentence**, built from the level's own
`CONDITION` and two text slots:

```c
sub_413360(colpath, &w, &h, &points, &seconds);   // MAPINFO + CONDITION out of the .col
if (mode == 1)  goal = slot160(seconds / 60) + " " + slot161(points);
else            goal = slot158            + " " + slot159(points, seconds / 60);
sprintf(description, txt_contents, goal);
```

`sub_413360` is a plain `.col` reader: `MAPINFO` gives width and height, `CONDITION` gives
points as a float and seconds, which the caller divides by 60 into **minutes**. The four
slots are the ones the pause panel already uses:

| slot | key | Polish |
|---:|---|---|
| 158 | `prompt.time_goal` | `Aby ukończyć ten poziom, musisz zdobyć` |
| 159 | `prompt.time_goal_format` | `%d punktów w ciągu %d minut.` |
| 160 | `prompt.points_goal_format` | `Zdobądź jak najwięcej puntków w ciągu %d minut.` |
| 161 | `prompt.points_target_format` | `Potrzebujesz przynajmniej %d punktów!` |

The result is cached at `game+20652` and owned there; the next call frees it first.

## The description screen, screen 16

`CLevelDesc`, background `CO_GUI_MENU_BASE_BG_06`, caption `-` until `sub_421CD0` replaces
it. Text is drawn in **Arial 24**. Two backdrops and two buttons:

| element | art / slot | x | y | w | h |
|---|---|---:|---:|---:|---:|
| title | set from the record, see below | 0 | 16 | 800 | 64 |
| description panel | `CO_GUI_MENU_LEVEL_BACKDROP_DESC` | 16 | 112 | 480 | 392 |
| info panel | `CO_GUI_MENU_LEVEL_BACKDROP_INFO` | 528 | 112 | 256 | 392 |
| `Wróć` | slot 198 | 16 | 536 | — | — |
| `Kontynuuj` | slot 193 | 624 | 536 | — | — |

`sub_421CD0(screen, difficulty, w, h, description, record)` formats five strings from the
level's **highscore record**, and the format strings here are C literals, **not text-table
slots** — they are the one part of this screen that is not localisable:

| field | source | format |
|---|---|---|
| best time | `record[+48]` | `%02d:%02d` from seconds, or `--:--` when it is `12345.0` |
| best score | `record[+24]` | `%06d`, or `---` when it is 0 |
| size | `w`, `h` | `%d x %d` |
| difficulty | `off_46C088[clamp(difficulty, 0, 6)]` | slots 225–231 |
| title | `off_46C0A4[(int)record[+0]]` | `%s (#%02d)` — slots 232+n and the level number |

The title indexes the slot table by the **record's own level number**, which is why it is
stored as a float in the file at all. `sub_421AC0` then draws them beside their labels:

| rect | align | content |
|---|---:|---|
| `(24, 128, 464, 360)` | 0 | the description text |
| `(536, 128, 240, 32)` | 0 | slot 194 `Najlepszy czas` |
| `(536, 168, 240, 32)` | 1 | best time |
| `(536, 224, 240, 32)` | 0 | slot 195 `Najlepszy wynik` |
| `(536, 264, 240, 32)` | 1 | best score |
| `(536, 320, 240, 32)` | 0 | slot 196 `Rozmiar` |
| `(536, 360, 240, 32)` | 1 | size |
| `(536, 416, 240, 32)` | 0 | slot 197 `Poziom trudności` |
| `(536, 456, 240, 32)` | 1 | difficulty |

Label and value are 40 px apart, pairs 96 px apart; align 0 is left and 1 is right, matching
the screenshot's left-aligned labels over right-aligned values.

Buttons: `Kontynuuj` (id 1) → screen 1, starting the level. `Wróć` (id 2) → screen 15.

**There is no unlock check anywhere on this path.** The tree refuses a locked level by giving
its button id 0; once the description screen is open, `Kontynuuj` always starts the level.

## The result screens, 7 and 8

Both are two buttons at the same two places, on `CO_GUI_MENU_BASE_BUTTON_*`:

| screen | class / background | id 1 at (16, 536) | id 2 at (624, 536) |
|---|---|---|---|
| 7 win | `CWinScreen` / `CO_GUI_SCREENS_WIN` | slot 174 `Główne menu` → screen 3 | slot 175 `Następny poziom` → **screen 15** |
| 8 loss | `CLooseScreen` / `CO_GUI_SCREENS_LOOSE` | slot 176 `Główne menu` → screen 3 | slot 177 `Powtórz` → screen 9 |

Two corrections to earlier assumptions:

- **`Następny poziom` goes to the level tree, not to the next level.** The caption promises a
  next level; the target is screen 15, where the freshly-unlocked nodes have just turned
  yellow. The port must send it to the tree.
- **`Instrukcja` (172) and `Opuść grę` (173) are on no screen at all.** Neither slot has a
  single cross-reference in the image: they are dead strings the build still ships. Of slots
  172–178 the result screens use only 174–177.
- **Neither result screen draws anything of its own.** `CWinScreen` and `CLooseScreen` leave
  the draw vtable slot at the base implementation, where `CHighscore` and `CLevelDesc`
  override it. So each is its background picture plus its two buttons — no score, no time,
  no caption.

The win screen plays sound `S1100` on entry and stops whatever `game+19056` was playing.

### Screen 9, restart

`sub_407320` is the entire case, and it **preserves nothing**:

```c
sub_407140(game);                        // tear the level down
sub_405750(game); sub_4058A0(game); sub_405930(game);
sub_4061C0(p_p_Destination ? &p_p_Destination : "test.col");
sub_406AF0(game);
```

That is the same sequence case 1 runs on a fresh start, over the same `p_p_Destination` path
`sub_408D00` wrote. `sub_407370` then sets the screen id to **1**, not 9. So a restart is a
clean reload of the same file, from zero score and a full clock.

## Highscores, screen 14

`CHighscore`, background `CO_GUI_MENU_BASE_BG_04`, title slot 200 in rect `(16, 16, 592, 64)`.
Built with the table pointer `game+19196`, so it reads all 28 in-memory records.

| id | slot | art | x | y | action |
|---:|---|---|---:|---:|---|
| 1 | 207 `Główne menu` | `MENU_BASE_BUTTON` | 16 | 536 | screen 3 |
| 2 | 202 `Czas` | `MENU_BASE_BUTTON` | 624 | 32 | toggle the column |
| 3 | 203 `1 do 7` | `MENU_HISCORE_BUTTON` | 368 | 536 | page 0 |
| 4 | 204 `8 do 14` | `MENU_HISCORE_BUTTON` | 512 | 536 | page 1 |
| 5 | 205 `15 do 21` | `MENU_HISCORE_BUTTON` | 656 | 536 | page 2 |

**Only three pages are reachable.** `sub_403F20`'s case 14 handles a button 6 that would
select page 3, and slot 206 (`22 do 28` / `22 bis 28`) holds its caption, but `sub_420A20`
never constructs it. Page 3 and the seven records behind it are dead in the shipped build —
consistent with the tree's empty seventh column.

The page index lives at `+1260` (`sub_421110` just stores it) and the column at `+1261`.
`sub_4210C0` flips the column and relabels its own button with the **other** column's name,
slot 201 `Wynik` or slot 202 `Czas`. Initial state is page 0 with `+1261 = 1`, which is the
**score** board; the button therefore starts out offering `Czas`.

### The rows

`sub_4210A0` is the draw override — the base draw, then `sub_421120`, which walks **seven
records** starting at `52 * (7 * page)` and puts four fields on each:

| column | rect on row 0 | content |
|---|---|---|
| number | `(16, 154, 64, 40)` | `(#%d)` from `record[+0]` |
| title | `(88, 154, 400, 40)` | `off_46C0A4[level]`, the slot 232+n title |
| name | `(496, 154, 184, 40)` | `record[+4]` on the score board, `record[+28]` on the time board |
| value | `(688, 154, 96, 40)` | the score or the time, below |

Rows step 46 px: y = 154, 200, 246, 292, 338, 384, 430. Each column's rect is a fixed offset
added to the row's own `(16, y)`; the tables are at `0x470820` (four column rects) and
`0x470880` (seven row rects, stride 16).

**The toggle moves the name column with the value column.** On the score board the row shows
`record[+4]` beside `record[+24]`, formatted `"% 8d"` or `"     ---"` when the score is 0; on
the time board it shows `record[+28]` beside `record[+48]`, formatted `"%02d:%02d"` or
`"--:--"` when it is the 12345 sentinel. So each board names whoever set that board's record,
which is why the two names are separate fields in the first place.

Both value formats are space-padded to right-align in the original's fixed-width GUI font.
The port's font is proportional, so it right-aligns the column instead and drops the padding.

Slot 206 (`22 do 28`) is never built, so the fourth page and its seven records stay dead.

Slots 162–165 (`highscore.best_score_format` and friends) are **not** used here. Their only
reference is `sub_4061C0`, the level loader, so they belong to the loading screen, which
shows the level's records while it loads.

## Music

`sub_407370` starts a track only on four cases: `Menu1` on screens 2 and 3, `Menu2` on
screens **13 and 14** only. The tree, the description screen and character select start
nothing and simply keep whatever is playing, which is `Menu1` because every route to them
passes through the main menu.

## What the port builds on this

`tools/export_level_index.py` reads the two tree tables and both `.col` files per level into
`resources/levels/index.json`, so the lattice, the unlock edges, the difficulty and each
level's size and condition are generated rather than transcribed. It refuses to run unless
the column table is still triangular and the difficulty table is still the column minus one.

`autoloads/progress_store.gd` keeps the original's fields, its two sentinels and its
win-only write policy, but puts the registry values and `HIGHSCORE.DAT` together in one
`user://progress.cfg`: a `[progress]` section holding the two masks and a `[level_N]`
section per level. It does not write the binary file or touch the registry.

Two divergences worth naming:

- **A level with no imported scene opens its description but cannot be started.** The
  original ships all 21, so it never has to refuse one; this port has imported some, and
  `Kontynuuj` is disabled for the rest rather than hiding them from the tree.
- **The screens are laid out in an 800x600 safe frame** that a wider window pillarboxes in
  black, as the original does. See [widescreen.md](widescreen.md).

The description screen's `%s` splicing is shared with the pause panel through
`scenes/shared/goal_text.gd`, since both show the same recovered sentence.

## Not chased

The 9-slice `CO_GUI_WINDOWS_*` frame — which screens draw it — was left for the task that
needs it.
