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
| 2 | Intro; starts `Menu1` |
| 3 | Main menu; starts `Menu1` |
| 4 | Loading |
| 5 | The catch minigame. The opponent portrait is 7 when the catching agent's type is 1, the boss, and 4 otherwise |
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
to the description screen; its button 29 returns to the main menu. Sound setup moves each
volume by 5 and clamps to 0–100, with defaults of 75 for music and 65 for effects.

**Not recovered yet:** which key reaches pause or the quit prompt. The mechanism is known
— screen 10 sets the pause bit and `sub_403780` then advances nothing, and the prompt
strings `Pauza`, `Czy na pewno chcesz wyjść?` and `(T)ak lub (N)ie` all sit in the
localisation table — but nothing here shows the binding, and the level-1 title
`Ostatnie wyjście F4` is a pun rather than evidence. The port therefore has no pause and
no way out of a level short of finishing it; picking a key would be inventing behaviour.

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
