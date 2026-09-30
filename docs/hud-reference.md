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
| Score field | `(85, 500)` | 0 | Arial 22, regular (flags `0x64`; see "Fonts") |
| Clock field | `(250, 500)` | 0 | Arial 22, regular (flags `0x64`) |
| Hover text | `(135, 556)` | 100 | Arial 22, regular (flags `0x64`), colour `(250, 250, 250)`, initially `...` |
| Action icon | `(170, 477)` | 100 | a `CGUIRectangle` over the ACTICON set, `+1163 = 255` |
| Aggression bar | `(410, 497)` | 100 | `CO_GUI_CONSOLE_AGGRO_FULL` |
| Clock bar | `(662, 536)` (its **centre**) | 0x8000 | `CO_GUI_CONSOLE_CLOCK_FULL`, radius `+96 = 36.0`, start angle `+1140 = 0.5` |
| Matrix lamp | `(754, 537)` | 1 | `CGUIActionIcon`, `CO_GUI_CONSOLE_MATRIX_ACT` |
| Urination lamp | `(756, 485)` | 1 | `CGUIActionIcon`, `CO_GUI_CONSOLE_PISS_ACT` |
| Smoking lamp | `(717, 461)` | 1 | `CGUIActionIcon`, `CO_GUI_CONSOLE_SMOKE_ACT` |
| `THERMO_UP`, `AGGRO_UP` | `(5, 5)` | 100 | 800 × 600 banners, created hidden, `+1163 = 220` |
| Warning captions | `(240, 50)` | 0 | Arial 30, regular (flags `0x64`). `game+14744` is `THERMO_UP`'s child and `game+14756` is `AGGRO_UP`'s, so each shows with its banner. Both are created at `(10, 10)` and then moved |

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
right one**, which means the `czas` and `wynik` labels painted into the Polish console art
sit over the wrong values.

**That mistake belongs to the Polish release, not the game.** The German build's own console
sprite reads `punkte` on the left and `zeit` on the right, correctly naming the fields
underneath. So each build ships its own art and the port shows each unaltered, swap included;
a language with no art of its own draws its labels in the German order. See
[strings-reference.md](strings-reference.md).

And the round bar tracks the **progress of the action the player is performing**, not
aggression — it is the elapsed and total duration of the current prank.

The lamps read the player's inventory at `player+1008`: smoking needs **both** slot 5 and
slot 6, the Matrix lamp needs slot 14, and urination needs slot 26. Slot 26 is the item
`Napełnij pęcherz` grants, which cross-checks against the action table.

The lamps are also buttons, the only way into the player's modes 2, 3 and 5.
[player-ability-reference.md](player-ability-reference.md) covers them. In the port,
`console.gd` takes a left press strictly inside a lit lamp's sprite rect, in the band's own
coordinates, and hands the lamp's bit to `AbilityController`. It consumes that press, so the
world never sees it. The rects stay at their 800 × 600 offsets inside `Band`, so they follow
the band on a wider canvas.

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
- `this+104` is the gap between digits: digit i is drawn at
  x = `+8` + (i + 1) × the cell's width + i × `+104` (`0x45C398`–`0x45C3A5`), so the advance is
  the cell's width plus the gap (see "The countdown is a digit strip" in
  [minigame-reference.md](minigame-reference.md)). The format string is at `this+124` and the
  value at `this+96`.
- With `this+112` set the digits **roll**: the previous digit for each position is cached
  at `this+184+i`, and the draw blits the old glyph offset by
  `v = this+120 * 25 * this+116` and the new one directly below it, where `this+116` is a
  phase advanced by the frame delta and reset at 1.0. Otherwise each position eases toward
  its target offset by `this+120` per frame.

## Fonts

Verified on 2026-09-25 against a disposable copy of `sacked.exe.i64`. The German
`Gefeuert.exe` was read too, and its font requests were checked against its bytes.

**One creator.** `sub_42B680(face, size, flags)` makes every font. It is the only caller of
`CreateFontA`: the import at `0x46503C` has one code reference, `0x42B6EC`. Only bits 0 and 1
of `flags` are ever read:

- bit 0 picks the weight, 800 when set and 400 when clear (`and eax, 1` …
  `and eax, 0FFFFFE70h` / `add eax, 320h`, `0x42B6B5`–`0x42B6D8`);
- bit 1 sets italic (`and ecx, 2` / `cmp cl, 2` / `setz dl`).

Everything else is fixed:

- `nHeight = size & 0xFFFF`, positive, so GDI matches the cell height, not the em;
- charset `0xEE`, `EASTEUROPE_CHARSET` (`0x42B6CA`);
- quality 4, `ANTIALIASED_QUALITY` (`0x42B6C2`);
- width, escapement, orientation, underline and strike-out all 0.

The flags are stored nowhere. `esi` holds them from `0x42B69D` until the brush handle
overwrites it at `0x42B713`.

**Every font the Polish build makes is regular Arial.** `sub_42B680` has twelve callers and
no data reference, so it is never reached through a vtable. The callers pass flags 0 or 100:

| Font | Arial size | Flags | Created by, at the call |
| --- | --- | --- | --- |
| `game+2000`, `+2004`, `+2008`, `+2012`, `+14784` | 20, 20, 24, 28, 20 | 0 | `sub_405430`: `0x405490`, `0x4054F6`, `0x405552`, `0x4055AE`, `0x40560A` |
| The level description's `+1240` | 24 | 0 | `sub_421570`: `0x421864` |
| The menus' `+1168`, `+1164`, `+1172` | 32, 22, 42 | 0 | `sub_423C50`: `0x423DA2`, `0x423DB5`, `0x423DC8` |
| Every `CGUIText`'s default, `+0x60` | 20 | 0 | `sub_45A480`: `0x45A4E9` |
| A `CGUIInput`'s `+0x17C` | 18 | 0 | `sub_45C5E0`: `0x45C6DA` |
| The clock `game+14760` and the score `game+14764` | 22 | 100 | `sub_405930` through `sub_45A650`: `0x405B4F`, `0x405BBB` |
| The hover text `game+14796` | 22 | 100 | the same: `0x405D59` |
| The warning captions `game+14744` and `game+14756` | 30 | 100 | the same: `0x405E4E`, `0x405F76` |

**The 100 is not a weight.** This page used to call it "weight 100". It is the flags argument.
`sub_45A650`, `CGUIText::SetFont`, has those five callers and no others. It deletes the
element's default Arial 20 at `+0x60` (`0x45A66B`–`0x45A678`), builds a new font with
`sub_42B4A0`, and passes its own face, size and flags to `sub_42B680` unchanged
(`0x45A6A4`–`0x45A6C0`). 100 is `0x64`, which sets bits 2, 5 and 6. Bits 0 and 1 are clear, so
the console text comes out at weight 400 and upright, the same regular Arial as everything
else. **No text in the game is bold or italic.** The pushes are `6A 64` at `0x405B28`,
`0x405B94`, `0x405D35`, `0x405E36` and `0x405F5E`.

Why a caller passes 100 is not in the binary. It may be left over from an interface that once
took a GDI weight, where 100 is `FW_THIN`; that is inferred. The German original passes the
same 100 at its five console calls, so the value is older than the localisation.

**Cell height, not em.** A positive `nHeight` asks GDI for that cell height, ascent plus
descent. Arial and Liberation Sans share `usWinAscent` 1854, `usWinDescent` 434 and 2048
units per em, as read from `images/gui/fonts/liberation-sans-regular.ttf`. So the em is
2048/2288 = 0.8951 of the number the game asks for:

| Asked for | 18 | 20 | 22 | 24 | 28 | 30 | 32 | 42 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Em, pixels | 16.11 | 17.90 | 19.69 | 21.48 | 25.06 | 26.85 | 28.64 | 37.59 |

**Which em GDI picks** is not in the binary, but the reference screenshots settle it. It is
the rounded one, `MulDiv(N, 2048, 2288)`, which is also the largest em whose rounded ascent
and descent still fit the cell: 16, 18, 20, 21, 25, 27, 29 and 38 for the sizes above. Three
measurements agree, and truncation fails two of them:

- The two Arial 42 titles, screen 16's `Pierwszy ostatni dzień (#01)` (468.7 px of ink) and
  screen 12's `Wybierz swoje alter ego` (401.7 px), are within 0.5 % of Liberation Sans at
  38. Against 37 they are 1.4 % to 2.7 % wider, with the rounding remainders kept or not
  (see "In the port").
- Screen 16's Arial 24 body steps 207 px over nine line pitches, 23.0 each. That is em 21's
  rounded ascent 19 plus its rounded descent 4.
- Screen 12's two-line Arial 22 name prompt has its ascenders 22.2 px apart: em 20 gives
  18 + 4 = 22, em 19 would give 21.

Widths are taken from the two 1920 × 1080 captures (`ds5bnh36ens.png`, `hdnzy5neny.png`)
cropped to their 1440 × 1080 frame, at the half-crossing of the red channel over blue or the
blue channel over orange, and divided by 1.8. The 800 × 600 and 640 × 480 JPEGs lose the thin
edges to chroma subsampling and read up to 4 % narrow, so they are not used.

**How the glyphs are made.** `sub_42B680` renders characters 0x20 to 0xFF once, with
`ExtTextOutA` and `ETO_OPAQUE`. The text is white (`SetTextColor(0xFFFFFF)`) on magenta
(`SetBkColor(0xFF00FF)`). The target is a top-down 32-bit DIB:

- its width is the sum of each glyph's width plus 1, and its height is the tallest cell;
- characters below 0x20 get width 1;
- the glyph table at font `+4` holds 16-byte entries `{x, 0, cx, cy}`.

The atlas image is made by `sub_42CFD0` into font `+0x1C`. `sub_42C1D0` pre-fills it with
magenta (`0x42B906`), and `sub_42C300` keys it on `0xFF00FF` (`0x42B97D`).

**How a text is drawn.** `CGUIText::Draw` is `sub_45A730`, at slot `+0x7C` of the vtable
`off_46703C` (`0x4670B8`). It draws the string twice through `sub_42B9A0`:

1. a shadow in (30, 30, 30), 2 pixels right and 2 down (`0x45A82D`, `0x45A876`, `0x45A87E`);
2. the text in the element's colour `+0x64`–`+0x66`, one depth unit nearer
   (`0x45A8CB`–`0x45A904`).

Each pass sets blend mode 35 (`0x45A806`, `0x45A8AA`). `sub_42B9A0` ORs 4 into it for the
blit (`0x42BA1C`, restored at `0x42BCC2`), so the glyphs are drawn in mode 39, by `0x44D780`
(entry 39 of the table at `0x47168C`):

```text
skip if (src & 0xFFFFFF) == 0xFF00FF    // the exact key
skip if zbuffer < depth
dst = (src_i * tint_i) >> 8             // opaque; writes the depth
```

That holds while renderer `+48` is not 1 and the renderer's scale, `+32`/`+36`, is 256.

- **The shadow is opaque.** Under a white glyph it is about (29, 29, 29). The weight 128 that
  `sub_45A730` sets through `sub_42D1D0` (`0x45A858`) goes to renderer `+0x1C`, and this
  blitter never reads it.
- **The text always covers its own shadow,** because it is one depth unit nearer.
- **Nothing fakes a bold.** `sub_42B9A0` blits each character once, one `sub_42CCF0` call per
  character. The second pass is the shadow.
- **The colour bytes.** `sub_45A730` hands `+0x64`, `+0x65` and `+0x66` to `sub_42D1E0` as its
  first, second and third arguments (`0x45A8CB`–`0x45A8DD`). They land in bytes 0, 1 and 2,
  which are red, green and blue in the back buffer's `R, G, B, X` order (see
  [field-of-view-reference.md](field-of-view-reference.md)). The console never depends on
  the order: the default is white (`sub_45A480`) and the hover text is (250, 250, 250).
- **The edges.** An antialiased edge pixel, white blended toward magenta, does not match the
  exact key, so it is drawn, tinted, on both passes. The binary cannot say whether Windows
  emits such pixels for `ANTIALIASED_QUALITY`, but the reference screenshots show it does:
  every glyph edge in them is pink and every shadow edge purple, over the orange panels and
  the blue backdrops alike.

**Layout**, in `sub_42B9A0`:

- a character advances by its glyph's `cx`, and the atlas's 1-pixel gap is not advanced;
- a text starts at the clip rectangle's corner plus the offset its caller passes, and `\n`
  returns to that same x, the clip's x plus the offset (`0x42BBB3`), and moves down by glyph
  entry 0's `cy`, which is the font's tallest cell, GDI's `tmHeight`. `sub_42BD80`, the height
  every caller centres a text by, reads entry 74's (`+1196`), the same cell;
- `\t` advances four space widths, `glyph[0x20].cx` at table `+0x208`;
- words wrap against the room left on the line, which each drawn glyph's `cx` uses up. The
  first line's room is the clip width `+0x10` less the start offset (`mov ebp, [esi+10h]` /
  `sub ebp, edx`, `0x42BAB6`–`0x42BAC0`). After a wrap or a `\n` the room is the whole clip
  width again (`0x42BB08`, `0x42BBAD`), while the line still starts at the offset. So every
  line after the first may run as far past the clip's right edge as the offset, and the blit
  cuts its glyphs at the clip rectangle (`sub_42CCF0` gets it at `0x42BB8A`). The clip comes
  from the renderer's or, through `sub_42BD20`, from the rect the caller sets;
- `sub_42B520` cuts the string into runs of blanks and runs of everything else, a blank being
  9, 10 or 32 only. A run whose widest line (`sub_42BCD0`) is at least the room left
  (`cmp eax, ebp` / `jl`, `0x42BAE4`) starts a new line first and loses one leading blank. So
  a word wraps only once the line would reach the room. The blank after it is a run of its
  own: if it reaches the room, it wraps the line and is dropped; if the next word wraps
  instead, the blank stays at the end of the line above, drawn and unseen;
- a carriage return is not a blank. Like every character below 0x20 it is a 1-pixel glyph
  that draws nothing, so a file's CRLF draws as one line break and makes the word before it
  one pixel wider.

**Every text draw, and the copy under it.** Each of the game's text draws puts its own copy
under the glyphs first. `sub_42B9A0` is always the one doing the drawing, and it has these
callers:

| Draw | What it draws | The copy: tint, offset | The text | Where the text starts |
| --- | --- | --- | --- | --- |
| `CGUIText`, `sub_45A730` | the console's score, clock and hover text; both warning captions | (30, 30, 30), +2 +2, mode 39 | its own colour, mode 39 | the element's position |
| `CMenuBase`, `sub_423F70` | every menu screen's title, in its Arial 42 | (48, 48, 48), +3 +3, mode 39 (`0x424068`, `0x424084`) | white | centred both ways in `+1216`, by the whole string's width and one cell |
| `TGUIExtButton<T>`, `sub_422C80` | every menu button's caption, in the menu's Arial 22, the character-select portraits included | (48, 48, 48), +2 +2, mode 36 (`0x422DBA`, `0x422DE2`) | white (`0x422E16`) | per axis by `+1204`/`+1206`: 0 centres, 1 ends 7 px short of the right or bottom edge, anything else starts 3 px in |
| `CPlayerSetup`, `sub_424D50` | screen 12's `Imię do tabeli najlepszych wyników`, in the menu's Arial 22 | (48, 48, 48), +3 +3, mode 39 (`0x424DCE`), in the same clip | white | (140, 463), 2 px into a clip of (138, 454, 208, 56) (`0x470F98`) |
| `CHighscore`, `sub_421380` | every highscore cell, in the menu's Arial 22 | (32, 32, 32), +2 +2, mode 39 (`0x42143C`) | white, mode 7 | 4 px in from the cell's top-left corner |
| `CLevelDesc`, `sub_421BA0` | screen 16's body and its eight info texts, in its Arial 24 | (32, 32, 32), +2 +2, mode 39 (`0x421C5C`) | white, mode 7 | as `sub_421380`, or for a value 4 px down and ending 7 px short of the right edge |
| `CGUIInput`, `sub_45CE00` | the volume boxes, the coworker-name boxes and screen 12's name box (`sub_4245E0`: `0x424AFF`, its font `+1168` at `0x424C7D`) | (32, 32, 32), +2 +2, mode 39 (`0x45CF2E`) | its own colour | by `+416`: 2, the default, x = (w − text width) / 2 − 2 (`0x45CEE1`–`0x45CEF0`), so the copy is the one centred across; 1, x = w − text width − 4; 0, x = 2. y = (h − cell) / 2 (`0x45CE97`–`0x45CEB7`). The port's text node sits 2 px left of the box to land there (`scenes/shared/gui_input.gd`) |
| `Main_RenderUpdate` | the pause panel's two goal lines and `Pauza`; the quit prompt's two lines | (0, 0, 0), (20, 20, 20) and (0, 0, 0), each +2 +2, mode 36 | (250, 190, 100), white and (250, 250, 250) | x = `400 − w/2` |
| `sub_417460` | a selected colleague's name | (40, 10, 0), +2 +2, mode 36 | (250, 180, 40) | see [names-reference.md](names-reference.md) |

Mode 36 (`0x44CED0`) is mode 39 without the depth test: keyed, tinted and opaque. Mode 7
(`0x444E30`) copies the keyed glyph untinted, with the depth test. So every copy is opaque and
every text covers its own copy. A tint multiplies white to one level below itself: 48 draws
47, 32 draws 31, 30 draws 29 and 20 draws 19. The reference screenshots show it. They are
16-bit, and the copies under the 48-tinted titles, captions and prompt sample as (41, 45, 41),
which is 47 in RGB565, where 48 would read (49, 49, 49); the copy under screen 16's 32-tinted
body samples as (25, 28, 25), which is 31. A text drawn in mode 39 goes through the same
multiply: white draws 254 and (250, 250, 250) draws 249.

`sub_421380` and `sub_421BA0` lay the copy out exactly as the text, with the clip rectangle
moved 2 px down and right with it. `sub_424D50` instead starts its copy 5 px into the same
clip as the text (5, 12 against 2, 9), so the copy's first line has 3 px less room than the
text's.

`TGUIExtButton<T>` has nine instantiations, one per menu class, and `sub_422C80` sits in all
nine vtables; in `TGUIExtButton<CPlayerSetup>`'s, at `0x46636C`, it is slot `+0xA0`. Every
button is built with alignment (0, 0) except the two
character-select portraits, which slot `+0x90` (`sub_423B40`) sets to (0, 1): centred across,
and 7 px up from the bottom edge. `sub_421AC0` draws screen 16 from the rects at `0x470A40`:
the body at (24, 128, 464, 360) in mode 0, then each label at (536, y, 240, 32) in mode 0 and
each value 40 px below it in mode 1, for y = 128, 224, 320 and 416.

**`International.ttf`.** `sub_405430` registers it with `sub_42BD60("International.ttf")`
(`0x4054B2`, `0x4054B7`), which is `AddFontResourceA` (`0x42BD74`). The file is third-party
freeware. Its name table calls the family `International Playboy`, its weight is 400 and its
OS/2 code pages are Latin-1 only (`ulCodePageRange1 = 0x1`). Its cmap has no `ß`, and of the
Polish letters only `ą` and `ó`. The Polish `sacked.exe` holds no `Playboy` string, so it
registers the face and never asks for it.

**The German original does ask for it.** `Gefeuert.exe`'s creator, at `0x42BCA0`, reads the
same two bits but pushes charset 1, `DEFAULT_CHARSET` (file offset `0x2BCEA`). Thirteen of its
sixteen font requests name `International Playboy`, the string at `0x46D960`. Only three name
Arial:

| Font | `Gefeuert.exe` | `sacked.exe` |
| --- | --- | --- |
| `sub_405430`'s five | Arial 20, then International Playboy 20, 30, 35 and 20 | Arial 20, 20, 24, 28 and 20 |
| The level description | International Playboy 28 (`0x421E64`) | Arial 24 |
| The menus' three | International Playboy 36, 28 and 48 (`0x4242E8`, `0x4242FB`, `0x42430E`) | Arial 32, 22 and 42 |
| A `CGUIText`'s default | Arial 20 | Arial 20 |
| A `CGUIInput` | Arial 18 | Arial 18 |
| The clock and the score | International Playboy 25 | Arial 22 |
| The hover text | International Playboy 28 | Arial 22 |
| Both warning captions | International Playboy 35 | Arial 30 |

The German console fonts go through its `SetFont` at `0x45AF20`, all with flags 100 (the
pushes at `0x405F48`, `0x405FB4`, `0x406170`, `0x406256` and `0x40637E`). So the Polish
localisation moved every International Playboy font to Arial and resized each one. The face
has no Polish letters, which is presumably why; that is inferred. The German build's menus,
level description and console were set in International Playboy, regular, though its cmap has
no `ß`. The port takes its German text from that build (see
[strings-reference.md](strings-reference.md)); which face German gets is still open (see "In
the port" below).

Charset `0xEE` is how the Polish build's Arial reaches the CP1250 letters. Godot works from
Unicode, so that part needs no porting.

### In the port

**The face.** `images/gui/fonts/liberation-sans-regular.ttf` is Liberation Sans 2.1.5
Regular, under the SIL Open Font License 1.1 in `LICENSE-liberation-sans.txt` beside it. It
has Arial's advance widths and vertical metrics. It is the default font of
`resources/ui_theme.tres`, which `project.godot` sets as `gui/theme/custom`, so every control
draws in it. Nothing under `scenes/` or `autoloads/` names another face, and the face does not
fall back to the system's for a character it lacks.

**One face for every language, for now.** The German text is drawn in Liberation Sans at the
Polish build's sizes, like the other two languages. The German original drew its menus, level
description and console in `International Playboy` at its own sizes (the table above), and
that face has no `ß`. Whether German should get that face, with a fallback for `ß`, is a
decision for the user; until then it gets the Polish build's Arial.

**The rasterisation** is set by `[importer_defaults]` in `project.godot`, because the
`.import` sidecar is not committed:

- grey-level antialiasing, since `ANTIALIASED_QUALITY` is not ClearType;
- normal hinting, the face's own instructions, as GDI runs Arial's;
- no subpixel positioning, so every glyph starts on a whole pixel, as `sub_42B9A0`'s do;
- kerning off (`kern` = 0), since the original has only per-character widths;
- no system fallback (`allow_system_fallback` off). `sub_42B680`'s atlas holds 0x20–0xFF of
  code page 1250 and nothing else, so a character outside Liberation Sans, which only a typed
  name can bring, draws as the face's missing-glyph box rather than in whatever face the
  machine has;
- no MSDF and no mipmaps;
- rounding remainders kept. This one is a port choice, below.

**The edge fringe is left out, a port choice.** The port does not draw the pink glyph edges
and purple shadow edges of "The edges" above. Godot's grey-level antialiasing blends each edge
pixel into whatever lies under it, and there is no magenta key to miss. Reproducing the fringe
would take a glyph atlas of the port's own, drawn on magenta and keyed as `sub_42B680`'s is,
or a text shader that tints the partial-coverage pixels. It shows on every screen, so it is in
the backlog rather than settled.

**The sizes are the rounded ems.** Every recovered Arial N is drawn at
`MulDiv(N, 2048, 2288)`. That is 20 for the menu's Arial 22, which is the theme's default
size, and 38 for the titles, 29 for the input boxes, 21 for Arial 24, 20 for the console's
Arial 22 and 27 for its Arial 30 captions.

**How that rule was picked.** The rule was measured against the reference screenshots. The
error is the mean difference in ink width over all 22 measurable texts in the two 1080p
captures: 2 Arial 42 titles, 13 Arial 24 texts and 7 Arial 22 captions.

| Rule | Arial 42 | Arial 24 | Arial 22 | All 22: mean, RMS |
| --- | --- | --- | --- | --- |
| Truncated em (37, 21, 19), each advance rounded | −1.7 % | +4.4 % | −0.1 % | +2.4 %, 4.1 % |
| Rounded em (38, 21, 20), each advance rounded | +0.2 % | +4.4 % | +3.1 % | +3.6 %, 4.2 % |
| Truncated em, remainders kept | −2.6 % | +1.3 % | −2.6 % | −0.3 %, 2.6 % |
| **Rounded em, remainders kept** | **+0.4 %** | **+1.3 %** | **+3.9 %** | **+2.0 %, 3.0 %** |

- **Hinting changes nothing measurable.** None, light and normal hinting give identical
  widths to the pixel at every size. FreeType's interpreter hints only vertically, and Godot
  rounds the advance either way. The glyph heights differ by one pixel at most. So the port
  keeps normal hinting, which runs the face's own instructions as GDI does.
- **The remaining error is Arial's hinted advance widths.** GDI advances by them and
  Liberation Sans does not have them. At ems 20 and 21, Liberation's rounded advances run
  3–4 % wide. Keeping the rounding remainders cuts the Arial 24 group from 4.4 % wide to
  1.3 %.
- **Why rounding and not truncation.** By width alone, truncation with remainders scores
  better, 2.6 % RMS against 3.0 %. That is only because Liberation's wide advances at em 20
  hide behind the smaller em 19. The line pitch cannot hide it: the Arial 22 prompt's lines
  are 22 px apart, and only em 20 has a 22-pixel cell. The titles are 0.4 % from em 38 and
  2.6 % from em 37. So the port takes the rule that every measurement agrees with, which is
  also the one Wine uses to match Windows.

What is left shows in the widths, not in the breaks. Level 1's hint line `Czy wiesz, że Twoi
koledzy zawsze Cię zauważą,` measures 451 px of ink in the screenshot and advances 463 px in
the port. It still breaks where the screenshot does, because it is not the body's first line
(see "Line breaks" below). With the rounded em, one German title wraps where it fitted at em
37: level 15's `Ich liebe den Geruch von Rauchbomben... (#15)`, 811 px against the rect's 800.
GDI's width at em 38 is within 0.5 % of the port's, so the original's Arial 42 would wrap it
too, starting the first line at a negative x (see [shell-reference.md](shell-reference.md)).

**Line breaks.** A `Label` that wraps by itself gives every line the same width and counts the
blank after a word when it fits that word, and neither is `sub_42B9A0`'s rule (see "Layout").
So the two multi-line texts the original breaks against a clip, screen 16's body and screen
12's name prompt, are broken by `scenes/shared/gdi_text_wrap.gd`. It applies the rule with the
face's own advances, measuring each line as the `Label` will draw it, rounding remainders
included, and hands the `Label` the finished lines with its own wrapping off. It reads every
line feed of a `Level_XX.txt` text as the file's CRLF, one pixel wider. With it, level 1's hint
fits `zauważą,` on its line as the screenshot does: that line is the body's eighth, with the
clip's whole 464 px, and the blank after the word wraps the line instead of pushing the word
down. A `Label` 460 px wide needed 469 for the word and its blank. Across the 126 bodies the
rule gives 12 one line fewer than that `Label` and none a line more, and the prompt breaks as
it did in all three languages. The titles still wrap with the `Label`'s own rule, which
centres each line (see [shell-reference.md](shell-reference.md)).

**Ink past the clip.** The port does not cut screen 16's body at the clip's right edge, x 488.
Liberation Sans reaches up to 2 px past it on five lines whose Arial the original keeps inside
it: level 1's and level 20's in Polish, level 13's in German and levels 14 and 21 in English.
A cut there would lose ink the original shows. The furthest ink ends at x 490, inside the
panel, which ends at x 496.

**The line pitch** is GDI's cell. FreeType rounds the ascent and the descent up where GDI
rounds them to nearest, which makes Godot's line one pixel taller at the top and one at the
bottom at every em a multi-line text uses: 24 for 22 at em 20, 25 for 23 at em 21, and 44 for
42 at em 38. So the theme's `Label` `line_spacing` is −2, and every line steps by GDI's
`tmHeight`. A label that centres one line in a rect lands its baseline exactly where GDI's
does, because the two extra pixels split evenly. A label whose top sits at a recovered y
draws its baseline one pixel lower than the original's. The port keeps the recovered
coordinates anyway, since 1 px is below what the screenshots can resolve.

**The copies are theme type variations** in `resources/ui_theme.tres`. Each one draws, at the
recovered offset, the colour the recovered tint leaves under a white glyph: one level below
the tint, as the screenshots show. The theme's `Label` sets `shadow_outline_size` to 0, so no
copy is thickened, not even the ones scenes draw with their own overrides:

| Variation | Stands for | Tint | Copy |
| --- | --- | --- | --- |
| `MenuTitle` | `sub_423F70`, at size 38 | (48, 48, 48) | (47, 47, 47), +3 +3 |
| `MenuButtonCaption` | `sub_422C80`, every caption on a screen's `TextureButton` | (48, 48, 48) | (47, 47, 47), +2 +2 |
| `MenuPrompt` | `sub_424D50`, the character-select name prompt | (48, 48, 48) | (47, 47, 47), +3 +3 |
| `MenuTableText` | `sub_421380`, the highscore cells | (32, 32, 32) | (31, 31, 31), +2 +2 |
| `LevelDescText` | `sub_421BA0`, screen 16's body and info, at size 21 | (32, 32, 32) | (31, 31, 31), +2 +2 |
| `ConsoleText` | `sub_45A730`, the score, the clock and the hover text | (30, 30, 30) | (29, 29, 29), +2 +2 |
| `ConsoleCaption` | `sub_45A730`, both warning captions, at size 27 | (30, 30, 30) | (29, 29, 29), +2 +2 |

The input boxes (`sound-reference.md`, `names-reference.md`, and screen 12's name box in
`scenes/screens/character_select.tscn`), the pause and quit panels
(`scenes/hud/level_prompts.gd`) and a colleague's name (`scenes/npc/npc.tscn`) draw their
copies themselves, with the same product: (31, 31, 31) under the boxes, black and
(19, 19, 19) under the panels, and (39, 9, 0) under the name, what its (40, 10, 0) tint leaves.
The texts drawn in mode 39 keep their nominal colours, white and
(250, 250, 250), one level above what the multiply leaves. No screen can tell 254 from 255,
and the 16-bit screenshots store both as the same value.

A `Label` draws its shadow from its own lines, so each copy has the text's line breaks, and a
label that clips cuts its copy at its own edge. The highscore cells clip, where `sub_421380`
moves the copy's clip 2 px down and right with it, so a title cut at its column's edge loses
up to 2 px of its copy there that the original keeps. The name prompt's copy, with its 203 px
first line, breaks where the text does in all three languages; `tests/check_ui_font.gd`
checks that it stays so.

`tests/check_ui_font.gd` pins all of this: the face and its licence, each rasterisation
setting and its importer default, the system fallback off, Arial's metrics, a glyph for every
character of every string, the rounded em for each recovered size, the line pitch against the
two measured pitches and the titles' 42-pixel cell, every variation's copy as the multiply
leaves it, which variation each scene node carries, and where the character-select title,
name prompt and portrait captions start. It also scans every script, scene and resource under
`scenes/` and `autoloads/` for anything that would bring another face or rasterisation:
Godot's fallback font, a font override, a `FontVariation`, a `SystemFont` or `LabelSettings`.
`tests/check_level_description.gd` pins the line breaks: level 1's body line for line as the
screenshot shows it, the two rooms, the kept and dropped blanks and the CR's pixel.

## Not recovered

Arial's own hinted advance widths, which GDI draws with and Liberation Sans cannot
reproduce (see "Fonts"). The em GDI picks for each cell height, and whether its antialiased
edges survive the magenta key, are settled by the reference screenshots.

Two questions this section used to hold are closed:

- **The world is drawn behind the console's transparent top edge.** `Main_RenderUpdate` fills
  800 × 510 pixels with the backdrop (`0x40291B`) and sets the world clip to renderer
  `+0x38`–`+0x44` = `(1, 1, w − 1, h − 91)` (`0x402947`–`0x402989`). In
  `images/gui/hud/console.png` the lowest pixel that is not fully opaque is on row 109, screen
  y 509: 2 pixels there, 4 on row 108, none from row 110 down. So the world shows through the
  wavy edge, and nothing below y 510 is ever uncovered. The port draws the console over the
  world, and the console is opaque from y 510 down, so the port shows nothing there that the
  original does not. See [field-of-view-reference.md](field-of-view-reference.md) for the
  frame order.
- **The camera** centres the player's ground anchor and clamps nothing at the map edges,
  which is what the port's bare `Camera2D` already does; see "The camera" in
  [widescreen.md](widescreen.md).

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

`sub_41AF60` clears 31 bytes, `player+1008` to `+1038`, when a level starts: seven dwords
with `rep stosd` from `+0x3F0`, then a word and a byte (`0x41AF88`–`0x41AFC0`). So the
player always begins empty-handed and every lamp is dark. That is why level 1's rows needing
items 9, 10, 22, 24 or 29 can never be reached: nothing on that level grants them.
`PrankController.inventory` has the same 31 slots. It used to have 28, which dropped every
grant of items 28–30 (actions 54, 137, 9 and 39) and let actions 115, 135 and 136 through
without items 28 and 29.

An ability feeds the stopwatch and the hover bar from the same fields as a prank:
`AbilityController` writes them through `PrankController`, so the console's data path does not
change. See [player-ability-reference.md](player-ability-reference.md).

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
The caption is a separate Arial 30 element, `game+14744`, at (240, 50) reading
**`Uważaj! Twoi koledzy... ojej!`**, registered as the banner's child so the two rise and
fall together. `AGGRO_UP` is the same shape — `game+14752`, built hidden at (5, 5) with the
same alpha by `sub_405930`, with its own Arial 30 child caption at `game+14756` — and it is
the **"you have been spotted" banner**: `sub_407990`
raises it the moment an agent catches the player, and it comes down 2.0 seconds later when
the minigame starts. See [catch-reference.md](catch-reference.md).

The alpha is the banner art's alone. Each caption is a `CGUIText` of its own, which
`sub_45A730` draws in mode 39, keyed and opaque, over an opaque `(30, 30, 30)` copy (the table
under "Fonts"). In the port the 220 is the banner sprite's `self_modulate`, not its
`modulate`, so the child caption and its `(29, 29, 29)` copy do not inherit it;
`tests/check_hud.gd` asserts it.

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
