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

Characters are tested against that buffer on the GPU. `CharacterDepthCompositor` gives every character sprite a `ShaderMaterial` running `scenes/shared/character_depth.gdshader`, which decodes the sprite's own depth plane, compares `base_y - pixel_depth` against the static score at the same world pixel, and discards the fragment when the world is in front. The shader snaps its quad to whole pixels and samples with nearest filtering so the result matches the original's integer blitter. Because the static composite is one sprite drawn after the characters, shaded character sprites sit one z-index above it.

Two characters whose opaque rectangles overlap cannot resolve each other this way — a 2D canvas has no shared depth buffer — so each connected overlap group still composites on the CPU, onto its own surface and bounded by that group alone. A character that overlaps nobody costs no CPU compositing at all. All rendering stays in Godot's 2D canvas.

To verify runtime masks against the extracted source planes, run `python3 tools/export_world_depth_maps.py --check`. Without `--check`, that tool exports the 64 object masks and wall atlas mask used by level 1. It only reads the reference extraction. The original glass sprites have no extracted Z plane; glass is not part of this depth-mask pipeline.

See [map-authoring.md](map-authoring.md) for creating maps with the Godot editor.
