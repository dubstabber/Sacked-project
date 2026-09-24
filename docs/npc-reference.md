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

`sub_417730` moves NPCs toward their current waypoint using the exact logical normalized vector `(dx, dz) / sqrt(dx² + dz²)`, multiplied by current speed, frame delta, and the multiplier at `+76`. Their velocity is continuous toward the target; only sprite facing is quantized into eight directions. Coworker, secretary, and janitor update functions (`sub_419CE0`, `sub_41E360`, `sub_41A8D0`) adjust current speed to `base_speed + 0.15 * integer_at_1064`. Their slowed flag at `+1792` sets the multiplier to 0.2 instead of 1.0. The boss tick `sub_419740` applies the same slowdown multiplier but does not apply that speed-increase formula. Those same three ticks also widen the agent's notice radius and cone with the band, which is covered in [catch-reference.md](catch-reference.md); the boss is exempt from all three. The speed increase is implemented (see "How angry the office gets" below); the slowed state at `+1792` is not — it belongs to one of the player's own unported abilities.

## Runtime route generation

The level's `SPAWN` records establish characters and their initial locations. The inspected `LEVEL_00` data has four spawns: player `(12, 9)`, boss `(1, 12)`, male employee 1 `(3, 2)`, and female employee 1 `(6, 1)`. It has no serialized NPC patrol routes. An authored route in the Godot port is an authoring feature, not an extracted original schedule.

## Which agent is created first

Who gets which desk depends entirely on the order the agents are made in, because
`sub_4185B0` claims the first free workstation it finds. That order is **not** the order the
`SPAWN` records sit in the file.

`sub_412FB0`'s `SPAWN` branch appends each record to a doubly-linked list at `game+1852` in
file order and counts them at `game+1856`. `sub_406AF0`, the level's start-up, then drains
that list **by spawn type in ascending order**: one call each for types 0, 1, 2 and 3, then
a `while` loop per type for 4, 5, 6 and 7. `sub_413320(type)` walks the list from its head
and returns the first record still carrying that type, then sets bit 15 of the type field to
mark it spent, which is what ends each loop.

Three consequences, all reproduced by `build_npcs`:

- **Creation order is ascending spawn type, and file order within one type.** The port sorts
  the spawn records by `spawn_id`, and Python's sort is stable, so records of one type keep
  the order they were read in.
- **Types 1, 2 and 3 are created at most once.** They get a bare `if`, not a loop, so a
  second boss, secretary or janitor record is simply never consumed. Level 7 ships two
  secretary records and the original creates one secretary.
- **The boss and the janitor get no desk and no chair.** `CObj_Boss` (`sub_404B90`) and
  `CObj_Housekeeper` (`sub_404D20`) call `sub_418790`, which writes 0 to both `+1836` and
  `+1840`; only the secretary (`sub_404EC0`) and the four coworker variants
  (`sub_405010`/`sub_4051D0`, each with a 0/1 argument) call `sub_4185B0`. This is why the
  two of them fail the initial work request described below rather than taking a coworker's
  desk.

`sub_406AF0` also resets the coworker-name pool (`sub_4156B0`) before the first agent exists,
and ends by picking the level theme with `rand() % 3`.

The original agents choose targets at runtime. `sub_416D50` selects a target item via `sub_417120`, obtains its interaction position from `sub_410030`, rounds the ground coordinates with `int(value + 0.5)`, and generates a path. The interaction position is the object's ground position plus the orientation-transformed floats from object-definition offsets `+536/+540`.

`sub_4061C0` builds a pathfinding grid from `INFODATA` bit 0: blocked cells become byte 255 and free cells become zero. `sub_41E910` expands four neighbors in order left, up, right, down, rejecting out-of-bounds cells, blocked cells, and the immediate parent. The queue search at `sub_41EFB0` adds the grid-byte cost to the accumulated path cost and uses squared Euclidean distance to the goal as its heuristic. Since ordinary free cells cost zero, this is not a shortest-path guarantee equivalent to conventional unit-cost A*.

`sub_41F540` then replaces eligible pairs of cardinal steps with diagonal steps only if both adjacent orthogonal cells are free. Route entries are four 32-bit fields: X, Z, direction code, and a distance field (1024 for cardinal, 1448 for merged diagonal). Direction codes 1–8 mean `(0,-1)`, `(1,-1)`, `(1,0)`, `(1,1)`, `(0,1)`, `(-1,1)`, `(-1,0)`, `(-1,-1)`; zero is terminal.

NPC traversal at `sub_417730` aims at a route entry's cell plus its direction vector. When the distance is below **0.4 logical tiles**, it advances the route index. Completing the route frees it, turns toward the target item, and calls `sub_417B00` to begin the action. It does not use the port's former six-screen-pixel arrival threshold or a fixed pause after every waypoint.

Before pathfinding, `sub_418D20` temporarily marks other entity positions as occupied, then restores those cells afterward. NPC construction at `sub_415D50` disables the player-style static collision flag at `+100`; original NPC avoidance relies on generated paths and agent handling. The port's shared physical grid collision is an explicit additional safeguard for authored movement.

## Goals and target selection

`sub_415D50` initializes need values to random 20–100, except goal 3 starts at 10. While there is no route or active action, `sub_416770` decreases each of the eight needs by `delta * rate * 0.5`, clamped to 0–100. `sub_415FF0` chooses the lowest need whose disabled flag at agent `+1020 + 4 * goal` is clear, falling back to goal 2 when every goal is disabled; `sub_4165D0` queues that goal when its value is below 15. After completing a goal, its need is reset to random 60–100. This is a changing needs-based routine, not an endless repeat of one workstation action.

The decay cadence matters. `sub_416540`, the last handler in `sub_416770`'s chain, reports "busy" while the shared timer at `+1124` is positive, so needs hold still during an action and during a retry delay. Once that timer reaches zero it starts the queued goal through `sub_416660`. A **failed** start returns zero, so the same tick still decays every need and calls `sub_4165D0`, which re-queues the lowest need and resets `+1124` to zero — the 0.5–1.5 second retry delay only survives when nothing is queued. An agent whose queued goal can never succeed therefore keeps decaying its other needs and moves on while one of them is lower, instead of stalling on the goal it cannot reach — until that goal's own need reaches 0, after which nothing can drop below it (see "When a goal can never succeed" below).

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

`sub_4187F0` builds candidate lists for each goal from its item category, filtered by the room identifier at the item's rounded anchor. Each goal has a bit mask at agent `+1864 + 4 * goal`; room `r` is allowed if `mask & (1 << r)` is nonzero. It retains at most 64 candidates per goal. Each archetype's initialiser (its `vtbl+28`) writes the masks as immediates between its calls to `sub_4184B0` and `sub_4187F0`:

```text
Boss       sub_4196A0: 10, 266, 328, 256, 128,  76, 264, 72
Secretary  sub_41E2C0: 11,  11,  76,   4, 128, 332,  12, 72   (0x41E30C-0x41E34A)
Janitor    sub_41A830: 11,  11,  76,  22, 128,  92,  12, 72   (0x41A87C-0x41A8BA)
Coworkers  sub_419C10: 11,  11,  76,   5, 128,  76,  12, 72
```

The secretary and the janitor differ from the coworkers only in goal 3 (work) and goal 5 (social). Goal 5's mask is never consulted, because the social goal picks an agent rather than an item, so only goal 3's candidate lists change: on level 8 the coworkers' row used to put the room-0 flipchart on the secretary's alternate-work list. The janitor, who has no workstation, never uses his.

`sub_417120` chooses randomly among eligible targets. For goal 3, if an assigned workstation exists, `(rand() & 0xfff) < 0xe00` selects it (7/8 of the range); otherwise it chooses alternate category-2 work equipment. It can return both active-monitor and passive-chair pointers, with the chair's interaction position preferred for the walking destination. Without an assignment, goal 3 returns no target unless the internal variant at `+1748` equals 3. None of the ordinary spawned boss, janitor, secretary, or coworker variants uses that value. Boss and janitor therefore fail every work request; they do not select arbitrary desks. For the boss that costs little: his work need starts at 10 and his rate for it is 0, so any other need that decays below 10 takes the turn. The janitor's rate is 50, so his work need falls to 0 within a second of idling and stays there, and from then on it wins every tie against goals 4–7 (see "When a goal can never succeed" below): he only ever pursues goals 0, 1 and 2, plus the repairs a reaction files.

`sub_416660` sets a successful action's default duration to random **10–16 seconds**, then starts the route. The action timer only decreases when no route is active. A failed route waits random **0.5–1.5 seconds** before retrying, and abandons the queued goal after five failures.

`sub_417320` picks the social partner: it walks the whole agent list and keeps the **last** agent that is not itself, whose gender at `+1744` differs from its own, and which lies within **8 logical tiles** — not the nearest one. `sub_416960` then aims at a point **1.2 tiles in front** of that agent, derived from the agent's own eight-direction facing, and `sub_416770` rebuilds that route every **three seconds** while it walks. Boss and male coworkers have gender 0; female coworkers have gender 1 (`sub_404B90`, `sub_405010`).

Note that `sub_4187F0` builds each goal's candidate list **once**, at startup, and `sub_417120` draws a random index from that stored list. It does not rescan the item list per attempt, and it does not filter on occupation at selection time — occupation is only checked when the action starts. Neither `sub_417120` nor its lookup `sub_410EA0` reads `item+216`, and goal 3's assigned pair comes back whole even when the chair is taken. `sub_417B00` tests `+216` only on arrival: at `0x417D64` for cubicles, `0x417EDB` for work chairs 68–71 and `0x417F16` for relaxed seats, plus `sub_418230`'s own test (`0x418285`) in the monitor's seat search. An agent that finds its target taken claims nothing and stands there for the 10–16 seconds `sub_416660` set when the goal started; `sub_4165D0` then completes the goal as usual. The port used to drop taken points from the candidate list, which the original never does.

## Workstations and seated actions

`sub_4185B0` assigns secretary/coworker workstations at startup. It searches active monitor item types 152–155 around the spawn, increasing the search radius from 0.5 to 10 in steps of 0.5. It then searches for a chair near that monitor, with radius 1–3 in steps of 1. Matches use strict distance below the current radius and original item order, not a nearest-item sort. Boss/janitor initialization calls `sub_418790` to clear the assignment instead. In `LEVEL_00`, male employee 1 receives monitor instance 10 / original `ITEM2` and chair instance 9 / `ITEM1`; female employee 1 receives monitor 14 / `ITEM6` and chair 13 / `ITEM5`.

Item types here are `(packed_kind >> 4) & 0xfff`, as returned by `sub_40FE90`. On arrival, `sub_417B00` starts the following verified ordinary actions:

| Item types | Behavior | Duration |
| --- | --- | --- |
| Active 152–155, monitors | Find a free chair within 1.8 tiles; claim it and sit for work | 50–60 seconds |
| Passive 68–71, office swivel chairs | Claim chair and sit for work | 40–50 seconds |
| Passive 121–122 or 179–184, executive/lounge chairs and sofas | Claim seat; relaxed sitting | 15–25 seconds |
| Active 129, copier | The first user ever claims it and holds it in state 9, restoring state 0 afterward; everyone after stands idle | 20 seconds, every visit |
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

No tick has a panic branch. The secretary's table names `PANIC`, `PANIC#WET` and `PANIC#FOAM` at slots 3–5, but no caller of `sub_41A510` asks her for them: her factory `sub_404EC0` starts her on slot 2 (`0x404F5F`) and `sub_41E360` picks only slots 0, 1, 2, 6, 7 and 9. No tick has a cleanup branch either; the janitor's only job is the repair a reaction files (below). The social goal is recovered in full above, the anger meter under "How angry the office gets", and the reaction to a tampered object under "Reacting to a sabotaged object".

## Implemented autonomous subset

`scenes/npc/npc_brain.gd` implements needs-based selection for all seven characters: boss, secretary, janitor, both male employees and both female employees. Their initial needs, work preference, decay rates, room masks, random durations, completion resets, and failure delays use the values above, including the decay cadence: a failed goal start still decays every need on the same tick, and a goal whose candidate list is empty is disabled with its rate zeroed. Assigned chair/workstation paths remain separate from seat occupation. Explicit authored routes override this brain.

The speeds, decay rates, notice constants and room masks are no longer transcribed: `tools/export_npc_profiles.py` reads all seven records out of `sub_4184B0`'s table at `0x46E7D8` into `resources/original/npc_profiles.json`, and the brain loads that once per class. The room masks are compiled-in immediates rather than table columns, so the exporter finds each archetype's initialiser through its vtable slot (`0x46532C`, `0x465394`, `0x465360`, `0x4653C8`, each checked against the tick in the slot after it) and replays the stores between its `sub_4184B0` and `sub_4187F0` calls, refusing any instruction outside `mov eax, imm32`, `mov [ebx+disp32], imm32`, `mov [ebx+disp32], eax` and `mov ecx, ebx`. Until then the brain gave the secretary and the janitor the coworkers' row.

All eight goals are implemented. On arrival the brain runs `sub_417B00`'s dispatch: monitors claim a free seat within 1.8 tiles and work for 50–60 seconds, office swivel chairs sit for 40–50 seconds, executive chairs and sofas claim the seat and sit relaxed for 15–25 seconds with the anchor shifted 30 % toward the interaction point, toilet cubicles are claimed and entered for 10–15 seconds, the copier takes 20 seconds, the special-action item types run 15 seconds, and anything else keeps the default 10–16 second timer. The seated clip is each archetype's own tick's choice. Coworkers and the secretary sit with `SIT#EASY` on a relaxed seat and `SIT#USE` otherwise. The boss plays `SIT#IDLE` on **any** seat: `sub_419740` selects slot 3 whenever the seated flag `+1800` is set (`0x4197F1`–`0x4197FF`) and never reads the relaxed flag `+1804`, and his table at `0x46EAE0` has only four slots (`STAND#IDLE`, `STAND#EXPLODE`, `WALK`, `SIT#IDLE`), so `CHEF_SIT#EASY` is never even loaded — the port still imports it, as unused art. The janitor plays `SIT#EASY` on any seat (`sub_41A8D0`, `0x41A969`). The anchor shift and the outward facing belong to `sub_4161E0` and apply to every archetype. The special-action types raise the flag at `+1812` for 15 seconds (`0x417E96` for the active types, `0x417F6E` for the passive ones) for every archetype, but only the coworkers' tick reads it: `sub_419CE0` plays slot 5 `SPECIAL#1` (`0x419DC3`), and a text search for `+714h]` finds no other reader. The boss (`sub_419740`), the secretary (`sub_41E360`) and the janitor (`sub_41A8D0`) stand in their idle slot for those 15 seconds, so the port asks only coworkers for `special-1`. The secretary's and janitor's tables do name a `SPECIAL#1` (`0x46EEE4` slot 8, `0x46EBD8` slot 5), and `tools/character_action_clips.json` still imports both, as unused art.

Goal 5 walks to a point 1.2 tiles in front of the last opposite-gender agent within eight tiles and stands there for the default 10–16 seconds, rebuilding the route every three seconds while it walks. Goal 6 asks a coworker for slot 6 `SPECIAL#2` (`sub_419CE0`, `0x419DF1`); the other three ticks have no goal-6 branch, so the boss, the secretary and the janitor stand at an ashtray in their idle slot. Neither `LEVEL_00` coworker variant ships that clip, so on that map it plays the idle fallback exactly as `sub_41A510` does; male employee 2 and female employee 2 do ship it. Female employee 2's copy is missing its `180` view alone, and `sub_41A510`'s own fallback to view `000` covers that, which is what `npc.gd`'s `_action_clip` reproduces. She ships no `SPECIAL#1` at all, so the special-action item types drop her to idle the way they already do for male employee 2. Neither goal is ever disabled, matching `sub_4187F0`.

Coworkers use `SIT#USE` throughout work instead of the original rare per-tick `SIT#IDLE` selection, because reproducing a per-tick clip swap needs the original's clock-driven action playback, which this port has not verified for action clips. The anger meter, the `+1064` speed increase and reacting to a tampered object are implemented and described below.

### The copier

`sub_417B00`'s case 129 (`0x417E6E`–`0x417E8A`) writes 20.0 to the busy timer `+1124` on every arrival. Only when the copier's `item+216` is clear does it also claim it (`+216`, `+220`) and raise the agent's `+1808`. While that flag and the timer are up, `sub_416340` turns the agent toward the copier and puts the copier into state 9 on every tick, which is what makes its `DESTROYED_1` loop run in ordinary play with no prank involved. At expiry it restores state 0 and clears `+1808`, but never `item+216`. Nothing else frees it before the level restarts. The only writers that clear `+216` are the level start `sub_406AF0`, the two item initialisers `sub_40FEF0` and `sub_410060` (the `vtbl+28` slots at `0x4655AC` and `0x465578`, which the item factory `sub_410550` calls while `sub_412FB0` loads the level), and the seat and cubicle exits `sub_4161E0` and `sub_416090`. The repair reset `sub_4100B0` does not touch it. So the first agent to use the copier is the only one that ever runs it. Everyone after, that agent included on a later visit, stands idle at it for the same 20 seconds, and the goal completes as usual.

The port keeps this claim as `copier_claimed` on the activity point, separate from the seat `occupant`. `reset_actions()` leaves it alone, and so do releasing a seat and stopping a brain; only reloading the level clears it. The brain restores state 0 when the first user's activity ends, is interrupted or the agent is stopped. The port used to use 10–16 seconds when the copier was busy, and released the claim at the end, so every later user ran it again.

### Where a route ends

`sub_416D50` rounds **both** ends of a route to a cell with `(__int64)(v + 0.5)`: the agent's own position at `0x416D8A`/`0x416D8C` and the target's interaction point at `0x416E2B`/`0x416E2D`, each clamped to the map. `sub_41EE70` pushes the start cell into the search without testing it, and `sub_41E910` refuses a neighbour only when its grid byte is 255. `sub_417730` then walks the route entry by entry; the terminal entry carries direction code 0, so it aims at the goal cell itself and arrives within 0.4 tiles (`0x4177AF`). `sub_416960` rounds the social point 1.2 tiles ahead the same way (`0x416A60`/`0x416A72`). So a target is reachable exactly when its interaction point's **cell** is free, however close the point itself lies to a wall.

The port routes the same way. `npc_brain.gd` sends an agent to the centre of the rounded cell rather than to the exact point, for item targets and the social point alike; a free cell's centre always clears the `0.35` footprint of the static collision the port keeps (and `sub_415D50` disables at `+100`), because every other cell centre is a whole tile away on one axis. Authored `NPCRoute` waypoints still go to their exact points. The port walks all the way to the centre rather than stopping 0.4 tiles short.

The other end is the point an agent is stood back on. `sub_4161E0` (seats) and `sub_416090` (cubicles) return it to the **exact** interaction point, which can be flush against a wall or, for a few seats the monitor's seat search can hand out, inside a blocked cell. When the ordinary search refuses to start there, `npc.gd` plans from that point's rounded cell with the cell itself exempt from the search, as `sub_41EE70` never tests it, and steps back onto the cell's centre first. Walking keeps its collision throughout; the step back only moves the body out of the overlap.

Before routes ended on cells the port walked to the exact point, and the footprint test refused every target whose point sits within 0.85 tiles of a blocked cell. On `LEVEL_00` that was the toilet cubicle `(11.68, 0.99)` against blocked `(11, 1)`, the sink `(7.99, 13.34)` against `(8, 14)` and the sofa `(12.21, 6.13)` against `(13, 6)` — which is why the boss never sat on the sofa — and on levels 1–8 some fifty candidate points in all, among them the secretary's own chair on level 2, seven coworkers' chairs on levels 4, 6 and 7, the only drink on levels 5 and 6, every relax seat on level 3 and the toilets on levels 3 and 8. The original reaches all of them.

### When a goal can never succeed

`sub_415FF0` starts from 999 and takes a need only when it is **strictly** lower (`0x41600B`), so among equal needs the lowest goal index wins. Needs clamp at 0 (`sub_416770`), and only two things lift one again: completing its goal (`sub_4165D0`, 60–100) and the end of a reaction (`sub_416450`, all eight). `sub_415FD0`, the need setter, has no other caller besides the constructor `sub_415D50`. `sub_416660` drops a failing goal from the queue after five failures but never touches its need, and `sub_4165D0` queues the lowest need again on the very next tick. So a goal whose every candidate is out of reach **for that agent** pins its need at 0 for good, and from then on it beats every higher-numbered goal, which is never pursued again until a reaction resets the needs. One unreachable candidate among reachable ones only costs retries, because `sub_417120` draws a new random candidate on every attempt. Goals 5 and 6 are never disabled, so an empty goal-6 list pins its need just the same.

A candidate is out of reach in the original when its interaction point's cell is blocked, since the search never enters one. On the imported maps (levels 1–8 and the 5s and 8s points layouts, searched from each agent's spawn with the port's own search) every candidate of a goal is out of reach here:

| Level | Goal | Agents | Why |
| --- | --- | --- | --- |
| 1 | 6, smoking | everyone | the only ashtray, `STANDASCHER02`, has its interaction cell `(13, 5)` blocked |
| 2 | 1, drinks | the boss | his only drink (mask 266: rooms 1, 3 and 8) is the `WASSERKOCHER` at blocked `(2, 25)` |
| 2 | 6 | everyone | the boss has no ashtray in his rooms; the others only `STANDASCHER01`, at blocked `(4, 17)` |
| 2 | 7, relaxing | everyone | `SOFA01` at `(2, 5)` and `SESSEL01` at `(2, 4)` are both blocked |
| 3 | 1 | everyone | the only drink, a `WASSERKOCHER` at blocked `(9, 2)` |
| 3 | 2, decoration | everyone | all five candidates are blocked |
| 4–8 | 6 | everyone | no ashtray in anyone's rooms: an empty list, which is never disabled |
| 8 | 1 | everyone but the boss | the only drink in their rooms, `KAFFEEMASCHI`, at blocked `(1, 13)` |

The janitor's work goal belongs on the same list on every map he is on, as above. The effect is largest on level 3: once need 1 reaches 0 it outranks work too, and over 600 simulated seconds (seed 4091) none of the coworkers sat down to work after about 250 s; they only ate, and retried the kettle on 26–40 % of their ticks. On levels 2 and 4–8 goal 6 starves goal 7, so nobody relaxes except early in a level or after a reaction. All of this is inferred from the recovered rules; the original game was not run to compare, and the port adds nothing to soften it.

`LEVEL_00`'s only standing ashtray sits at tile `(12.79, 5.21)` and its interaction offset of `+0.6` in X keeps the approach inside cell `(13, 5)`, which the original collision grid marks blocked. Goal 6 therefore cannot complete on this map in the original either, and the port reproduces that: over 900 simulated seconds on five seeds the boss spends 2–8 % of his ticks retrying it.

**What to expect from the level-1 boss.** He uses the toilet every few minutes, but the sofa only now and then, and in some level starts never. Once his smoking need has decayed to 0 against the ashtray, goal 6 wins every tie against goal 7; the social goal, whose front cell is often blocked, does the same while it keeps failing. So he sits down early in a level, after being provoked, or not at all. Over 900 simulated seconds he sat on it once with seeds 42 and 7 (at 26.9 s and 30.1 s), twice with seed 11, and never with seeds 1037 and 99.

### What the wider cast changed

Level 2 spawns six of the seven characters at once, and `tests/check_npc_level_2_runtime.gd` runs all of them on the real map for two simulated minutes. Three things only show up there:

- **The secretary never changes clip when she reacts.** `sub_41E360` has no branch for the reaction flag at all, so `_start_reaction` asks her for `idle` rather than a `PISSED` her table does not name. She is angry — goal 8, the ANGRY bubble, the player's 25 points — without a pose for it. See [catch-reference.md](catch-reference.md).
- **The janitor has no seated work clip.** His table (`0x46EBD8`) holds only `SIT#EASY`, so every seated state resolves to it, and `STAND#USE` at slot 3 is named but never selected by `sub_41A8D0`. It is therefore not imported, and the brain asks for `SIT#EASY` on every seat.
- **Goal 4 completes.** An agent really does step inside a toilet cubicle. An agent performing any activity has been placed on the item's own anchor by `sub_4161E0` or `sub_416090` — inside a blocked cell, in the cubicle's case — so the runtime checks do not test a footprint. They assert the original's own invariant instead: an agent that is not on an item's anchor stands in a free cell, except on the interaction point it was stood back on and while it steps off it.

Before routes ended on cells, the footprint test cost much more on this map than on `LEVEL_00`: over those two minutes the janitor retried navigation 1143 times and the secretary 292, and the secretary never reached her own chair, `DREHSTUHL04`, whose interaction point is flush against a wall. Now they retry 9 times and not at all, and every agent with a desk on levels 2–8 sits down at its own chair within the two minutes, which `check_npc_level_2_runtime.gd` and `check_npc_campaign_runtime.gd` assert.

The port additionally releases claims and restores standing positions when a brain is disabled, removed, or its activity target/seat disappears. An action with no clip at all plays the idle fallback and warns once, matching `sub_41A510` rather than failing the goal. These are authoring/runtime safety behavior, not claims about original object-deletion handling. The isolated `tests/check_npc_brain.gd` exercises target filters, goal disabling, the arrival dispatch for each item class, work startup, durations, occupation, need resets, retry bounds, authored-route override, and interrupted/missing-action cleanup with a stub actor. `tests/check_npc_level_runtime.gd` runs the three original agents on the imported map for two simulated minutes, asserts someone uses the toilet, and with seed 42 checks that the boss sits on the sofa with `SIT#IDLE`. `tests/check_npc_routes.gd` covers the step back from a point flush against a wall and from inside a blocked cell.

## Thought bubbles

`agent+1080` is the agent's **current goal**, not a separate bubble field: `sub_416570`
clears it to `-1` along with the rest of the goal state, and `sub_4165D0` completes the goal
it holds before queueing the next one into `+1082`. `sub_417460` draws
`bubbleNames[agent+1080]` from the table at `0x46E7A8`, **135 pixels above** the agent at
alpha 180, so a bubble is up for exactly as long as its goal is.

The bubble is **not depth tested**. `sub_417460` sets the blitter's mode field (`+24` on the
object at `agent+68`, which `sub_42CCF0` masks to 6 bits to index a 64-entry blitter table)
to 7 for the agent itself and to **20** for the bubble, restoring it afterwards. Mode 20 is
one of the few entries that is the *same function* in the z-tested and untested tables
(`0x431030` for 8-bit sources, `0x446270` for 32-bit): it alpha-blends the source over the
back buffer and writes the z value, but never compares against it. So nothing already drawn
can hide a bubble, even though it is handed the agent's own z. The port reproduces that by
drawing the bubble above the world composite instead of into it; see
`scenes/npc/thought_bubble.gd`.

The table's ten entries therefore line up with the goals one for one:

| 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| FOOD | COFFEE | HAPPY | BACKTOWORK | TOILETT | SOCIAL | CIGARETTE | RELAX | ANGRY | REPAIR |

Goal **8 is the reaction state**: `sub_416090` and `sub_416450` set it. Goal 9 is written in
one place only, `sub_4164E0` at `0x416535`, and that write is never reached (see "Reacting to
a sabotaged object" below), so the `REPAIR` bubble is never seen. The port's brain raises
goals 0–8; the bubble carries all ten.

`sub_417460` also draws two things the port does not yet. One is the agent's name over its
head while `agent+1788` marks it as the coworker last clicked; the name, its pool and the
selection rule are in [names-reference.md](names-reference.md). The other is three jittered
green copies of the sprite while `agent+1792` is set.

## How angry the office gets

The console's bar at (410, 497) reads `game+14728`, and `sub_402350` rebuilds that every
frame as the **mean of every agent's own `agent+1076`**. Three things feed off it.

**Where an agent's own meter comes from.** `sub_4187F0` ends with
`agent+1060 = 100.0 / n`, where `n` counts how many of goals 0–4 came out of its candidate
scan with anything to aim at. `sub_417B00` then hands over one of those shares the first
time each goal is spoiled — the flag at `agent+980 + 4 * goal` makes it once per goal — and
clamps the total at 100. So an agent is at its angriest once that many different goals have
been ruined for it, which on level 1 is five.

The same branch has a special case for goal 3: an agent that walks to its **own
workstation** and finds it tampered with sets `agent+1032`, the disabled flag for that
goal, and gives up on working for the rest of the level. It also adds 25 to `agent+952`,
that goal's decay rate, which can never be felt because the goal it belongs to has just
been disabled.

**The bands.** `sub_402350` also writes `clamp(floor(mean * 0.04), 0, 3)` into every
agent's `agent+1064`, reading the mean as it stood at the start of the frame. `sub_419CE0`,
`sub_41E360` and `sub_41A8D0` walk at `base_speed + 0.15 * that`, so the whole office picks
up pace as it sours — up to 0.45 tiles a second at the top band. `sub_419740`, the boss,
reads the band but does not apply that formula. The same three ticks also add `0.2 * band`
to the notice radius and `5.0 * band` to the notice cone, so a soured office sees further
and wider as well as moving faster — see [catch-reference.md](catch-reference.md).

**The warning.** When the band rises, `sub_402350` calls `sub_407960`, which shows
`game+14740` — the `THERMO_UP` overlay the console builds hidden at (5, 5) — and sets
`game+14748` to 2.0. `sub_403780` counts that down by the frame delta and hides it again at
zero. The comparison is between *unclamped* bands, so an office already past the top band
cannot announce itself twice.

## Reacting to a sabotaged object

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
the flag actions 110 and 112 apply — is angry for as long as it stays locked in. Once its
cubicle timer has run out, every tick sets goal 8 (`0x416143`) and returns busy without
moving the agent off the item's anchor, so it stays inside. The first tick after `item+224`
clears, which only an item reset does (a finished repair, below), it steps back out onto the
interaction point and releases the cubicle. `sub_4165D0` then completes goal 8, and
`sub_415FD0` writes that goal's need slot, which lies past the eight needs `sub_416770`
decays (`0x4168F0`). So being let out satisfies nothing: the inmate still wants the toilet
it never got to use. The port does all of this. Its locked-in agent used to be stood back on
the interaction point at the end of its first timer and sulk outside the cubicle, and a
repair would only have let it out at the end of the current 10–12 second sulk.

The arrival path in `sub_417B00` awards **25 points** through `sub_41DEA0(0x19, x, y)` at the
agent's own position, which confirms the published walkthrough's "+25 when a colleague tries
something you broke" against the executable.

### What sets `agent+1820`

`0x417C86` is the **set**, not a clear, and it is the first thing `sub_417B00` does rather
than a case in its item-type switch:

```c
item = agent+1112;                       // the active item it walked to
if ( item && sub_418B10(item) == 1 && item+228 == 1 )
{
    ... goal-3 bookkeeping ...
    agent+1820 = 1;
    agent+1124 = rand01 * 2 + 10.0;      // busy 10 to 12 seconds
    for ( each entry in agent+1732 )     // the world's entity list
        if ( entry->obj->[112] == 1 )    // the player
            sub_41DEA0(25, agent+20, agent+28);
}
else { ... the ordinary item-type dispatch ... }
```

`sub_418B10` is a liveness check — it walks the world's item list for the pointer — so the
real test is **`item+228`**. `sub_41B240` sets that at `0x41B83D`, in the same breath as
clearing the used slot's flag at `item+slot+252`, and it is **unconditional**: finishing
*any* player action on an object leaves it tampered with, whatever the action did. Only the
item reset `sub_40FEF0` puts it back to 0, so within a level the mark is permanent.

Two consequences worth stating. The test is on `agent+1112`, the **active** item, so an
agent whose pick landed in the passive slot — a chair, a sofa, a plant — walks onto it
without noticing. And the reaction cannot live in the candidate filter: `sub_417120` picks
targets without consulting `+228`, so an agent has to walk all the way to a broken object
before it can be angry about it.

`sub_41DEA0` adds its 25 to `player+984`, the score, and calls `sub_40A0D0` to float the
number at the agent's position. The port does both: `_start_reaction` passes the agent's
position to `LevelSession.add_score`, which floats the number through
`scenes/effects/score_popup.gd` (see [hud-reference.md](hud-reference.md)).

### Animation

The reaction flag picks a slot from each archetype's own animation table, and the names are
not shared:

| Archetype | Table | Slot | Clip |
| --- | --- | --- | --- |
| Coworkers | `0x46EB44`, `sub_419CE0` | 7 | `PISSED` |
| Boss | `0x46EAE0`, `sub_419740` | 1 | `STAND#EXPLODE` |
| Secretary | `0x46EEE4`, `sub_41E360` | — | none — her tick has no `+1820` branch ([catch-reference.md](catch-reference.md)) |

Both ship 8 views and both loop. They are imported through
`tools/character_action_clips.json` as `pissed` and `explode`.

### What the port leaves out

`sub_417B00` does two more things in that branch that hook into systems the port does not
have yet:

- **`agent+1816` and `agent+1832`**: a janitor (`agent+1740 == 3`, tested at `0x417BCF`)
  whose broken item is one of the 30 types `sub_4180F0` lists files it as a repair job.
  Everyone else goes through `sub_4181F0` instead, which answers only for a type-173 cubicle
  (`0x418203`) with `item+224` set. The janitor's list holds both cubicles, 173 and 262, and
  he files them whether or not anyone is locked in. A locked type-262 cubicle
  (`TOIKABINE&EIMER`, lockable on levels 4 and 6) therefore waits for the janitor. Both
  branches also write `agent+1124`, but the unconditional 10-to-12-second write below them
  overwrites it, so the reaction is always the same length.

  **The job never shows the `REPAIR` bubble.** `sub_416770` runs its handlers as one
  short-circuit chain, `sub_416450` (`0x4168C8`) before `sub_4164E0` (`0x4168D4`), each ending
  the chain when it reports busy. The reaction flag `+1820` is raised at `0x417C86` whenever a job is
  filed (`+1816` is only written at `0x417BEA` and `0x417C2B`, and both fall through to it),
  so while the timer runs `sub_416450` sets goal 8 and ends the chain. At expiry it clears
  `+1820`, resets the needs and returns 0. `sub_4164E0` then sees the timer spent and takes
  its expiry branch, `sub_4100B0` on `+1832`. The `+1080 = 9` write at `0x416535` is
  unreachable.

  **Both halves are implemented.** `npc_brain.gd` files `_repair_job` in `_start_reaction`
  when the agent is a janitor and the item's type is in the exported table, or when anyone
  else meets a locked type-173 cubicle. It holds goal 8, the `ANGRY` bubble, for the
  reaction like any other. On `_on_activity_finished` it puts the item back: the activity
  point's `reset_actions()` plus state 0 on the object. The clip stays the reaction's own,
  because no per-tick function has a repair branch. The port used to raise goal 9 for a
  filed job, and let anyone file for any locked item, type 262 included.

  The cubicle route only works because picks ignore occupation (see "Goals and target
  selection"). While the brain dropped taken points from its candidate lists, a locked
  cubicle, whose inmate keeps its claim, could never be picked. `sub_4181F0` then never
  fired, and nobody locked in by action 110 or 112 was ever let out.
  `tests/check_npc_brain.gd` now runs the whole rescue: a colleague picks the locked, tampered,
  occupied cubicle, reacts, files the repair, and the repair's end lets the inmate out.

  The 30 types come from `tools/export_repairable_types.py`, which decodes `sub_4180F0`'s
  jump table out of the binary. What a finished repair does to the item, including that it
  clears `item+228` and releases a cubicle lock, is in
  [catch-reference.md](catch-reference.md).
