# Map placement and 2D depth masks

The original floor art is 94 × 48 pixels, but the grid pitch is **96 × 48**. At a tile coordinate `(x, y)`, the original renderer projects to `(48 * (x - y), 24 * (x + y))`. Godot's diamond-down TileMap adds a common cell-center offset of `(48, 24)`. Object positions use the same axes, including fractional tile positions. Sprites keep their original signed pivots; their top-left is the projected anchor minus the pivot.

This was verified against the original executable's tile renderer `0x4120A0`, entity projection `0x41A2D0`, and sprite placement `0x42D780`. The screenshot `/home/ydro/Downloads/debug1.png` independently agrees: the boss desk, trophy, filing cabinet, flipchart, and kitchen fixtures align using 48-pixel horizontal steps. The previous 47-pixel steps accumulated horizontal drift.

`SPRITEZB` stores an unsigned 16-bit depth for each sprite pixel. Runtime `*-depth.png` files preserve it as `R + 256 * G`; alpha marks valid pixels. The original blitter `0x42ECC0` adds that value to a base Z and keeps the smaller result, with later pixels winning ties. Entity base Z is `trunc(49152 - projected_y / 2)`; wall base Z is `trunc(49188 - projected_y / 2)`. The equivalent comparison used here keeps the larger score:

```
object/character: ceil(int(anchor_y) / 2) - pixel_depth
wall:             ceil(int(anchor_y) / 2) - 36 - pixel_depth
```

The original computes projection relative to its camera before truncation. This port uses stable world-space rounding, so camera movement does not change depth ties. It can differ from the original by one depth unit at a rounding boundary.

The original draws wall cells in row order, map objects in their ITEM insertion order, then characters (`0x4028C0`, `0x411E20`, `0x412FB0`, `0x410550`). The port preserves this order for equal-depth pixels. There is no Y sort of whole sprites.

`WorldDepthCompositor` builds the static color image and depth buffer from the current scene's objects and wall tiles. It caches the result until placement, visibility, or asset selection changes, and rebuilds only when the scene signals a change rather than on a timer. Its preview is a transient child, so generated images and hidden-source render flags are not saved into authored scenes. Alongside the CPU score array it publishes `depth_texture`, the same scores as a single-channel `FORMAT_RF` image.

### Repainting only what changed

Composing level 1 from scratch walks about 1.2 M pixels and takes roughly **600 ms**, which is fine once on load but not once per frame of a prank's transition. A change therefore repaints in place: each actor's covered rectangle and change signature are remembered, the union of every removed, added and changed rectangle is recomposed from the actors that intersect it, and the result is blitted into the kept color and score images. A pixel depends only on the actors covering it and on their order, so the patched buffer is byte-identical to a full recomposite — `tests/check_world_depth_incremental.gd` asserts exactly that for all eight of level 1's multi-frame clips and for a removed object.

The whole buffer is still recomposed when its bounds would grow, when the actors' relative order changes, when the image caches are dropped, or when more than half of it is dirty. Bounds are never shrunk, because the remembered rectangles are relative to the buffer's origin.

Measured on level 1: **about 16 ms per state swap**, peaking near 26 ms for the Colamat's large frames, against a 125 ms frame interval for an 8 fps clip. Roughly 10 ms of that is the per-pixel compose itself (a dirty rectangle of ~10 k pixels covered by six actors, so ~19 k pixel visits), about 3.5 ms is republishing the CPU score array, and the rest is collecting actors and computing the dirty rectangles. Godot 4.7 has no partial texture upload, so both images are re-uploaded whole.

In the running game, with those uploads included, a transition does not change the average frame time — 8.1 ms both idle and while the Colamat plays — and costs one longer frame per swap, 27 ms for the Colamat and 38 ms for the 33-frame Pappaufsteller. So a prank drops at most a frame here and there at 60 fps instead of freezing the game for most of a second.

Level 2 is the first map large enough to test that scaling. It is 17 × 32 tiles against level 1's 16 × 16, so its composite spans 2256 × 1128 px — **2.54 MP against 1.04 MP** — and it carries 167 objects rather than 71. Both images are still far inside the 4096 px limit; the widest map in the campaign reaches 2880 px. Measured over 600 frames with the brains running, level 2 holds **98.7 fps with an 11.1 ms worst frame**, against level 1's 107.6 fps and 14.2 ms, so the larger composite costs startup time rather than frame time.

Levels 3 to 8 confirm that on six more maps. Each was loaded in a 1067 x 600 window and
left running for eight seconds with its whole cast awake:

| Level | Tiles | Objects | Agents | Load to first frame | Mean frame |
| --- | --- | --- | --- | --- | --- |
| 1 | 16 x 16 | 71 | 3 | 1.37 s | 8.33 ms |
| 2 | 17 x 32 | 167 | 6 | 2.31 s | 8.36 ms |
| 3 | 26 x 16 | 123 | 5 | 1.85 s | 8.32 ms |
| 4 | 22 x 24 | 157 | 9 | 2.27 s | 8.36 ms |
| 5 | 20 x 20 | 123 | 5 | 1.94 s | 8.33 ms |
| 6 | 32 x 12 | 130 | 11 | 2.02 s | 8.39 ms |
| 7 | 29 x 22 | 148 | 7 | 2.27 s | 8.33 ms |
| 8 | 25 x 25 | 258 | 8 | 2.70 s | 9.53 ms |

The load figure is the bake, and it tracks the composite's area rather than the object
count: level 8 carries 258 objects against level 3's 123 and costs 0.85 s more because its
map is larger, not because of them. **Frame time is flat across all of them** at about
8.3 ms, which is the 120 fps the display is capped to, and level 8 is the only map that
measurably exceeds it.

Every map also throws occasional long frames, between 10 and 47 ms, and **they are not a
property of the map**: the same level measures 10 ms on one run and 43 ms on the next, and
level 1 does it too. They are not confined to start-up either. They are sporadic, they do
not accumulate, and nothing here has tied them to the depth pipeline, so they are recorded
rather than explained.

### Clips that never stop

Level 2 is the first map with **looping** object states. Four of them ship real frames — the copier's `DESTROYED_1` (25 frames at 16 fps), the aquarium's `DESTROYED_2` (25 at 16), the projector screen's `DESTROYED_1` (17 at 16) and the stove's `DESTROYED_1` (9 at 8) — and every `DESTROYED_n` in the container carries a loop flag where no `DESTROY_n` does. The copier matters most: `sub_417B00` puts it into state 9 whenever an NPC photocopies something, so it loops in ordinary play with no prank involved.

The dirty-rect path above is built for a transition that ends. A clip that never ends repaints its rectangle at its own frame rate for the rest of the level, and with those four objects looping at once level 2 falls from **119.8 fps to 53.4**, with the worst frame going from 10.2 ms to 64.8 ms.

So a looping object leaves the bake. `MapObject` moves itself out of `depth_world_objects` and into `depth_composited_characters` for as long as a looping clip runs, which makes it an ordinary depth-tested actor: the shader still tests it per pixel against every other object in the static composite, two looping objects that overlap each other still resolve on the CPU exactly as two characters would, and a new frame costs a texture swap instead of a repaint. It moves back the moment the state changes. With that, the same four loops cost **119.9 fps and an 8.34 ms average** — indistinguishable from not looping at all.

Characters are tested against that buffer on the GPU. `CharacterDepthCompositor` gives every character sprite a `ShaderMaterial` running `scenes/shared/character_depth.gdshader`, which decodes the sprite's own depth plane, compares `base_y - pixel_depth` against the static score at the same world pixel, and discards the fragment when the world is in front. The shader snaps its quad to whole pixels and samples with nearest filtering so the result matches the original's integer blitter. Because the static composite is one sprite drawn after the characters, shaded character sprites sit one z-index above it.

Two characters whose opaque rectangles overlap cannot resolve each other this way — a 2D canvas has no shared depth buffer — so each connected overlap group still composites on the CPU, onto its own surface and bounded by that group alone. A character that overlaps nobody costs no CPU compositing at all. All rendering stays in Godot's 2D canvas.

To verify runtime masks against the extracted source planes, run `python3 tools/export_world_depth_maps.py --check`. Without `--check`, that tool exports the object masks and wall atlas mask the imported levels need. It only reads the reference extraction. The original glass sprites have no extracted Z plane; glass is not part of this depth-mask pipeline.

See [map-authoring.md](map-authoring.md) for creating maps with the Godot editor.
