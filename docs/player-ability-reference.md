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
- **Agents.** The character loop does the same (`0x402A3D`, `0x402A7A`) with weight 200.
- **The effects list** does the same (`0x402BAF`).

So the highlight is a blend at a fixed weight, 180/256 for items and 200/256 for agents, with a
pulsing brightness lift. It is not additive.
[player-action-reference.md](player-action-reference.md) and
[names-reference.md](names-reference.md) now describe it this way.
`scenes/shared/object_highlight.gdshader` (`blend_add`, with alpha `120/255 + 80/255 sin`)
still follows the old additive reading, so the green copies should not copy that shader.

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
