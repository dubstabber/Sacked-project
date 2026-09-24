# Original level rules, modes and screen flow

Verified on 2026-09-21 against a disposable copy of `sacked.exe.i64`. The original
executable and database were not modified. Addresses are virtual addresses in the shipped
`sacked.exe` (479232 bytes, SHA-256 `6404096c…`).

## The CONDITION chunk

`sub_412FB0` is the level loader. Its `CONDITION` branch reads an 8-byte payload and
validates both halves before storing them on the map object:

```text
f32 time_limit_seconds   accepted only within [1.0, 3600.0]   -> map+1864
u32 score_target         accepted only within [1, 99999]      -> map+1860
```

An out-of-range value leaves the previous field untouched. `LEVEL_00.col` carries
`360.0 / 4000`; the same level's `LEVEL_00S.col` carries `300.0 / 3000`.

A second, lighter reader, `sub_413360`, opens a level file and returns only `MAPINFO`'s
width and height plus the two `CONDITION` values. It is what the level-description screen
uses, so a level's time and score can be shown without loading the map.

## Two modes, two files

`sub_408D00` builds the level path from a flag at `game+20700`:

```text
game+20700 == 0  ->  LEVELS\LEVEL_%02d.COL
game+20700 == 1  ->  LEVELS\LEVEL_%02dS.col
```

`sub_403F20`'s main-menu case writes that flag: the first button sets it to 0 and the
second sets it to 1, and both then move to the player-setup screen. Those buttons are
`Gra na czas` and `Gra na punkty`, so **the time game plays the plain file and the points
game plays the `S` file**. `sub_405430` initialises the flag to 0 at startup.

This is what the `S` variants are for. They are not a second campaign: across all 21
levels they differ from the plain files only in `CONDITION`, except for six levels that
also move a handful of items.

The port follows the same split. One imported scene normally serves both modes, because
`tools/build_level_scene.gd` writes both `CONDITION`s onto the level's `LevelSession` and
`level_session.gd` picks between them by mode. Where the `S` file also moves the map the
importer emits a second scene from it — `scenes/level_Ns.tscn`, from
`resources/levels/level_Ns.json`, which carries `"game_mode": "points"` — and
`ScreenManager.level_scene_path` asks for that one in the points game. Measured against the
shipped files, the six divergences are:

| Level | `S` file changes | What moved |
| --- | --- | --- |
| 5 | `items` | three items nudged inside their own tile |
| 8 | `layers` | three `LAYER0` floor cells |
| 11 | `items`, `spawns` | 190 objects become 191: one parked off the map's left edge and a replacement added |
| 12 | `items` | three items nudged |
| 19 | `items`, `spawns` | 407 objects become 406, and the tail of the item list reindexes |
| 20 | `items` | one item nudged |

The `spawns` difference on 11 and 19 is only the chunk trailer's instance ids shifting by
one behind the inserted or removed item; the spawn records themselves are identical.

## Winning and losing

The in-level tick is `sub_403780`. It returns immediately when the pause bit
`game+12740 & 0x20` is set, so a paused level advances nothing at all.

Relevant fields:

| Field | Meaning |
| --- | --- |
| `game+14668` | score target; **0 falls back to 10000** |
| `game+14672` | time limit in seconds as a float; **≤ 0 falls back to 1200.0** |
| `game+14708` | elapsed seconds, as an integer — **the clock counts up** |
| `player+984` | the player's score |

The predicate, with the fallbacks applied:

```text
points game (game+20700 == 1):
    if elapsed >= limit:
        score >= target  ->  win screen
        otherwise        ->  lose screen

time game (game+20700 == 0):
    if elapsed <= limit and score >= target  ->  win screen
    if elapsed >  limit                      ->  lose screen
```

So the time game ends the moment the target is reached and is lost when the clock passes
the limit, while the points game always runs the full time and is judged at the end. That
matches the objective strings: `Zdobądź jak najwięcej punktów w ciągu %d minut.` against
`Potrzebujesz przynajmniej %d punktów!`.

Ten seconds before the limit the tick starts the looping sound `S1012` and remembers its
handle in `game+19056`, which is the countdown warning.

## Screens

`sub_407370(game, n)` switches screens and `game+19044` holds the current one.
`sub_403F20` dispatches each screen's button result.

| n | Screen |
| --- | --- |
| 1 | Playing a level. Loads the path `sub_408D00` prepared, or `test.col` if there is none |
| 2 | Boot loading screen; starts `Menu1`, loads the archives, then goes to 3. There is no intro; see [shell-reference.md](shell-reference.md) |
| 3 | Main menu; starts `Menu1` |
| 4 | Caught: the level holds still under the `AGGRO_UP` banner for 2 s, then goes to 5. Not a loading screen |
| 5 | The catch minigame, entered 2 s after an agent catches the player. Winning returns to screen 1 and losing goes to screen 8; see [catch-reference.md](catch-reference.md) |
| 6 | Quit; `WinMain` ends when it sees it |
| 7 | Win; plays `S1100` |
| 8 | Lose |
| 9 | Restart the level, then falls through to screen 1 |
| 10 | Pause; sets `game+12740 |= 0x20` rather than switching away |
| 11 | Sound setup |
| 12 | Player setup |
| 13 | Coworker names; starts `Menu2` |
| 14 | Highscores; starts `Menu2` |
| 15 | Level tree |
| 16 | Level description |

The level tree accepts buttons 1 to 21 and calls `sub_408D00(game, n - 1)` before moving
to the description screen; its button 29 returns to the main menu.

A screenshot of it (`sacked-reference-images/`, gitignored and local) shows what it draws:
21 spherical nodes on a diamond lattice over the blue vortex backdrop, linked by glowing
bars that fan out left to right from a single root. Each node is one of **three colours** —
green, yellow or red — and the shot has the leftmost few green, the next three yellow and
every node beyond them red. Read against the sprite names `LEVEL_BUTTON_FREE`, `_PLAYED`
and `_LOCKED`, that is played, playable and locked, with the yellow frontier sitting exactly
where the green ends. The title `Wybór poziomu` (slot 190) sits along the top and a single
`Główne menu` button (slot 191) in the bottom-left corner, which confirms both keys. The
linking bars are drawn in the same two colours as the nodes they join, so the path already
taken is lit differently from the path ahead. The node coordinates, the unlock rule behind
the three colours and the per-level difficulty index are all recovered in
[shell-reference.md](shell-reference.md).

### What the description screen draws

A screenshot of screen 16 for level 1 (`sacked-reference-images/`, gitignored and local)
settles almost all of its layout:

- A **title** centred along the top, `Pierwszy ostatni dzień (#01)` — the level's own title
  from slot 232 + n, with its **1-based number appended as `(#%02d)`**.
- The **left panel** (`MENU_LEVEL_BACKDROP_DESC`, 480 × 392) carries `Level_XX.txt` rendered
  whole, with the `%s` substituted: description paragraph, blank, the goal sentence, blank,
  blank, hint paragraph. For level 1 the goal reads `Aby ukończyć ten poziom, musisz zdobyć
  4000 punktów w ciągu 6 minut.` — that is slots 158 and 159, the pause panel's own two
  lines, run together into one sentence. So the `%s` is the mode's objective wording, and the
  port composes it from the same keys the pause panel uses.
- The **right panel** (`_INFO`, 256 × 392) is four label/value pairs, each label left-aligned
  with its value right-aligned on the following line: `Najlepszy czas` `02:54`,
  `Najlepszy wynik` `---`, `Rozmiar` `16 x 16`, `Poziom trudności` `Początkujący`. That is
  slots 194–197, a `---` sentinel that is a C literal rather than slot 163, level 1's MAPINFO
  width and height formatted `%d x %d`, and difficulty index 0.
- **`Wróć` bottom-left and `Kontynuuj` bottom-right** (slots 198 and 193), on the same button
  art the rest of the shell uses.
- The backdrop is the blue vortex the tree also uses.

The per-level difficulty index is `byte_465270`, which is the level tree's own column minus
one; see [shell-reference.md](shell-reference.md). Sound setup moves each
volume by 5 and clamps to 0–100, with defaults of 75 for effects and 65 for music; see
[sound-reference.md](sound-reference.md).

Pause is `game+12740` bit `0x20`, toggled by **scancode 121** and refused while the screen
is 4 (the caught pause). `sub_403780` returns immediately while it is set, so the clock, the console
and every agent stop together and only the drawing carries on. `Main_RenderUpdate` then adds
a panel spanning (49, 232) to (750, 372) restating the level's own CONDITION and the word
`Pauza`, centred on x 400 with a two-pixel drop shadow. The time game writes
`Aby ukończyć ten poziom, musisz zdobyć` / `%d punktów w ciągu %d minut.`; the points game
writes `Zdobądź jak najwięcej puntków w ciągu %d minut.` / `Potrzebujesz przynajmniej %d
punktów!`. Limit and target fall back to 1200 s and 10000 exactly as the tick does.

The quit prompt is **scancode 16 (`Q`)**, also refused on screen 4, and reaches screen 10:
an overlay from (49, 150) to (750, 230) holding `Czy na pewno chcesz wyjść?` and
`(T)ak lub (N)ie`, with the level still running behind it. The port answers it with `T`
and `N`, the initials the prompt itself names.

**Still not recovered:** which physical key scancode 121 is. Scancodes 1, 16, 57 and the
arrows 72/75/77/80 are standard set-1 codes, but 109, 111, 112, 114 and 121 fall in a range
no Polish or German keyboard uses for those functions, and the install ships no manual. The
port binds pause to `P`, for `Pauza`, as a stand-in until the key is identified.

## What the console shows

The same tick fills the HUD, which settles what the two digit fields are:

```text
sprintf(buffer, "%05u", player+984)                        // score
sprintf(buffer, "%02u:%02u", elapsed / 60, elapsed % 60)   // elapsed time, "XX:XX" above 5940 s
```

The score field is filled first and the clock second. In the reference screenshot the
five-digit field sits under the label `czas` (time) and the clock under `wynik` (score),
so **the two labels are swapped in the original console artwork**. Reproducing that is
faithful; correcting it is not.

Three more console elements are driven from here:

- The round bar is **action progress**, not aggression: it is
  `player+992 * 100.0 / player+1000`, the elapsed and total duration of the action the
  player is performing.
- The thermometer fill is `188 - (game+14728 * 1.42 + 46)`.
- The square field between the labels shows the **icon of the currently highlighted
  action**, indexed out of the same 66-entry ACTICON name table the action records use.
- The three lamps are lit from the player's inventory at `player+1008`: the first needs
  both slot 5 and slot 6, the second slot 14, the third slot 26.

## Fonts

`sub_405430` registers `International.ttf` with `AddFontResource`, then creates all five of
its fonts from **`Arial`** at sizes 20, 20, 24, 28 and 20. The bundled face is a
third-party freeware font that is missing most Polish diacritics, so the Polish build
cannot have rendered its own UI text with it.
