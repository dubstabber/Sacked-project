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

`WorldDepthCompositor` builds the static color image and depth buffer from the current scene's objects and wall tiles. It caches the result until placement, visibility, or asset selection changes. Its preview is a transient child, so generated images and hidden-source render flags are not saved into authored scenes. `CharacterDepthCompositor` compares each character pixel with the static depth buffer and other characters. All rendering stays in Godot's 2D canvas.

To verify runtime masks against the extracted source planes, run `python3 tools/export_world_depth_maps.py --check`. Without `--check`, that tool exports the 64 object masks and wall atlas mask used by level 1. It only reads the reference extraction. The original glass sprites have no extracted Z plane; glass is not part of this depth-mask pipeline.

See [map-authoring.md](map-authoring.md) for creating maps with the Godot editor.
