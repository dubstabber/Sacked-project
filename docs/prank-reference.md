# Original prank actions and item states

Verified on 2026-09-21 against a disposable copy of `sacked.exe.i64` and the shipped
`sacked.exe` (479232 bytes, SHA-256 `6404096c…`). The original executable and database were
not modified. Addresses are virtual addresses in that build, where RVA equals file offset.

## Where the action table lives

Every interactive object carries up to eight prank action ids. `sub_4103E0` resolves one:

```text
actinfo = 0x474C00 + 76 * item->m_action[p_set]
```

guarded by the asserts `p_set >= 0 && p_set <= 7` and
`m_action[p_set] >= 0 && m_action[p_set] <= 155` (`item_crazyoffice.cpp`), so the table is
**156 records of 0x4C bytes** at `0x474C00`.

The table is not a static array in the data section. The compiler emitted one straight-line
initializer, `sub_40A600` (reached through the `jmp` thunk at `sub_40A5F0`), that fills it
through registers: 3779 instructions, only `mov`/`xor`/`push`/`pop`/`ret`, no branches and
no calls, performing 3588 stores that all land inside `[0x474C00, 0x477A50)`. Individual
records are interleaved, and many values arrive in registers rather than as immediates, so
the table can only be read by replaying those stores. `tools/export_action_table.py` does
exactly that with a whitelist-only interpreter and refuses to run on any other build.

Three supporting static pointer tables are read directly:

| Table | Address | Entries |
| --- | --- | --- |
| Action names (localised) | `0x46BD04` | 156 |
| Action icon sprite names | `0x46C100` | 66 (assert `aicon[b] <= 65`) |
| Item state sprite names | `0x46DD54` | 16 |
| Thought bubble sprite names | `0x46E7A8` | 10 |

Action names are pooled: only 126 of the 156 slots are distinct, 27 point at the shared
placeholder `"..."` (`0x46BAE4`, the same literal the idle hover bar shows), and a record's
name is whatever the initializer copied into it — record 154 takes slot 84's string. Take
the name from the traced record, never from `names[id]`.

## Record layout

Offsets confirmed from the consumers; `sub_41B240` (`obj_player.cpp`) is the only function
that ever dereferences an `actinfo` pointer, so this list is complete.

| Offset | Type | Meaning | Read by |
| --- | --- | --- | --- |
| `+0x00` | `char*` | Display name, shown in the hover bar while the slot is highlighted | `sub_4101F0` |
| `+0x04` | `u8` | Index into the 66-entry ACTICON table | `sub_410170` |
| `+0x08` | `u32` | Score awarded on completion | `sub_410190` |
| `+0x0C` | `u32` | Duration in **tenths of a second** | `sub_4101B0` |
| `+0x10` | `u32` | Written, never read |
| `+0x14` | `u32` | Written, never read (non-zero on one record) |
| `+0x18` | `u8` | Player animation selector, 0–14 | `sub_4101D0` |
| `+0x19` | `u8` | Item id granted to the player | `sub_410240` |
| `+0x1A` | `u8` | Remove the object from the world afterwards (`sub_413310`) | `actinfo+26` |
| `+0x1B`, `+0x1C` | `u8[2]` | Required item ids; each is decremented on use | `sub_410260(item, set, 0/1)` |
| `+0x20` | `u32[4]` | Action ids this action **unlocks** on the same object | `sub_410450` |
| `+0x30` | `u32[4]` | Action ids this action **disables** on the same object | `sub_410450` |
| `+0x40` | `u16` | Resulting item state (plus the two markers below) | `sub_410210` |
| `+0x42` | `u8` | Apply the state at action **start** instead of on completion | `actinfo+66` |
| `+0x44` | `char*` | Sound id, e.g. `S0067` | `actinfo+68` |
| `+0x48` | `u8` | Play that sound at start rather than on completion | `actinfo+72` |

`sub_41D820` ignores a required-item slot whose value is `>= 0x1F`. No shipped record uses
such a value, so that guard never fires; all 43 records with a prerequisite name a real
item, and only the three `Zapal sobie` rows (22, 23, 24) need two at once.

## Item states

`sub_40FDA0(item, state)` clamps the state to 0–15, stores it at `item+124` and selects the
animation at `item + 128 + 4*state`. The 16 names at `0x46DD54` are:

```text
0 IDLE   1 USE   2..8 DESTROY_1..7   9..15 DESTROYED_1..7
```

**`DESTROY_1..7` (2–8) play once; every other state loops** — `sub_40FDA0` clears the loop
flag at `anim+548` exactly for `2 <= state <= 8`. This answers the copier's "state 9" noted
in `npc-reference.md`: state 9 is `DESTROYED_1`, a 25-frame looping clip, not a one-shot.
`NIXDA` (`0x46DF3C`) is not a state; it is the fallback name `sub_410715` uses when a
sprite lookup produces a null name.

Two `+0x40` values are markers rather than states: **17** means the object keeps its state
(the pickups), and **18** sets `item+232` for the duration of the action and clears it
afterwards. `sub_4100B0` resets an object: each of its eight slots is enabled when its
action id is non-zero, every id named in an enabled slot's **unlock** list is then disabled,
and the object is put in state 0.

## Availability

`sub_41D820(player, p_iact)` decides whether a slot appears in the round menu. In order:

1. There is a focus item and `m_action[p_iact] != 0`.
2. Both required item slots are satisfied from the player's inventory at `player+1008`.
3. The slot is enabled in the object's own `m_actionEnabled[]` at `item+252`.
4. Three action ids are additionally gated on cubicle occupancy (`item+216`):
   ids **43, 44, 138** need the cubicle **free**; id **110** needs it occupied by an agent
   whose type (`agent+1740`) is not 1; id **112** needs the occupant to be the boss, type 1.

`sub_41DA50` then fills the menu from the surviving slots, recording the action id, its
icon, its name and the slot index in `m_actionMap` (`player+972`).

## Player action flow

`sub_41B240` is the player's action state machine (`player+904`):

| State | Behaviour |
| --- | --- |
| 0 | Turn to face the focus item, play animation slot 0, build the menu, hover text `"..."` |
| 1 | Menu open; the hover bar shows the highlighted slot's action name |
| 2 | Commit: pick the animation from `+0x18`, arm the timer from `+0x0C`, apply the start-time state and sound if flagged |
| 3 | Tick until `elapsed >= duration / 10` seconds |
| 4 | Apply: score, required items decremented, resulting state, unlock/disable lists, granted item, optional removal, end-time sound, score popup |
| 5 | Abort: restore a start-time state and the saved position |

The `+0x18` selector maps to animation slots through `sub_41A510`:
`0→3, 1→4, 2→5, 3→6, 4→19, 5→17, 6→9, 7→10, 8→16, 9→15, 10→13, 11→14, 13→18, 14→20`, and
`12` picks slot 8 with a randomised facing (the urination actions). Selector 5 additionally
repositions the player onto the object (+0.8/+0.85 tiles, facing chosen from the object's
orientation) — entering a toilet cubicle — and state 4/5 restore the saved position when the
current slot is 17. `sub_41A510` indexes `entity + 4*(direction + 8*(slot+4))`, so slot
numbers are entity animation-array indices; which clip each slot holds for the player is not
recovered yet and is deliberately left to the task that imports the player action clips.

Granted items are added to `player+1008`: ids 6 and 9 are set to 99 rather than incremented
(inexhaustible), and id 22 adds 3. Score is added at `player+984` by `sub_41DE60`, which
also spawns the floating number.

Four action ids have global consequences beyond their own object (`sub_41DC80`): **79** puts
every item of type 253 into state 9, **116** does the same to the nearest type-265 item
within ±5 tiles, **118** to every item of category 9, and **110/112** set `item+224` on the
cubicle to lock the occupant in.

## What LEVEL_00 is worth

`tools/export_action_table.py --report --level 1` cross-references the traced table with the
imported level manifest and `CO_OBJECTS.DAT`. LEVEL_00 places **66 action rows** across its
71 objects, against a `CONDITION` score target of 4000:

| Class | Rows | Points | One action per object |
| --- | --- | --- | --- |
| No prerequisite | 31 | 6450 | 4250 |
| Pickup (grants an item) | 11 | 850 | 800 |
| Needs an item | 21 | 4750 | 4200 |
| Locked until another action | 3 | 600 | 400 |

So the target is reachable from prerequisite-free actions alone, with room to spare, and an
inventory is an enrichment rather than a gate for this level. Two of those free rows are the
cubicle-occupancy ones (110 at 250, 112 at 400), which the port cannot currently trigger
because its NPCs cannot reach the LEVEL_00 toilet (`npc-reference.md`); excluding them still
leaves 5800 points.

These point values agree with the published walkthrough for the German release — lock a
colleague in the toilet 250, lock the boss 400, urinate in the coffee pot 1000 — which is
secondary evidence only and is used by the exporter for nothing.
