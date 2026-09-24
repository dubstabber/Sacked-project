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
| 3 | 26 x 16 | 122 | 5 | 1.85 s | 8.32 ms |
| 4 | 22 x 24 | 157 | 9 | 2.27 s | 8.36 ms |
| 5 | 20 x 20 | 123 | 5 | 1.94 s | 8.33 ms |
| 6 | 32 x 12 | 130 | 11 | 2.02 s | 8.39 ms |
| 7 | 29 x 22 | 148 | 7 | 2.27 s | 8.33 ms |
| 8 | 25 x 25 | 258 | 8 | 2.70 s | 9.53 ms |

The load figure is the bake, and it tracks the composite's area rather than the object
count: level 8 carries 258 objects against level 3's 122 and costs 0.85 s more because its
map is larger, not because of them. **Frame time is flat across all of them** at about
8.3 ms, which is the 120 fps the display is capped to, and level 8 is the only map that
measurably exceeds it.

Every map also throws occasional long frames, between 10 and 47 ms, and **they are not a
property of the map**: the same level measures 10 ms on one run and 43 ms on the next, and
level 1 does it too. They are not confined to start-up either. They are sporadic, they do
not accumulate, and nothing here has tied them to the depth pipeline, so they are recorded
rather than explained.

### Clips that never stop

Level 2 is the first map with **looping** object states. Four of them ship real frames — the copier's `DESTROYED_1` (25 frames at 16 fps), the aquarium's `DESTROYED_2` (25 at 16), the projector screen's `DESTROYED_1` (17 at 16) and the stove's `DESTROYED_1` (9 at 8) — and every `DESTROYED_n` in the container carries a loop flag where no `DESTROY_n` does. The copier matters most: `sub_417B00` puts it into state 9 the first time an NPC photocopies something (only that first user ever raises it), so it loops in ordinary play with no prank involved.

The dirty-rect path above is built for a transition that ends. A clip that never ends repaints its rectangle at its own frame rate for the rest of the level, and with those four objects looping at once level 2 falls from **119.8 fps to 53.4**, with the worst frame going from 10.2 ms to 64.8 ms.

So a looping object leaves the bake. `MapObject` moves itself out of `depth_world_objects` and into `depth_composited_characters` for as long as a looping clip runs, which makes it an ordinary depth-tested actor: the shader still tests it per pixel against every other object in the static composite, two looping objects that overlap each other still resolve on the CPU exactly as two characters would, and a new frame costs a texture swap instead of a repaint. It moves back the moment the state changes. With that, the same four loops cost **119.9 fps and an 8.34 ms average** — indistinguishable from not looping at all.

**Leaving the bake does not leave the pick.** The original registers an item's click box every frame it draws the item, whatever its state (`sub_411E20` at `0x411F88`; see [player-action-reference.md](player-action-reference.md)). So every `MapObject` also joins `map_objects` (`MapObject.PICK_GROUP`) as it enters the tree and never leaves it, and `PrankController` and the F7 debug key pick from that group. When the pick read `depth_world_objects` instead, these objects could not be hovered once they looped: the copier after ASSCOPY, the radio, the stove and the aquarium after their pranks, and the copier while its first NPC user photocopied. The pointer over the looping stove even fell through to the dishwasher behind it.

**The focus highlight follows the object off the bake.** The original draws its pulsing copy right after the item and Z-buffered (`sub_411E20`), so the pulse lands exactly on the item's visible pixels and everything drawn later covers it. The port's `FocusHighlight` is an internal child at the front of `World`, one z above the layer the object is drawn on:

- **Over a baked object it sits at z 1.** It draws above the static composite, and every character at z 1 still covers it, because characters are ordinary children and ordinary children draw after internal-front ones.
- **Over an actor it sits at z 2.** That puts it above the actor's own sprite and above the character compositor's cluster surfaces, and it still draws before the thought bubbles at z 2. The surfaces are internal children at the back of `World`, so at z 1 they would draw over anything else on that layer.

The world depth test is unchanged. At z 2, though, the copy is also above every character, so it tests them as well. A looping object that overlaps a character is composed with it on a CPU surface, and its own sprite is hidden. `CharacterDepthCompositor.cluster_depth_for(sprite)` returns that surface's composed scores as an R32F texture, the same encoding as `depth_texture`, together with the surface's bounds. The texture is built only when asked for, and only after the surface has been recomposed. `object_highlight.gdshader` discards a pixel whose own score is below the surface's; a tie is the object's own pixel, as in the world test. The compositor runs after the player every frame, so it emits `composed` once it has drawn its surfaces, and the controller reads the scores again at that point. The test is therefore never a frame behind the surface on screen. An actor that overlaps no character needs no second test, because clusters form wherever opaque rectangles meet, so nothing else shares its pixels.

This was measured in a window at 800 × 600, with the NPCs frozen and the pulse's alpha held at 200. Each changed pixel was classified by the two sprites' own depth planes:

- **Copier after ASSCOPY, clean stand:** 6896 px lit.
- **Copier, clustered stands:** it clusters with the player at 8 of its 15 reachable stands. There it lit 5706–6896 px where it is in front and **0 px** where the player is. With the cluster test forced off, the same stands put 3783 px of copier on the player.
- **Radio, stove and aquarium:** they cluster at 4, 13 and 14 stands. They lit 0 px on the player in front at every one of them, against 120, 4979 and 11537 px with the test off.

`tests/check_looping_object_focus.gd` pins the pick, the layer and the cluster test.

Characters are tested against that buffer on the GPU. `CharacterDepthCompositor` gives every character sprite a `ShaderMaterial` running `scenes/shared/character_depth.gdshader`, which decodes the sprite's own depth plane, compares `base_y - pixel_depth` against the static score at the same world pixel, and discards the fragment when the world is in front. The shader snaps its quad to whole pixels and samples with nearest filtering so the result matches the original's integer blitter. Because the static composite is one sprite drawn after the characters, shaded character sprites sit one z-index above it.

Two characters whose opaque rectangles overlap cannot resolve each other this way — a 2D canvas has no shared depth buffer — so each connected overlap group still composites on the CPU, onto its own surface and bounded by that group alone. A character that overlaps nobody costs no CPU compositing at all. All rendering stays in Godot's 2D canvas.

To verify runtime masks against the extracted source planes, run `python3 tools/export_world_depth_maps.py --check`. Without `--check`, that tool exports the object masks and wall atlas mask the imported levels need. It only reads the reference extraction. The original glass sprites have no extracted Z plane; glass is not part of this depth-mask pipeline.

### The floor is one opaque mosaic

The original draws the floor before anything else: `Main_RenderUpdate` (`0x4028C0`) calls `sub_4120A0` for layer 0 at `0x40298C`. For that layer `sub_4120A0` sets `ctx+0x30 = 1` (`0x412126`), projects each cell relative to the camera, truncates the result to whole pixels (`_ftol` at `0x4122AF`–`0x4122BB`) and hands it to `sub_42D780`, which subtracts the pivot. Because `ctx+0x30` is set, `sub_42CCF0` routes the tile to `sub_42D210` and the dedicated floor blitter `sub_458DC0`. That blitter copies each of the tile's 48 rows through the palette as one opaque span. The spans come from the table at `0x471C34`, `(46, 2), (44, 6) … (0, 94), (0, 94) … (46, 2)`, 2304 pixels in all, and the blit uses no colour key, alpha, Z or scaling. Every tile in `images/floor/sacked-floors.png` has exactly that alpha, and at the 48/24 pitch the spans of neighbouring cells meet with no gap and no overlap. So the original's floor is one opaque mosaic in one backbuffer.

A `TileMapLayer` draws each cell as its own 94 × 48 quad instead. Whenever the texel grid misses the pixel centres, the two quads on either side of a staircase edge are sampled separately. That happens at any non-integer `canvas_items` stretch, such as 1.67× at 1920 × 1004, and at any fractional camera offset. With the inherited linear filter the two quads get partial alphas `a` and `1 − a`, so up to a quarter of the navy clear colour shows along every diamond edge. That comes to about 22 700 px a frame at 1920 × 1004. Nearest filtering alone leaves full clear-colour dots wherever a row of pixel centres lands on a texel boundary, for example at 1440 × 900, at an exact 2× and at 800 × 600 with a half-pixel camera. Snapping transforms or vertices, dropping texture padding and rounding the camera don't remove them either.

So `scenes/shared/floor_tile_layer.gd`, which `tools/build_level_scene.gd` attaches to every level's `FloorTileMapLayer`, does four things on `_ready`:

- It bakes the used cells into one RGBA image, masked by the atlas alpha so each diamond is copied whole and alone.
- It shows that image as an internal `Sprite2D` at the cells' whole-pixel origin.
- It draws the sprite with nearest filtering, like the walls, objects and characters.
- It turns off the layer's own drawing.

The cell data stays: `get_used_cells`, `map_to_local` and `get_cell_source_id` answer as before. In the editor the script does not run, so the layer still paints and draws its cells there. The floor is assumed static. Nothing sets a cell at runtime, and a cell set after `_ready` would not show.

At an integer scale the bake is pixel-identical to a nearest-filtered per-cell draw. At a non-integer scale the floor is now as crisp as the walls and characters, and it shimmers as much as they do while scrolling, where before it was blurred.

Seams were measured with the regenerated scenes, counting a seam as a pixel inside the map whose colour changes between a black and a white clear colour:

- **With the bake:** 0 seam pixels on levels 1 and 3. That held at 1920 × 1004, 1600 × 1006, 1440 × 900, 800 × 600 and an exact 2×, over a 5 × 5 grid of fractional camera offsets and during keyboard walks.
- **Per-cell draw:** 201 010 px over nine frames at 1920 × 1004.

The bake costs 12–37 ms per level load headless, or 16–41 ms with the texture upload, and 4–11 MB of texture. `tests/check_floor_bake.gd` pins the data: one internal sprite, every cell's rows equal to its atlas tile, and 2304 opaque pixels per cell. Seams themselves only show in a real render, so their measurement stays manual.

### Records left out of the scene

The original keeps every `ITEM` wherever it stands. The loader has no bounds test, and an item is culled only against the camera rectangle; see [widescreen.md](widescreen.md) for the addresses. Level 3's `LEVEL_02.col` `ITEM22` is a spare `MONITOR&TASTATUR#FRONTAL` standing five tiles off the map at (−5, 16). The original's 800 × 600 view never shows more than a ~10 px sliver of it, but the port's wider canvas shows the whole thing floating in the void.

`PARKED_RECORDS` in `tools/import_original_level.py` therefore lists that record, keyed by file and record name to its kind and position. The importer raises if the record ever stops matching. The record stays out of the manifest's `objects` and is listed under `parked_items` instead; only a manifest that parks something carries that key. `build_npcs` still runs over every item, as `sub_4185B0`'s startup search does, and the importer raises if a parked item would be an NPC's desk or chair.

Only three records in the campaign fail the original's own map lookup (`sub_4187F0` → `sub_412AE0` on the truncated `x + 0.5`, `y + 0.5`): this monitor, its copy in `LEVEL_02s.col`, and `LEVEL_10s.col` `ITEM132`. `ITEM132` is a pack of cigarettes the original shows whole at 4:3, so it stays. The other 224 records past an edge are wall-hung and overhang by at most a third of a tile. `tests/test_level_import.py` pins that census.

See [map-authoring.md](map-authoring.md) for creating maps with the Godot editor.
