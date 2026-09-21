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

### How the ring is laid out (recovered, not yet implemented)

`CGUIRoundMenu::Draw` is `sub_45BC90` and its tick is `sub_4066D0`. Together they place
every button each frame:

```text
R       = menu+96 * 1.5                       the ring radius
theta   = menu+104 - i * 0.60000002 + PI      entry i's angle
button  = (menu+8 - 16 + sin theta * R, menu+12 + cos theta * R), layer menu+16
```

- **The pitch between entries is a fixed 0.6 radians (~34.4°)**, not a share of a full turn,
  so the entries sit on an arc whose length grows with the entry count rather than spreading
  around the circle.
- **`menu+104` is an animated rotation, not a constant.** `sub_45BEC0(index)` stores the
  highlighted index at `+124` and its target angle `index * 0.6` at `+136`; the draw walks
  `+104` toward it by `frame_delta * menu+112` per frame and snaps once the gap is under
  0.01. `sub_405930` sets `+112` to **5.0**, overriding the constructor's 0.1. The
  highlighted entry is therefore the one rotated to `theta = PI`, which is **straight above
  the centre** — the ring turns under a fixed cursor rather than the cursor moving over it.
- **The radius animates the menu open and shut.** `sub_4066D0` grows `menu+96` from 0 toward
  **60** at `frame_delta * 150.0` while the menu is opening and shrinks it the same way
  while it closes, hiding the menu once it reaches 0. So the ring's settled radius is
  `60 * 1.5 = 90` pixels. The same value drives the fade: the global alpha is set to
  `radius / 60 * 254 + 1`, and the open/close passes set a bias of `+16.0` / `-16.0`.
- **The `-16` is only on x.** Buttons are `CGUIRectangle`s drawn from their top left, so the
  ring is half-centred horizontally and hangs from the top edge vertically. Reproducing that
  asymmetry is the faithful choice.
- **Selection is stepped, not pointed at.** `sub_4066D0` reads the input flags at
  `game+12740`: bit 0 steps `player+920` down, bit 1 steps it up while it stays below
  `player+980 - 1` (the entry count), and bits 2/4 commit. `sub_45BE80` gates the step on
  the rotation having settled.
- **The highlight is a tint, not a dimming.** The draw writes `(255, 255, 128)` into the
  selected button's colour fields at `+1160..1162` and `(255, 255, 255)` into every other
  one; when the menu's byte at `+120` is not `0xFF` they all go black.

The port does not do any of this yet: `scenes/hud/round_menu.gd` spaces the entries evenly
over a full turn on a fixed 64-pixel radius, picks the entry under the mouse, and dims the
rest instead of tinting the selected one. The angles it uses follow the engine's circle
convention from `sub_45A9E0` — angle zero at the top, running clockwise
(`x = cx + sin a * r`, `y = cy - cos a * r`).

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

Level 1 can reach selectors 0, 1, 2, 3, 6, 7, 8, 9 and 12, so the port imports those nine
clips for both characters — 67 views each, listed in `tools/character_action_clips.json`,
which the frame exporter and the library importer both read.

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
`game+19044` is 4 (loading). `sub_403780` returns immediately while it is set, so the clock,
the HUD and every agent stop; `Main_RenderUpdate` keeps drawing and adds a panel spanning
(49, 232) to (750, 372) with the level's target and time limit and the word `Pauza`,
centred on x 400 with a two-pixel drop shadow at (402, +2). The points game prints the two
values on separate lines (`Format_0`, `Format_1`); the time game uses one line (`Format`).
Limit and target fall back to 1200 s and 10000 exactly as the tick does.

**Quit** is **scancode 16 (`Q`)**, also refused on screen 4, and calls `sub_407370(game, 10)`.
Screen 10 is drawn by `Main_RenderUpdate` as an overlay panel from (49, 150) to (750, 230)
holding the prompt and `(T)ak lub (N)ie`; the rest of the game keeps running behind it.

Scancodes 1, 16, 57 and the arrows 72/75/77/80 are standard set-1 codes. The remaining
handled codes — 109, 111, 112, 114 and 121 — set camera and debug bits and the pause flag,
but which physical keys they are on the original's target layout is not recovered; 121 is
the pause toggle whatever it is labelled.

**Camera.** `game+12744` is the camera and `game+14700` its follow target. With bit `0x200`
set the target is the player; otherwise the target is cleared and the camera free-pans, its
direction taken from a 16-entry table at `0x46B424` (stride 12 bytes) indexed by the four
pan bits remapped as `bit1→0, bit0→1, bit2→3, bit3→2`, scaled by `game+12804 × dt` into
`game+12748/12752/12756`. What the camera clamps to at the map edges is still not
recovered.

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
