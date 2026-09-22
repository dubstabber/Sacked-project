# Original in-level console

Verified on 2026-09-21 against a disposable copy of `sacked.exe.i64`. `sub_405930` builds
every in-level GUI element when the game enters screen 1, and `sub_403780` feeds them each
frame. See [game-rules-reference.md](game-rules-reference.md) for the screens themselves.

## Layout

Each element stores its position at object `+8`/`+12` and its layer at `+16`. The values
are absolute screen coordinates in the original's 800 × 600 viewport. The port's canvas is
fixed only in height, so it keeps them as offsets inside two anchored 800 × 600 bands — see
"Carrying these coordinates onto a wider canvas" below and
[widescreen.md](widescreen.md).

| Element | Position | Layer | Source |
| --- | --- | --- | --- |
| Console frame | `(0, 0)`, `+1140 = 8` | 100 | `CO_GUI_CONSOLE_CONSOLE`, 800 × 200 |
| Score field | `(85, 500)` | 0 | Arial 22, weight 100 |
| Clock field | `(250, 500)` | 0 | Arial 22, weight 100 |
| Hover text | `(135, 556)` | 100 | Arial 22, colour `(250, 250, 250)`, initially `...` |
| Action icon | `(170, 477)` | 100 | a `CGUIRectangle` over the ACTICON set, `+1163 = 255` |
| Aggression bar | `(410, 497)` | 100 | `CO_GUI_CONSOLE_AGGRO_FULL` |
| Clock bar | `(662, 536)` (its **centre**) | 0x8000 | `CO_GUI_CONSOLE_CLOCK_FULL`, radius `+96 = 36.0`, start angle `+1140 = 0.5` |
| Matrix lamp | `(754, 537)` | 1 | `CGUIActionIcon`, `CO_GUI_CONSOLE_MATRIX_ACT` |
| Urination lamp | `(756, 485)` | 1 | `CGUIActionIcon`, `CO_GUI_CONSOLE_PISS_ACT` |
| Smoking lamp | `(717, 461)` | 1 | `CGUIActionIcon`, `CO_GUI_CONSOLE_SMOKE_ACT` |
| `THERMO_UP`, `AGGRO_UP` | `(5, 5)` | 100 | 800 × 600 banners, created hidden, `+1163 = 220` |
| Warning caption | `(240, 50)` | 0 | Arial 30, registered as `THERMO_UP`'s child so it shows with it |

`CGUIRectangle::Draw` (`sub_45B820`) draws from the element's own `(x, y)` as the **top
left**, and `+1140` is its alignment flag: `16` centres the sprite in the viewport, bit `4`
right-aligns it, bit `8` bottom-aligns it, and `0` — what every element but the frame uses —
means "place it where it says". `CGUIActionIcon` inherits that draw unchanged, so the
lamps follow the same rule. `CGUIRoundBarTex` is the exception and is described below.

The frame's own position is `(0, 0)` while every other element sits between y 461 and 556,
so `+1140 = 8` docks it to the bottom and its 200 pixels occupy **y 400 to 600**. Matching
the exported frame against the reference screenshot confirms it: sampling its 11730 opaque
pixels gives a mean channel error of 28 at a top edge of y = 400 against 73 or more at
±5 pixels. The frame's top edge is transparent and wavy, so the world shows through above
the opaque part.

### Carrying these coordinates onto a wider canvas

The alignment flag is what the port turns into an anchor. Because the original's viewport
was exactly 800 wide, its flags only ever had to resolve against 800 × 600, and every
recovered number above survives unchanged as an offset inside a band of that size:

| `+1140` | What the original does | What the port anchors |
| --- | --- | --- |
| `0` on a console element | place it where it says | an offset inside `Band`, which is bottom docked, so it rides with the frame |
| `0` on a banner or its caption | place it where it says | an offset inside `Banners`, which is top aligned |
| `8` (bottom) — the frame alone | `y = viewport_height − height` | `Band` anchored to the bottom edge, frame still at band y 400 |
| `16` (centre) | centre in the viewport | anchors of 0.5 with an offset of −size/2 |
| bit `4` (right) | right-align | `anchor_right = 1` |

No console element carries flag `16` or bit `4`; they are listed because the round menu and
the pause panels are centred by their own code, which the port derives from the live width
rather than pinning to 400.

**One divergence.** The frame's flag is `8` alone, with no centre bit, so the original
left-aligns it — indistinguishable from centring it in an 800-wide viewport. The port
centres it, which keeps the console symmetric under a wider view and lets the world show on
both sides of it. At 4:3 the two are identical.

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

## The floating score numbers

A score that happens somewhere in the world also floats off the spot that earned it.
`sub_41DE60(player, points)` adds to `player+984` and queues one at the player's own
position a world unit up; `sub_41DEA0` does the same for an agent that has just been caught
out by a tampered object. `sub_40A0D0` queues, `sub_40A310` ages, `sub_40A390` draws.

**The glyphs.** The sprite is `CO_EFFECT_FONT_SCORE` (falling back to `FONT_GOLDEN.TGA`),
13 glyphs of **24 × 32** side by side. `sub_40A0D0` stores each character of
`sprintf("%d")` as `c - 44` and the draw sources it at `24 * (byte - 1)`, which puts `-` on
glyph 0, the unused `.` and `/` on the two blanks, and `0`–`9` on glyphs 3–12. The advance
is **25** pixels, one more than a glyph is wide.

**The position.** `screen = (48 * (x - z), 24 * (x + z))` as everywhere else, minus the
camera, and then minus `height * 59` — a unit of height is 59 pixels here, unlike the 24 a
seated sprite's lift uses. Each character is then raised by its own table entry.

**The animation.** `sub_409E40` fills two 1280-entry tables once, rather than shipping them
as data, and the draw indexes both at `phase * 256 + 16 * character`, so every character
lags the one before it by a sixteenth of a second and the number peels upward left to
right. `sub_40A310` adds the frame delta to every phase and drops a number once it reaches
**4.0**, which is exactly where the first character's alpha hits zero.

```text
rise[i]  = int(clamp(i/256, 0, 2) * 72)                              while i/256 < 2
         = int((clamp(i/256, 0, 2) + wobble) * 64)                   otherwise
  wobble = (sin(i * 0.024543693) + 1) / 2 * clamp(i/256, 0.5, 1) / 2

alpha[i] = 4 * i          i < 64          fading in
         = 255            i < 768         held
         = (-1 - i) & 255 i < 1024        fading out
         = 0              otherwise
```

So a number climbs 144 pixels over two seconds, then hangs between 128 and 160 bobbing on a
sine of one turn per 256 steps, and the table is exactly long enough for the last live phase
of the longest number `snprintf` can produce (`1023 + 16 * 14`).

The port draws these in `scenes/effects/score_popup.gd`, over the world composite, the
characters and a thought bubble; `tests/check_score_popup.gd` pins both tables.

## The digit strip

`CO_GUI_CONSOLE_NUMBERS` is **not** what the console's two fields use — those are ordinary
Arial text. The strip belongs to `CGUIFNumber`, whose draw is `sub_45C190`. **No level
builds one**: the only caller of its constructor is `sub_413D40`, and the hidden object
`sub_405930` creates at `(400, 300)` is the `CGUIRoundMenu` the action ring uses, not a
digit strip. See [player-action-reference.md](player-action-reference.md) for its layout.

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
so the port's camera is unchanged and the console is drawn over the world. A wider canvas
shows more of the map, and more of the void past its edges, which makes the missing clamp
easier to notice but no better understood; the port does not invent one. See
[widescreen.md](widescreen.md) for the open question as filed.

## What drives each element (implemented)

`sub_403780` feeds the console every tick, and the port now follows it:

| Element | Source |
| --- | --- |
| Score, clock | `player+984`, `game+14708` |
| Hover bar | `player+1128`, the selected entry's name |
| Centre icon | `player+929 + player+920`, the selected entry's ACTICON, hidden at `player+920 == -1` |
| Stopwatch | `player+992 * 100 / player+1000` — how far the running action has come, swept clockwise from `+1140` |
| Lamps | `player+1008`: smoking needs slots 5 **and** 6, Matrix 14, urination 26 |
| Aggression bar | `game+14728 * 1.42 + 46` pixels of its 188, never hidden |

Both of those follow **`player+920`**, the selected menu slot, which outlives the ring: see
[player-action-reference.md](player-action-reference.md). So the centre icon and the hover
bar keep showing the action the player committed to for as long as it runs.

`sub_41AF60` clears 28 bytes at `player+1008` when a level starts, so the player always
begins empty-handed and every lamp is dark. That is why level 1's rows needing items 9, 10,
22, 24 or 29 can never be reached: nothing on that level grants them.

`game+14724` is the widget at **(662, 536)** — the stopwatch, `CO_GUI_CONSOLE_CLOCK_FULL`,
radius `+96 = 36.0` — so the running action sweeps around the stopwatch, not along the
aggression bar at (410, 497).

## The aggression bar and its warning

`game+14732` at (410, 497) is the one element `sub_405930` never hides, and `sub_403780`
feeds it every frame by cropping its right edge:

```text
game+14732 +1144 = 0                                        crop nothing off the left
game+14732 +1148 = 188 - (game+14728 * 1.42 + 46)           crop this much off the right
```

`CGUIRectangle::Draw` then sources `188 - (left + right)` pixels, so the width that survives
is `game+14728 * 1.42 + 46` — **46 pixels even at zero**, which is exactly the thermometer's
bulb, and the full 188 at 100. The crop is truncated rather than the fill, so the width is
the complement of a truncation: at a mean of 50 the bar is 117 pixels, not 116.

`game+14728` is the office-wide mean of every agent's own aggression, rebuilt each frame by
`sub_402350`; see [npc-reference.md](npc-reference.md) for where an agent's own comes from.

When that mean crosses into a higher band, `sub_402350` calls `sub_407960`, which shows
`game+14740` — the 800 × 600 `THERMO_UP` banner at (5, 5), alpha 220 — and sets
`game+14748` to 2.0. `sub_403780` counts that down by the frame delta and hides it at zero.
The caption is a separate Arial 30 element at (240, 50) reading
**`Uważaj! Twoi koledzy... ojej!`**, registered as the banner's child so the two rise and
fall together. `AGGRO_UP` is the same shape — `game+14752`, built hidden at (5, 5) with the
same alpha by `sub_405930` — and it is the **"you have been spotted" banner**: `sub_407990`
raises it the moment an agent catches the player, and it comes down 2.0 seconds later when
the minigame starts. See [catch-reference.md](catch-reference.md).

## How the stopwatch is swept

`CGUIRoundBarTex::Draw` is `sub_45AEE0`. It emits a gouraud-textured **triangle fan**, one
triangle per angular step, each sharing the element's own position as its apex:

```text
vertex at angle a:  x = cx + r * sin a          u = (sin a + 1) * r
                    y = cy - r * cos a          v = r - r * cos a
apex:               x = cx, y = cy              u = r, v = r
sweep:              a from  this+1140  to  this+1140 + progress * 6.28 + 0.01
```

Three consequences the port has to honour:

- **`(662, 536)` is the centre of the disc, not the corner of the texture.** `cx` and `cy`
  are integers and the vertex coordinates are truncated, so texel `(u, v)` lands on screen
  pixel `(cx - r + u, cy - r + v)` exactly: the texture's top-left `2r × 2r = 72 × 72`
  texels are painted over `(626, 500)`–`(698, 572)`. Sampling the exported art against the
  console frame agrees — the dial correlates best with its top-left texel at `(625, 499)`.
- **Only the disc is drawn.** The fan never covers the texture's corners, so the 75 × 77
  sprite's last three columns and five rows are never sampled.
- **The sweep does not start at the top.** `+1140 = 0.5` radians ≈ 28.6°, which is the angle
  the painted dial is tilted by: starting there puts angle zero on the dial's own `60` mark
  and 45% of a turn on its `27`.

The port reproduces this in `scenes/shared/round_bar.gdshader`, with the sprite offset by
`-radius` on both axes so its node still sits at the original element position.
