# Original in-level console

Verified on 2026-09-21 against a disposable copy of `sacked.exe.i64`. `sub_405930` builds
every in-level GUI element when the game enters screen 1, and `sub_403780` feeds them each
frame. See [game-rules-reference.md](game-rules-reference.md) for the screens themselves.

## Layout

Each element stores its position at object `+8`/`+12` and its layer at `+16`. The values
are absolute screen coordinates in the 800 × 600 viewport.

| Element | Position | Layer | Source |
| --- | --- | --- | --- |
| Console frame | `(0, 0)`, `+1140 = 8` | 100 | `CO_GUI_CONSOLE_CONSOLE`, 800 × 200 |
| Score field | `(85, 500)` | 0 | Arial 22, weight 100 |
| Clock field | `(250, 500)` | 0 | Arial 22, weight 100 |
| Hover text | `(135, 556)` | 100 | Arial 22, colour `(250, 250, 250)`, initially `...` |
| Action icon | `(170, 477)` | 100 | a `CGUIActionIcon` over the ACTICON set |
| Aggression bar | `(410, 497)` | 100 | `CO_GUI_CONSOLE_AGGRO_FULL` |
| Clock bar | `(662, 536)` | 0x8000 | `CO_GUI_CONSOLE_CLOCK_FULL`, `+96 = 36.0`, `+1140 = 0.5` |
| Matrix lamp | `(754, 537)` | 1 | `CO_GUI_CONSOLE_MATRIX_ACT` |
| Urination lamp | `(756, 485)` | 1 | `CO_GUI_CONSOLE_PISS_ACT` |
| Smoking lamp | `(717, 461)` | 1 | `CO_GUI_CONSOLE_SMOKE_ACT` |
| `THERMO_UP`, `AGGRO_UP` | `(5, 5)` | 100 | both created hidden, `+1163 = -36` |

The frame's own position is `(0, 0)` while every other element sits between y 461 and 556,
so `+1140 = 8` docks it to the bottom and its 200 pixels occupy **y 400 to 600**. Matching
the exported frame against the reference screenshot confirms it: sampling its 11730 opaque
pixels gives a mean channel error of 28 at a top edge of y = 400 against 73 or more at
±5 pixels. The frame's top edge is transparent and wavy, so the world shows through above
the opaque part.

## What each element shows

From `sub_403780`:

```text
[game+14764] at (85, 500)   <- sprintf("%05u", player+984)              the score
[game+14760] at (250, 500)  <- sprintf("%02u:%02u", t / 60, t % 60)     the elapsed clock
                               "XX:XX" once t exceeds 5940 seconds
[game+14796] at (135, 556)  <- player+1128, the focused action's name
[game+14736] at (170, 477)  <- the highlighted action's icon, or hidden
[game+14724] at (662, 536)  <- player+992 * 100 / player+1000
[game+14732]                <- 188 - (game+14728 * 1.42 + 46)
```

Two consequences worth stating plainly. The **score is the left field and the clock the
right one**, which means the `czas` and `wynik` labels painted into the console art sit
over the wrong values; that is the original's own mistake and reproducing it is the
faithful choice. And the round bar tracks the **progress of the action the player is
performing**, not aggression — it is the elapsed and total duration of the current prank.

The lamps read the player's inventory at `player+1008`: smoking needs **both** slot 5 and
slot 6, the Matrix lamp needs slot 14, and urination needs slot 26. Slot 26 is the item
`Napełnij pęcherz` grants, which cross-checks against the action table.

## The digit strip

`CO_GUI_CONSOLE_NUMBERS` is **not** what the console's two fields use — those are ordinary
Arial text. The strip belongs to `CGUIFNumber`, whose draw is `sub_45C190`, and the only
one built in a level is created hidden at `(400, 300)`.

Its mechanics, for whenever that class is needed:

- The glyph pitch is **25 pixels**, set as `this+108`, and digit *d* is sourced at
  `y = 25 * d`. This matches the strip's measured glyph tops to within a pixel even though
  those are not perfectly even.
- Horizontal advance per character is `this+104`, the format string is at `this+124` and
  the value at `this+96`.
- With `this+112` set the digits **roll**: the previous digit for each position is cached
  at `this+184+i`, and the draw blits the old glyph offset by
  `v = this+120 * 25 * this+116` and the new one directly below it, where `this+116` is a
  phase advanced by the frame delta and reset at 1.0. Otherwise each position eases toward
  its target offset by `this+120` per frame.

## Fonts

`sub_405430` registers `International.ttf` and then creates every font from **Arial**, at
sizes 20, 20, 24, 28 and 20; the in-level elements ask for Arial at 22 and 30. The bundled
face is third-party freeware missing most Polish diacritics, so it cannot have rendered the
Polish UI. The port draws this text with Godot's default font at the same sizes.

## Not recovered

The camera. Whether the world viewport is clipped above the console or simply drawn behind
its transparent top edge, and what `CIsoCamera` clamps to at the map edges, are still open,
so the port's camera is unchanged and the console is drawn over the world.

## What drives each element (implemented)

`sub_403780` feeds the console every tick, and the port now follows it:

| Element | Source |
| --- | --- |
| Score, clock | `player+984`, `game+14708` |
| Hover bar | the highlighted menu entry's name, `"..."` when none |
| Centre icon | the highlighted entry's ACTICON, hidden when nothing is highlighted |
| Stopwatch | `player+992 * 100 / player+1000` — how far the running action has come, swept from the top clockwise |
| Lamps | `player+1008`: smoking needs slots 5 **and** 6, Matrix 14, urination 26 |

`sub_41AF60` clears 28 bytes at `player+1008` when a level starts, so the player always
begins empty-handed and every lamp is dark. That is why level 1's rows needing items 9, 10,
22, 24 or 29 can never be reached: nothing on that level grants them.

`game+14724` is the widget at **(662, 536)** — the stopwatch, `CO_GUI_CONSOLE_CLOCK_FULL`,
radius `+96 = 36.0` — so the running action sweeps around the stopwatch, not along the
aggression bar at (410, 497). That one is `game+14732`, fed
`188 - (game+14728 * 1.42 + 46)`, and stays dark until detection is implemented.
