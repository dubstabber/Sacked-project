# Original movement and NPC behavior

Verified on 2026-09-17 using a disposable copy of the original IDA database. Addresses refer to the shipped `sacked.exe`; the original executable and database were not modified.

## Movement units and speeds

Movement speed is measured in logical ground-plane tiles per second. The original projection is `screen = (48 * (x - z), 24 * (x + z))`. Normalize direction in logical X/Z space, apply speed there, then project the resulting velocity. Normalizing the projected screen velocity would make movement speed depend on direction in the map.

The player initializer `sub_41AF60` stores `3.0` at entity offset `+56`. `sub_41B0C0` selects a direction from the table at `0x46B424`, copies it through `sub_42B3B0`, and passes `speed * delta_time` to `sub_42B3E0`. Cardinal logical directions use components `0` and `±1`; logical diagonals use `±0.707000017`. This approximates a unit-length diagonal rather than moving at full speed on both axes. There is no subsequent screen-space normalization. Using an exact normalized diagonal differs from the original rounded constant by about 0.015%.

At speed 3, a logical cardinal direction projects to `(±144, ±72)` pixels per second. Horizontal screen movement projects to approximately `203.616` pixels per second; vertical screen movement is approximately `101.808` pixels per second. These different projected speeds are intentional consequences of the isometric transform.

NPC class initializers write preliminary speeds, then `sub_4184B0` overwrites them with the actual profile table at `0x46E7D8`. Each of its seven records contains eleven floats. The first float is the speed; it is stored at both `+56` (current speed) and `+1852` (base speed).

| Character | Original spawn ID | Profile record | Base tiles/second |
| --- | --- | --- | --- |
| Boss (`CHEF`) | 1 | 0 | 1.8 |
| Secretary (`SEKRETAERIN`) | 2 | 1 | 1.8 |
| Janitor (`HOUSEMEISTER`) | 3 | 2 | 1.2 |
| Male employee 1 (`ANGESTELLTER#1`) | 4 | 3 | 1.5 |
| Male employee 2 (`ANGESTELLTER#2`) | 5 | 4 | 1.6 |
| Female employee 1 (`ANGESTELLTE#1`) | 6 | 5 | 1.7 |
| Female employee 2 (`ANGESTELLTE#2`) | 7 | 6 | 1.5 |

Factories `sub_404B90`, `sub_404EC0`, `sub_404D20`, `sub_405010`, and `sub_4051D0` establish those character types and variants. Internal type `+1740` is 1 for boss, 2 for secretary, 3 for janitor, and 4 for coworkers. Coworker gender at `+1744` is 0 for male and 1 for female; variant `+1748` is 0 or 1.

`sub_417730` moves NPCs toward their current waypoint using the exact logical normalized vector `(dx, dz) / sqrt(dx² + dz²)`, multiplied by current speed, frame delta, and the multiplier at `+76`. Their velocity is continuous toward the target; only sprite facing is quantized into eight directions. Coworker, secretary, and janitor update functions (`sub_419CE0`, `sub_41E360`, `sub_41A8D0`) adjust current speed to `base_speed + 0.15 * integer_at_1064`. Their slowed flag at `+1792` sets the multiplier to 0.2 instead of 1.0. The boss tick `sub_419740` applies the same slowdown multiplier but does not apply that speed-increase formula. Base-speed support does not imply these reaction states have been implemented.

## Runtime route generation

The level's `SPAWN` records establish characters and their initial locations. The inspected `LEVEL_00` data has four spawns: player `(12, 9)`, boss `(1, 12)`, male employee 1 `(3, 2)`, and female employee 1 `(6, 1)`. It has no serialized NPC patrol routes. An authored route in the Godot port is an authoring feature, not an extracted original schedule.

The original agents choose targets at runtime. `sub_416D50` selects a target item via `sub_417120`, obtains its interaction position from `sub_410030`, rounds the ground coordinates with `int(value + 0.5)`, and generates a path. The interaction position is the object's ground position plus the orientation-transformed floats from object-definition offsets `+536/+540`.

`sub_4061C0` builds a pathfinding grid from `INFODATA` bit 0: blocked cells become byte 255 and free cells become zero. `sub_41E910` expands four neighbors in order left, up, right, down, rejecting out-of-bounds cells, blocked cells, and the immediate parent. The queue search at `sub_41EFB0` adds the grid-byte cost to the accumulated path cost and uses squared Euclidean distance to the goal as its heuristic. Since ordinary free cells cost zero, this is not a shortest-path guarantee equivalent to conventional unit-cost A*.

`sub_41F540` then replaces eligible pairs of cardinal steps with diagonal steps only if both adjacent orthogonal cells are free. Route entries are four 32-bit fields: X, Z, direction code, and a distance field (1024 for cardinal, 1448 for merged diagonal). Direction codes 1–8 mean `(0,-1)`, `(1,-1)`, `(1,0)`, `(1,1)`, `(0,1)`, `(-1,1)`, `(-1,0)`, `(-1,-1)`; zero is terminal.

NPC traversal at `sub_417730` aims at a route entry's cell plus its direction vector. When the distance is below **0.4 logical tiles**, it advances the route index. Completing the route frees it, turns toward the target item, and calls `sub_417B00` to begin the action. It does not use the port's former six-screen-pixel arrival threshold or a fixed pause after every waypoint.

Before pathfinding, `sub_418D20` temporarily marks other entity positions as occupied, then restores those cells afterward. NPC construction at `sub_415D50` disables the player-style static collision flag at `+100`; original NPC avoidance relies on generated paths and agent handling. The port's shared physical grid collision is an explicit additional safeguard for authored movement.
