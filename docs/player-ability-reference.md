# The console lamps: smoking, urinating and the Matrix pill

Verified on 2026-09-25 against a disposable copy of `sacked.exe.i64` and the shipped
`sacked.exe` (479232 bytes, SHA-256 `6404096c…`). The original executable and database were
not modified. Addresses are virtual addresses in that build, where RVA equals file offset.

The three round lamps on the console are the only way into the player's modes 2, 3 and 5:
smoking, urinating and the Matrix pill. This covers how a lamp is clicked, what each mode
does state by state, the smoke and the puddle they leave, the slowed office the pill makes,
and which levels can light each lamp. Mode 4, foam, is in the binary, but nothing can start
it. The item action, mode 1, is in [player-action-reference.md](player-action-reference.md),
and being caught is in [catch-reference.md](catch-reference.md).

## Player fields

These are in addition to the ones in [player-action-reference.md](player-action-reference.md):

| Offset | Meaning |
| --- | --- |
| `+124` | View index, `int16`. View `d` faces `45 * d` degrees, and 0 is `_000` |
| `+988` | 1 for Anne, 0 for Jo (`sub_4049F0`, `0x404AE1` / `0x404AC9`) |
| `+992` / `+1000` | Elapsed seconds, and the total in hundredths (`duration_tenths * 10`). A timed state ends when `+992 * 100 >= +1000` |
| `+996` / `+1004` | The same pair for the Matrix slow-down |
| `+1013`, `+1014`, `+1022`, `+1034` | Inventory bytes for items 5 (cigarettes), 6 (lighter), 14 (the pill) and 26 (a full bladder) |
| `+1044` | 1 while the slow-down runs. Only the Matrix overlay reads it |
| `+1048` | The one timestamp shared by every effect the player spawns |
| `+1052` | The smoke, a `CSfxSmoke` |
| `+1060` | `CO_EFFECT.OGD`'s animation list (`sub_42AD20(3)`) |
| `+1064` | The effects list, `game+1960` (`0x404A96`) |
| `+1072` | The character list, `game+1924` (`0x404B29`) |
| `+1080` / `+1084` | The puddle, and its clip `CO_CHARS_JOBLESS_PISSPUDDLE_000` |
| `+1108` | The idle sound handle, which holds the looping footstep `S0601` |
| `+1116` | The `S0174` handle, or −1 |

`sub_41AF60` initialises the player. It clears 31 inventory bytes, `+1008` to `+1038`: seven
dwords, a word and a byte (`0x41AF88`–`0x41AFC0`). That matches the `>= 0x1F` guard in
`sub_41D820`. It also:

- zeroes `+992`, `+996`, `+1000` and `+1004` (`+996` at `0x41B08F`, `+1004` at `0x41B09B`);
- sets `+1080 = 0` (`0x41AFD2`), `+1116 = −1` (`0x41AFFC`), `+920 = −1` (`0x41B014`) and
  `+1128 = "..."`;
- puts mode and state to 0 (`0x41AFE4`, `0x41AFEA`).

The abilities never read their records' required items. Records 22–24 list `[6, 5]`, and 74,
75 and 76 list nothing. What each mode spends is hard-coded in its last state, as described
below.

## The lamps are buttons

`sub_405930` builds three `CGUIActionIcon`s. They are the last of the console's elements
(`0x4060E0`), made in the order Matrix, urination, smoking. Each gets an id at `+1164`
(`inc edi; mov [eax+48Ch], edi`, `0x4060D1`). The x values are immediates at `0x406010`,
`0x40601F` and `0x406027`. The y values are `0x1CB` plus 78, 26 and 2. The layer is
`+16 = 1` (`0x40609E`), so the draw z is `1 + 0x8000`.

| Lamp | `game+` | `+1164` | Top left | Sprite | Hit, strictly inside | Bit | Mode |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Matrix | 14768 | 1 | (754, 537) | `CO_GUI_CONSOLE_MATRIX_ACT`, 43 × 47 | x 755–796, y 538–583 | `0x4000` | 5 |
| Urination | 14772 | 2 | (756, 485) | `CO_GUI_CONSOLE_PISS_ACT`, 44 × 46 | x 757–799, y 486–530 | `0x1000` | 3 |
| Smoking | 14776 | 3 | (717, 461) | `CO_GUI_CONSOLE_SMOKE_ACT`, 47 × 45 | x 718–763, y 462–505 | `0x800` | 2 |

The coordinates are in the original's 800 × 600 console. How they carry onto the port's
wider canvas is in [hud-reference.md](hud-reference.md).

The class chain has three levels:

- `CGUIRectangle`: constructor `sub_45B780`, vtable `0x467298`, 34 slots.
- `CGUIButton`: constructor `sub_45B6D0`, vtable `0x467208`, which adds slot 34.
- `CGUIActionIcon`: vtable `0x4653E4`, 35 slots, COL `0x467B28`.

The icon differs from its button base in only two slots: 0, the destructor `sub_406160`,
and 19, the click. These slots matter:

| Slot | Offset | Function | Does |
| --- | --- | --- | --- |
| 5 | `+0x14` | `sub_45B4B0` | Hover rect. It is always empty, so the lamp never hovers |
| 6 | `+0x18` | `sub_408F90` | Set visible, `+48` |
| 19 | `+0x4C` | `sub_4061A0` | Click: `dword_473CDC = +1164`, return 1. `CGUIButton`'s own slot 19 is `0x45B770` (return 1), which IDA names `DllMain` |
| 20 | `+0x50` | `sub_45B670` | Release: returns 0 |
| 31 | `+0x7C` | `sub_45B820` | `CGUIRectangle::Draw` |
| 32 | `+0x80` | `sub_45B690` | Set hover: `+20` ∓ 100, `+36` |
| 34 | `+0x88` | `sub_45B720` | Click rect: (x, y, sprite w, sprite h) |

The click rect is exactly the lamp sprite's size. Slot 34 reads w and h from the registered
sprite's `+0x14` and `+0x18` through `sub_459680` (`0x45985F`, `0x459868`). That sprite is
the one `OGD_LoadContainer_Parse` built with `sub_42D480(word_47FC40, word_47FC42)`
(`0x42E021`–`0x42E03C`), from the size the container gives. A `.tga` is loaded from disk only
for a name that is not registered. The exported `images/gui/hud/lamp-smoke.png`,
`lamp-piss.png` and `lamp-matrix.png` are 47 × 45, 44 × 46 and 43 × 47, which matches the hit
rects in the first table.

### From the mouse to a mode

1. `sub_45D850` polls `DIMOUSESTATE2` once per frame into one byte. The held buttons are
   left 1, right 2, middle 4 and button 3 8. The release edges are left `0x10`, right `0x20`
   and middle `0x40` (`0x45D8BC`–`0x45D90B`). Button 3 has no release edge.
2. `sub_45D600` emits a motion event (type 4) and then a button event (type 3) carrying
   `v[1] = byte & 0xF` and `v[2] = byte & 0x70` (`0x45D689`, `0x45D6B9`). A button event
   goes out on every frame a button is held, not only on the press.
3. `sub_403FB0` handles both events. The GUI manager is `game+15088`.
   - The motion event moves the game cursor (`sub_415400`, `0x40433F`) and the manager's own
     cursor at `+52/+56` (`sub_459A40`, `0x404352`).
   - The button event ORs `v[1]` into `manager+64` (`0x40439F`) and then calls `sub_459AE0`
     (`0x4043A6`).
4. `sub_459AE0` returns at once unless `manager+64 & 1`, the left button, is set
   (`0x459AE9`). It walks the element list at `manager+12` in registration order, skipping
   null elements and invisible ones (`+48 == 0`, `0x459B38`). For a button it takes the rect
   from slot 34. If the manager's cursor is strictly inside it and the latch `manager+68` is
   0, it calls slot 19 with `(1, cx, cy)` (`0x459CC3`) and sets the latch (`0x459CC6`). An
   element earlier in the list can take the latch first, through its hover branch
   (`0x459C2E`) or the `CGUIWindow` branch (`0x459BD1`).
5. `sub_4061A0` stores the lamp's id in `dword_473CDC`.
6. Any release edge does four things (`0x4044AF`–`0x4044CC`). It clears `manager+64` and
   `+68`, sets `+72` and `+76`, and calls `sub_459D30`. That calls slot 20 on every visible
   element, which does nothing for a lamp.
7. On the next frame `sub_403FB0` first masks the input register with
   `game+12736 &= 0xFFFF82FF` (`0x403FDB`). It then turns the id into one bit and zeroes the
   global (`0x40408F`):
   - 1 becomes `0x4000` (`0x404086`);
   - 2 becomes `0x1000` (`0x40407B`);
   - 3 becomes `0x800` (`0x404070`).

   `sub_403780` copies the register into `player+908` (`0x4037A1`).
8. The world tick `sub_41CFC0` calls `sub_41CF20` (`0x41D003`) before its mode switch
   (`0x41D013`). `sub_41CF20` returns unless `player+900 == 0` (`0x41CF28`). It tests the
   act bit `0x400` with a focus item first (`0x41CF34`), then the lamp bits:

   | Bit | Mode | State | `+900` written at | `+904` written at |
   | --- | --- | --- | --- | --- |
   | `0x800` | 2 | 10 | `0x41CF5D` | `0x41CF67` |
   | `0x1000` | 3 | 20 | `0x41CF77` | `0x41CF81` |
   | `0x2000` | 4 | 30 | `0x41CF91` | `0x41CF9B` |
   | `0x4000` | 5 | 40 | `0x41CFAB` | `0x41CFB5` |

   The switch then runs that first state in the same tick.

`WinMain` runs each frame in this order: input (`0x411945`), the HUD (`0x411957`), the world
(`0x411969`) and the render (`0x41197B`). It advances the clock only after all four
(`0x411A09`). A press polled on frame N sets `dword_473CDC` after frame N's conversion has
already run, so the mode starts on frame N + 1.

`dword_473CDC` has five references:

- the read at `0x404058` and the zeroing at `0x40408F`, both described above;
- the write in `sub_4061A0` (`0x4061A6`);
- two clears in `sub_407370`, case 1 (`0x40741F`) and case 9 (`0x407447`).

### When a press counts

- **Only lit lamps.** Hidden elements are neither clicked (`0x459B38`) nor drawn
  (`0x4598E3`).
- **Only the left button, and on the press.** Right and middle clicks never pass the
  `+64 & 1` gate. The click fires on the first button event in which three things hold: the
  left button is down, the cursor is inside the lamp, and the latch is clear. Only a release
  edge of any button clears the latch (`0x4044B7`, `0x4044BA`). So:
  - one press fires once;
  - a press that starts elsewhere and is dragged onto a lit lamp fires;
  - a left hold that spans a right-button release fires again.
- **Urination wins where two lamps overlap.** The urination and smoking rects share x 757–763,
  y 486–505. The urination lamp is registered first, so it takes the latch.
- **The hit test uses the manager's cursor, which can be hidden.** During a right-button walk
  the visible pointer is the walk arrow. `sub_415500` draws that arrow 40 pixels from the
  screen centre along the heading (`0x41555C`–`0x4155D7`), not at the cursor. Both cursors
  integrate the same deltas, and both snap to the centre on the right release (`0x40448A`,
  `0x4044A3`). The re-centre branch in `sub_415400` (`0x41549D`) never runs, because the
  cursor mode is reset before the event loop (`0x404053`) and the motion event comes before
  the button event. So a lamp pressed mid-walk is hit by a cursor the player cannot see.
- **Not while the ring closes.** After a ring cancel, `sub_403780` drives `sub_4066D0` with
  `game+14792 = 2` while `+900 == 0` (`0x403B36`–`0x403B52`). Every HUD tick of that
  0.4-second close re-centres both cursors (`0x40685A`, `0x406873`), so the lamps cannot be
  reached. The close only advances while `+900 == 0`, so an ability started in that window
  would leave the half-closed ring frozen until it ends. That was read from the code, not
  observed.
- **The only start gate is `+900 == 0`.** `sub_41CF20` does not test the inventory, the
  screen or the pause; the lamp's visibility is the inventory gate.
  - A walking player is in mode 0 and starts at once.
  - With the ring up (`+900 == 1`) or another ability running, the bit is lost, because the
    next frame's mask clears it.

  A press is dropped, never queued.
- **The pause loses the press.** `sub_403FB0` still converts the id. But `sub_403780` returns
  before it copies the register (`0x40378D`), and `sub_402590` returns before any entity
  update (`0x4025B7`). So the press is lost unless the pause lifts on the very next frame.
  The pause key (`0x404150`–`0x404167`) does not go through `sub_407370` and does not clear
  `dword_473CDC`. The quit prompt sets the pause bit itself (`0x4075AF`), so its HUD and world
  dispatches (`0x403F33`, `0x40287B`) do nothing.
- **Not during the duel.** The duel runs its own GUI manager (`sub_404680`, `0x404745`), so
  the level's lamps cannot be pressed.
- **The caught banner still takes a press (read from the dispatch, not observed).** Screen 4
  still runs input, the HUD and the world (`0x4049AB`, `0x403F33`, `0x40287B`), at a zero
  time step (`0x411AD1`). A lamp press there starts an ability as soon as the player is back
  in mode 0:
  - the tick after a caught prank or a caught urination;
  - for a caught smoke, not until state 14 has finished waiting for the `SMOKE` clip.

  The ability then runs at dt 0. Mode 3 even reaches state 22, so its puddle is spawned. The
  catch cannot fire again, because it needs screen 1 (`0x402475`). A won duel returns to
  screen 1 through `sub_4027B0` → `sub_407370(1)` (`0x402832`), and the ability is still
  running.
- **Two frames of leniency.** The HUD refreshes the lamps after input, so a lamp is still lit
  for the click test after the ability that spent its last item. A press polled in the frame
  whose world tick runs state 13, 23 or 43, or in the frame after it, starts one more
  ability with the item at 0. The end-state decrement then clamps at 0.
- **A release can take the press (inferred).** Every left release sets
  `game+12736 |= 0x400` and `12740 |= 0x10` (`0x40445C`–`0x404478`), wherever the cursor is.
  Suppose the release is polled on frame N + 1, the frame the lamp's bit arrives, and a focus
  item exists. Then `sub_41CF20` starts mode 1 instead, and the lamp's bit is lost. With a
  longer hold, the ability is already running by the time `0x400` arrives. The same bit also
  selects an agent under the cursor (`0x4039D7`–`0x403A3F`), so an agent standing behind a
  lamp can get its name shown.

  An item behind the console cannot stay the focus, for these reasons:
  - the item pick is gated on `+900 == 0` (`0x4032B8`) and on the 2.0-tile reach
    (`0x4033D3`);
  - the camera follows the player, because bit `0x200` is never cleared, and it clamps
    nothing (see player-action-reference.md);
  - the nearest lamp pixel, (718, 462), is about 6.7 tiles of screen offset from the centred
    player.

  So such an item is tinted yellow and dropped (`0x403443`–`0x403459`).

### What the lamps draw

Each lamp is one static sprite, drawn by `CGUIRectangle::Draw` (`sub_45B820`) from its top
left (`+1140 = 0`), uncropped, at z `+16 + +20 = 0x8001`. The tint bytes `+1160`–`+1163` stay
at zero from the constructor, so the draw uses blend mode 7, which does not modulate
(`0x45B955`). There is no hover art, because slot 5's empty rect never lets `sub_45B690` run.
There is no pressed art either, because the click only stores the id. **Visibility is the
lamp's only state.** Each unpaused `sub_403780` tick sets it from the inventory:

| Lamp | Lit when | Address |
| --- | --- | --- |
| Smoking | items 5 **and** 6 are both non-zero | `0x40395B`, `0x403963` |
| Matrix | item 14 is non-zero | `0x403995` |
| Urination | item 26 is non-zero | `0x4039B9` |

`sub_405930` creates the lamps visible (`0x45B34C`, then slot 6 with 1 at `0x4060CB`). The
first HUD tick hides them, because the inventory has just been cleared.

Where the smoking and urination lamps overlap, both draw at z `0x8001`. Which one ends up on
top depends on `sub_42CCF0`'s sort, which was not analysed. It hardly matters: only 8 pixels
of that overlap are opaque in both `lamp-smoke.png` and `lamp-piss.png`.

## Mode 2: smoking

The handler is `sub_41BC50`. It reads its records directly as globals
(`0x41BCF1`–`0x41BD5C`), not through an item's slot:

| Room category at the player | Record | Name | Duration | Score | Stored at (duration, score) |
| --- | --- | --- | --- | --- | --- |
| 3 | 22 | `Zapal sobie (w poczekalni)` | 120 tenths | 10 | `0x40B27C`, `0x40B272` |
| 4 | 76 | `Zapal sobie (w serwerowni)` | 120 tenths | 350 | `0x40D0AB`, `0x40D0A1` |
| 8 | 24 | `Zapal sobie (w gabinecie szefa)` | 120 tenths | 500 | `0x40B3B6`, `0x40B3AC` |
| anything else | 23 | `Zapal sobie (gdziekolwiek)` | 120 tenths | 300 | `0x40B32E`, `0x40B324` |

`sub_40A600` writes them. The name pointers are `0x475288`, `0x476290`, `0x475320` and
`0x4752D4`. State 10 takes the room category as `sub_412AE0(int(x + 0.5), int(z + 0.5), 4)`,
converting each sum with `ftol` and taking the 0.5 from `flt_4652B4` (`0x41BCA5`–`0x41BCDF`).
That is the same rounding as mode 3's. The call returns `INFODATA` bits 16–23 (see
[collision-reference.md](collision-reference.md)). The objects placed in each room identify
them, and the names agree:

- room 3 holds the sofas, the standing ashtrays and the TV, so it is the waiting room;
- room 4 holds the servers and PC towers, so it is the server room;
- room 8 holds the boss's case, minibar and safe, so it is the boss's office.

| State | Set at | What it does |
| --- | --- | --- |
| 10 | `0x41CF67` | Picks the record. Sets `+1000 = 1200`, `+1128` = the record's name and `+992 = 0`. Plays slot 12 `SMOKE` and sets that clip's loop flag `+548 = 0`, start `+552 = now` and finished flag `+556 = 0` (`0x41BC7E`–`0x41BC9F`). Stops the idle sound `+1108` (`0x41BD67`–`0x41BD83`). Sets `+1048 = now` (`0x41BCAE`). The facing is left as it is. Goes to 11 (`0x41BCB4`) |
| 11 | `0x41BCB4` | `+992 += dt`. Once `+992 > 0.4` (`flt_46587C`, strict, `0x41BDBA`) it spawns the smoke (below), sets `+1048 = now` again (`0x41BF6C`) and goes to 12 (`0x41BF72`) |
| 12 | `0x41BF72` | When `SMOKE`'s `+556` is 1, it restores that clip's loop 1, start 0 and finished 0, and plays slot 0 (`0x41BFA0`–`0x41BFCA`). `+992 += dt`. At `+992 * 100 >= +1000` it zeroes `+992` and `+1000` (`0x41BFF6`, `0x41BFFC`) and goes to 13 (`0x41C002`), so the stopwatch is empty from that tick |
| 13 | `0x41C002` | Asks the room at the player again, with the same rounding as state 10 (`0x41C029`–`0x41C04F`), and pays that room's score through `sub_41DE60` (`0x41C07E`). It reads the scores as globals, each record's `+8`: `0x475290`, `0x476298`, `0x475328` and `0x4752DC` for 22, 76, 24 and 23 (`0x41C054`–`0x41C076`). Takes one from inventory item 5, clamped to 0–99 (`0x41C083`–`0x41C0AA`). Jumps past state 14's stores to set mode and state to 0 (`0x41C0A8`/`0x41C0B0` → `0x41C100`, `0x41C106`); the timers are already 0 |
| 14 | `0x40254E`, only by the catch | If slot 12 is still playing, waits for its `+556` (`0x41C0BC`, `0x41C0CC`). Then plays slot 0 looping, zeroes `+992` and `+1000` (`0x41C0F4`, `0x41C0FA`) and returns to mode 0 (`0x41C100`, `0x41C106`). It pays no score and spends nothing |

**The lighter is never spent.** States 13 and 14 do not touch the smoke.

**Smoking plays no sound.** `S0040`, the records' `sound_at_start`, is written only by
`sub_40A600` (`0x40B2E3`, `0x40B395`, `0x40B41D`, `0x40D10C`). A record's sound (`+0x44`,
with its flag at `+0x48`) is read only by `sub_41B240`, through an item's slot
(`0x41B67D`–`0x41B698`, `0x41B97F`–`0x41B99D`). No `CO_OBJECTS.DAT` item offers 22, 23, 24 or
76. None of the twelve call sites of `sub_42A6A0` is in `sub_41BC50`.

Timed from the state-10 tick S:

| Time | Event |
| --- | --- |
| S + 0.4 s | the smoke is spawned |
| about S + 2.4 s | first burst of particles |
| about S + 4.4 s | second burst |
| S + 4.9 s | emission stops |
| about S + 9.4 s | the smoke is deleted |
| S + 12.0 s | state 13 |

### The `SMOKE` clip

The clip is slot 12, and it is the same in all eight views (`extracted/animations_godot`):

| Character | Frames | Rate | Length |
| --- | --- | --- | --- |
| Jo, `JOBLESS_SMOKE` | 10 | 8 fps | 1.25 s |
| Anne, `ANNE_SMOKE` | 11 | 16 fps | 0.6875 s |

The player tick calls `CObjectAnim_SelectFrameFromTime` (`0x407E10`) last, through `vtbl+36`
(`0x41D4D6`). With the loop flag at 0 it gives frame `trunc((now − start) * fps * speed)`
until that reaches the frame count. It then clamps to the last frame and sets `+556`
(`0x407F27`). State 12 sees the flag on the next tick, so the last frame stays up for one
extra tick. The idle that follows is locked to the game clock, because its start is always 0.
`Animation_AllocRegister` sets `+552 = 0` (`0x42E430`). Every later store to slot 0's start
also writes 0: free mode (`0x41B166`), states 23 and 24 (`0x41C5B1`, `0x41C601`), and states 43
and 44 (`0x41CE63`, `0x41CEF4`). **So Jo smokes for 1.25 s and then stands idle for
the remaining 10.75 s. Anne smokes for 0.69 s and then idles for about 11.3 s.** Both stay in
mode 2 the whole time and cannot move.

### The smoke: `CSfxSmoke`

The smoke is constructed only at `0x41BE27`. The vtable `0x465900` has two references: that
one, and the destructor body `sub_41E180`.

`CSfx_BASE`'s constructor `sub_426380` (vtable `0x46675C`) first allocates 20 particles of
104 bytes through `sub_4264A0`, which clamps the count to 1–2048. The smoke's twelve vtable
slots are `CSfx_BASE`'s, except for the destructor (`0x41E160`) and slot 11:

| Slot | Function | Role |
| --- | --- | --- |
| 3 | `0x426B60` | Draw |
| 4 | `0x426920` | Project every particle |
| 6 | `0x426AB0` | On-screen test, a 64 × 64 box |
| 8 | `0x4268F0` | Tick: `dt = DeltaTime_Calculate` (`0x42B420`), then `sub_426730(dt)` |
| 9 | `0x407E10` | Frame from time, called with each particle's age |
| 11 | `0x4272E0` | Per-particle velocity |

**The spawn** happens in state 11 (`0x41BDA4`–`0x41BF7E`):

```text
a        = (int16 player+124 * 45.0 + 180.0) * 0.017453     // 0x465548, 0x465544, 0x465540
position = (x - 0.21 sin a,  y + 1.85,  z + 0.21 cos a)      // sub_42B330
velocity = (-0.21 sin a,     0,         0.21 cos a)          // sub_42B390
```

The 0.21 and −0.21 are doubles at `0x465930` and `0x465938`, and 1.85 is at `0x4658F8`.
0.017453 is close to π/180 but not exactly it.

- The position is 0.21 tiles along the facing, `(sin 45d°, −cos 45d°)` in (x, z) for view d.
  View 0 is −z (`_000`) and view 2 is +x (`_090`).
- It is 1.85 units up, at the mouth. The emitter never moves after this.
- `+116` and `+120` get the Strings animation and frame 0. The animation is found in
  `player+1060` by `stricmp` against `CO_EFFECT_STRINGS` (`0x41BEA0`–`0x41BF11`, string
  `0x46EDC0`).
- `sub_427290` initialises the smoke.
- The smoke is pushed onto `player+1064`, gets an id at `+80`, and takes the list's render
  state (`sub_42B410`).

`sub_427290` does four things:

- It re-allocates for **200** particles (`0x427296`). The constructor's 20-particle array
  leaks.
- It installs a point domain at the origin (`sub_4264F0`). The domain's slot 0, `0x426F10`,
  returns the point unchanged, so particles have no spawn spread.
- It copies 112 bytes of parameters from `0x471378` to `+136`.
- It clears the stop flag `+248`.

**Emission** runs at the end of every tick, in `sub_426730` (`0x426861`–`0x4268DD`):

```text
acc += dt                                         // +244, starts at 0
if acc >= 2.0 and +248 == 0:                      // +236
    n = trunc(floor(25.0) * ceil(acc / 2.0))      // +240
    emit n particles (sub_426600); acc = 0
```

- **The first burst comes 2.0 s after the spawn.** The first tick's dt is 0, because
  `DeltaTime_Calculate` seeds `+72`, so the burst lands on the first frame after 2.0 s of game
  time.
- **A burst is 50 particles, not 25.** By then `acc` has passed 2.0 by a fraction of a frame,
  so `ceil` gives 2. It would be 25 only if `acc` landed on exactly 2.0; this follows from the
  formula.
- **There are two bursts.** The second comes about 2.0 s after the first. The player tick
  calls `sub_426C60` once `now − player+1048 > 4.5` (`flt_465A34`, strict, `0x41D081`). That
  sets `+248 = 1` for good and returns whether no particle is left, so no third burst comes.
- **So a smoke emits 100 particles in all.** At most 200 can be alive; `sub_426570` returns
  null when the array is full.
- **Slow frames change the count.** A frame longer than 2.0 s would emit 75 or more at once.
  At frame times near 0.25 s the second burst can come after the 4.5-second gate and be
  skipped.

**A new particle** (`sub_426600`) draws eight values from the RANMAR generator `sub_45E1C0`,
each in `[0, 1)`. Nothing in the smoke uses `rand()`. The rows below are in draw order:

| Quantity | Start | End, at age 5 | Parameter offsets |
| --- | --- | --- | --- |
| Age | `0.0 + 0.6 r`, so pre-aged | — | `+136`, `+140` |
| Alpha | `240 + 1.0 r` | 1.0 | `+204`, `+208`, `+212` |
| Rise `g` | `0.0 − 0.1 r` | −6.0 | `+156`, `+160`, `+164` |
| Speed factor | `1.2 + 0.0 r` | 0.0 | `+144`, `+148`, `+152` |
| Size | `0.01 + 0.01 r` | 0.6 | `+216`, `+220`, `+224` |
| `c0` | `235 + 10 r` | 185 | `+168`, `+172`, `+176` |
| `c1` | `235 + 10 r` | 185 | `+180`, `+184`, `+188` |
| `c2` | `245 + 10 r` | 195 | `+192`, `+196`, `+200` |

The rest of the block is:

| Offset | Value | Meaning |
| --- | --- | --- |
| `+228` | 5.0 | lifetime |
| `+232` | 0.2 | its inverse |
| `+236` | 2.0 | emission interval |
| `+240` | 25 | particles per interval |
| `+244` | 0 | the accumulator |

Each particle starts at the emitter's position. Slot 11 sets its velocity to
`(1.4 vx, vy, 1.4 vz)` of the emitter (1.4 at `0x4667A0`), which is
`0.294 * (sin 45d°, 0, −cos 45d°)` and the same for every particle. **Particles differ only in
their pre-age, their colour and their rise.**

**Each tick** (`0x426751`–`0x42684D`):

```text
age += dt
if age >= 5.0: remove it          // sub_4265A0 moves the last particle into its slot, processed next
f     = 0.2 * age                 // reaches 1 exactly at death
value = start + (end - start) * f // speed, g, c0, c1, c2, alpha, size
k     = dt * speed
x += k * vx;   z += k * vz
y += k * vy - dt * g * 0.1        // 0.1 at 0x466798; vy is 0
if y < 0.1: y = 0.1               // never reached by the smoke
```

A particle drifts along the facing at `0.3528 * (1 − 0.2 age)` tiles per second and rises
faster as it ages. From pre-age 0 it travels about 0.88 tiles and climbs about 1.51 units,
which is 72 pixels. It never rotates.

**Its frame** is `floor(8 * age) mod 16`. That is `SelectFrameFromTime` with the particle's
own age, start 0 and the Strings `ANIM` (`CO_EFFECT.OGD` offset `0x23CFDA`: id 10, 8 fps,
16 frames of 64 × 64 with the pivot at (32, 32), looping by default). It is neither random nor
the global clock. Because of the pre-age, a new particle starts on a frame from 0 to 4.

The `ANIM` is already exported, as
`extract-sacked-assets/extracted/animations_godot/CO_EFFECT_CO_EFFECT_Strings_godot.json`.
Its frames are the sprites `strings_001` to `strings_016` in order, so frame n is
`strings_(n + 1)`.

**The projection** is `sub_426920` (`0x42696F`–`0x4269B1`):

```text
dx = x - cam.x;   dz = z - cam.z
sx = 48 (dx - dz)
sy = 24 (dx + dz) - 48 y                    // 48 px per height unit; characters use 24
screen   = (sx - cam+44, sy - cam+48)
top_left = trunc(screen + 32 - 32 size) - 32   // pivot (32, 32): centred on the particle
Z        = trunc(49152 - trunc(sy) * 0.5 + 48.0)   // 0x4269C0; sy before the camera offset
```

The blitter scale is `s = max(1, trunc(size * 255))` in 1/256 units. The 255.0 is at
`0x46679C`; it is not 256. Sampling is nearest, at a step of `0x10000 / s`, so the 64 × 64
frame covers `((s * 63) >> 8) + 1` pixels. That is 1–2 pixels at birth, 5–6 at pre-age 0.6
and 38 at death. The on-screen test uses the unscaled 64 × 64 box.

**The draw** is `sub_426B60`. It sets blend mode 46 (`0x426B74`), then for each particle the
tint `sub_42D1E0(trunc c0, c1, c2)`, byte `+43 = 255`, the alpha `trunc(alpha)` and the
scale. It leaves mode 5 set afterwards (`0x426C4D`). Strings is 32 bpp with no Z plane, so
`off_47176C[46] = 0x453E20` draws it:

```text
skip if (src & 0xFFFFFF) == colour key          // Strings' key is 0x000000
skip if screenZ < Z                              // never writes Z
a     = src >> 24
out_i = ((255 - a) * dst_i >> 8) + ((a * ((src_i * tint_i) >> 8)) >> 8)
```

That has three consequences:

- **Particles never fade.** Mode 46 reads neither the global alpha nor byte `+43`, so the
  240 → 1 alpha ramp has no effect. A particle draws its sprite's own per-pixel alpha, tinted,
  at full strength until it disappears at age 5.
- **Black pixels are dropped.** Strings' colours are only pure white and pure black, and both
  carry real alpha. Over the 16 frames, 22814 white pixels and 18829 black ones have
  alpha > 0. The colour key removes every black pixel, so only the white strands show.
- **The tint is a slightly blue white that turns grey.** `sub_42D1E0(r, g, b)` stores its
  arguments in bytes 0–2, and the back buffer's byte order is `R, G, B, X` (see
  [field-of-view-reference.md](field-of-view-reference.md)). So `c0` tints red, `c1` green
  and `c2` blue: (235–245, 235–245, 245–255) at birth, falling to (185, 185, 195). The smoke
  sitting had read byte 0 as blue under `pipeline.md`'s older assumption; the byte order
  corrects that.

**Depth.** Each particle has a single Z, because the sprite has no Z plane. In the port's
convention, where larger is nearer (see [map-rendering.md](map-rendering.md)), its score is
`ceil(int(sy) / 2) − 48`. That places it 48 units further back than a character at the same
ground point, and its height counts double. At a height of 1.85 it tests like a ground point
about 185 pixels up-screen (`48 * 1.85 + 96`). Walls, items and characters with a nearer Z
hide it. It is drawn after every character, in list and array order with no sort, and clipped
to the world area, x 1–799 and y 1–509.

**Removal** happens only in the player tick (`0x41D072`–`0x41D13D`), when three things hold:

- `+1052` is set;
- `now − +1048 > 4.5`;
- `sub_426C60` reports that no particle is alive.

The tick then finds the smoke in the effects list by id, calls its deleting destructor,
erases it and clears `+1052`. That happens on the frame after the last particle dies, about
9 s after the spawn. A catch does not remove it.

**Orphans (read from the code, not observed).** State 11 overwrites `+1052` without checking
for an old smoke (`0x41BE3B`), and state 10 resets `+1048`. The stop gate looks only at
`+1052`. Suppose a second smoke starts less than 4.5 s of game time after the first. That can
happen after a caught smoke, because the catch spends nothing and a won duel resumes with the
clock frozen throughout. The first smoke then stays in the list with emission still on, and
emits 50 particles every 2 s until the level is torn down. Urinating while a smoke is alive
postpones its stop gate the same way.

## Mode 3: urinating

The handler is `sub_41C120`.

| Room category | Record | Name | Duration | Score |
| --- | --- | --- | --- | --- |
| 8 | 75 | `Nasikaj (w gabinecie szefa)` | 70 tenths (`0x476250`, set at `0x40D024`) | 800 (`0x47624C`, set at `0x40D01A`) |
| anything else | 74 | `Nasikaj (gdziekolwiek)` | 70 tenths (`0x476204`, set at `0x40CFA3`) | 500 (`0x476200`, set at `0x40CF99`) |

The category is `sub_412AE0(int(x + 0.5), int(z + 0.5), 4)`, with the 0.5 at `0x4652B4`.

| State | Set at | What it does |
| --- | --- | --- |
| 20 | `0x41CF81` | Picks the record. Sets `+1000 = tenths * 10.0 = 700` (`0x41C17A`), `+1128` = its name (`0x4761F8` or `0x476244`) and `+992 = 0`. Picks a facing (below) with `sub_41A3F0`, plays slot 7 `PISS#1` (`0x41C207`) and stops `+1108` (`0x41C20C`–`0x41C232`). Goes to 21 (`0x41C212`) |
| 21 | `0x41C212` | `+992 += dt`. Deletes the old puddle (`0x41C26E`–`0x41C2FF`), sets `+1048 = now` (`0x41C260`) and builds the new puddle (below). If `+1116 == −1`, starts `S0174` into it (`0x41C4A8`–`0x41C4C3`). Goes to 22 (`0x41C4C9`) |
| 22 | `0x41C4C9` | `+992 += dt`. At `+992 * 100 >= +1000`, which is 7.0 s, it zeroes `+992` and `+1000` (`0x41C510`, `0x41C516`) and goes to 23 (`0x41C506`) |
| 23 | `0x41C506` | Asks the room at the player again (`0x41C52A`–`0x41C550`) and pays 800 in category 8, else 500 (`0x41C555`–`0x41C564`), through `sub_41DE60` (`0x41C567`). Takes one from inventory item 26, clamped to 0–99 (`0x41C56C`–`0x41C593`). Plays slot 0 with loop 1, start 0 and finished 0. Sets mode and state to 0 (`0x41C5D2`, `0x41C5D8`). Stops `S0174` and sets `+1116 = −1` (`0x41C638`, `0x41C63D`) |
| 24 | `0x402568`, only by the catch | Plays slot 0 looping, zeroes the timers, and sets mode and state to 0 (`0x41C622`, `0x41C628`). The same call as state 23's stops `S0174`. It pays no score and spends nothing |

**The facing** comes from two `rand() & 8` tests (`0x41C1CF`–`0x41C1FA`), the same rule as
selector 12 in [player-action-reference.md](player-action-reference.md). The first choice
is taken half the time and the other two a quarter each:

| Character | `+988` | First choice | Second | Third |
| --- | --- | --- | --- | --- |
| Anne | set | view 2, `_090` | view 3, `_135` | view 4, `_180` |
| Jo | clear | view 0, `_000` | view 6, `_270` | view 7, `_315` |

These are exactly the `PISS#1` views each character ships: Anne 090/135/180 and Jo
000/270/315, six frames at 16 fps, 0.375 s. The player keeps this facing afterwards.

Mode 3 changes neither the clip's loop flag nor its start, and nothing else does either.
`Animation_AllocRegister` sets the start `+552` to 0 (`0x42E430`). These are the only stores
to `+552` on a player clip:

- the current clip after `sub_41A510` of slot 0 or 2 in free mode (`0x41B166`, `0x41B1D6`);
- mode 1's selector clip (`0x41B2D0`, `0x41B3D1`). The selector map never yields slot 7;
- `SMOKE` (`0x41BC99`, `0x41BFBE`, `0x41C0E4`);
- the puddle's clip (`0x41C444`);
- slot 0 (`0x41C5B1`, `0x41C601`, `0x41CE63`, `0x41CEF4`).

So `PISS#1`'s start stays 0 in every view. The clip loops, as its `ANIM` says, about 18.7 times
over the 7 s, and it is locked to the game clock: the frame is
`floor((now mod 0.375) * 16)`. In the port that is a clock-driven clip.

**The sound** is `sub_42A6A0(player+1104, "S0174", 0, 0)`. The string is at `0x46EE04`, and
`+1104` is `game+15136`.

- The third argument is the looping flag. It reaches `IDirectSoundBuffer::Play(0, 0, a3 != 0)`
  through `sub_45E7E0` → `sub_45EE60` → `sub_45F9B0` (`0x45F9D0`).
- The fourth argument makes a sound positional. `sub_42A970` then sets its volume to
  `0.9 − clamp(dist, 0.1, 16) * 0.0625 * 0.9`.

**So `S0174` plays once, at full effects volume, and is not positional.** It lasts 6.762 s
(mono, 22050 Hz, 16-bit, 149104 frames), so it ends about 0.24 s before state 23. The
records' own sound, `S0074`, is never played. States 23 and 24 stop it with
`sub_42A7C0(+1116, 0)` (`0x41C638`), and the player's destructor stops it at teardown
(`0x41AF1C`). Two quirks follow:

- `sub_42A970` frees the slot once the sound ends (`0x42A9A0`), and slots are handed out
  lowest-free-first. So state 23's stop can hit a different sound that was started in the
  last 0.24 s.
- DirectSound plays in real time, so `S0174` keeps playing through the pause while the 7 s
  timer is frozen.

### The puddle: `CPisspuddle`

The class chain is `CPisspuddle : CObjAnim_CO : CObjectAnim : CObjectBase` (COL `0x467EC0`,
type descriptor `0x46EDE8`). State 21 builds it inline (`0x41C305`–`0x41C343`):
`new(0x388)`, `sub_4110E0` (the `CObjectAnim` constructor), entity type `+112 = 0`, a zeroed
tail, and the vtable `0x465964`.

- The only field it adds is `+900`, a float alpha, set to 0.7 (`0x3F333333`, `0x41C45D`).
- It has no click box (`+88 = 0`) and no highlight (`+92 = 0`).
- Its twelve vtable slots are `CObjAnim_CO`'s (`0x465820`) except slot 3, the draw, which is
  `sub_41E1C0`.
- Its projection is `sub_41A2D0`, shared with the player and the agents.
- Slot 7 (`sub_41A290`, called at `0x41C498`) resets its scale to 1.0.

**The art.** `sub_41D630`, the player's sprite setup (vtable slot 11), looks up the literal
`CO_CHARS_JOBLESS_PISSPUDDLE_000` (`0x46EE70`, `0x41D716`) whatever the character's prefix.
**So Anne's puddle is Jo's**; there is no Anne puddle. It has 11 frames (the sprites
`Piss_000`–`Piss_020`, even numbers only) at 8 fps, all 8 bpp with a Z plane. The `ANIM` is
already exported as
`extract-sacked-assets/extracted/animations_godot/CO_CHARS_CO_CHARS_JOBLESS_PISSPUDDLE_000_godot.json`,
with these sizes and pivots:

| Frame | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Size | 19×11 | 21×14 | 22×17 | 24×19 | 28×23 | 31×25 | 37×30 | 44×34 | 50×39 | 59×43 | 68×48 |
| Pivot | 9,5 | 10,6 | 10,7 | 11,8 | 13,10 | 15,11 | 18,13 | 21,15 | 24,18 | 29,20 | 34,22 |

The Z plane is a floor ramp that falls by 0.5 per row. In the last frame it is about 180 at
the top, 169 at the pivot row and 159 at the bottom, and 255 where the frame is transparent.

**It grows once.** State 21 sets the shared clip's loop flag to 0, its start to now and its
finished flag to 0 (`0x41C407`–`0x41C44A`). The puddle's own tick therefore shows frame
`min(floor((now − start) * 8), 10)` and holds the 68 × 48 frame from 1.25 s on, even though
the `ANIM` says it loops. The clip object is shared, not copied. That is harmless only because
there is never more than one puddle.

**Where it goes** (`0x41C350`–`0x41C3F4`):

```text
a = (int16 player+124 * 45.0 + 180.0) * 0.017453
d = player+988 ? 0.2 : 0.6                   // doubles 0x465940/0x465948, 0x465950/0x465958
position = (x - d sin a,  0.1,  z + d cos a) // sub_42B330; 0.1 pushed at 0x41C3DD
```

So Anne's puddle lands 0.2 tiles ahead along her facing and Jo's 0.6 tiles ahead, both 0.1
units up. View 0 is −z, 2 is +x, 4 is +z and 6 is −x. Offsets in 800 × 600 pixels from the
player's anchor, for the views each character can face:

| Character | View | Offset (px) |
| --- | --- | --- |
| Anne | 2 | (+9.6, +2.4) |
| Anne | 3 | (0, +4.4) |
| Anne | 4 | (−9.6, +2.4) |
| Jo | 0 | (+28.8, −16.8) |
| Jo | 6 | (−28.8, −16.8) |
| Jo | 7 | (0, −22.8) |

Anne's puddle appears just below her feet on screen. Jo's appears up-screen, behind him.

**The draw.** `sub_41A2D0` projects the puddle like a character:

- `sy = trunc(24 (dx + dz) − 24 y)`;
- the depth base is `trunc(49152 − sy / 2)`, from `sy` before the camera offset;
- the scale is applied about the frame's pivot: `top_left = anchor − pivot * s`.

The 0.1 height lifts the puddle 2.4 pixels and puts its depth base about 1.2 units behind a
floor-level entity at the same x/z.

`sub_41E1C0` draws the puddle only when it is on screen. It uses **blend mode 22**
(`0x41E1D5`), the alpha byte `(char)trunc(+900 * 256)` and the scale `max(1, trunc(s * 256))`,
then restores the previous mode. The 256.0 is at `0x465508`, so an alpha of 0.7 gives byte
179. Mode 22 has two 8-bpp Z-plane blitters, `0x442CD0` unscaled and `0x435B70` scaled:

```text
skip the colour key (the unscaled one also skips palette index 255)
draw only if base + spriteZ <= zbuffer        // never writes Z
out = (src * a >> 8) + (dst * (255 - a) >> 8)
```

The scaled blitter samples nearest at a step of `65536 / s`, spans `((w − 1) * s) >> 8`
pixels, and reads the Z plane through the same mapping without scaling its values. The
effects list's default mode 14 uses the same unscaled blitter. The two modes differ only once
the puddle is scaled, after 10 s: mode 14 would use each palette entry's own alpha, and mode
22 uses the puddle's alpha.

The puddle is drawn after every item and character, in the effects pass (`0x402B38`). **Only
its Z test puts it under them.**

- Walls (mode 5, `0x42EBA0`), items (mode 7, which `sub_411E20` sets for the item pass at
  `0x411E40`) and characters (mode 7, `0x42ECC0`) all write Z, so all three hide it.
- The floor writes no Z, and Z is cleared to `0xFFFF` every frame (`0x402906`), so the
  puddle always covers bare floor.
- The player's shadow (94 × 48, 32 bpp, no Z plane) is drawn in mode 10 at depth 65000
  without writing Z (`0x41D5EF`–`0x41D616`), so the puddle blends over it.
- A character standing on the puddle mostly hides it. The exception is foot pixels with Z
  170–174: the translucent puddle is blended over those.
- Against the player who made it: Anne's puddle has a depth base about 1.2–2.2 units nearer
  than hers, and Jo's is 8.4–11.4 units further back than his.

**Growth and fade** happen in the player tick (`0x41D143`–`0x41D252`), with
`age = now − player+1048`:

```text
if age > 10.0:                                  // 0x4652F4, strict
    s = 1.0 + 0.08 (age - 10)                   // 0x465A30; sub_42B450(s, s), each clamped to >= 0.01
    puddle+900 = 0.7 - 0.085 (age - 10)         // 0x4652C0, 0x465A2C
if age > 17.0:                                  // 0x465A28
    delete it; player+1080 = 0
```

| Age | Alpha byte | Scale |
| --- | --- | --- |
| up to 10 s | 179 | 1.0 |
| 12 s | about 135 | 1.16 |
| 14 s | about 92 | 1.32 |
| 16 s | about 48 | 1.48 |
| 17 s | 26 | 1.56 (`s = 399`, 105 × 74 pixels) |

Both branches run on the tick that crosses 17. Nothing else calls `sub_42B450` (`0x41D184`).

**There is only one puddle.** A new urination deletes the old one at once, with no fade.
Level teardown, `sub_407140`, deletes the whole effects list (`0x4071F7`) on a win, a loss, a
restart and a quit.

**Nothing reacts to the puddle:**

- the vtable has one reference, its own store;
- the type descriptor is named only by its COL and its base-class descriptor, and every
  dynamic cast in the binary is in the GUI code;
- only `sub_41AF60`, `sub_41C120` and `sub_41CFC0` touch `player+1080`;
- the effects list is on no agent's path: `sub_402260`, `sub_402470` and `sub_41CD10` walk
  `game+1924` and want `+112 == 2`;
- the puddle writes nothing to the map.

The secretary's `PANIC`, `PANIC#WET` and `PANIC#FOAM` (slots 3–5 of `0x46EEE4`) are never
selected (see [catch-reference.md](catch-reference.md)), and `CO_CHARS.OGD` ships no `PANIC`
art.

### One clock for every effect

`player+1048` is the only timestamp. These write it:

- smoking's state 10 (`0x41BCAE`) and its spawn (`0x41BF6C`);
- urination's state 21 (`0x41C260`);
- foam's state 31 (`0x41C7E0`), which is unreachable.

Every effect's lifetime check in `sub_41CFC0` reads it (`0x41D085`, `0x41D155`, `0x41D18D`,
`0x41D1B9`, `0x41D26A`, `0x41D29D`, `0x41D34E`). The pill does not touch it.

**So lighting a cigarette restarts a puddle's age.** If the puddle was already fading, its
scale and alpha freeze, because the `> 10` branch stops writing them. They snap back to 1.0
and 0.7 once the new age passes 10, and the puddle lives 17 s counted from the smoke. In the
same way, a new urination postpones a live smoke's stop.

## Mode 5: the Matrix pill

The handler is `sub_41CD90`. `sub_40A600` stores record 73 at
`0x474C00 + 0x4C * 73 = 0x4761AC`:

| Field | Value | Store | Read |
| --- | --- | --- | --- |
| `+0x00` name | `...` (`0x46BAE4`, through `off_46BE28`) | `0x40CEEA` | `0x41CDBB` |
| `+0x04` icon | 33, `MATRIXPILLE` | `0x40CEF0` | — |
| `+0x08` score | 10 | `0x40CEF7` | `0x41CE3B` |
| `+0x0C` duration | 20 tenths (`edi = 0x14`, set at `0x40A7FC`) | `0x40CF01` | `0x41CDA9` |
| `+0x14` after-effect | 400 tenths | `0x40CF0C` | `0x41CEB7` |
| `+0x1B` required item | 14 | `0x40CF25` | — |

**`+0x14` is read**, once, here. `fild dword_4761C0` (record 73 + `0x14` = 400) at `0x41CEB7`
is multiplied by 10.0 (`flt_4652F4`) and stored to `+1004` at `0x41CEC5`. It is the only
non-zero `+0x14` in the table, and this is the only read of any record's `+0x14`. It is the
pill's after-effect in tenths. `tools/export_action_table.py` calls the field
`effect_duration_tenths`, and its `--check` pins this read and that record 73 alone carries one.

The ability modes read their records directly as globals: mode 2 at `0x41BCF1`–`0x41BD5C`,
mode 3 at `0x41C17A`–`0x41C1B1` and `0x41C558`–`0x41C55F`, mode 4 at `0x41C6C6`–`0x41C71E` and
mode 5 as in the table above. So `sub_41B240` is not the table's only reader.
[prank-reference.md](prank-reference.md) records both points in its record layout.

| State | Set at | What it does |
| --- | --- | --- |
| 40 | `0x41CFB5` | Sets `+992 = 0`, `+1000 = 200` (`0x41CDA9`) and `+1128 = "..."`. That is the same pointer free mode writes, so the hover bar does not change. Goes to 41 (`0x41CDC0`) |
| 41 | `0x41CDC0` | Goes to 42 (`0x41CDDA`) and adds no time |
| 42 | `0x41CDDA` | `+992 += dt`. At `+992 * 100 >= +1000` (`>=`, `0x41CE0F`) it sets `+992 = +1000 = 0` and goes to 43 (`0x41CE17`) |
| 43 | `0x41CE17` | Pays 10 (`sub_41DE60`). Plays slot 0 with loop 1, start 0 and finished 0 (`0x41CE4E`–`0x41CE69`). Sets mode and state to 0 (`0x41CE7B`, `0x41CE81`). Takes one from inventory item 14, clamped to 0–99 (`0x41CE87`, `0x41CE8F`). Sets `+996 = 0` (`0x41CEAF`) and `+1004 = 4000` (`0x41CEC5`). Calls `sub_41CD10(1)` (`0x41CECB`) |
| 44 | nowhere | Resets the clip and the state. Nothing ever writes 44 |

States 40–42 change **no clip and no sound**, and they do not move the player. A player who
was walking keeps the looping `WALK` playing in place, with the footstep `S0601` still
sounding, for the full 2 s until state 43 switches to idle. The first mode-0 tick with no
direction held then stops the footstep (`0x41B189`). The pill pays its score when it ends,
not when it starts. It can never be caught (see below).

**The slow-down timer** runs in `sub_41CFC0` after the mode switch (`0x41D401`–`0x41D458`):

```c
if (+1004 <= 0.0) +1044 = 0;
else {
    +996 += dt;  +1044 = 1;
    if (+996 * 100.0 > +1004) { +996 = +1004 = 0; sub_41CD10(0); }   // strict
}
```

- **It lasts 40.0 s.** It counts from the tick that runs state 43, including that tick's dt,
  and ends when the accumulated time exceeds 40.
- **The overlay lasts one frame longer.** `+1044` is still 1 on the tick that releases the
  slow-down and 0 from the next one.
- **It stops whenever the level clock stops.** dt is not clamped, but the level clock only
  advances on screen 1 while unpaused (`0x41199C`–`0x411A09`). So the pause, the quit prompt,
  the caught banner and the duel all stop both the 2 s and the 40 s. A won duel resumes with
  exactly the time that was left.
- **A second pill would restart it.** State 43 writes the timer unconditionally, so a second
  pill would restart a full 40 s, pay the score again and spend another pill. In the shipped
  levels it cannot happen: only object type 244, `MATRIXPILLE`, grants item 14 (through action
  85, which removes the object), and there is one per level. That is inferred from the data.

**Who is slowed.** `sub_41CD10(v)` walks `player+1072`, the character list `game+1924`. It
saves and restores the list's cursor, because `sub_402590` is iterating the same vector. It
writes `agent+1792 = v` (`0x41CD55`) on every entry with `+112 == 2` (`0x41CD4B`) that is not
the player (`0x41CD51`).

- The `CAgent` constructor `sub_415D50` sets `+112 = 2` (`0x415F2D`) and `+1792 = 0`
  (`0x415EEC`).
- The player is type 1 (`0x41B0A1`).
- Items and effects are kept in other lists.

**So every agent is slowed: the boss, the secretary, the janitor and the four coworkers. The
player never is.**

**What being slowed changes.** Four agent ticks open with the same lines, right after
`DeltaTime_Calculate`:

- the boss, `sub_419740` (`0x41975A`);
- the coworkers, `sub_419CE0` (`0x419CFB`);
- the janitor, `sub_41A8D0` (`0x41A8EA`);
- the secretary, `sub_41E360` (`0x41E37B`).

```c
m = (agent+1792 == 1) ? 0.2 : 1.0;      // immediates 0x3E4CCCCD / 0x3F800000
agent+76 = m;
if (agent+116) (agent+116)+536 = m;     // the current clip's speed
```

Only `sub_417730` reads `+76`, once, at `0x417934`: `step = speed * +76 * dt`
(`0x417934`–`0x417949`). The speed is what `sub_42B3D0` returns, `+56` (`fld [ecx+38h]`), the
current speed and not the base. For the coworkers, the secretary and the janitor that is the
base `+1852` plus 0.15 × the aggression band (see [npc-reference.md](npc-reference.md) and
[catch-reference.md](catch-reference.md)); the boss's tick skips the band, so his is the
base. **So agents walk at a fifth of their current, banded speed.**

The clip speed feeds `CObjectAnim_SelectFrameFromTime`, which picks the frame from absolute
time:

```text
rate     = fps * speed
looping  : frame = floor(((now - start) mod (count / rate)) * rate)
one-shot : frame = floor((now - start) * rate); finished once it reaches count
```

**So every clip an agent plays runs at a fifth of its rate, the walk included, and a change of
speed makes the frame index jump instead of slowing down smoothly.**

- One-shot clips last five times longer. That matters for the coworkers' and the
  secretary's `IDLE#2`: their ticks wait for its finished flag (`0x419E0A`, `0x41E449`).
- The clips are shared. Each archetype's clip table (`sub_419850` boss, `sub_419ED0`
  coworkers, `sub_41A9F0` janitor, `sub_41E510` secretary) stores the registry's own object,
  so one agent's speed write reaches every agent using that clip.
- Only the clip that is current when the tick starts gets the speed. A clip switched to
  later in the same tick keeps its old speed for that frame. After the release, a clip that
  is not current keeps 0.2 until it next becomes current.
- These are unaffected, because none of them reads either field: the needs and goal timers
  (`sub_416770` gets the raw dt), the 0.4-tile arrival radius, the notice test, the field of
  view, the catch and the aggression band. The 0.2 at `0x4658A8` is the band's radius factor,
  not the slow-down.

**The green copies.** While `+1792` is 1, the agent draw `sub_417460` adds three copies of
the current frame (`0x41762D`–`0x41772F`). They come after everything else it draws:

1. the sprite (mode 7);
2. the thought bubble (mode 20, alpha 180, at y − 135);
3. the name (mode 36, depth 64000);
4. the shadow `+1736` (mode 10, depth 65000).

It then restores the blend mode.

```text
mode 54                                   // 0x41763F
weight 120                                // sub_42D1D0, ctx+28
tint (40, 255, 40)                        // sub_42D1E0
brightness +60                            // sub_42D200, ctx+43
three times:
    depth = agent depth - 2
    y = anchor_y + rand() % 4 - 2         // -2..+1, drawn first
    x = anchor_x + rand() % 6 - 3         // -3..+2
    draw the frame at (x, y, depth)       // 0x4176A5, 0x4176E0, 0x41771B
```

Each copy gets fresh offsets on every rendered frame. Character sprites are 8 bpp with a Z
plane, so `0x471924` → `sub_43B050` draws them:

```text
skip the colour key; skip if zbuffer < spriteZ + depth    // never writes Z
c_i   = min(255, (palette_i * tint_i >> 8) + 60)
out_i = (c_i * 120 >> 8) + (dst_i * 135 >> 8)
```

This is a plain blend, at 120/256, of a brightened green copy. It is not additive, and it is
tested 2 depth units in front of the agent. The 32-bpp variants, `0x450530` and `0x450B80`,
skip the +60.

The hover highlights use the same mode 54, and the copy's weight stays fixed while its
brightness pulses:

- **Items.** `sub_411E20` sets mode `0x36` (`0x411EBA`), the weight `item+7` through
  `sub_42D1D0` (`0x411EC8`) and the tint `item+4..6`. `item+7` is 180 for every item tint. The
  brightness is `0x78 − ftol(sin(item+0x48 * flt_4652F0) * dbl_4652E8)`, set through
  `sub_42D200` (`0x411EFF`), so it is the brightness that swings between 40 and 200.
- **Agents.** The character loop sets the same mode 54 with weight 200 (`0x402A3D`, `0x402A7A`)
  but calls the agent's own draw `sub_417460`, which overwrites the blend mode (mode 7 body,
  mode 20 bubble), so for a colleague the weight is dead: its opaque body does not change and
  its shadow and bubble just draw twice (stronger, lighter). See "How the highlight is drawn" in
  [player-action-reference.md](player-action-reference.md).
- **The effects list** does the item's brightened pass (`0x402BAF`).

So an **item's** highlight is a blend at the fixed weight 180/256 with a pulsing brightness lift;
it is not additive. A **colleague's** is not a brightened copy at all.
[player-action-reference.md](player-action-reference.md) and
[names-reference.md](names-reference.md) now describe it this way.
`scenes/shared/object_highlight.gdshader` blends that brightened copy at the item weight
(180/255), not additively; see
[player-action-reference.md](player-action-reference.md).

**The overlay.** `player+1044` has one reader, the player's draw `sub_41D500` (`0x41D514`).
While it is 1 and the player is on screen, that draw first paints a four-corner gradient
over the world with `sub_42CB60` → `sub_4584D0`, then draws the player.

| Corner | Dword | Colour |
| --- | --- | --- |
| Top left | `0x00A000` (`0x41D546`) | (0, 160, 0), green |
| Top right | `0x0000A0` (`0x41D54E`) | (160, 0, 0), red |
| Bottom left | `0xA00000` (`0x41D556`) | (0, 0, 160), blue |
| Bottom right | `0xA0A000` (`0x41D55E`) | (0, 160, 160), cyan |

- **Area.** The rectangle is 0..800 × 0..600, clipped to the world pass's (1, 1)–(799, 509).
  The gradient steps come from the clipped size (4096/799 and 4096/509), so the corner
  colours sit at the corners of the world area.
- **Blend.** The interpolation is bilinear in 12-bit fixed point. With alpha 0 (`0x41D583`),
  `sub_4584D0` takes its averaging branch,
  `dst = ((dst >> 1) & 0x7F7F7F) + ((grad >> 1) & 0x7F7F7F)`: half the scene and half the
  gradient. It does not touch Z.
- **Colours.** The colours above read the dwords in the back buffer's `R, G, B, X` byte order,
  recovered in [field-of-view-reference.md](field-of-view-reference.md). The pill sitting had
  named them under the older `0x00RRGGBB` assumption (blue top right, red bottom left, olive
  bottom right) and left the order open. No screenshot has confirmed either reading.
- **What it covers.** It is painted at the player's place in the character loop, and the
  player is always entry 0 of `game+1924`:
  - `sub_407140` empties the list at teardown (`0x4071C3`, end = begin);
  - the level start `sub_406AF0` spawns type 0, the player, first (`0x406B3D`). It falls back
    to (5.0, 10.0) when there is no `SPAWN` record. Only then does it spawn types 1–7;
  - the other `sub_419490` push, at `0x418E30`, fills a map list, not `game+1924`.

  So the floor, the field-of-view tint, the walls and the items are tinted. The player, every
  agent, the effects and the HUD never are.

**At a level's start** everything is rebuilt: the new agents start unslowed and `sub_41AF60`
zeroes the timers. Returning to the level from screen 10, 5, 4 or 9 resumes it in memory and
keeps a running slow-down. The clips' speed lives on shared registry animations, which are
not rebuilt; that costs at most one frame.

## Mode 4: foam, unreachable

`sub_41C660` has states 30–33 (`0x41CF9B`, `0x41C77A`, `0x41CB9B`, `0x41CBEE`, then 0 at
`0x41CCB3`). If it ran, it would:

- play slot 11, `FOAMING`;
- spawn a `CFoam` (vtable `0x4659F4`: the puddle's vtable except for its draw, `sub_41E260`;
  alpha 0.9, set at `0x41C994`; animation `player+1096` = `CO_EFFECT_FOAM`);
- spawn a `CSfxSparks` (vtable `0x4659AC`: 250 particles, parameters from `0x4713E8`, the
  Strings animation at `0x41CAF3`, and a ±2° heading jitter from `rand()`);
- read records 69–72 directly (`0x41C6C6`–`0x41C71E`, `0x41CC35`–`0x41CC4A`). Each is named
  `...`, lasts 40 tenths and scores 400, 500, 600 or 800;
- reset `+1048` (`0x41C7E0`).

**Nothing can start it**, because its bit `0x2000` is never raised:

- The only ORs into the input register's high byte are the lamps' three (`0x404070`,
  `0x40407B`, `0x404086`), `0x400` (`0x404271`, `0x40446D`) and `0x100` (`0x4043DA`).
- Every full store to the register writes `0x200` (`0x401362`, `0x40468E`, `0x4047AE`,
  `0x4048BB`, `0x4072C3`).
- `player+908` is written only at `0x4037A1` and `0x41B01A`.
- `dword_473CDC` only ever holds 1–3.

`CO_CHARS` has no `FOAMING` sprites either. The mode has no abort state and is not in the
catch set.

## The console, the cursor and the catch while an ability runs

**Console.** `sub_403780` feeds an ability's fields to the console exactly as it feeds a
prank's (see [hud-reference.md](hud-reference.md)):

- **Stopwatch.** `game+14724 +112 = +992 * 100.0 / +1000` while `+1000 > 0`, else 0
  (`0x40384C`–`0x403888`), a fraction from 0 to 1. Smoking sweeps its 12.0 s, including the
  0.4 s before the smoke appears, and reads 0 from the tick that moves it to 13; urinating
  sweeps 7.0 s; the pill sweeps 2.0 s and shows 0 on
  its first two frames. The 40 s slow-down is not shown.
- **Hover bar.** `game+14796 = +1128` on every tick where `+1128` is set (`0x403AB9`). It
  shows the record's name from the first state until the first mode-0 tick writes `...`
  (`0x41B19E`, `0x41B20A`). The pill's name is `...`.
- **Centre icon.** Hidden while `+920` is −1 (`0x403AD5`–`0x403AFB`). Only mode 1 writes any
  other value there, so it stays hidden for every ability.
- **Lamps.** As described above. Each goes dark on the first HUD tick after its item reaches
  0.

**Cursor.** At the top of every `sub_403FB0`, `sub_4154B0(game+15000, 1)` shows the clock
for states 2–4, 11–13, 21–23, 31–33 and 41–43, and the pointer otherwise
(`0x403FF6`–`0x40403F`, `0x404053`).

- States 10, 20 and 40 turn into 11, 21 and 41 within their own tick, so the input pass never
  sees them. The clock therefore shows from the second frame after the press until one frame
  after the last state.
- The aborts, 14 and 24, show the pointer.
- The walk arrow cannot appear while an ability runs: the right-button branch needs
  `+900 == 0` or `+904 == 1` (`0x4043B1`–`0x4043C2`).

**Movement.** Only the free-mode tick `sub_41B0C0` moves the player. `sub_42B3E0` is called
from it (`0x41B125`) and from the agents' `sub_417730` (`0x417950`), and nowhere else.

- An ability stops the player at once, even mid-walk.
- Smoking and urinating replace the clip and stop the footstep loop. The pill does neither.
- `and al, 0Fh` at `0x403FC1` wipes a right-button walk's movement bits on the next frame,
  and the right-button branch stops raising them. Arrow-key bits stay set.
- When the ability ends, a right button that is still held raises the walk again on the next
  mouse event, and the first mode-0 tick walks.
- A right release still re-centres both cursors on the player, `sub_4155F0` and `sub_45A290`
  (`0x40447E`–`0x4044A3`). That branch tests no mode, so it runs under a prank or an ability
  as well, and it starts no walk.

**No way out.** Escape (`0x40410A`), the down arrow and the right button (`0x404520`) act only
when `+904 == 1`, which is the ring. The only aborts are the catch's states 14 and 24; nothing
writes 34 or 44. A level end (`sub_403780` → `sub_407370(7/8)`, `0x403C27`/`0x403C65`)
abandons an ability in the middle of a state. The world is not ticked on those screens, and
`sub_41AF60` resets the player at the next start.

**The catch.** `sub_402470` runs on screen 1 only (`0x402475`). It catches on the player's
state alone, in `[2, 3]`, `[11, 12]` and `[21, 22]` (`0x40248E`–`0x4024AA`), for an agent
that meets three conditions:

- it has `+112 == 2` (`0x4024D2`);
- it is not in a cubicle, `+1824 == 0` (`0x4024EB`);
- `sub_418310` says it sees the player.

The notice test reads no mode or state, so **smoking and urinating are noticed exactly like a
prank** (see [catch-reference.md](catch-reference.md)).

- The pill (40–44) is never caught. Neither are the first states, 10 and 20, or the last,
  13 and 23.
- The catch runs last in the world tick. `sub_402590` ticks the character list `game+1924`
  (`0x402600`), then the effects list `game+1960` (`0x4026BE`), then `Update_Dispatcher`
  (`0x411FF0`, called at `0x402749`) for the items on the map's list, then the collision
  `sub_4019D0` (`0x402750`), and only then the catch (`0x402757`). The player is on the
  character list, so smoking is catchable from its very first tick.
- Urination's state 21 is catchable only on that first tick, before the puddle exists. From
  then on it is state 22.

On a catch, `sub_402470` stores the catcher (`0x402521`), writes 14 (`0x40254E`) or 24
(`0x402568`), and opens the caught banner (`sub_407370(4)`, `sub_407990`). It touches no
timer, name, item or effect.

- **The item survives a catch.** Neither 14 nor 24 pays or spends, so the cigarette or the
  bladder is kept and the lamp stays lit.
- **The stopwatch holds.** It keeps the partial sweep until state 14 or 24 zeroes it.
- **Spawned effects stay.** A smoke or puddle already spawned stays and ages on its own
  clock. That clock stands still through the banner and the duel, and so does a state 14
  waiting for the `SMOKE` clip, since clips run on the same frozen clock.
- A catch in state 11 or 21 means nothing had been spawned yet.

## Which levels light which lamp

This table is read from the imported manifests, `resources/levels/level_*.json`. An object's
action slots are its type's `CO_OBJECTS.DAT +528` list. These actions grant the lamp items:

| Item | Action | Name | Object | Type |
| --- | --- | --- | --- | --- |
| 5 | 48 | `Zabierz papierosy` | `ZIGARETTEN` | 176 |
| 6 | 19 | `Zabierz zapalniczkę` | `FEUERZEUG` | 145 |
| 14 | 85 | `...` | `MATRIXPILLE` | 244 |
| 26 | 84 | `Napełnij pęcherz` | `KÜHLSCHRANK` | 150 |
| 26 | 154 | `Napełnij pęcherz` | `FLASCHE` | 6 |
| 26 | 130 | `Opróżnij prywatną butelkę szefa` | `CHEFMINIBAR` | 257 |

- None of these actions requires an item, and none waits behind another slot's unlock, so
  each is available from the start.
- Only 31 `Odmroź lodówkę`, on the same fridge, disables 84.
- The safe on `TRESOR` unlocks 85, but no `TRESOR` carries 85, so the pill never sits behind
  the safe.

Every source was checked for reach with a 4-connected walk from the spawn, the 2.0-tile reach
and the sight ray. That is a static approximation, not a play-test, and all but one source
passed. The failure was not named at the time. It is `ZIGARETTEN` `ITEM132` in 11s, #140 in
`level_11s.json`, and it cannot be reached. The manifest puts it off the grid at
(−3.698, 1.490), with its interaction point at (−3.698, 2.490). Column 0 is movement-blocked
along those rows, so that point is more than 4 tiles from any walkable position, against the
2.0-tile reach. That it is the sweep's unnamed failure is deduced: it is the one source no
check could pass. [map-rendering.md](map-rendering.md) names the same record.

The room columns come from each manifest's `collision_grid.room_ids`, which is
`(INFODATA >> 16) & 0xFF`. Room 3 lets smoking pay record 22. Room 4 pays 76. Room 8 pays
smoking's 24 and urination's 75. Every level also has other rooms, for 23 and 74.

| Level | Smoke (5 + 6) | Pill (14) | Bladder (26), by action | Rooms 3 / 4 / 8 |
| --- | --- | --- | --- | --- |
| 1 | yes | — | 154, 84 | 3, 4, 8 |
| 2 | yes | yes | 84 only | 3, 8 |
| 3 | yes | — | 154 | 3 |
| 4 | no cigarettes | — | 84 only | 4, 8 |
| 5, 5s | yes | — | 84 only | 8 |
| 6 | yes | — | 84, 154 | 8 |
| 7 | yes | — | 84, 130 | 4, 8 |
| 8, 8s | yes | — | 84, 154, 130 | 3, 4, 8 |
| 9 | no cigarettes | — | 84, 154, 154 | 3, 8 |
| 10 | yes | — | 84 only | 3, 8 |
| 11 | yes | — | — | 4, 8 |
| 11s | yes | — | — | 4, 8 |
| 12, 12s | yes | yes | — | 3 |
| 13 | yes | yes | 84, 154, 130 | 3, 4, 8 |
| 14 | yes | — | 84, 130, 154 | 8 |
| 15 | yes | yes | 154 | 3, 8 |
| 16 | yes | yes | 84, 154, 130 | 3, 4, 8 |
| 17 | yes | yes | 84, 154 | 8 |
| 18 | yes | yes | 154, 84 | 3, 8 |
| 19, 19s | yes | yes | 84, 154, 154, 130 | 3, 8 |
| 20, 20s | yes | — | 84, 154, 130 | 3, 8 |
| 21 | yes | — | 154 | none |

- **All three lamps** light on levels 2, 13 and 15–19 (with 19s).
- On 2, 4, 5, 5s and 10 the fridge is the only source of item 26, so using 31 on it first
  costs the lamp.
- In 11s the points-mode file moves `ZIGARETTEN` `ITEM132` (#140) off the grid, to
  (−3.698, 1.490), where it cannot be reached. It adds `ITEM190` (#198) at (5.24, 19.97), next
  to where `ITEM132` stands in level 11 (5.28, 19.97), so smoking still works.
- **For a play-test, level 13 is the best map.** It has all three special rooms (3 at cell
  (20, 19), 4 at (24, 3), 8 at (5, 4)) and every kind of source:
  - cigarettes #203 at (22.45, 1.59), inside the server room;
  - the lighter #134 at (1.31, 10.65);
  - the pill #157 at (2.50, 8.58);
  - the boss's minibar #200 at (1.20, 0.93).
- **Level 2 is the earliest with all three lamps.** It opens once level 1 is cleared. It has
  no server room, and its only bladder source is the fridge, #82.

## Not recovered

- **How many frames a real click lasts.** DirectInput is polled once per frame, so the press
  and the release always land on different frames. Whether the release usually comes on the
  frame right after the press depends on the frame rate, which is not established. That is
  the only case where the act bit takes the lamp's press.
- **The RANMAR seed**, and so the smoke's exact random sequence. Only the ranges matter.
- **`SPRITEHDR +536`** (`sprite+560`). It is 1 on every `*_alpha` sprite, and mode 46 never
  reads it.
- **No screenshot check.** No screenshot of the smoke, the puddle, the green copies or the
  overlay was checked. The overlay's colours rest on the byte order alone. The smoke's missing
  fade and its `+48` depth bias look like bugs in the original, but they are what the binary
  does.
- **`player+1044`'s initial value.** Neither the constructor nor `sub_41AF60` writes it, so it
  holds heap garbage until the first tick.
- **Which of records 69–72 mode 4 picks.** The mode is unreachable.
- **Inferred rather than observed:** an ability started under the caught banner, the orphaned
  smoke, the release taking the lamp's press, the unreachable item behind a lamp, and that
  `ITEM132` was the reach sweep's unnamed failure.

## In the port

The lamps, the controller behind them and modes 2, 3 and 5 are in place, with the smoke, the
puddle, the slowed office, its green copies and the overlay. A request for foam is still
dropped, as nothing can raise it.

### The controller

`scenes/player/ability_controller.gd` sits beside `PrankController` in
`scenes/player/player.tscn`. It is the part of `sub_41CFC0` that is not a prank. Each tick
it:

1. takes a lamp's request, as `sub_41CF20` does (`0x41D003`);
2. runs one state of the running mode (`0x41D013`);
3. holds the player's effects to the shared clock: the smoke's stop (`0x41D072`–`0x41D13D`),
   then the puddle's growth and removal (`0x41D143`–`0x41D252`);
4. runs the pill's slow-down timer (`0x41D401`–`0x41D458`) and shows the overlay by `+1044`;
5. picks the clip's frame last (`0x41D4D6`);
6. ticks every effect it spawned, which is what `sub_402590` does to `game+1960` after the
   character list (`0x4026BE`).

Nothing between the character list and the effects list reads an effect, so ticking them
straight after the player changes nothing.

Its fields are the player's:

| Field | Original |
| --- | --- |
| `mode`, `state` | `+900`, `+904` for modes 2–5 |
| `timer`, read as `elapsed` and `total` | `+992` in seconds, `+1000` in hundredths |
| `slow_timer`, read as `slow_elapsed` and `slow_total`; `slowdown_shown` | `+996`, `+1004`; `+1044` |
| `overlay` | what `sub_41D500` paints while `+1044` is up |
| `effect_clock` | `+1048` |
| `smoke` | `+1052` |
| `puddle` | `+1080` |
| `piss_sound` | `+1116`, with `null` for its −1 |
| `effects` | what the player pushed onto `game+1960` |

`now` is the level's clock: the sum of the controller's own frame steps, which stands still
whenever the tree is paused, as the original's clock stands still off screen 1. The
durations and scores come from `resources/original/actions.json`; only the room-to-record
choice is the code's own.

**The timers are float32 sums, as `+992` and `+996` are.** The step is a float (`0x41CFDA`).
Each add loads it, adds the field and stores the result with `fst`, and the state then compares
the sum still on the x87 stack, not the float it stored (`0x41BDAA`–`0x41BDBA`,
`0x41BFCF`–`0x41BFE5`, `0x41C24A`–`0x41C268`, `0x41C4DD`–`0x41C4F3`, `0x41D415`–`0x41D435`).
A prank, mode 1, keeps the same two fields the same way: `sub_41B240`'s state 2 zeroes `+992`
and stores `+1000 = tenths * 10.0` with `fstp` (`0x41B5E7`, `0x41B5FA`–`0x41B60B`), and state 3
adds, stores with `fst`, multiplies by 100.0 and compares (`0x41B6DE`–`0x41B6F4`), zeroing both
on its way to state 4 (`0x41B705`–`0x41B711`). The CRT's start-up call
`_controlfp(0x10000, 0x30000)` (`0x461CEE`), `_PC_53`, holds the x87 to 53 bits, so that sum and
its product with 100 round as the port's doubles do. `scenes/player/player_timer.gd` is that
pair in the port, and both `PrankController` and `AbilityController` keep theirs in it:
`add_elapsed()` adds the step as a float32, stores the sum as a float32 and hands back the
unrounded sum, which `reached()` tests; the slow-down timer is another `PlayerTimer`, tested
strictly by `passed()`, and state 11 compares the sum against the float32 0.4 at `flt_46587C`.
It matters at real frame rates: at 60 fps urinating's 7.0 s ends on the 420th step and
smoking's 12.0 s on the 721st, with the smoke spawned on the 24th, where the double sums the
port used to keep gave 421, 720 and 25. The pranks' durations, 10 to 120 tenths, end on a
different step from a double sum's at 60 fps for 1, 5, 6, 7, 8 and 12 seconds (61, 300, 360,
420, 480 and 721 steps, against 60, 301, 361, 421, 481 and 720). Comparing the stored float
instead would spawn the smoke a tick late at 13 of the whole rates from 20 to 300 fps.

**The clock's constants are shared, one float each.** The 10.0 at `flt_4652F4` that turns a
record's tenths into hundredths and the 100.0 at `flt_465304` that turns elapsed seconds into
hundredths are read by all four timed modes: a prank's states 2 and 3 in `sub_41B240`
(`0x41B605`, `0x41B6EE`), smoking's state 10 once per room branch (`0x41BCF7`, `0x41BD10`,
`0x41BD30`, `0x41BD50`) and its state 12 (`0x41BFDF`), urinating's state 20 once per branch
(`0x41C180`, `0x41C19F`) and its state 22 (`0x41C4ED`), and the pill's states 40 and 43
(`0x41CDAF`, `0x41CEBF`) and 42 (`0x41CDFE`). The player tick reads the same 100.0 for the
slow-down's test (`0x41D42F`) and the same 10.0 three more ways: as the puddle's ten-second
gate (`0x41D15B`, `0x41D168`, `0x41D199`), as the same gate for the foam effect, which nothing
reaches (`0x41D270`, `0x41D27D`), and as the rate of prank 79's blackout,
`player+1068 -= dt * 10` (`0x41D475`). `sub_403780` reads the same 100.0 to feed the stopwatch
`+992 * 100 / +1000` (`0x40386B`). `tools/export_ability_timers.py` reads both, with smoking's
0.4 (`flt_46587C`, `0x41BDBA`) and the smoke's 4.5 (`flt_465A34`, `0x41D08B`), and pins every
one of those readers. `PlayerTimer.factor()` hands all four out of
`resources/original/ability_timers.json`, and the puddle's gate (`puddle.gd`'s `grow_after()`)
and the blackout (`prank_controller.gd`'s `_advance_blackout()`) take the 10.0 from there too,
so each float is read out once, by one exporter.

**The gate and the console stay with `PrankController`.** `+900` is one field in the
original, so `PrankController` has a fourth state, `ABILITY`, taken by `begin_ability()` and
given back by `end_ability()`. While it is held the ring cannot open and the item pick is
off (`0x4032B8`); the colleague under the cursor is still picked. A lamp only starts from
`FREE`. The console still reads `PrankController` alone, through `highlight_changed`,
`progress_changed` and `inventory_changed`:

- an ability writes its record's name with `show_ability_record()`;
- it feeds the stopwatch with `report_ability_progress(elapsed, total / 100)`;
- it spends with `spend_item()`, which clamps to 0–99.

So `console.gd` reads an ability exactly as it reads a prank. `grant_item()` is the grant
that `sub_41B240` state 4 has always made. The first free tick after an ability writes `...`
back, as `sub_41B0C0` does, unless the ring opened in the meantime.

### The lamps in the port

`scenes/hud/console.gd` takes the left press in `_input`:

- A press counts strictly inside a lit lamp's own sprite rect, in whole band pixels.
- The lamps are walked in registration order, Matrix, urination and smoking, so urination
  wins the overlap.
- The manager's latch is kept. Any left, right or middle release clears it. Button events
  are re-tested every frame the left button is held, so a drag onto a lit lamp fires, and so
  does a lamp that lights under a held press.
- A press that fires is marked handled. The ring, which the port opens on the press, and the
  colleague selection never see it. Motion is not consumed.

The console calls `AbilityController.request()` with the lamp's bit. The controller looks at
it on its next tick only, and drops it unless the player is free then. The pause and unpause
notifications drop it too, which covers the pause key, the quit prompt, the caught banner
and the duel. The original loses it to the pause, and `sub_407370` clears the id itself in
cases 1 and 9 (`0x40741F`, `0x407447`), on the way back from the quit prompt and the duel.
Godot handles input before the
frame's processing, so an ability starts in the frame its press arrives, one frame earlier
than the original.

No lamp is pressed while the ring is visible, open or closing. The original makes the lamps
unreachable through the close by re-centring the cursor on every tick of it (`0x40685A`); the
port warps the pointer once, so it refuses the press instead.

Four recorded losses:

- **Under the caught banner.** The original still runs input and the world on screen 4 at a
  zero step, so a lamp pressed there starts an ability as soon as the player is free, and
  mode 3 even spawns its puddle. The port pauses the whole tree, so no lamp can be pressed
  under the banner. The duel takes no lamp press in either, as it runs its own GUI manager.
  [catch-reference.md](catch-reference.md) records the same loss for the ring.
- **Two frames of leniency.** The port's lamp goes dark on the `inventory_changed` that spends
  the last item, before a later press can land, so there is never an extra ability with the
  item at 0.
- **A release taking the press.** The press the HUD consumed is the one that would open the
  ring or select a colleague, so neither the act bit nor an agent behind the lamp gets it.
- **A drag from a focused item.** The port opens the ring on the left press (see
  [player-action-reference.md](player-action-reference.md)), so a press that starts on a
  focused item and is dragged onto a lit lamp opens the ring, and the ring refuses the lamp.
  The original raises the act bit only on the release (`0x40445F`–`0x404478`); the lamp's
  bit, raised during the drag, reaches `sub_41CF20` first and starts the ability, and the
  release's `0x400` then finds `+900` taken. `tests/check_console_lamps.gd` pins the port's
  side.

### Smoking

States 10 to 14 run as the table above has them, one per tick.

- **Stopping and starting the player.** State 10 calls `Player.hold_for_ability()`. That
  stops a right-button walk where it stands without re-centring the pointer, and stops the
  footstep loop. The clock is the pointer from that tick until the player is free again, and
  the plain pointer shows in state 14. Escape, the down arrow and the right button do nothing
  while the ability runs. `release_from_ability()` resumes the walk if the right button is
  still held at the end.
- **A right release re-centres.** While `input_locked` holds the player, for a prank as for an
  ability, a right release calls `MovementArrow.recentre()`: the pointer goes back onto the
  player as `sub_4155F0` puts it, the clock stays, and no walk starts.
- **The last states.** State 12 zeroes the timers as it hands over to 13, so the stopwatch is
  empty on that tick. State 13 asks the room at the player again and pays that room's score;
  the hover bar keeps the name state 10 chose until the first free tick.
- **The clip.** `SMOKE` is played by `AnimationController.play_once()`. The imported clip loops,
  as its `ANIM` says, so the `AnimationPlayer` is stopped and the frame is set from the clip's
  keys at `now − start`. The finished flag is raised in the same pass that picks the frame,
  last in the tick, so state 12 sees it one tick later and the last frame stays up for that
  tick. The idle that follows is the clock-driven one.
- **The record** comes from the room at the player; see "The room grid" below.

### The smoke in the port

`scenes/effects/smoke.gd` is a `MultiMeshInstance2D`, one instance per particle, drawn with
`scenes/effects/smoke.gdshader`.

- **Parameters.** The 112-byte block from `0x471378`, the 200 and the spawn's, the tick's and
  the projection's own constants are read out of `sacked.exe` by
  `tools/export_smoke_params.py` into `resources/original/smoke.json`, each at the address its
  code reads it from. Its `--check` pins the file to the executable, every value to the tables
  above and every instruction that reads a constant, opcode and operand, with
  `tools/original_exe.py`'s `pin_readers()`. Every exporter that pins a constant's readers
  shares that helper: the smoke's, the puddle's, the view angles', the ability timers', the
  field of view's and the action table's. The view's angle, `(view * 45.0 + 180.0) * 0.017453`,
  is not in that file: the puddle and the field-of-view cone read the same three floats, so
  `tools/export_view_angles.py` exports them once into `resources/original/view_angles.json`,
  pinned at every reader, and `scenes/shared/view_angle.gd`'s `of_view()` computes the angle
  for both effects.
- **Particles.** The emitter, the ramps, the 200 cap, the swap-remove order,
  the drift and rise and the `25 * ceil(acc / 2)` bursts are as recovered. Each particle's
  fields are float32, as `sub_426730` stores them, in one `PackedFloat32Array`. The smoke
  keeps its own last time and ticks with `now`, the way `DeltaTime_Calculate` seeds, so its
  first step is 0.
- **The random source.** RANMAR's seed is not recovered, so a Godot `RandomNumberGenerator`
  stands in, in the same eight-draw order. A check can hand in its own source.
- **The frame** is `floor(8 * age) mod 16` from `resources/effects/strings.json`, the fps
  there, which `frame_of()` computes for the draw. All sixteen frames sit in one
  `Texture2DArray`, and the shader samples it at the blitter's step of `0x10000 / s`, texel
  for texel. The quad's top left is `floor(screen + 32 − 32 size) − 32` in world pixels; the 32
  is the frames' pivot, the negated `[-32, -32]` offset `tools/export_gui_assets.py` writes for
  each frame into the same file, and the loader refuses frames that disagree. The original truncates camera-relative coordinates, which are positive on
  screen, so the result is the same.
- **The blend.** Mode 46 is done in premultiplied form: the shader writes
  `(a * ((src * tint) >> 8)) >> 8` with an alpha of `(a + 1) / 256`, so the back buffer keeps
  `(255 − a) / 256` of itself. Nothing fades. A pixel whose colour is pure black is discarded,
  which is Strings' colour key.
- **Depth.** The score is `ceil(int(sy) / 2) − 48` in world space, the convention in
  [map-rendering.md](map-rendering.md). The shader tests it against the world composite. The
  characters' Z is tested through their own depth planes: those of the depth-composited actors
  whose frames overlap the smoke, which are the characters and any object whose clip loops.
  It tests the six nearest; a seventh would not hide it, which is a port limit. The smoke
  writes nothing. The test is `scenes/effects/effect_depth.gd` and
  `scenes/effects/effect_depth.gdshaderinc`, which the puddle uses too.
- **The bubbles are not in the test.** `sub_417460` hands an agent's thought bubble the same Z
  as its sprite, `agent+0x10` (`0x41752F`–`0x417544`, against `0x417490`–`0x4174A3` for the
  sprite), and mode 20 writes that Z wherever it draws (see
  [npc-reference.md](npc-reference.md)). So in the original a bubble hides the particles
  behind its agent. The port draws a bubble at z 2 with no depth, under the smoke. Whether the
  names write Z is not recovered.
- **What that shows.** A character's depth plane runs about 150 at the head to 170 at the
  feet. A particle over a character standing where it was spawned is therefore nearer, and it
  covers that character, the smoker's own head included. That is what the formulas give.
- **The depth test was checked in a window.** A probe on level 13 forced every particle's
  score far back. The character test then hid 1632 pixels inside the player's frame, and the
  world test hid the rack and the desk.
- **Draw order.** The smoke is the last child of `World` at z 3. That puts it after the
  characters (z 1), the bubbles (z 2) and the names; the rising scores in `LevelRuntime` come
  after it. The walk arrow, which is a world sprite in the port, sits at z 4, over both:
  `Main_RenderUpdate` draws it (`sub_415500`, `0x402D01`) after the effects pass and the GUI,
  so a smoke that outlives its ability never covers it.
- **The draw.** Each tick projects every particle once, into the `MultiMesh` buffer and the
  bounds the depth test reads, and the actor uniforms are set again only when the set of
  overlapping actors changes. The multimesh has a fixed box far past the level: the canvas
  keeps the rect it took from the smoke's first draw, which is empty, and a buffer set later
  does not refresh it, so without the box a window showed no smoke at all.
- **Clipping.** The smoke has no clip of its own. The original clips it to the world area,
  `(1, 1)`–`(799, 509)`. The port clips its world to nothing but the viewport and draws the
  console over it, and at 4:3 the console is opaque from y 510 down. So the only difference is
  the one-pixel border, which the port's world does not keep either.
- **Removal.** The controller's gate stops the emission once `now − effect_clock > 4.5` and
  frees the smoke on the first tick that finds it empty. A level's teardown frees it with
  `World`.
- **The quirks are kept.** State 11 overwrites `smoke` without a look, so an orphaned smoke goes
  on emitting until the level ends. Every state that writes the effect clock resets the one
  clock the smoke is gated on.

A run on level 13, in the server room with items 5 and 6 and the lamp clicked through a real
mouse press, showed this at 800 × 600 and at 1067 × 600:

| Time after the press | What the screenshot shows |
| --- | --- |
| 0.2 s | the `SMOKE` clip's first frame and the stopwatch's first sliver |
| 1 s | the cigarette at the mouth, and no particles yet |
| 3 s | the first burst, small at the chin |
| 6 s | a cloud over the head, and the stopwatch at half |
| 12.5 s | `00350` and a rising `350`, `...` in the hover bar, and the lamp dark |

The hover bar showed record 76's name throughout.

A second run, after the smoke moved to one instance buffer, showed the same shots, except
that it held two packs, so the lamp stayed lit at 12.5 s. It also showed the stopwatch empty
on the tick state 13 comes, a right release at 7 s putting the pointer back on the player
with the clock still up, and the walk arrow of a later walk drawn over a caught smoke. The
depth probe gave the same counts as before. At 200 particles the tick costs about 0.6 ms a
frame and the depth uniforms 0.02 ms, against 2.2 ms and 0.6 ms before.

### Urinating

States 20 to 24 run as the table above has them, one per tick.

- **The record** comes from the room at the player: 75 in the boss's office and 74 anywhere
  else. State 23 asks the room again for the score it pays, as smoking's state 13 does, and the
  hover bar keeps state 20's name.
- **The facing** is `PrankController.piss_facing()`: the two `rand() & 8` tests over
  `PISS_VIEWS`, Anne's 2, 3, 4 and Jo's 0, 6, 7 in the original's order. The prank's selector 12
  calls it too (see [player-action-reference.md](player-action-reference.md)).
  `AbilityController.facing_roll` stands in for `rand()`, so a check can fix it. The player
  keeps the view after state 23 or 24.
- **The clip.** `PISS#1` is played through `Player.play_action_animation()` and is clock-driven:
  `Player.apply_profile()` hands `AnimationController.configure()` the
  `<id>-actions/<id>-piss-1-` prefix beside the idle's and the walk's. Its frame is therefore
  `floor((t mod 0.375) * 16)` on the clock the port's idle and walk already follow,
  `Time.get_ticks_usec()`, rather than on the level's clock.
- **The player** is stopped as for smoking: `hold_for_ability()` stops the walk and the
  footstep loop in state 20, the clock shows through state 23, and the pointer on 24.
- **The sound.** State 21 asks `LevelAudio.play_effect("S0174")`, which hands it to
  `ScreenManager`, the port's `game+15136`. It plays once, at the full effects volume, on the
  SFX bus, with no position. The player it returns is `piss_sound`, `+1116`.
  - States 23 and 24 stop it with `LevelAudio.stop_effect()` and let go of it.
  - So does the controller's `_exit_tree()`, as `~CObj_Player` does (`0x41AF1C`), and every way
    out of a level frees the player.
  - The sound ends 0.24 s before state 23, and `ScreenManager` frees a player whose sound has
    ended. `stop_effect()` takes a freed player as already stopped, so the handle is dropped
    quietly. The first windowed run found state 23 tripping over that freed player.
  - The original's slot, freed at the same moment, can go to another sound, which state 23
    then stops. The port's handle is its own player, so that quirk cannot happen.
- **The pause.** `ScreenManager`'s players always process, so `S0174` plays on through the
  pause key and the quit prompt while the ability's clock, and with it the 7 s, stands still,
  as in the original. A windowed run held a 0.6 s pause 1.5 s into the sound: its playback went
  from 1.49 s to 2.05 s, and `now` did not move.

### The puddle in the port

`scenes/effects/puddle.gd` is a `Sprite2D` drawn with `scenes/effects/puddle.gdshader`.

- **Parameters.** `tools/export_puddle_params.py` reads these out of `sacked.exe` into
  `resources/original/puddle.json`, each at the address its instruction names:
  - the two reaches as doubles, and the 0.1 and 0.7 immediates;
  - the growth and fade constants, and the 0.01 clamp on both scales (the second clamp
    stores the same bits as an immediate, which `--check` compares with the float);
  - the 256 of the draw and the 24 px of the projection.

  Its `--check` pins both the file and each instruction that reads a value, opcode and
  operand. The view's three floats come from `view_angles.json`, as the smoke's do. The
  ten-second gate is `flt_4652F4`, the player clock's 10.0, so it comes from
  `ability_timers.json` (see "The clock's constants are shared").
- **Placement.** `place()` puts the puddle `d` tiles along the view, 0.2 for Anne and 0.6 for
  Jo, 0.1 units up, and stores x and z as the floats `sub_42B330` receives. The offsets in
  the table above hold to within 0.05 px.
- **The clip** is `scenes/effects/puddle_animations.res`, read key by key with each frame's
  pivot and the `-depth.png` beside it. The frames are loaded into a static cache that every
  later puddle shares, so only the game's first puddle loads them. `tick()` shows the last frame that has started by
  `now − start`, so frame 10 holds from 1.25 s. Each puddle keeps its own start. The original
  shares one clip object, which makes no difference while there is only ever one puddle.
- **Projection**, in world pixels, with `floor` for the original's camera-relative truncation
  as for the smoke:

  ```text
  anchor   = ground(x, z) - (0, 24 * 0.1)
  base     = ceil(int(anchor.y) / 2)                    // the score of a Z of 0
  top_left = floor(floor(anchor) + pivot - pivot * s) - pivot
  quad     = ((w - 1) * S >> 8) + 1  by  ((h - 1) * S >> 8) + 1,  S = max(1, trunc(s * 256))
  ```

  Here `s` is the float scale. The sprite is placed on that quad and scaled to fill it.
- **The blend** is mode 22 in premultiplied form. The shader writes `(src * a) >> 8` with an
  alpha of `(a + 1) / 256`, so the back buffer keeps `(255 − a) / 256` of itself, where `a` is
  `trunc(alpha * 256)`. It reads the frame and its Z plane at the blitter's step of
  `0x10000 / S`, texel for texel. The destination half is not truncated, so a pixel can come
  out one above the blitter's.
- **Depth.** Each pixel's score is the base less its own Z-plane value. The shader tests it
  with the smoke's helper, `scenes/effects/effect_depth.gd` and `effect_depth.gdshaderinc`:
  - against the world composite, which holds the walls and the items;
  - against the own depth planes of up to six overlapping depth-composited actors, which stand
    in for the characters' Z.

  A tie draws, and nothing is written. On the frame state 21 builds the puddle in, `tick()`
  hands the shader the test along with the rest of the draw: a node added during a frame gets
  no `_process` in that frame, so that frame would otherwise have drawn with no test at all,
  over Anne's boots or the boss's desk. On every later frame `tick()` leaves the test alone and
  the puddle's own `_process` sets it up, once, after the controller's tick and the characters
  that move later in the frame: the puddle is appended to `World` after the player, which holds
  the controller. A windowed run with Anne's clip held draws the spawn frame around the puddle
  pixel for pixel as the frame after it.

  A puddle that lies behind the boss's desk shows a thin yellow edge along the desk's base on
  every frame. That edge is the original's. The desk's own Z plane (`SPRITEZB` of
  `ChefSchreibtisch02#270`, copied verbatim into `chef-schreibtisch02-270-depth.png`) gives 203
  of its 463 outline pixels a Z of 255, where its body runs 147–186. `0x42ECC0` keeps the
  smaller Z, so those pixels sit 70–110 units farther back than the body in the original's Z
  buffer, as they do in the port's composite. A puddle whose Z falls between the two passes
  mode 22's test on the outline and fails it on the body. Other desks' planes do the same:
  166 of 400 outline pixels for `Schreibtisch01#000`, 137 of 307 for `CouchTisch02`.
- **Draw order.** The puddle is a child of `World` at z 3, after the characters, their bubbles
  and names. The rising scores and the walk arrow come after it. Effects draw in the order
  they were spawned, as the list does. The player's shadow is drawn with the player, so the
  puddle blends over it.
- **The bubbles are not in the test**, as for the smoke. A bubble writes its agent's Z
  (`agent+0x10`) wherever mode 20 draws it, so in the original a bubble of a colleague who
  stands in front of the puddle hides the puddle there: the puddle's pixels fail mode 22's
  test. The port draws the bubble at z 2 with no depth, so the puddle blends over it. A run
  on level 13 showed it at 800 × 600: Anne urinating in the corridor at (9, 7), and the
  janitor, standing nearer with his feet at y 480, had his bubble under the puddle's lower-left
  lobe at y 304–326, blue 55 there where the bubble alone reads 185.
- **Growth and removal.** The controller's gate does what the player tick does. Past 10 s on
  `effect_clock` it calls `grow(age)`, which stores the scale, clamped to 0.01, and the alpha
  as floats. Past 17 s it takes the puddle off `effects` and frees it. A new state 21 frees the
  old puddle first, so there is only ever one, and a level's teardown frees it with `World`.
- **The shared clock is kept.** Smoking's state 10 and its spawn still write `effect_clock`, so
  lighting up restarts a puddle's age. Its scale and alpha stay where they were, snap back near
  1.0 and 0.7 once the new age passes 10, and it lives 17 s from the smoke's spawn.
- **Nothing reads the puddle** in the port either.

A run on level 13 with item 26 granted and the urination lamp clicked through a real mouse
press, in the corridor at (9, 7) and in the boss's office at (5, 4), as Jo at 800 × 600 and as
Anne at 1067 × 600, showed this:

| Age | What the screenshot shows |
| --- | --- |
| 0.5 s | `PISS#1` in the picked view (Jo up-right, Anne down-right) with its stream, frame 3 of the puddle, the record's name and the stopwatch's first sweep |
| 3 s | the grown 68 × 48 puddle, translucent over the carpet. Jo's legs stand in front of his; Anne's boots cover hers except their lowest pixels. In the office the desk's base cuts off its top |
| 7.5 s | `500` or `800` rising, `...`, the lamp dark, the player idling in the same view, the puddle unchanged |
| 11 s | 73 × 52 at alpha 155 |
| 15 s | 95 × 67, faded to alpha 68 |
| 17.5 s | the floor bare again |

The last three were reached by moving `effect_clock` back, since the age is
`now − effect_clock`.

A probe with every clip frozen spread a puddle to 1.5 behind Jo at the boss's desk:

- the character test hid 1137 pixels of it inside Jo's frame;
- the world test hid 1769 pixels behind the desk's base and a partition wall;
- every one of the 5762 opaque texels matched mode 22, computed from the frame and a
  screenshot without the puddle, to within 1, and 948 exactly.

### The pill

States 40 to 43 run as the table above has them, one per tick, in `AbilityController._pill()`.

- **The record.** Record 73 gives the name, which is `...`, the 20 tenths as a total of 200 and
  the score of 10, all from `resources/original/actions.json`. State 43's slow-down total is
  record 73's `effect_duration_tenths`, 400, times 10.0 and stored as a float32, never a
  literal. The 10.0 of states 40 and 43 and the 100.0 of state 42 and of the slow-down's test
  are not the pill's own: `flt_4652F4` and `flt_465304` are shared by modes 1 (a prank,
  `sub_41B240`), 2, 3 and 5, the player tick and the stopwatch feed, and come from
  `ability_timers.json` (see "The controller").
- **The player** is held as for the other two, with the clock up through 42 and nobody moving,
  but `hold_for_ability(false)` leaves the clip and the footstep alone. A player walking when
  the lamp is pressed goes on playing `WALK` where they stand, clock-driven as ever, and the
  footstep loop goes on sounding: `Player.footsteps_held` keeps the locked physics tick from
  stopping it. State 43 idles the player and frees them; the first free physics tick with no
  direction held stops the footstep, as `0x41B189` does, and a right button still held walks
  on.
- **The spend and the stopwatch.** 43 spends item 14 through `PrankController.spend_item()`, so
  the Matrix lamp goes dark on the same `inventory_changed`. The stopwatch reads 0 on the ticks
  of 40 and 41, sweeps 2.0 s in 42 and reads 0 from the tick that zeroes the timers.
- **Never caught.** No pill state is in `CATCH_STATES`.
- **The agents.** `AbilityController.set_agents_slowed()` is `sub_41CD10`: it sets `slowed` on
  every member of `npc_agents` under the player's `World`, which is the boss, the secretary,
  the janitor and every coworker. The player is not in that group and has no such flag.
- **The timer.** `_advance_slowdown()` runs after the mode's state on every tick
  (`0x41D401`–`0x41D458`). It sums `+996` as a float32, shows the overlay by `+1044`, and past
  `+996 * 100 > +1004` zeroes both and calls `set_agents_slowed(false)`. The overlay is still up on that tick and gone on the next.
  It counts from 43's own tick, on the level clock, so it stands still with the paused tree and
  resumes where it stood. A second pill runs 40 to 43 again and restarts the forty seconds;
  a level start builds a new player and new agents, so nothing carries over.
- **State 44** is left out, as nothing writes it.

A run on level 13 with item 14 granted, the player walking on the right button and the Matrix
lamp pressed with a real left click, at 800 × 600 and at 1067 × 600, showed this:

| Time | What the screenshot shows |
| --- | --- |
| 1 s after the press | the player in a `WALK` frame where the press caught him, `...` in the hover bar, the stopwatch half swept, the Matrix lamp still lit, no overlay; the log has the footstep loop on and the player 0 px from where he was |
| 3 s | the overlay, green top left and red top right over the floor, walls and items; the player and every character over it untinted; the agents green; `10` rising; the lamp dark |
| 20 s | the same, the agents crawling |
| 39.9 s after state 43 | still green and still overlaid, the janitor and the boss walking in at a crawl |
| 41 s after state 43 | the office in its own colours, the agents at their own pace |

State 43 came 2.03 s after the press, and all ten of level 13's agents were slowed from it.

### The slowed office in the port

`scenes/npc/npc.gd` carries `slowed`, `agent+1792`. Its setter hands the clip speed to the
agent's `AnimationController` and shows or hides the copies. The two numbers are the
immediates the four ticks load, the float32 0.2 and 1.0, which `tools/export_slowdown_params.py`
reads out of `sacked.exe` into `resources/original/slowdown.json`; `scenes/npc/slowdown.gd`
loads that file once for the agents, the copies and the overlay.

- **The walk step.** `walk_multiplier()` is `+76`. Both walk steps, the navigation one and the
  older patrol one, multiply `get_move_speed_tiles()` by it. That speed is the current one, the
  base plus 0.15 times the band for everyone but the boss, so a slowed agent walks at a fifth of
  its banded pace. `get_move_speed_tiles()` itself is untouched, and so is everything that reads
  it.
- **The clips.** `AnimationController.speed_scale` is the clip speed `+536`, 1 for the player
  and for any agent not slowed. A clock-driven clip, the idle and the walk, shows the frame of
  `floor(((clock * speed) mod length) * fps)`, so every slowed walker keeps step with every other
  and the change of speed jumps the frame. A clip the `AnimationPlayer` runs is given the speed
  as the player's `speed_scale`, and on a change of speed it is put where
  `CObjectAnim_SelectFrameFromTime` would have it: `(elapsed * speed) mod length` for a looping
  clip, `elapsed * speed` for a one-shot. `elapsed` is the clip's own unscaled time, which stands
  still with the tree as the `AnimationPlayer` does. So `IDLE#2` lasts five times longer and the
  coworker's tick waits for it, and a release that puts it past its end finishes it at once,
  with the `animation_finished` a clip that runs out raises: the `AnimationPlayer` stops on a
  seek to the end without it. A one-shot that has already finished keeps its last frame.
- **What is left alone.** The needs and goal timers, the arrival, the notice test, the field of
  view, the catch and the band read neither the flag nor the speed.
- **One frame the port does not keep.** The original's clips are shared registry objects that
  take the speed from whichever agent's tick last ran, and a clip switched to in the middle of a
  tick keeps the old speed for that frame. The port gives each agent its own speed for every
  clip it plays, so both one-frame differences are gone.

### The green copies in the port

`scenes/npc/slowed_copies.gd` is a `Node2D` in `scenes/npc/npc.tscn` after `NameLabel`, at z 3.
It is shown while the agent is slowed and runs only then, paused or not. Every frame it:

- takes the agent's current frame and the spot `CharacterDepthCompositor` draws it at, the
  rounded top left of the sprite;
- draws three offsets from `random`, a stand-in for `rand()` that answers 0 to 32767, in the
  original's order: `y = r % 4 − 2` first and then `x = r % 6 − 3`, for each copy in turn. A
  check can hand in its own;
- draws the frame three times at those offsets through `scenes/npc/slowed_copies.gdshader`.

The numbers, three copies, the tint, the brightness, the weight and its complement, the cap,
the 2 depth units and the two jitters, come from `slowdown.json`, read from `sub_417460` and
`0x43B050`.

- **The blend.** The shader is mode 54 in premultiplied form:
  `c = min(255, (src * tint >> 8) + 60)` with tint (40, 255, 40), written as `(c * 120) >> 8`
  with an alpha of `121 / 256`, so the back buffer keeps `135 / 256` of itself. The destination
  half is not truncated, so a pixel can come out one above the blitter's. It is a plain blend,
  like the blitter, the same mode-54 form `scenes/shared/object_highlight.gdshader` now uses.
- **Depth.** Each pixel's score is the agent's base `ceil(int(y) / 2)` plus 2, less the frame's
  own Z-plane value, and it is tested with the effects' helper, `scenes/effects/effect_depth.gd`,
  against the world composite and the depth planes of the six nearest overlapping actors. The
  agent's own frame is among them, so a copy shows over its agent wherever the agent's plane is
  within 2 of the copy's, which is nearly everywhere. Nothing is written. `EffectDepth` gained a
  `world` to name `World` from under an agent.
- **Under a paused tree.** `Main_RenderUpdate` goes on drawing under the pause panel, behind
  the quit prompt and on the caught banner, where only the world tick stops, and `sub_417460`
  rolls `rand()` for every copy it draws. So the node runs with `PROCESS_MODE_ALWAYS`: the port
  pauses its tree on all three, and the copies go on jittering over the agent's frozen frame.
  It reads the frame and the depth inputs and changes nothing else. The field of view's tint,
  by contrast, stands still there (see "The frozen office" in
  [field-of-view-reference.md](field-of-view-reference.md)).
- **Inside a cluster.** `CharacterDepthCompositor` hides the sprites of overlapping characters
  and draws their composite instead. The copies read the hidden sprite's frame, which stays
  current, and test each character's own plane, so a cluster changes nothing.
- **The draw order.** z 3 puts the copies after the agent's sprite (z 1), its shadow (z 0),
  its bubble (z 2) and, by tree order, its name, and before the effects, the rising scores, the
  walk arrow and the HUD.
- **Two differences from the list's order.** The original draws each agent's copies before the
  next agent's sprite. Here every character is drawn before any copies, and each copy tests the
  other characters' planes wherever they are in the list. So a character drawn later and
  further back, which in the original paints over a copy where the copy's own agent does not
  cover it, is under the copy here, over a margin of up to 3 pixels. And the bubbles are not in
  the test, as for the smoke.

A frozen pair of frames with one agent's copies off and on changed 1532 pixels at 800 × 600 and
2365 at 1067 × 600, none of them more than 4 pixels outside the agent's frame, and most of them
greener than before. The seated coworker's chair back hid them where it stands in front. Since
the copies roll on under a paused tree, a later pair held every agent's rolls fixed: 1549 and
2725 pixels, again none outside. The pause key, pressed as a real key 1 s into the slow-down,
stopped the forty seconds where they stood and left one agent's copies with 30 different sets
of offsets over 30 paused frames, at both sizes.

### The overlay in the port

`scenes/player/slowdown_overlay.gd` and its shader are `sub_41D500`'s gradient.
`AbilityController` builds it the first time `+1044` is up, as the player's first child, an
internal one, and shows it for exactly the ticks `slowdown_shown` is set.

- **Where it draws.** It sits at z 1, the z `CharacterDepthCompositor` gives every sprite it
  draws, and those draw in tree order: the looping items under `World/Objects`, then the
  player, then the agents, then the clusters. As the player's first child the overlay comes
  after every item and before every character, as it is painted at the player's place in the
  character list. Everything at a lower z is under it: the floor (−20), the field-of-view tint
  (−10), the walls (−5), the glass (−4), the world composite and the shadows (0). The effects
  (3), the rising scores, the walk arrow and the HUD are over it.
- **A looping item in a cluster stays under it.** A looping item whose frame overlaps a
  character's is composed with it on the CPU, and its own sprite is hidden. The composite used
  to be one surface drawn after every character, so while the player stood at an item they had
  just broken, or an agent walked past a looping copier, the item's pixels came out over the
  overlay in their own colours. The compositor now composes each cluster's item pixels onto a
  surface of their own, an internal child at the back of `World/Objects` at z 1: after the
  items and before the overlay, where the original draws them in its item pass. The cluster's
  own surface keeps the characters' pixels. A pixel is on whichever surface the actor that wins
  it belongs to, never on both, so without the overlay the pair shows the same picture as the
  one surface did.
- **The shadows are under it** in the port. The original draws each shadow with its character,
  after the overlay; the port draws every shadow at z 0 beneath the world composite, so the
  walls cover them. The difference is the shadows' own ellipses, which here darken the tinted
  floor's scene half rather than the tinted floor.
- **The item highlight** of a looping item is drawn at z 2 and so over the overlay; a still
  item's is at z 1 before the player, and under it, as the original draws both in the item pass.
- **The gradient** is `sub_4584D0`'s arithmetic, per pixel in the shader: each row steps
  `4096 / height` and each column `4096 / width`, both truncated, each accumulated product
  shifted down 12 as an arithmetic shift, and the result halved and added to the halved scene.
  In premultiplied form that is `floor(g / 2)` with an alpha of one half; the scene's half is
  not truncated, so a pixel can come out one above the original's. The corners are bytes 0, 1
  and 2 of the four dwords, read as R, G and B: green (0, 160, 0) top left, red (160, 0, 0) top
  right, blue (0, 0, 160) bottom left, cyan (0, 160, 160) bottom right. That byte order is the
  one [field-of-view-reference.md](field-of-view-reference.md) recovered; no screenshot of the
  original's overlay confirms it.
- **Where the gradient lies.** The shader works from the pixel on screen, `SCREEN_UV` times the
  canvas, so the camera does not move it; the node draws one quad far past any level. The clip
  is `Main_RenderUpdate`'s `(1, 1, w − 1, h − 91)`, taken with the port's canvas: columns 1 to
  w − 1 and rows 1 to h − 91, so 799 × 509 at 800 × 600 and 1066 × 509 at 1067 × 600.
- **A wider canvas is spread over the original's clip**, a port choice. The steps come from the
  original's own 799 × 509, as `4096 / 799` and `4096 / 509` truncated, and each column of a
  wider clip is first put on one of the original's 799 in integers, `column × 798 / (w − 2)`,
  as each row of a taller one is on its 509 by `row × 508 / (h − 92)`. At 800 × 600 that maps
  every column and row onto itself, so the arithmetic is the original's to the pixel; on any
  other canvas the corner colours still sit at the corners of the world area, which is what the
  steps are for. Running the steps at the port's width instead would truncate
  `4096 / 1066` to 3 and leave the right-hand edge at 3195 / 4096 of the way to its corners at
  1067 wide, and at about half the way on a 32:9 canvas: a pale right-hand side the original
  never showed. See [widescreen.md](widescreen.md).
- **Past the clip.** The port's world has no one-pixel border and, beside the console band on a
  wider canvas, runs on below h − 91 (see "The world is not clipped" in
  [widescreen.md](widescreen.md)). There the gradient's nearest column or row goes on, so the
  floor the console leaves uncovered is tinted like the floor above it, as the field of view's
  tint does. At 800 × 600 the console covers everything below the clip.

The runs above checked the overlay pixel by pixel on a frozen frame, off and on. At 800 × 600,
267 255 pixels came out `(dst >> 1) + (g >> 1)` exactly and 97 820 within 1; 108 860, the
characters and the HUD drawn over it, were untouched; and the other 6065 were translucent things
drawn over it, the bubbles, the copies' edges and the FPS label. The top-left pixel went from
(78, 79, 71) to (39, 120, 36) and the top-right from (178, 174, 173) to (166, 89, 87), so
`SCREEN_UV` runs down the screen as the gradient does. A copier put into its looping
`DESTROYED_1`, and so drawn at z 1, came out tinted in all 1365 of its sampled pixels.

After the two fixes above, the same check on every third pixel each way, with the copies' rolls
held fixed for the pair, gave 29 972 exact, 10 731 within 1, 12 030 untouched and 667 other at
800 × 600, and 42 277, 14 914, 12 760 and 1249 at 1067 × 600, the strips beside the console below
row 509 among the matches. The last column at 1067 wide is now the same `(155, 4, 0)` of the
gradient as the last column at 800. The radio put into its looping state and the player's frame
over it were one cluster, the radio's pixels on the item surface under `World/Objects`: its
opaque pixels outside the player's frame came out averaged, 234 exact and 89 within 1 at
800 × 600, 193 and 53 at 1067 × 600, and none untouched, as with the player standing clear of
it. Before the fix a cluster left an aquarium's pixels in their own colours, 2483 of 2566 of
them at 800 × 600.

### The catch

`CatchWatch` also catches states 11 and 12, and 21 and 22, through
`AbilityController.is_catchable()`, with the notice test it uses for pranks. It then writes the
abort state through `AbilityController.catch()`. The pill is never caught.

- **The abort runs at once.** Screen 4 ticks the world at a zero step under the banner
  (`0x40287B`, `0x411AD1`), and the port pauses the tree there instead. So `catch()` runs the
  controller once at a zero step itself, the original's first banner frame:
  - state 24 idles, frees the player and stops `S0174` in the frame of the catch;
  - state 14 frees the player at once if `SMOKE` has already run out, and otherwise waits for
    it on the frozen clock.
- **The order.** The watch runs after the player in the frame. So smoking can be caught from
  its first tick, and urinating's state 21 only on the tick that set it, before the puddle
  exists.
- **Nothing is paid or spent.** The lamp stays lit, and a smoke or puddle already spawned
  stays and ages on the clock the banner freezes.
- **The hover bar's `...`** comes back on `PrankController`'s first free tick, after the duel.
  The original writes it on the banner's second frame, since the paused tree stops
  `PrankController` as well.

### The room grid

`tools/build_level_scene.gd` emits each manifest's `collision_grid.room_ids`, flat and
indexed `x + width * z`, into the level's `CollisionTileMapLayer` as `room_ids`, with
`room_grid_size` beside them. `CollisionMapLayer.room_category(tile)` answers
`sub_412AE0(int(x + 0.5), int(z + 0.5), 4)`. `int()` truncates toward zero as `ftol` does, so
x = −0.9 still reads column 0, and a cell off the grid answers 0.

### The inventory

`PrankController.inventory` has 31 slots, as `sub_41AF60` clears. It used to have 28, which
dropped every grant of items 28–30 (actions 54, 137, 9 and 39) and let actions 115, 135 and
136 through without items 28 and 29.

### Checks

- `tests/check_player_abilities.gd`, on level 13:
  - the four records by room, and state 13 at 12.0 s with the stopwatch already empty;
  - state 13 paying the room it finds then;
  - the pay, the spend and the lamp;
  - the spawn strictly after 0.4 s, the stop past 4.5 s and the removal;
  - the clip and its extra tick;
  - the console's feed;
  - a left click on the lit smoking lamp going through the real console to this controller,
    which starts smoking on its next tick;
  - the dropped requests and their order;
  - the held player, the keyboard walk that goes nowhere, and the right release that
    re-centres;
  - the walk arrow drawn over the smoke;
  - the catch, and a smoke caught after its clip freeing the player at once;
  - items 28 and 29;
  - urinating's two records, state 23 at 7.0 s, the stopwatch, the spend and the lamp, and
    state 23 paying the room it finds then;
  - the facing for both characters, the pick's order, and both `PISS` clips in every view
    it picks;
  - the puddle ahead along the view for both characters;
  - `S0174` once and held, stopped by 23 and 24 even after it has ended, and playing on
    through a pause;
  - one puddle at a time, its spread at 12 and 16.9 s, and its removal after 17 s but not
    at 17;
  - the catch in 21 and 22, and never in 20 or 23;
  - smoking restarting the puddle's window;
  - the float32 timers at 60 fps: the stored step, 7.0 s on the 420th step, and the smoke's
    spawn and 12.0 s on the 24th and the 721st;
  - the depth test the puddle's shader is handed on the tick that builds it and a frame later,
    and the smoke's once it has particles: the world composite, and the player among the actors
    with his frame, depth plane and base;
  - the teardown stopping `S0174` and freeing the puddle;
  - the pill: 40 to 42 with `...`, a total of 200, the stopwatch at 0 for two ticks, 42 ending
    on the 32nd sixteenth of a second, `WALK` and the footstep going on while the player stands,
    no state caught; 43 paying 10, idling, freeing, spending item 14 and slowing every agent
    and never the player, with `+1004` at 4000 and `+996` counting from its own tick;
  - the slow-down still up at exactly 40.0 s and released on the tick past it, the overlay one
    tick longer, the pause stopping it, and a second pill restarting the full 40 s; each of
    these and the two overlay checks takes its own pill, so none depends on the order;
  - the overlay as the player's first child at z 1, after the items and before every
    character, its clip at 800 × 600, 1067 × 600 and 800 × 640, and its steps from the
    original's 799 × 509;
  - a looping item a character overlaps: its pixels on a surface at the back of
    `World/Objects` at z 1, before the overlay, the character's on the cluster's surface after
    it, and no pixel on both;
  - smoking's state 10 and urinating's state 20 stopping a sounding footstep, and the locked
    tick not starting it again.
- `tests/check_slowed_agents.gd`, on level 2, which has all four archetypes:
  - the pill slowing all six agents and not the player;
  - one physics step of a coworker, the secretary and the janitor at band 2, and of the boss,
    slowed and not: a fifth of the current speed, the boss's without the band;
  - the clock-driven walk's frame at `clock * 0.2`, and the jump;
  - `IDLE#2` lasting five lengths, and finishing at once when a release puts it past its end;
  - a looping action clip jumping to `elapsed * 0.2` and back;
  - the copies: the order of the rolls, the jitter's ranges, the spot, the base plus 2, the
    blend's numbers, the world composite and the agent's own plane in the test, and the z;
  - the copies rolling fresh offsets on every frame of a paused tree;
  - the copies of an agent drawn in a cluster;
  - the release at 40 s, and a new level starting with nothing slowed and no overlay.
- `tests/check_character_depth_compositor.gd`: a looping item's pixels composed onto their own
  layer and a character's onto the cluster's, the shared pixel on the winner's layer whichever
  was composed first.
- `tools/export_slowdown_params.py --check`: the 0.2 and 1.0 of the four ticks, the copies' and
  the overlay's numbers, the clip and the instructions around them against `sacked.exe`.
- `tools/export_ability_timers.py --check`: the shared 10.0, 100.0, 0.4 and 4.5, and every
  reader of them in the prank's states, the three modes, the player tick (the puddle's and the
  foam's gates and the blackout's rate among them) and the stopwatch feed.
- `tests/test_original_exe.py`: `pin_readers()`, which the six exporters that pin a
  constant's readers share, refusing the right address behind the wrong opcode and the right
  opcode reading another address.
- `tools/export_view_angles.py --check`: the view's 45.0, 180.0 and 0.017453, and every reader
  of them in the smoke's spawn, the puddle's and the field-of-view cone.
- `tests/check_player_interaction.gd`: a prank's 70 tenths ending on the 420th step at 60 fps.
  It and the three other checks that run a prank to its end (`check_prank_consequences.gd`,
  `check_sound_table.gd`, `check_looping_object_focus.gd`) step it at 60 fps until it ends:
  one step of `total_seconds()` reaches a float32 total only for a whole number of seconds
  (13 tenths gives a sum of 1.2999999523, whose hundredths fall short of 130).
- `tools/export_action_table.py --check` and `tests/test_original_action_data.py`: record 73's
  `effect_duration_tenths` of 400, the only one, and the one instruction that reads it.
- `tests/check_smoke_effect.gd`: the exported parameters, the Strings frames' shared pivot
  (32, 32) as `strings.json` gives it, and the particle mechanics and the instance buffer
  against a fixed random source.
- `tools/export_smoke_params.py --check`: the parameters against `sacked.exe`.
- `tests/check_puddle.gd`: the exported parameters, the ten-second gate taken from the player's
  clock rather than `puddle.json`, the six landing spots, the clip played
  once per puddle, the depth base and the quad, the spread and fade to 17 s, what the
  shader is handed, and `tick()` setting up the depth test with no frame run, the actors
  nearest first; on a later frame, `tick()` leaving the test alone and the puddle's own
  `_process`, after a stand-in controller's tick, testing the actor only the spread quad
  reaches. `tests/check_player_abilities.gd` pins that the puddle comes after the player in
  `World`.
- `tools/export_puddle_params.py --check`: the puddle's constants against `sacked.exe`.
- `tests/check_console_lamps.gd`: the lamps' input rules.
- `tests/check_level_maps.gd`: every level scene's room grid against its manifest.
