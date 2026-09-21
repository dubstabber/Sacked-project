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

## Goals and target selection

`sub_415D50` initializes need values to random 20–100, except goal 3 starts at 10. While there is no route or active action, `sub_416770` decreases each of the eight needs by `delta * rate * 0.5`, clamped to 0–100. `sub_415FF0` chooses the lowest need whose disabled flag at agent `+1020 + 4 * goal` is clear, falling back to goal 2 when every goal is disabled; `sub_4165D0` queues that goal when its value is below 15. After completing a goal, its need is reset to random 60–100. This is a changing needs-based routine, not an endless repeat of one workstation action.

The decay cadence matters. `sub_416540`, the last handler in `sub_416770`'s chain, reports "busy" while the shared timer at `+1124` is positive, so needs hold still during an action and during a retry delay. Once that timer reaches zero it starts the queued goal through `sub_416660`. A **failed** start returns zero, so the same tick still decays every need and calls `sub_4165D0`, which re-queues the lowest need and resets `+1124` to zero — the 0.5–1.5 second retry delay only survives when nothing is queued. An agent whose queued goal can never succeed therefore keeps decaying its other needs and moves on as soon as one of them drops lower, instead of stalling on the goal it cannot reach.

`sub_4187F0` sets the disabled flag for goals 0, 1, 2, 3, 4 and 7 whose candidate list came out empty, and calls `sub_416040` to zero that goal's decay rate so its need can never become the lowest again. Goals 5 and 6 are never disabled this way.

The following goal descriptions are inferred from the verified target categories and item names. Category numbers come from `sub_418B70`/`sub_418BE0` and the packed item's `(kind >> 16) & 0xff` field; they are not the texture grouping in `CO_OBJECTS.DAT`.

| Goal | Target category / behavior | Representative targets |
| --- | --- | --- |
| 0 | 4, food / kitchen | Brunchman, fridge, microwave, cooker |
| 1 | 5, drinks | Coffee machine, cola machine, minibar, water dispenser |
| 2 | 9, decoration / recreation | Plants, windows, posters, arcade machines |
| 3 | 6, workstation; alternate category 2 | Assigned monitor/chair; printer, copier, phone, other work equipment |
| 4 | 8, toilet | Toilet cubicles |
| 5 | Social target | Another agent; a dedicated path-to-agent branch supersedes the category lookup |
| 6 | 1, smoking | Standing ashtrays |
| 7 | 7, relaxation | Lounge chairs and sofas |

The eight need-decay rates are the final eight floats of each speed-profile record:

| Profile | Goal 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Boss | 5 | 5 | 65 | 0 | 10 | 7 | 10 | 20 |
| Secretary | 10 | 20 | 10 | 60 | 15 | 5 | 10 | 10 |
| Janitor | 10 | 10 | 10 | 50 | 0 | 1 | 10 | 10 |
| Male employee 1 | 12 | 15 | 19 | 87 | 15 | 15 | 13 | 9 |
| Male employee 2 | 9 | 9 | 8 | 79 | 9 | 10 | 10 | 21 |
| Female employee 1 | 17 | 8 | 16 | 86 | 21 | 17 | 19 | 7 |
| Female employee 2 | 6 | 19 | 10 | 85 | 11 | 10 | 10 | 17 |

`sub_4187F0` builds candidate lists for each goal from its item category, filtered by the room identifier at the item's rounded anchor. Each goal has a bit mask at agent `+1864 + 4 * goal`; room `r` is allowed if `mask & (1 << r)` is nonzero. It retains at most 64 candidates per goal. The initializer masks are:

```text
Boss:      10, 266, 328, 256, 128,  76, 264, 72
Secretary: 11,  11,  76,   4, 128, 332,  12, 72
Janitor:   11,  11,  76,  22, 128,  92,  12, 72
Coworkers: 11,  11,  76,   5, 128,  76,  12, 72
```

`sub_417120` chooses randomly among eligible targets. For goal 3, if an assigned workstation exists, `(rand() & 0xfff) < 0xe00` selects it (7/8 of the range); otherwise it chooses alternate category-2 work equipment. It can return both active-monitor and passive-chair pointers, with the chair's interaction position preferred for the walking destination. Without an assignment, goal 3 returns no target unless the internal variant at `+1748` equals 3. None of the ordinary spawned boss, janitor, secretary, or coworker variants uses that value. Boss and janitor therefore fail the initial work request and move on as another need becomes lower; they do not select arbitrary desks.

`sub_416660` sets a successful action's default duration to random **10–16 seconds**, then starts the route. The action timer only decreases when no route is active. A failed route waits random **0.5–1.5 seconds** before retrying, and abandons the queued goal after five failures.

`sub_417320` picks the social partner: it walks the whole agent list and keeps the **last** agent that is not itself, whose gender at `+1744` differs from its own, and which lies within **8 logical tiles** — not the nearest one. `sub_416960` then aims at a point **1.2 tiles in front** of that agent, derived from the agent's own eight-direction facing, and `sub_416770` rebuilds that route every **three seconds** while it walks. Boss and male coworkers have gender 0; female coworkers have gender 1 (`sub_404B90`, `sub_405010`).

Note that `sub_4187F0` builds each goal's candidate list **once**, at startup, and `sub_417120` draws a random index from that stored list. It does not rescan the item list per attempt, and it does not filter on occupation at selection time — occupation is only checked when the action starts.

## Workstations and seated actions

`sub_4185B0` assigns secretary/coworker workstations at startup. It searches active monitor item types 152–155 around the spawn, increasing the search radius from 0.5 to 10 in steps of 0.5. It then searches for a chair near that monitor, with radius 1–3 in steps of 1. Matches use strict distance below the current radius and original item order, not a nearest-item sort. Boss/janitor initialization calls `sub_418790` to clear the assignment instead. In `LEVEL_00`, male employee 1 receives monitor instance 10 / original `ITEM2` and chair instance 9 / `ITEM1`; female employee 1 receives monitor 14 / `ITEM6` and chair 13 / `ITEM5`.

Item types here are `(packed_kind >> 4) & 0xfff`, as returned by `sub_40FE90`. On arrival, `sub_417B00` starts the following verified ordinary actions:

| Item types | Behavior | Duration |
| --- | --- | --- |
| Active 152–155, monitors | Find a free chair within 1.8 tiles; claim it and sit for work | 50–60 seconds |
| Passive 68–71, office swivel chairs | Claim chair and sit for work | 40–50 seconds |
| Passive 121–122 or 179–184, executive/lounge chairs and sofas | Claim seat; relaxed sitting | 15–25 seconds |
| Active 129, copier | Set copier animation/state 9 while using, restore state 0 afterward | 20 seconds |
| Active 139, 140, 146, 147, 150, 151 | Special-action flag, e.g. drinks and kitchen devices | 15 seconds |
| Passive 5–9, 88, 97, 98, 115 | Special-action flag | 15 seconds |
| Active 173 or 262, toilet cubicles | Claim cubicle and enter it | 10–15 seconds |
| Other unmodified ordinary targets | Retain the default action timer | 10–16 seconds |

The monitor's seat search includes types 68–74, 86, 93, 94, 121, and 122. Seat/cubicle occupation is stored at item `+216`, with occupant pointer `+220`; startup allocation temporarily claims objects and the level startup later clears those claims. Assignment and current occupation are separate concepts.

While sitting, `sub_4161E0` moves the NPC to the seat's ground anchor and logical height **0.1**, projecting the image 2.4 pixels upward before the original integer rendering conversion. For ordinary work sitting, facing points from the interaction point toward the seat, i.e. opposite the interaction offset. `sub_41A400` converts a logical vector `(dx, dz)` into the sprite angle with `180 - atan2(dx, dz) * 57.29579`, then rounds to an eight-direction index.

For a seat with original base interaction offset `(1, 0)`:

| Object orientation | Transformed interaction offset | Work-sitting sprite suffix | Screen facing |
| --- | --- | --- | --- |
| 0 / 000 | `(1, 0)` | 270 | Up-left |
| 1 / 090 | `(0, 1)` | 000 | Up-right |
| 2 / 180 | `(-1, 0)` | 090 | Down-right |
| 3 / 270 | `(0, -1)` | 180 | Down-left |

Relaxed sitting instead faces along the interaction offset and shifts the ground anchor 30% toward the interaction point. When either sitting timer ends, `sub_4161E0` places the NPC at the seat's interaction point and clears the seat's occupation.

Coworker animation slots are `0 IDLE#1#ATMEN`, `1 IDLE#2`, `2 WALK`, `3 SIT#IDLE`, `4 SIT#USE`, `5 SPECIAL#1`, `6 SPECIAL#2`, `7 PISSED`, `8 SIT#EASY` (table `0x46EB44`, tick `sub_419CE0`). The tick picks in this order: walking uses `WALK`; sitting uses `SIT#EASY` when the relaxed flag at `+1804` is set, otherwise `SIT#USE` for random values 0–4080 and `SIT#IDLE` for 4081–4095 from `rand() & 0xfff`; the special-action flag at `+1812` uses `SPECIAL#1`; the reaction flag at `+1820` uses `PISSED`; goal 6 uses `SPECIAL#2`; and standing idle picks `IDLE#2` for 4089–4095. Secretary equivalents are slots 6/7/9 for idle/use/easy (`0x46EEE4`, `sub_41E360`). The boss uses slot 3 `SIT#IDLE` (`0x46EAE0`, `sub_419740`).

`sub_41A510` resolves a slot against the agent's current eight-direction index. A slot with no clip for that view falls back to the clip for view `000`, and a slot with no clip at all falls back to the idle slot. Each coworker variant ships only one of `SPECIAL#1` and `SPECIAL#2`, so goal 6 plays the idle fallback for the variant-1 coworkers in `LEVEL_00`.

Full prank reactions, panic, cleanup, anger progression, and the complete social interaction state machine remain outside this reference's recovered ordinary-action subset. A port implementing only workstation behavior should identify that limit rather than describing it as the complete original NPC AI.

## Implemented autonomous subset

`scenes/npc/npc_brain.gd` implements needs-based selection for the three imported `LEVEL_00` profiles: boss, male employee 1, and female employee 1. Their initial needs, work preference, decay rates, room masks, random durations, completion resets, and failure delays use the values above, including the decay cadence: a failed goal start still decays every need on the same tick, and a goal whose candidate list is empty is disabled with its rate zeroed. Assigned chair/workstation paths remain separate from seat occupation. Explicit authored routes override this brain.

All eight goals are implemented. On arrival the brain runs `sub_417B00`'s dispatch: monitors claim a free seat within 1.8 tiles and work for 50–60 seconds, office swivel chairs sit for 40–50 seconds, executive chairs and sofas claim the seat and sit relaxed for 15–25 seconds with the anchor shifted 30 % toward the interaction point, toilet cubicles are claimed and entered for 10–15 seconds, the copier is claimed for 20 seconds, the special-action item types run 15 seconds, and anything else keeps the default 10–16 second timer. Work sitting uses `SIT#USE` (`SIT#IDLE` for the boss) and relaxed sitting uses `SIT#EASY`; the special-action types use `SPECIAL#1`.

Goal 5 walks to a point 1.2 tiles in front of the last opposite-gender agent within eight tiles and stands there for the default 10–16 seconds, rebuilding the route every three seconds while it walks. Goal 6 asks for slot 6 `SPECIAL#2`; neither `LEVEL_00` coworker variant ships that clip, so it plays the idle fallback exactly as `sub_41A510` does. Neither goal is ever disabled, matching `sub_4187F0`.

Two `LEVEL_00` targets cannot be reached, for different reasons. The toilet cubicle's interaction point lands on tile `(11.68, 0.99)`, whose cell `(12, 1)` is **free** — the original pathfinder, which only rejects blocked cells, walks there. The port refuses it because a character's `0.35` half-extent footprint overlaps blocked cell `(11, 1)` at `0.68` tiles, under the `0.85` the shared grid collision requires. That follows from the port's decision to give NPCs the static collision `sub_415D50` disables at `+100`: the original lets an agent stand flush against a wall, the port does not. Goal 4 therefore retries on this map until another need drops lower, which costs the boss roughly 14 % of its ticks. Removing it means letting NPC movement ignore static collision the way the original does, which would undo the port's deliberate safeguard.

`LEVEL_00`'s only standing ashtray sits at tile `(12.79, 5.21)` and its interaction offset of `+0.6` in X keeps the approach inside cell `(13, 5)`, which the original collision grid marks blocked. Goal 6 therefore cannot complete on this map in the original either. The port reproduces that: the attempt fails, the agent keeps decaying its other needs, and the tie-break in `sub_415FF0` — first index wins — hands the turn to a lower-numbered goal once that need also reaches zero.

Coworkers use `SIT#USE` throughout work instead of the original rare per-tick `SIT#IDLE` selection, because reproducing a per-tick clip swap needs the original's clock-driven action playback, which this port has not verified for action clips. The copier's own object animation state 9 is not modelled; only the agent side of that action is. Prank reactions, panic, cleanup, anger progression and the `+1064` speed increase remain unimplemented.

The port additionally releases claims and restores standing positions when a brain is disabled, removed, or its activity target/seat disappears. An action with no clip at all plays the idle fallback and warns once, matching `sub_41A510` rather than failing the goal. These are authoring/runtime safety behavior, not claims about original object-deletion handling. The isolated `tests/check_npc_brain.gd` exercises target filters, goal disabling, the arrival dispatch for each item class, work startup, durations, occupation, need resets, retry bounds, authored-route override, and interrupted/missing-action cleanup with a stub actor. `tests/check_npc_level_runtime.gd` runs the three original agents on the imported map for two simulated minutes.

## Thought bubbles

`agent+1080` is the agent's **current goal**, not a separate bubble field: `sub_416570`
clears it to `-1` along with the rest of the goal state, and `sub_4165D0` completes the goal
it holds before queueing the next one into `+1082`. `sub_417460` draws
`bubbleNames[agent+1080]` from the table at `0x46E7A8`, **135 pixels above** the agent at
alpha 180, so a bubble is up for exactly as long as its goal is.

The table's ten entries therefore line up with the goals one for one:

| 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| FOOD | COFFEE | HAPPY | BACKTOWORK | TOILETT | SOCIAL | CIGARETTE | RELAX | ANGRY | REPAIR |

Goals **8 and 9 are the reaction states**: `sub_416090` and `sub_416450` set goal 8, and
`sub_4164E0` sets goal 9. The port's brain supports 0–7, so it raises the first eight; the
bubble already carries all ten.

`sub_417460` also draws two things the port does not yet: the agent's name over its head
while `agent+1788` marks it as the one the cursor selected, and three jittered green copies
of the sprite while `agent+1792` is set.

## Reacting to a sabotaged object (recovered, not yet implemented)

`agent+1820` is the reaction flag, and `sub_416450` is the whole reaction:

```c
if ( !agent+1820 ) return 0;
if ( agent+1124 > 0.0 )        // the ordinary busy timer
    agent+1080 = 8;            // the ANGRY goal, so the ANGRY bubble
else {
    agent+1820 = 0;
    for ( n = 0; n <= 7; n++ )
        sub_415FD0(n, rand 60..100);   // every need reset, as if satisfied
}
```

So the reaction runs for as long as the agent's own busy timer, shows goal 8 for that whole
stretch, and ends by resetting **all eight needs** to a random 60–100 rather than only the
one it was pursuing.

`sub_416090` is a separate goal-8 case: an agent inside a cubicle whose `item+224` is set —
the flag actions 110 and 112 apply — is angry for as long as it stays locked in.

The arrival path in `sub_417B00` awards **25 points** through `sub_41DEA0(0x19, x, y)` at the
agent's own position, which confirms the published walkthrough's "+25 when a colleague tries
something you broke" against the executable.

Still to recover before this can be built: the exact test that *sets* `agent+1820`. The
region around `0x417C86` clears it on an ordinary arrival, so the setting branch is
elsewhere in `sub_417B00`'s item-type switch. The reaction must not live in
`is_available()`, which `_candidates()` calls when choosing a goal — an agent has to walk to
a broken object before it can be angry about it.

Assets: `PISSED` ships 8 views for all six coworker archetypes and `CHEF_STAND#EXPLODE` 8
views for the boss; neither is imported yet. Both would go through
`tools/character_action_clips.json`.
