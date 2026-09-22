# Wide-screen

The original runs in a fixed 800 × 600 viewport and every GUI coordinate in
[hud-reference.md](hud-reference.md) and [gui-assets.md](gui-assets.md) is absolute within
it. This port deliberately diverges: **the canvas stays 600 logical pixels tall and grows
sideways with the window.** This is the first port-side divergence that changes what the
player sees, so what follows separates what is recovered from what the port decided.

## The canvas

`project.godot` sets a base viewport of 800 × 600, `window/stretch/mode="canvas_items"` and
`window/stretch/aspect="expand"`. Expand keeps the base as a **minimum in both axes** and
grows whichever one the window has room for:

| Window | Canvas | Notes |
| --- | --- | --- |
| 800 × 600 (4:3) | 800 × 600 | the original's own shape; everything is pixel-identical to a fixed build |
| 1920 × 1080 (16:9) | 1067 × 600 | 267 extra logical pixels of width, scaled 1.8× |
| 1280 × 1024 (5:4) | 800 × 640 | 40 extra logical pixels of height |

The rule is `canvas = (600 × aspect, 600)` while the window is wider than 4:3, and
`(800, 800 / aspect)` while it is taller. Measured: a 1920 × 1006 window (1080p with the
desktop panel taking the rest) reports a canvas of 1145 × 600, and 1280 × 1006 reports
800 × 628 — both exactly what the rule gives. A window manager may clamp a requested size,
so check the canvas rather than the window when verifying.

`canvas_items` rather than `viewport`: at 1.8× the pre-rendered art is resampled unevenly
either way, and `viewport` would additionally pixelate every label and the name field, which
currently render at the window's true resolution. The original had the same problem — a
screenshot of it on a 1920 × 1080 display is a 1440 × 1080 pillarbox, i.e. the same
non-integer resample. `scale_mode="integer"` is not used because it would snap 1080p back to
1× and defeat the 600-tall decision. If scroll shimmer ever becomes objectionable, the knob
to try is `rendering/2d/snap/snap_2d_transforms_to_pixel`; the shaders' own `pixel_snap`
works in world space and does not help here.

**Off-map colour.** A wider canvas shows more of the void past a map's edges, so
`rendering/environment/defaults/default_clear_color` is set to `(16, 16, 74)`. That is not a
guess: it is the uniform colour of the off-map area in a reference screenshot of the
original at 1920 × 1080, sampled inside the pillarbox at (300, 20) and (250, 100), and it is
the fourth most common colour in that image at 59 159 pixels. What DirectDraw call produces
it is not recovered.

## Two bands carry the HUD

`scenes/hud/console.tscn` keeps its `CanvasLayer` and gains two 800 × 600 `Control` bands.
`Band` is anchored to the bottom centre and holds everything the original bottom-docks with
frame flag 8; `Banners` is anchored to the top centre and holds the two full-plate banners,
which the original places with flag 0. Every recovered offset inside them is unchanged. The
flag-to-anchor mapping is tabulated in [hud-reference.md](hud-reference.md).

Both bands are `MOUSE_FILTER_IGNORE`. This is load-bearing: a `STOP` control covering
800 × 600 would swallow every click before the prank controller and the player see it.

The banners are **never scaled**. `thermo-up.png` and `aggro-up.png` are a starburst in the
upper left plus a horizontal ribbon on an otherwise transparent 800 × 600 plate, not a
full-screen tint, so stretching them to a wider canvas would pull the ribbon away from the
caption sitting on it.

## Derived rather than pinned

Two recovered constants are centres, and a centre cannot stay a constant on a canvas whose
width moves:

- The ring menu's `(400, 200)` from `sub_406510` is the centre of the band the console
  leaves free, so `round_menu.gd` derives it as `(width / 2, (height − 200) / 2)`. At 4:3
  that is exactly `(400, 200)`.
- The pause and quit panels are recovered at x 49..750 and centre their text on x 400.
  `level_prompts.gd` shifts both by half the added width and centres text on the live width,
  keeping the recovered widths and y positions.

## Art screens: a safe frame in a black margin

Every screen built from 4:3 art centres its existing absolute layout inside a `SafeFrame`, a
`Control` anchored to the middle of the canvas at exactly 800 × 600 with its pointer ignored.
Nothing inside it moves. Behind it sits `Margin`, a full-rect black `ColorRect`, also ignoring
the pointer. It is a scene convention rather than a shared script, because anchors already
express it and two nodes do not need an abstraction.

**Black is the original's own answer.** A screenshot of the original's loading screen on a
1920 × 1080 display (`sacked-reference-images/`, gitignored and local) shows it pillarboxed:
the 4:3 frame centred at 1440 × 1080 with plain black either side. The port expands the
canvas rather than pillarboxing it, but for a screen whose art stays 4:3 the margin is the
same thing, so it is the same colour.

The first attempt filled the margin with a covered, dimmed copy of the screen's own art. It
was wrong twice over: it diverged from the original for no reason, and on the boot screen it
reproduced the hand-lettered title and the publisher logo legibly down both sides, reading as
a rendering fault. Dimming it far enough to destroy the lettering left it indistinguishable
from black anyway.

Note that the margin is **not** the same colour as the world's off-map void. Inside the
original's 4:3 frame the area past the edge of a map is the navy `(16, 16, 74)` set as the
clear colour above; black is only what lies outside the frame. The level expands rather than
pillarboxing, so it uses the navy and never the black.

This applies to `boot_loading`, `main_menu`, `character_select`, `level_tree`,
`level_description`, `level_result` and `highscores` today, and to every screen built later.

**One visible change at 4:3.** The main menu's background art is 800 × 800 and was being
letterboxed into an 800 × 600 rect, leaving bars down both sides. It now covers that rect,
showing the centre crop at 1:1. Where the original placed this sprite is an open question
below.

## Unchanged

The camera and the depth pipeline needed nothing. The camera is a bare `Camera2D` on the
player with no limits; the world depth composite is a full-map bake in world space with no
viewport coupling, and `character_depth.gdshader` indexes it by world pixel, never by
`SCREEN_UV`. A wider view costs more rasterisation and lets more objects animate at once,
but it cannot change what is occluded. The movement cursor already warps through the live
canvas transform, and both mouse-picking paths already invert it.

## Open questions

Filed rather than guessed, in the order they matter:

1. **The camera's edge clamp.** `CIsoCamera` is named but its rule is unrecovered
   (`game+12744` is the camera, `game+14700` its follow target, bit `0x200` makes it follow
   the player). A clamp derived from the depth composite's bounds would be wrong twice over:
   the rule is not recovered, and those bounds are the object extent rather than the floor's.
   The port stays unclamped. Note that the reference screenshot puts the player at roughly
   (394, 267) in 800 × 600 space rather than dead centre, so either a follow offset or a
   clamp is in play. Godot pins to `limit_left`/`limit_top` when the viewport is wider than
   the limited span, which a 1067-wide canvas would hit on narrow maps.
2. **Where the original places `CO_GUI_SCREENS_MENU_BACKGROUND`.** Its `+8`/`+12` and
   `+1140` in the screen-3 builder decide whether the 800 × 800 swirl is centre-cropped or
   top-aligned. The port centre-crops.
3. **The DirectDraw clear colour** behind the sampled `(16, 16, 74)`.

## Verifying

`tests/check_widescreen.gd` drives the console, the ring, the prompts and all four art
screens at 800 × 600, 1067 × 600 and 800 × 640, and asserts each one keeps a black margin behind its frame. The headless root window reports no size, so
each fixture is mounted in a `SubViewport` of its own.

In the running game:

```bash
./Godot_v4.7.2-stable_linux.x86_64 .                      # 4:3, then F1 for fullscreen
./Godot_v4.7.2-stable_linux.x86_64 . --resolution 1067x600
./Godot_v4.7.2-stable_linux.x86_64 . --resolution 800x640
```
