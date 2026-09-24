# The player's side of a prank

Verified on 2026-09-21 against a disposable copy of `sacked.exe.i64` and the shipped
`sacked.exe` (479232 bytes, SHA-256 `6404096c…`). The original executable and database were
not modified. Addresses are virtual addresses in that build, where RVA equals file offset.

This covers how an object becomes the focus, how the round menu is built and opened, which
input drives each step, and where pause, quit and the camera live. What each action record
means is in [prank-reference.md](prank-reference.md); this is the machinery around it.

## Player fields

`game+14676` is the player. Within it:

| Offset | Meaning |
| --- | --- |
| `+900` | Top-level mode: 0 free, 1 item action, 2–5 the other four `sub_41CFC0` branches |
| `+904` | State inside that mode. Mode 1 uses 0–5; the others use 10–13, 20–23, 30–33, 40–43 |
| `+908` | Input mask, copied wholesale from `game+12736` every tick |
| `+912` | `m_focusItem` |
| `+920` | `m_itemAction`, the highlighted **menu entry**, or −1 |
| `+921` | `u8[8]` action id per menu entry |
| `+929` | `u8[8]` ACTICON index per menu entry |
| `+940` | `char*[8]` action name per menu entry |
| `+972` | `u8[8]` **slot index** per menu entry (`m_actionMap`) |
| `+980` | `u16` number of menu entries (`m_itemSelectNum`) |
| `+984` | Score |
| `+988` | Character flag; selects the urination facings (see below) |
| `+992` / `+1000` | Elapsed and total action time |
| `+1008` | `u8[…]` inventory, indexed by item id |
| `+1040` | Item state saved before a start-time state change, restored on abort |
| `+1068` | Countdown; on expiry every type-253 item returns to state 0 (`sub_411070`) |
| `+1104` / `+1108` / `+1112` | Sound context, idle sound handle, action sound handle |
| `+1128` | Hover bar text |
| `+1132` | Position saved before the player is moved onto an object |

**`m_actionMap` holds slot indices, not action ids.** `sub_41DA50` writes the loop counter
`n7` (0–7) there, the `amap >= 0 && amap <= 7` assert guards it, and every accessor
(`sub_4101D0`, `sub_410190`, `sub_410210`, `sub_4103E0`, `sub_410260`, `sub_410240`,
`sub_410450`) takes a slot and resolves it through the focus item. The action id is read
separately as `item+244+slot`.

## Choosing the focus item

`Main_RenderUpdate` (`0x4028C0`) does this every frame, immediately before drawing the quit
prompt. It runs only when `game+15028 == 0`, `game+15084 == 1` (no round menu open) and the
player's mode `+900` is 0:

1. `sub_4132E0(game+15012, game+15016)` picks the item under the mouse cursor.
2. The item must answer 1 to `vtbl+44`, and is marked hovered with `item+204 = 1`.
3. `sub_410030` gives the item's interaction position, `sub_42B370` the player's. Both get
   `+0.5` added on each axis, and the difference is taken.
4. `sub_41D7F0` sets the focus item, which calls `sub_41DA50` to build the menu.
5. The item is then tinted through `item+4..7` (RGBA) and either kept or dropped:

| Condition | Tint | Focus |
| --- | --- | --- |
| Menu is empty (`player+980 == 0`) | `(255, 50, 50, 180)` red | dropped |
| Menu non-empty, but out of range or no line of sight | `(255, 255, 50, 180)` yellow | dropped |
| Menu non-empty, in range, line of sight clear | `(255, 255, 255, 180)` white | kept |

Range is `sqrt(dx² + dz²) <= 2.0` logical tiles, and sight is `sub_412E30` between the two
points in quarter-cell units (`×4`), the `INFODATA` bit 1 ray from
[collision-reference.md](collision-reference.md). That ray is an integer Bresenham walk in
quarter cells, converting each sample to a cell with `>> 2` and stopping at the first one
that blocks; it tests every sample from the start to the destination inclusive, so an
interaction position inside a sight-blocking cell can never be focused. None of level 1's
38 are.

**The player never walks to an object.** There is no pathfinding on this route: an object
out of range simply tints yellow and cannot be acted on until the player has walked close
enough by hand. The interaction position is only ever used as the point to measure from, so
the port does not need it to be a standable cell — which is why 20 of level 1's 38 prankable
placements having an unreachable interaction point does not matter here.

A second, independent pick (`sub_42BF20`) highlights the character under the cursor into
`game+14696`, tinted `(255, 255, 255, 200)`, and `sub_41D810` records it.

## Building the menu

`sub_41DA50(player)` walks slots 0–7, and for each one `sub_41D820` accepts (the filter in
[prank-reference.md](prank-reference.md)) appends the action id, the ACTICON index, the name
and the slot index to the four arrays above, counting into `+980`. Remaining entries are
zeroed and their names set to the shared `"..."` literal. With no focus item, all eight are
cleared.

## Opening the ring

`sub_406510` opens it, `sub_4066D0` closes it, and `game+14792` is the open flag. The tick
`sub_403780` drives both: entering state 1 opens the ring, and any state other than 1 or 5
closes it, as does leaving mode 1 altogether.

`sub_41DB60` collects the icon indices; if it returns 0, or any index exceeds 65, the open
fails and `sub_403780` sends the machine straight to state 5 (abort). Each entry becomes a
button authored against an 800×600 reference with layer 0, carrying the ACTICON name from
the 66-entry table at `0x46C100`.

The menu object is then placed at **x 400, y 200, on layer 100** — `+8`/`+12` are a GUI
element's position and `+16` its layer, as `sub_405930` uses them for the console. So the
ring is centred horizontally and centred vertically in the 0–400 band the console leaves
free, rather than in the 600-pixel window. Opening highlights the first entry
(`player+920 = 0`) and clears `game+15084`, which is what suspends focus picking while the
ring is up. The buttons are created at (800, 600) on layer 0 and moved into place by the
menu itself.

### How long the selection lives

`player+920` is the selected menu slot, and it is **not** cleared when the ring shuts.
`sub_41B240` writes `-1` into it in exactly two places: its case 4, once the action has
applied, and its case 5, when the action is cancelled. Committing (case 2) instead
re-asserts the chosen entry's name into `player+1128`, and case 3 — the action running —
touches neither.

`sub_41CFC0` picks the player's tick from `player+900`, and the one for "no action session"
is `sub_41B0C0`, which writes `player+1128 = "..."` on both its branches, standing and
walking. So the hover bar is restored the first frame after the action ends rather than
lingering.

The console reads both fields every frame (`sub_403780`), so the practical effect is that
**the centre icon and the hover bar keep showing the committed action for its whole
duration** and clear together when it applies. See
[hud-reference.md](hud-reference.md).

### How the ring is laid out

`CGUIRoundMenu::Draw` is `sub_45BC90` and its tick is `sub_4066D0`. Together they place
every button each frame:

```text
R       = menu+96 * 1.5                       the ring radius
theta   = menu+104 - i * 0.60000002 + PI      entry i's angle
button  = (menu+8 - 16 + sin theta * R, menu+12 + cos theta * R), layer menu+16
```

- **The pitch between entries is a fixed 0.6 radians (~34.4°)**, not a share of a full turn,
  so the entries sit on an arc whose length grows with the entry count rather than spreading
  around the circle. Eight entries cover 4.2 radians and still do not meet. The two
  constants cross-check each other: at radius 90 a 0.6 radian step puts neighbouring
  entries `2 * 90 * sin(0.3) = 53.2` pixels apart, which clears a 48-pixel ACTICON by five.
- **`menu+104` is an animated rotation, not a constant.** `sub_45BEC0(index)` stores the
  highlighted index at `+124` and its target angle `index * 0.6` at `+136`; the draw walks
  `+104` toward it by `frame_delta * menu+112` per frame and snaps once the gap is under
  0.01. `sub_405930` sets `+112` to **5.0**, overriding the constructor's 0.1. The
  highlighted entry is therefore the one rotated to `theta = PI`, which is **straight above
  the centre** — the ring turns under a fixed cursor rather than the cursor moving over it.
  The draw measures that gap *before* it moves, so the frame that lands on the target still
  reports the ring as turning and only the one after it reports it settled.
- **The radius animates the menu open and shut.** `sub_4066D0` grows `menu+96` from 0 toward
  **60** at `frame_delta * 150.0` while the menu is opening and shrinks it the same way
  while it closes, hiding the menu once it reaches 0. So the ring's settled radius is
  `60 * 1.5 = 90` pixels, and it opens and shuts in 0.4 seconds.
- **The `-16` is a plain nudge, not centring.** Every `CO_GUI_ACTICON` sprite is 48 × 48 and
  `CGUIRectangle` draws one from its top left, so subtracting 16 from x alone does not
  centre anything — it just shifts the whole ring left. Reproducing that asymmetry is the
  faithful choice.
- **Selection is stepped, not pointed at.** `sub_4066D0` reads the input flags at
  `game+12740`: bit 0 steps `player+920` down, bit 1 steps it up while it stays below
  `player+980 - 1` (the entry count), and bits 2 or 4 commit. `sub_45BE80` returns `+100`,
  the draw's own "still turning" flag, and gates both steps on it, so at most one step lands
  per turn of the ring. `sub_403FB0` builds those bits fresh every frame, so a step the ring
  was too busy for is dropped rather than queued.
- **The steps come from horizontal mouse motion.** In `sub_403FB0` the mouse-motion event
  carries `(dx, dy)` — `sub_415400` adds them to the cursor, so they are relative — and
  `dx < -8` raises bit 0 while `dx > 8` raises bit 1. Two unidentified scancodes, 111 and
  112, raise the same bits. Commit is bit 4, which is **space (scancode 57) or the mouse
  button**, or bit 2, scancode 109. The port's `interact` action is already space and the
  left button, so committing needed no change.
- **The highlight is a tint, not a dimming.** The draw writes `(255, 255, 128)` into the
  selected button's colour fields at `+1160..1162` and `(255, 255, 255)` into every other
  one. When the menu's byte at `+120` is not `0xFF` it writes `(0, 0, 0)` instead, which
  `CGUIRectangle::Draw` reads as "no modulate at all" rather than as black.
- **`+120` is a gate, not a fade.** `sub_4066D0` feeds it `radius / 60 * 254 + 1`, but the
  draw only ever compares it against 255, so in practice the tint simply arrives with the
  last pixel of the opening ring. Nothing reads the `+16.0` / `-16.0` that the open and
  close passes write to `+108`.

The port follows all of this in `scenes/hud/round_menu.gd`, checked by
`tests/check_round_menu.gd`. It steps on `InputEventMouseMotion.relative.x` and leaves the
two unidentified scancodes unbound.

## How the highlight is drawn

The item loop in `Main_RenderUpdate` draws each item once through `vtbl+12`, and then, if
`item+92 == 1`, draws **the same sprite a second time** on top:

```text
alpha mode 54
sub_42D1D0(item+7)
sub_42D1E0(item+4, item+5, item+6)     // the RGB from the table above
sub_42D200(120 - sin(item+72 * 2.5) * -80.0)
vtbl+12(item)                          // draw again
```

So the item itself is never modulated and never goes transparent — the highlight is an
additive second pass whose alpha swings between **40 and 200** at 2.5 rad/s, which is what
makes it pulse. `item+72` is the item's own phase and `item+4..6` the tint colour.

The port reproduces that directly: the object stays in the static world composite, opaque
and untouched, and a second sprite is drawn over it with
`scenes/shared/object_highlight.gdshader` — `blend_add`, the same depth test characters use
so the pulse only reaches pixels where the object is actually visible, and
`modulate = (tint.rgb, 120/255 + 80/255 * sin(2.5 t))`.

## The player's animation slots

`sub_41A510(entity, slot)` indexes the player's animation array, and the clip each slot
holds is named by a 21-entry table of `char*` at **`0x46EC04`**:

| Slot | Clip | Slot | Clip | Slot | Clip |
| --- | --- | --- | --- | --- | --- |
| 0 | `IDLE#1#ATMEN` | 7 | `PISS#1` | 14 | `PHONE#CALL` |
| 1 | `IDLE#2` | 8 | `PISS#2` | 15 | `PHONE#TYPE` |
| 2 | `WALK` | 9 | `STEAL` | 16 | `KETCHUP` |
| 3 | `STAND#USE` | 10 | `DRINK` | 17 | `ASSCOPY` |
| 4 | `KNEE#USE` | 11 | `FOAMING` | 18 | `BUCKET` |
| 5 | `KICK` | 12 | `SMOKE` | 19 | `FLIPBAG` |
| 6 | `PUNCH` | 13 | `SPRAY` | 20 | `FLIPBAG2` |

Composed with the selector map in `sub_41B240`, a record's `+0x18` therefore chooses:

| Selector | Slot | Clip | Selector | Slot | Clip |
| --- | --- | --- | --- | --- | --- |
| 0 | 3 | `STAND#USE` | 8 | 16 | `KETCHUP` |
| 1 | 4 | `KNEE#USE` | 9 | 15 | `PHONE#TYPE` |
| 2 | 5 | `KICK` | 10 | 13 | `SPRAY` |
| 3 | 6 | `PUNCH` | 11 | 14 | `PHONE#CALL` |
| 4 | 19 | `FLIPBAG` | 12 | 8 | `PISS#2` (random facing) |
| 5 | 17 | `ASSCOPY` | 13 | 18 | `BUCKET` |
| 6 | 9 | `STEAL` | 14 | 20 | `FLIPBAG2` |
| 7 | 10 | `DRINK` | | | |

Selector 5 being `ASSCOPY` explains the reposition it carries: the player steps onto the
copier before photocopying himself.

### The reposition, recovered

`sub_41B240`'s selector-5 branch at `0x41B484` reads the focused item's orientation, a signed
16-bit quarter-turn index at `item+196`, multiplies it by 90.0 and compares the result with
90.0 again. Orientation 0 takes one branch and everything else the other:

| Orientation | Facing set | Offset added to the player |
| --- | --- | --- |
| 0 | 2, the `090` view | `(+0.80, +0.85)` |
| 1, 2, 3 | 4, the `180` view | `(+0.85, +0.80)` |

The two facings are exactly the two views `ASSCOPY` ships, which is why it has two rather
than eight. The move itself is a third call taking the new x, the new y and **1.8**, and the
branch ends by pushing animation slot 17. The constants are at `0x4658F4` (90.0), `0x4658F0`
(0.8) and `0x4658EC` (0.85), with 1.8 as an immediate.

The port's level manifests already carry each object's orientation as its `variant` field,
and level 2's single copier is orientation 0, so it takes the first row.

The campaign reaches selectors 0–14, and the port imports all fifteen clips for both
characters — 109 views each, listed in `tools/character_action_clips.json`, which the frame
exporter and the library importer both read. Selector 13, `BUCKET` at slot 18, is carried by
action 151 `Wlej wodę do kabiny` on one `TOIKABINE&EIMER` per level on levels 4, 6, 9, 12,
13, 14, 20 and 21, so levels 1 and 2 alone never show it. `check_player_action_clips.gd`
fails on any placed selector without a clip rather than skipping it.

Two things in the source needed care:

- **`ASSCOPY` ships only two views**, `090` and `180`, because the original repositions the
  player onto the copier and so only ever shows it from the two sides it can be stepped onto
  from. `PrankController._step_onto_object` applies that reposition, and the clip then plays
  from whichever of the two sides it chose.
- **`ANNE_ASSCOPY_090`'s pivot is negative.** `SPRITEHDR` stores it as a signed 16-bit pair,
  but the extraction helper read it unsigned, so `pivot_x` comes through as 65531 where it
  means −5, and the reference JSON's `offset.x` carries −65531 to match. The library importer
  sign-extends it and rejects anything still beyond ±4096, which would otherwise place a
  sprite most of a screen away. Every one of the 6903 extracted frames has
  `offset == -pivot`, so the importer reads the pivot and negates it rather than trusting the
  precomputed offset.
- **Eleven frames ship no Z plane.** They are the even-numbered frames of
  `ANNE_PHONE#CALL_135`, which have no `SPRITEZB.bin`. The exporter already draws such a
  frame without a depth mask, reproducing the engine's own untested blit, so the five clips
  land as 728 colour frames and 717 masks.

Together the five clips add about 12 MB to LFS, rather more than the 3.6 MB estimated before
they were exported.

## While an action runs

`sub_4154B0(game+15000, 1)` puts up the clock cursor for the whole of states 2, 3 and 4 of
any mode, and the player is playing an animation rather than walking. The port therefore
swaps in `images/gui/cursors/clock-000.png` and sets `input_locked` on the player for the
length of the action, releasing both when it applies.

## The action machine

`sub_41CFC0` dispatches on mode `+900`; mode 1 is `sub_41B240`, whose six states are listed
in [prank-reference.md](prank-reference.md). Corrections and additions found here:

- **State 0** turns to face the item with
  `180 - atan2(item_x - player_x, item_z - player_z) * 57.29579`, then plays slot 0.
- **The urination facings come from `player+988`.** Selector 12 picks slot 8 and, with the
  flag set, one of directions 2/3/4; with it clear, one of 0/6/7 — which is exactly the
  split between Anne's `PISS` views (090/135/180) and Jo's (000/270/315). Each choice is a
  `rand() & 8` test, so the three are not equally likely: the first is taken half the time
  and the other two a quarter each.
- **An object is only removed when the action also grants an item.** The `+0x1A` removal
  branch in state 4 is nested inside `if (granted_item)`, so a record that sets removal
  without granting anything never fires it.
- **Four action ids pick their result state from the object's current one**, ignoring the
  table's `+0x40`, when the action has no start-time state:

  | Action id | Current item state → new state |
  | --- | --- |
  | 12 | 12 → 6, 9 → 4, otherwise 3 |
  | 44 | 11 → 5, otherwise 2 |
  | 46 | 9 → 4, otherwise 3 |
  | 99 | 12 → 6, 15 → 4, otherwise 3 |

- State 4 also sets `item+228 = 1` on the object, clears the slot's enabled flag before
  applying the unlock and disable lists, and calls `sub_41DE60(score)` last.

## Input

`sub_403FB0` turns events into the mask at `game+12736`, which `sub_403780` copies into
`player+908`. The mask is cleared each frame with `&= 0xFFFF82FF`, so only bits 0–7, 9 and
15 persist; bit `0x400` is therefore a one-frame edge. If bit `0x100` was set last frame the
mask is first reduced to its low four bits.

| Bit | Meaning |
| --- | --- |
| `0x0001` … `0x0008` | Camera pan left / right / up / down (arrow scancodes 75, 77, 72, 80) |
| `0x0010`, `0x0020`, `0x0040`, `0x0080` | The four movement axes, combined for diagonals |
| `0x0100` | Right mouse button held |
| `0x0200` | Camera follows the player — the default, set at `0x401362`, `0x40468E`, `0x4047AE` |
| `0x0400` | **Act**: start the item action |

`sub_41CF20` is what consumes it: with `0x400` set and a focus item present it puts the
player into mode 1 state 0; bits `0x800`, `0x1000`, `0x2000` and `0x4000` start modes 2–5.

Raising `0x400`: **scancode 57 (space)**, and a mouse event whose third field carries `0x10`
— the click. Holding the **right mouse button** (button mask bit 2) instead sets `0x100`,
switches the cursor to mode 2 and converts the cursor's 8-way direction index
(`game+15024`, taken `& 7`) into the movement bits:

```text
0 → 0x20|0x40   1 → 0x20   2 → 0x20|0x80   3 → 0x80
4 → 0x10|0x80   5 → 0x10   6 → 0x10|0x40   7 → 0x40
```

That branch is gated on the player being in free mode or with the menu open, which is how
right-clicking doubles as the menu's cancel.

**Cancelling the menu.** At the end of `sub_403FB0`, if escape was pressed (`game+12740`
bit `0x40`), or movement bit `0x80` is set, or the right button is held (`0x100`), a player
in state 1 is moved to state 5. Escape itself is scancode 1, and it only cancels: it is not
a quit key.

**Cursor**, via `sub_4154B0(game+15000, mode)`:

| Mode | When |
| --- | --- |
| 0 | Anything else — the pointer |
| 1 | The player's state is 2, 3 or 4 within any mode (`{2,3,4, 11,12,13, 21,22,23, 31,32,33, 41,42,43}`) — the clock, shown while an action runs |
| 2 | Right button held — the directional walk arrow |

Mouse movement also feeds `sub_415400(game+15000, dx, dy)`, and a horizontal delta past ±8
sets `game+12740` bit 1 or 2.

## Pause, quit and the camera

**Pause** is `game+12740` bit `0x20`, toggled by **scancode 121** and refused while screen
`game+19044` is 4 (the caught pause). `sub_403780` returns immediately while it is set, so the clock,
the HUD and every agent stop; `Main_RenderUpdate` keeps drawing and adds a panel spanning
(49, 232) to (750, 372) with the level's target and time limit and the word `Pauza`,
centred on x 400 with a two-pixel drop shadow at (402, +2). The points game prints the two
values on separate lines (`Format_0`, `Format_1`); the time game uses one line (`Format`).
Limit and target fall back to 1200 s and 10000 exactly as the tick does.

**Quit** is **scancode 16 (`Q`)**, also refused on screen 4, and calls `sub_407370(game, 10)`.
That case sets the pause bit (0x4075AF), so the game **stops behind the prompt**, and
`Main_RenderUpdate` draws the pause panel together with screen 10's overlay from (49, 150)
to (750, 230) holding the prompt and `(T)ak lub (N)ie`. While it is up only
`sub_404990`'s case 10 reads keys: `T` (`J` in the German build), or code 44 (DIK_Z,
labelled `Y` on a QWERTZ keyboard) in both builds, goes to the main menu;
`N`, Enter or Space go back to the level with the pause bit cleared; nothing else does
anything. See [game-rules-reference.md](game-rules-reference.md) for the codes and what the
port binds.

Scancodes 1, 16, 57 and the arrows 72/75/77/80 are standard set-1 codes. The remaining
handled codes — 109, 111, 112, 114 and 121 — set camera and debug bits and the pause flag,
but which physical keys they are on the original's target layout is not recovered; 121 is
the pause toggle whatever it is labelled.

**Camera.** `game+12744` is the camera and `game+14700` its follow target. With bit `0x200`
set the target is the player; otherwise the target is cleared and the camera free-pans, its
direction taken from a 16-entry table at `0x46B424` (stride 12 bytes) indexed by the four
pan bits remapped as `bit1→0, bit0→1, bit2→3, bit3→2`, scaled by `game+12804 × dt` into
`game+12748/12752/12756`. It clamps nothing: `CIsoCamera`'s virtual at `0x409240` only
rebuilds its rectangle as ± the 400 / 300 half-extents, and `sub_402590` copies the follow
target's position into it every tick; see "The camera" in [widescreen.md](widescreen.md).

## HUD bindings confirmed here

`sub_403780` feeds the console directly, which settles the open questions in
[hud-reference.md](hud-reference.md):

- Round bar `game+14724`: `+112 = player+992 * 100 / player+1000`, zero when no action runs.
- Thermometer `game+14732`: `+1144 = 0`, `+1148 = 188 - (game+14728 * 1.42 + 46)`.
- Centre icon `game+14736`: hidden when `m_itemAction` is −1 or its icon index is −1,
  otherwise the **highlighted** entry's ACTICON name.
- Lamps: smoking `game+14776` needs inventory 5 **and** 6, Matrix `game+14768` needs 14,
  urination `game+14772` needs 26.
- Score `%05u` from `player+984`; clock `%02u:%02u` from `game+14708`, `XX:XX` past 5940.
- The looping warning `S1012` starts once `limit - elapsed <= 10`, its handle in
  `game+19056`.
