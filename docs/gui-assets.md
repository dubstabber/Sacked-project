# GUI and effect sprite export

`tools/export_gui_assets.py` copies original GUI and effect sprites into `images/`. It
decodes the raw chunks rather than picking one of the ~18 speculative variant PNGs the
extraction writes beside each sprite, because those variants were produced before the
channel order was known and several are wrong.

## Decoding

Every sprite folder has `SPRITEHDR.json` with its width, height and bit depth.

**8bpp** — `SPRITECB8.bin` holds one palette index per pixel (`len == width * height`, no
row padding) and `SPRITEPAL.bin` holds 256 `[R, G, B, 0]` quads. The fourth byte of a quad
is padding. Transparency is a colour key on **palette index 255**, not on a colour: only
163 of the 224 8bpp sprites have magenta at index 255, and the rest use white, green, blue
or black, so keying on the colour would punch holes in them. Keyed pixels keep their
palette colour with alpha 0, which is what the hand-copied files did.

This rule reproduces all 33 GUI images that were copied out by hand before this tool
existed, pixel for pixel.

**32bpp** — `SPRITECB.bin` holds four bytes per pixel in **(R, G, B, A)** order. The proof
is `CO_EFFECT_FEUER_PALETTE`, a 256-entry fire ramp: read this way its entries run
`(199,16,4)` red → `(252,252,51)` yellow → `(254,254,233)` white with a rising alpha, and
any other order turns the ramp blue. 47 of the 50 true-colour sprites carry a genuine
graded alpha, including the character shadow's fade-out tail.

One sprite, `CO_GUI_CONSOLE_CLOCK_FULL`, stores zero in the alpha byte of every pixel — the
same unused pad the palette quads carry — so the exporter forces it opaque. A sprite that
needs a colour key instead names one in `COLOUR_KEYS`; none does yet.

## A fixed bug

`images/gui/screens/menu_background.png` was a byte copy of the extraction's unsuffixed
32bpp PNG, which mistook the first byte for alpha and produced alpha 0 on all 640 000
pixels. The main menu referenced it and drew no background at all. The exporter now owns
that file and re-exports it opaque.

## Bitmap font strips

Both strips are 8bpp and are exported whole; slicing belongs to whatever draws them.
Measured from the decoded pixels, because neither divides evenly:

**`images/gui/hud/numbers.png`** (from `CO_GUI_CONSOLE_NUMBERS`, 14×280) holds **eleven**
glyphs, not ten — the extra one is a second zero, which an odometer-style roll needs. Each
glyph is 16 px tall and 8 px wide (x 3..10), except the `1`, which is 2 px wide (x 6..7).
The glyph tops are y = 1, 26, 51, 77, 101, 126, 151, 176, 202, 227, 252, so the pitch
varies between 24 and 26 px and a fixed cell height would shear every glyph from the third
on. The strip is a **single-colour mask**: every opaque pixel is `(0, 0, 0)`, while the
original screenshot shows white digits with a dark edge, so the console colours this at
draw time. There is no `:` glyph, yet the HUD shows a clock as `00:11`.

**`images/gui/fonts/score-digits.png`** (from `CO_EFFECT_FONT_SCORE`, 312×32) is **13 cells
of 24 px**, indexed by `character - 0x2D`: cell 0 is `-`, cells 1 and 2 (`.` and `/`) are
blank, and cells 3..12 are `0`..`9`. Glyph content is inset and variable width (16–22 px).
Unlike the console digits this one is full colour, a golden gradient with 237 distinct
colours. The `-` glyph implies score popups can be negative.

## Naming

Destinations drop the archive prefix, split the CamelCase runs and lower-case the result,
so `CO_GUI_ACTICON_AbstraktNehmen` becomes `images/gui/acticons/abstrakt-nehmen.png`. The
executable spells the same icon `CO_GUI_ACTICON_ABSTRAKTNEHMEN`, so
`tools/export_action_table.py` joins the two case-insensitively and records the resulting
path as each action's `icon_image`.

## The console

`images/gui/hud/console.png` (800×200) matches the original screenshot: the player portrait
at the far left, the `czas` and `wynik` labels, a square cut-out field between them, a wide
cut-out bar along the bottom for hover text, the thermometer, the stopwatch, and **three**
round lamp slots. Three is also how many lamp sprites the executable references — smoke,
urination and the Matrix pill — so `EDDING_ACT` and `FIRE_ACT` ship unused and are not
exported. The top edge is transparent and wavy; the world is visible above it.
