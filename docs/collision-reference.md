# Original collision behavior

Verified against a disposable copy of `sacked.exe.i64` on 2026-09-17. The original executable and database were not modified. These findings supersede the older speculative sprite-AABB discussion in the extracted sprite documentation.

## Static collision data

The `INFODATA` record in each original level contains one little-endian 32-bit value per map cell, indexed as `x + width * z`. `sub_412320` allocates this buffer at map offset `+36`; `sub_412FB0` loads the record into it. `sub_412AE0` reads it:

| Query mode | Returned data | Observed use |
| --- | --- | --- |
| `1` | Bit 0 | Movement blocking |
| `2` | Bit 1 | Line-of-sight / interaction ray blocking |
| `4` | Bits 16–23 | Area / room identifier |
| Other | Entire 32-bit value | Raw cell data |

Out-of-bounds queries return zero. The original relies on authored blocking cells around the playable area; this accessor does not manufacture an impassable boundary.

This is a logical occupancy grid. A wall or piece of furniture does not collide according to its PNG rectangle or its per-pixel rendering depth mask. Small items can sit on furniture without introducing a second collision obstacle. Runtime movement reads the saved occupancy grid; the object factory at `sub_410550` does not derive collision geometry from sprite dimensions.

`LEVEL_00` has 117 movement-blocking cells and 92 visibility-blocking cells in its 16 × 16 buffer. Its wall layer contains 88 occupied cells, including two in the otherwise unused right-hand padding at `(15, 6)` and `(15, 8)`. Preserve the complete source buffer even when only 15 × 15 cells contribute to the visible floor. The remaining 29 movement blockers have no wall tile. Cell `(8, 3)` blocks visibility but permits walking; doorway cells `(3, 4)` and `(4, 4)` permit walking while the adjacent wall cell `(5, 4)` blocks it.

Object-definition offset `+520` contains a value that resembles an editor placement bitmap, but the inspected runtime factory does not consume it and the saved level does not consistently stamp every nonzero value. For example, the plant item at `(0.666667, 4.75)` and cabinet at `(0.833333, 7.583333)` have nonzero values there, while their rounded anchor cells `(1, 5)` and `(1, 8)` are traversable. The saved `INFODATA` grid remains authoritative; deriving prefab footprints from that field requires further evidence.

The floats at object-definition offsets `+536` and `+540` are not obstacle dimensions. The factory rotates them and stores them at entity offsets `+208` and `+212` through `sub_410010`; `sub_410030` uses them for the interaction position. Do not interpret them as furniture width and depth.

## Coordinates and character footprint

The ground plane is the original logical X/Z plane, projected by `sub_41A2D0`:

```text
screen_x = 48 * (x - z)
screen_y = 24 * (x + z)
```

The static collision pass adds `(0.5, 0.5)` to old and requested logical positions before selecting cells. Therefore cell `(i, j)` occupies `[i - 0.5, i + 0.5] × [j - 0.5, j + 0.5]` in the original ground coordinates. It projects to a diamond centered on `project(i, j)`, with vertices `(0, -24)`, `(48, 0)`, `(0, 24)`, and `(-48, 0)` relative to that center. The half-cell shift belongs to grid indexing, not to an extra displacement of the character's collision anchor.

`sub_4019D0` uses a character clearance of **0.35 logical tiles on each axis**, and resolves contact at **0.36 tiles** to leave a small separation. The corresponding square footprint projects to a diamond extending 33.6 pixels horizontally and 16.8 pixels vertically from the character's ground anchor. This footprint is independent of animation frame, facing, texture dimensions, and sprite pivot.

## Movement response

`sub_402590` advances entities through virtual update offset `+32`, then calls `sub_4019D0` to resolve collisions. The static branch applies to entities with the flag at `+100` set to one. Player initialization at `sub_41AF60` enables this flag.

The original static resolver:

1. Reads old position from entity offsets `+32/+36/+40` through `sub_42B310`, and requested position from `+20/+24/+28` through `sub_42B370`.
2. Adds `0.5` to both ground coordinates, then visits the integer cells along the old-to-new path with `sub_412B50`.
3. For each visited cell, gathers movement-blocking bits in its 3 × 3 neighborhood. Bit order is row-major: top-left `1`, top `2`, top-right `4`, left `8`, center `16`, right `32`, bottom-left `64`, bottom `128`, bottom-right `256`.
4. Uses movement-line intersections with the cell's four sides (`sub_401880`) to determine the approached boundary. Tests include the 0.35-tile clearance around side endpoints.
5. Clamps the obstructed logical coordinate 0.36 tiles inside the free cell while retaining the other requested coordinate, producing sliding along the original X/Z axes. Diagonal neighbors receive explicit corner checks. The center bit has no direct correction branch.
6. Subtracts `0.5` and writes the corrected position through `sub_42B330`.

Projected screen-space physics has a different sliding metric from logical X/Z collision resolution because the isometric transform changes angles. A port using screen-space physics should acknowledge that response difference even when its projected footprints match.

`scenes/shared/grid_collision.gd` implements these neighborhood, line-intersection, and coordinate-clamping rules in logical coordinates. It splits requested motion into steps of at most 0.25 tiles per axis so large physics ticks cannot jump past blockers. This subdivision is a port robustness measure, not a recovered original constant. Each step still uses the recovered 0.35/0.36 clearances and checks crossed cells. The helper also uses `floor(position + 0.5)` to support authored maps at negative coordinates; the original positive-coordinate maps use truncating integer conversion after adding 0.5.

The walking routine at `sub_41B0C0` selects walking animation and footstep sound from requested input before this collision pass. Holding movement into a wall therefore keeps the original walking animation and footsteps active. The original player speed is initialized to 3.0 logical units per second at `sub_41AF60`; changing the port's current movement speed is a separate concern from adding collision.

## Other collision-related behavior

The earlier branch in `sub_4019D0` handles entity proximity for entities with flag `+104` set. It collects nearby entities within 0.7 logical units and calls virtual method `+40`. The player initializes `+104` to zero, so that branch does not establish ordinary player-to-NPC blocking. Static collision support alone is not evidence for making all characters solid to each other.

`sub_412E30` traces interaction visibility using bit 1. It walks a line in quarter-cell increments, converts each sample back to a full cell with a right shift by two, and stops when that cell blocks visibility. Movement and interaction visibility are distinct flags; a future interaction system should retain that distinction.
