# Being noticed, being caught, and the minigame hand-off

Verified on 2026-09-21 against a disposable copy of `sacked.exe.i64`. The original executable
and database were not modified. Addresses are virtual addresses in the shipped `sacked.exe`
(479232 bytes, SHA-256 `6404096c…`).

This answers what the earlier references left open: `hud-reference.md`'s "`AGGRO_UP` … fires
from a different game mode, which is not recovered", `npc-reference.md`'s unrecovered
secretary reaction slot and its note that goal 9 `REPAIR` "the brain cannot pick yet", and
`game-rules-reference.md`'s one-line entry for screen 5.

## The check

`sub_402470` is the whole trigger. `sub_402590` — the in-level update, which returns early
while the pause bit `game+12740 & 0x20` is set — calls it once a frame, after every entity
has been updated and after `sub_4019D0` resolves movement.

It runs only while `game+19044 == 1`, the playing screen, and only when the player's state
`player+904` is in:

```text
{2, 3}  ∪  {11, 12}  ∪  {21, 22}
```

Those are states 2–3 of mode 1 and the same two states of modes 2 and 3 — **the stretch
during which an action is actually being performed**. So the player is only ever caught
mid-prank: walking past a coworker, standing still, or having the ring menu open is safe,
and so is the first state of an action, the turn-to-face.

It then walks the world's entity list (`game+1928` to `game+1932`) and stops at the **first**
entry that satisfies all three of:

| Test | Meaning |
| --- | --- |
| `entity+112 == 2` | the entity is an agent (the player is 1) |
| `sub_418310(agent, player) == 1` | the agent can see the player — below |
| `agent+1824 == 0` | the agent is not shut inside a toilet cubicle |

There is no chase, no warning state and no accumulation: the frame the test passes, the
player is caught. Insertion order decides who catches you when two agents could.

## `sub_418310` — the notice rule

A two-argument `__thiscall`: `this` is the agent, and the player is pushed as the argument
(`0x4024d8`–`0x4024e1`).

```c
dx = player.x - agent.x;
dz = player.z - agent.z;
if (fabs(dx) > 8.0) return 0;                 // cheap box reject
if (fabs(dz) > 8.0) return 0;
dist = sqrt(dz*dz + dx*dx);
if (dist > agent+1068) return 0;              // the notice radius

angle = fabs(agent+1848 - (180.0 - atan2(dx, dz) * 57.29579));
if (angle > 180.0) angle = 360.0 - angle;     // shortest way round

return (agent+1072 * 0.5 >= angle || dist <= 2.0)
    && sub_412E30(agent, player) != 0;        // the same sight ray the player uses
```

Three things are worth stating plainly.

**The cone is bypassed within 2.0 tiles.** `dist <= 2.0` is an `||`, so an agent notices a
prank two tiles away whatever it is facing. That is exactly the hint `Levels/Level_00.txt`
gives the player — *"Czy wiesz, że Twoi koledzy zawsze Cię zauważą, jeśli siejesz zniszczenie
blisko nich? Nawet jeśli są odwróceni plecami."* — so the hint is literal, and the port does
not need a vision cone alone.

**The sight ray is the one the port already has.** `sub_412E30` in quarter-cell units
(`(v + 0.5) * 4`), the same call and the same conversion `prank_controller.gd` uses to decide
whether the player may act on an object, described in `collision-reference.md:64`. A wall
between the two hides the player even at one tile.

**The facing is a heading that follows the eight-way sprite index, not the index itself.**
`agent+1848` is a float in degrees. Every frame `sub_402260` calls `sub_4179B0` for every
agent, which aims it at the sprite's view, `45 * agent+124`, plus a sway of
`10 * sin(agent+1844 + agent+72)`, and moves it 1/8 of the short way there (`sub_45E270`,
`0x417A4C`), wrapped into `[0, 360)`. It never feeds back into the index: `sub_41A400` sets
`agent+124` from a walking or facing direction with `floor((angle + 22.5) / 45) & 7`, and the
look-around steps it. So the cone sways ten degrees either side of the view the sprite shows,
and an agent that has just turned still sees roughly where it was looking. The details, and the
60 Hz the port runs them at, are in [npc-reference.md](npc-reference.md).

## Where the radius and the cone come from

They are columns 1 and 2 of the same seven-record profile table at **`0x46E7D8`** that
carries the speeds and the decay rates. `sub_4184B0` (`0x418519`–`0x418546`) loads each of
the first three floats **twice**, once into the live field and once into a saved base:

| Table column | Live field | Saved base |
| --- | --- | --- |
| 0 — speed, tiles/s | `agent+56` | `agent+1852` |
| 1 — notice radius, tiles | `agent+1068` | `agent+1856` |
| 2 — notice cone, degrees | `agent+1072` | `agent+1860` |

Columns 3–10 are the eight goal decay rates already in `npc-reference.md`. The record is
eleven floats, so the stride is 44 bytes.

| Character | Spawn id | Radius | Cone | (speed) |
| --- | --- | --- | --- | --- |
| Boss | 1 | 5.8 | 75° | 1.8 |
| Secretary | 2 | 5.0 | 60° | 1.8 |
| Janitor | 3 | 5.0 | 70° | 1.2 |
| Male employee 1 | 4 | 5.2 | 60° | 1.5 |
| Male employee 2 | 5 | 5.1 | 55° | 1.6 |
| Female employee 1 | 6 | 5.0 | 60° | 1.7 |
| Female employee 2 | 7 | 5.3 | 55° | 1.5 |

The cone is halved on each side of the facing, so the boss sweeps ±37.5° and the two
second-variant employees ±27.5°. `sub_415D50` initialises every agent to radius **5.0** and
cone **60.0** before the profile overwrites them, which is what an agent with no profile
would use.

## The aggression band widens all three

The three per-tick functions that apply the band — `sub_419CE0` (coworkers), `sub_41E360`
(secretary) and `sub_41A8D0` (janitor) — end with the same three lines, reading the band at
`agent+1064` that `sub_402350` writes:

```c
agent+56   = band * 0.15 + agent+1852;   // speed,   +0.45 tiles/s at band 3
agent+1068 = band * 0.2  + agent+1856;   // radius,  +0.6 tiles at band 3
agent+1072 = band * 5.0  + agent+1860;   // cone,    +15° at band 3
```

So a soured office does not merely walk faster — it **sees further and wider**, which is the
mechanical link between the thermometer and the risk of being caught. `npc-reference.md`
previously recorded only the speed third of this.

`sub_419740`, the boss, has no such tail at all: it applies neither the speed formula nor the
two widenings, so the boss keeps 5.8 tiles and 75° for the whole level.

## `agent+1824` — who cannot catch you

Only `sub_416090`, the toilet-cubicle behaviour, ever raises it. An agent that has walked
into a cubicle sets it to 1 while its timer runs (`0x4161c1`) and clears it when it steps
back out (`0x41612f`); `sub_415D50` starts it at 0 and `sub_416770` clears it. An agent
locked in by actions 110 or 112 — the cubicle's `item+224` — never reaches the clearing
branch, so **locking a colleague in a cubicle also blinds them until a repair lets them
out** (goal 9 below).

## The hand-off

On a hit `sub_402470` does four things, in order:

1. `game+14688` = the catching agent. This is the only place it is written, and screen 5
   reads it back.
2. The player's state is pushed to that mode's abort state: `<= 3` → 5, `11..12` → 14,
   `>= 21` → 24. The action is cancelled rather than completed, so a prank interrupted by
   being caught pays nothing.
3. `sub_407370(game, 4)` — the **caught pause**. Case 4 is the one case that only sets
   `game+19044` and returns: nothing new is built, the level keeps drawing, and `WinMain`
   gives it a zero time step so everything holds still (see
   [shell-reference.md](shell-reference.md)). Earlier notes called it the loading screen;
   the original has none.
4. `sub_407990`.

`sub_407990` shows `game+14752` — the `CO_GUI_CONSOLE_AGGRO_UP` overlay that `sub_405930`
builds hidden at (5, 5) with alpha 220 (`0x405ed5`–`0x405f1d`), the same shape as
`THERMO_UP` — and then displays one of four Polish exclamations picked with `rand() & 3`
from `off_46BFD0`:

| 0 | `Mamy cię!` |
| 1 | `A kto to?!` |
| 2 | `Co się dzieje?` |
| 3 | `Co za bezczelność!` |

**So `AGGRO_UP` is the "you have been spotted" banner.** It is not tied to another game mode;
`hud-reference.md`'s open question is closed by this path.

Both `sub_403780` (`0x403ba0`) and `Main_RenderUpdate` (`0x4035f6`) then watch `game+72`
while the screen is 4. At **2.0 seconds** (`flt_4652C4`) the tick hides `AGGRO_UP` again and
the render update calls `sub_407370(game, 5)`. The banner is therefore up for exactly the
length of that pause, and the minigame follows it.

## Screen 5 and its result

`sub_407370`'s case 5 (`0x40752b`–`0x4075a4`) builds the minigame with

```c
n4 = (catcher && catcher+1740 == 1) ? 7 : 4;      // 1 is the boss
sub_406430(n4, game+19052 + 2, 8, 8, sub_407840(catcher));
```

`game-rules-reference.md:88` read the 7/4 as the opponent portrait. It is not: the portrait
is the fifth argument, a sprite **name**, and 7/4 is a separate difficulty-shaped argument
whose meaning `sub_406430` settles. That is left to the task that builds the minigame.

`sub_407840` maps the catcher to its portrait sprite, from the type at `agent+1740`, the
gender at `agent+1744` and the variant at `agent+1748`:

| Catcher | Sprite |
| --- | --- |
| Boss (type 1, and the fallback for a null or unknown catcher) | `CO_GUI_MINIGAME_ENEMY_BOSS` |
| Secretary (type 2) | `CO_GUI_MINIGAME_ENEMY_CS` |
| Janitor (type 3) | `CO_GUI_MINIGAME_ENEMY_HM` |
| Female employee 1 (type 4, gender 1, variant 0) | `CO_GUI_MINIGAME_ENEMY_WORKER1` |
| Female employee 2 (type 4, gender 1, variant 1) | `CO_GUI_MINIGAME_ENEMY_WORKER2` |
| Male employee 1 (type 4, gender 0, variant 0) | `CO_GUI_MINIGAME_ENEMY_WORKER3` |
| Male employee 2 (type 4, gender 0, variant 1) | `CO_GUI_MINIGAME_ENEMY_WORKER4` |

`ENEMY_ANNE` and `ENEMY_JOBLESS` are the player's own side of the duel, not catchers.

`sub_402860` → `sub_4027B0` polls the running minigame through `sub_415010`:

| Result | Meaning | Then |
| --- | --- | --- |
| 1 | still playing | nothing |
| 2 | the player lost | destroy it, `sub_407370(game, 8)` — **the lose screen** |
| 3 | the player won | destroy it, `sub_407370(game, 1)` — **back into the level** |

Case 1 refuses to reload the level when the previous screen was 10, 5, 4 or 9, so returning
from the minigame resumes the level already in memory rather than restarting it. Nothing on
this path touches the score or the aggression meter: winning the duel costs only the
interrupted action and the time, and losing it ends the level outright.

## Goal 9, `REPAIR`

`sub_4164E0` is the whole of it, and it is the mirror of `sub_416450`'s reaction:

```c
if (!agent+1816) return 0;            // no repair job filed
if (agent+1124 > 0.0)                 // the ordinary busy timer
    agent+1080 = 9;                   // the REPAIR goal (0x416535) -- never reached
else {
    job = agent+1832;
    agent+1816 = 0;
    if (job) sub_4100B0(job);         // <- the item is reset
    agent+1832 = 0;
}
```

The first branch is dead code. Both writes of `+1816` (`0x417BEA`, `0x417C2B`) fall through
to `0x417C86`, which raises the reaction flag `+1820`, so a filed job always comes with a
reaction. `sub_416770` asks `sub_416450` first (`0x4168C8`) and stops there while it
reports busy, which it does, holding goal 8, for as long as the timer runs. At expiry it
clears `+1820` and returns 0, and only then does `sub_4164E0` run (`0x4168D4`), with the
timer already spent. **So the `REPAIR` bubble never shows.** A filed repair looks exactly
like any other reaction, `ANGRY` bubble included, and the item is reset when it ends.

`sub_4100B0` is the item's own action reset — the same call `npc_activity_point.gd` already
makes from `_ready`. Decoded in full it does four things, in order:

1. For each of the eight slots, set `item+252+i` to 1 where `item+244+i` carries an action id
   and 0 where it does not — **every action the player used up comes back**.
2. Walk each enabled slot's four `unlocks` entries in the action records and disable any slot
   whose action one of them names, so an action that is gated behind another starts locked
   again.
3. Clear `item+224` and `item+228`, the cubicle lock and the tampered flag.
4. Call `sub_40FDA0(0)`, which clamps a state to 0..15 and writes `item+124` — the object
   goes back to state 0.

Step 3 settles a question the earlier notes disagreed about. `npc-reference.md` said only
`sub_40FEF0` ever clears `item+228`; that is wrong, this clears it too. It also means **a
completed repair releases a colleague locked in a cubicle**, which is what the cubicle route
below depends on. `sub_40FEF0`, the separate full item reset, clears `item+200`, `+216`,
`+220`, `+224`, `+228` and `+232` and then randomises `item+236`.

The job is filed by `sub_417B00`, as `npc-reference.md` describes: through `sub_4180F0` for
a janitor (`+1740 == 3`), and through `sub_4181F0` for anyone else, which takes only a
type-173 cubicle with `item+224` set (`0x418203`). The janitor's list below holds both types,
but he never walks to a cubicle. His toilet rate in `0x46E7D8` is 0, `sub_415D50` starts his
needs at 20–100 and reactions reset them to 60–100, `sub_4165D0` only queues a need below 15,
and his failing work goal starves goals 4–7 anyway. So a colleague locked in a type-262
cubicle is never let out before the level is reloaded; that is inferred from these rules,
not observed. A type-173 inmate is freed by whichever coworker, secretary or boss walks up to
it next.

`sub_4180F0` is not a plain switch: the compiler built it as a jump table. The item type from
`sub_40FE90` is biased by −102, bounds-checked against 167, used to index a 168-byte selector
table at `0x41813C`, and that byte picks one of two branches — store the item in `agent+1832`
and return 1, or return 0. `tools/export_repairable_types.py` decodes those instructions and
reads the selector table rather than transcribing the result, which is:

```text
102 110 126 127 129 135 136 137 141 143 144 152 153 154 155
173 177 190 191 192 197 237 240 248 250 255 262 267 268 269
```

Those include the four workstation types 152–155 and both toilet cubicles, 173 and 262.

Note that none of the four per-tick functions has a branch for the repair job, so an agent
filing one keeps whatever clip its other flags choose — the janitor's `STAND#USE` (slot 3)
is never selected by `sub_41A8D0`. Whether anything else raises it is left to the task that
implements the goal.

## The archetype animation tables

Read from the binary at the addresses below; `sub_41A510(agent, slot)` resolves a slot
against the eight-way index, falling back to view `000` and then to the idle slot.

| Table | Archetype | Slots |
| --- | --- | --- |
| `0x46EAE0` | Boss (`sub_419740`) | 0 `STAND#IDLE`, 1 `STAND#EXPLODE`, 2 `WALK`, 3 `SIT#IDLE` |
| `0x46EB44` | Coworkers (`sub_419CE0`) | 0 `IDLE#1#ATMEN`, 1 `IDLE#2`, 2 `WALK`, 3 `SIT#IDLE`, 4 `SIT#USE`, 5 `SPECIAL#1`, 6 `SPECIAL#2`, 7 `PISSED`, 8 `SIT#EASY` |
| `0x46EBD8` | **Janitor** (`sub_41A8D0`) | 0 `IDLE#1#ATMEN`, 1 `IDLE#2`, 2 `WALK`, 3 `STAND#USE`, 4 `SIT#EASY`, 5 `SPECIAL#1`, 6 `PISSED` |
| `0x46EEE4` | **Secretary** (`sub_41E360`) | 0 `IDLE#1#ATMEN`, 1 `IDLE#2`, 2 `WALK`, 3 `PANIC`, 4 `PANIC#WET`, 5 `PANIC#FOAM`, 6 `SIT#IDLE`, 7 `SIT#USE`, 8 `SPECIAL#1`, 9 `SIT#EASY` |
| `0x46EC04` | Player | the 21 entries already in `player-action-reference.md` |

The janitor's tick picks slot 2 walking, slot 4 while `+1800` (seated), slot 6 while `+1820`
(the reaction flag), and slot 0 otherwise.

**The secretary has no reaction clip.** `sub_41E360` has no `+1820` branch at all: it picks
slot 2 walking, then while `+1800` either slot 9 (relaxed) or slot 7 / slot 6 on the same
`rand() & 0xfff <= 0xff0` split the coworkers use, then slot 1 for `> 0xff8` and otherwise
slot 0. `npc-reference.md:279` recorded this as "not recovered"; the answer is that she
reacts like everyone else in the shared goal code but never changes clip. Her `PANIC` slots
3–5 are unreachable from the tick, and `CO_CHARS` ships her no `PANIC` art, so they would
fall back to idle even if they were.

## Odds and ends confirmed on the way

- **`agent+1792`**, the slowed flag, sets the movement multiplier `agent+76` to **0.2**
  instead of 1.0 in all four ticks, and `sub_417460` draws the three jittered green copies
  while it is set. It is written by `sub_41CD90` (`0x41cd57`), which is the handler for
  **player mode 5** — so the green jitter and the slowdown are one of the player's own
  abilities, not a catch mechanic.
- **The player's other modes.** `sub_41CFC0` dispatches `player+900` to `sub_41B0C0` (0,
  free), `sub_41B240` (1, the item action), `sub_41BC50` (2), `sub_41C120` (3),
  `sub_41C660` (4) and `sub_41CD90` (5). Modes 2–5 are player abilities in their own right
  and are left for a later task; only their existence matters here, because the catch test
  covers modes 1–3 and not 4–5.
- **`player+1068`** counts down by `dt * 10` in `sub_41CFC0` and, on reaching zero, walks
  every type-253 item back to state 0 through `sub_411070`/`sub_40FDA0` — confirming
  `player-action-reference.md:32`.
- The player object's source file is `D:\Projects\CrazyOffice\obj_player.cpp`; the assert at
  `0x41cfe8` names `m_soundHdl`. The project's working title was *CrazyOffice*.

## What the port takes from this

Nothing here needs a port extension. The notice test uses the same sight ray, the same
`180 - atan2(dx, dz) * 57.29579` heading convention and the same logical tile units the port
already works in. The two new per-character constants come out of the profile table, so they
belong in the exporter that task Q6 adds rather than in GDScript.

Sizing, for the tasks that follow:

- **The catch trigger is small.** One `_process` on the level, a scan of the `npc_agents`
  group in insertion order, and a `notices(player)` on the brain that reuses
  `GridCollision`'s sight ray. The only new state is the cubicle blindness, which
  `npc_activity_point.gd` already has a home for. The facing the port needs — a continuous
  angle rather than the eight-way index — is the one genuinely new field on the actor.
- **Goal 9 is small too**, now that a completed repair is just `reset_actions()` on the
  point. The 30 types are a switch, not a table, so they want a Python exporter that reads
  the case values out of the binary rather than a transcription into GDScript.
- **The minigame is the large one** and is untouched here: 48 sprites, fourteen paired
  `ICON`/`SPELL` entries, two bars and four state overlays. That sitting has since happened
  and its results are in [minigame-reference.md](minigame-reference.md).

## What screen 5 looks like

A screenshot of the original mid-duel (`sacked-reference-images/`, gitignored and local)
settles the layout, though none of the rules. Reading it:

- The two portraits face each other across the screen, opponent on the **left** and the
  player on the **right**, both full height and both against the same blue swirl the menu
  uses. The shot shows a blonde female opponent against `ENEMY_JOBLESS`.
- Two horizontal bars sit along the **top**, one per side, filled from a red end through
  orange and yellow to green. The opponent's is short and the player's nearly full, so a bar
  is that side's remaining standing rather than damage dealt.
- A **two-digit number** sits centred just under the bars — a countdown, reading 03.
- Each side has a **speech bubble** at head height. The opponent's holds a `SPELL` (a red
  bonfire); the player's is **empty** while it is the player's turn. So `BUBBLE`/`BUBBLE2`
  are the two sides' bubbles rather than two states of one.
- A **console strip** runs along the bottom, holding the `ICON` set in **two groups**: four
  on the left with a fifth blank slot, eight on the right. The cursor is over the right
  group. The left group is the opponent's sequence and the right group the player's answer
  buttons, split by the difficulty; see "The two rows of buttons" in
  [minigame-reference.md](minigame-reference.md).

That is enough to place the elements and to know what the turn looks like. The rules, which
icon answers which spell, what the timer does at zero and how the bars move, were recovered
later and are in [minigame-reference.md](minigame-reference.md).

### How screen 5 is built

`sub_407370`'s case 5 is short, and its five arguments are a head start for the sitting that
builds the screen:

```c
ebx = 1;                                  // set once in the prologue: the boss's type
difficulty = 4;
if (game+14688 && game+14688 + 1740 == ebx)   // the catcher is the boss
    difficulty = 7;
portrait = sub_407840(game, game+14688);      // the ENEMY_* name for that catcher
sub_406430(game, difficulty, game+19052 + 2, 8, 8, portrait);
```

So the "7 for the boss, 4 otherwise" really is a difficulty, passed first; the second
argument is the **current level index plus two**, which suggests the duel gets harder as the
campaign does; and the two 8s are a pair whose meaning `sub_406430` settles. `game+14688` is
the catcher stored by the hand-off above, and `agent+1740 == 1` is the boss, matching the
janitor's 3 in [npc-reference.md](npc-reference.md).

## What the port implements

`scenes/level/catch_watch.gd` is `sub_402470`: a `_process` on the level runtime that, while
the level is unpaused and unfinished and the player's prank controller is in `ACTING`, walks
the `npc_agents` group in order and stops at the first agent that is not blind and whose
brain `notices()` the player. `NPCBrain.notices()` is `sub_418310` — the eight-tile box, the
radius, the cone with its two-tile bypass, then `CollisionMapLayer.has_line_of_sight()`,
which is the same `sub_412E30` ray the player's own reach test uses.

Three details the port had to add rather than reuse:

- **A notice heading.** The actor keeps only `last_direction` for its sprite, snapped to the
  eight views. `notice_heading` beside it is `agent+1848`, eased toward that view plus the sway
  once per 1/60 s. `facing_screen` is its screen direction, and the brain converts it into
  logical tiles through the collision layer, because an angle is not preserved by the
  isometric projection. The port used to aim the cone straight along the unsnapped walking or
  activity direction.
- **Cubicle blindness.** `_inside_cubicle` mirrors `agent+1824`, raised when the brain claims
  a cubicle and cleared when it releases the seat.
- **An abort.** `PrankController.abort_action()` is the mode's abort state: it drops the
  action without scoring it, clears an `in_use` mark and undoes a start-time result state.

`Console.warn_of_catch()` raises the exported `AGGRO_UP` banner with one of the four
exclamations for 2.0 seconds, the length of the caught pause the original spends there.

**The caught pause freezes the office.** Screen 4 hands the level a zero time step, so
`CatchWatch` pauses the tree the moment it catches and counts the banner's two seconds on
real time from `PROCESS_MODE_ALWAYS`. The clock, the aggression meter, every colleague and
every looping clip hold still under the banner. One-shots and the theme play on, since their
players always process, and the theme is held only when the duel opens, as case 5 does. The
duel then takes the banner down, which the console's own countdown, paused with everything
else, would not. **One recorded loss**: the original's level tick still reads input at a zero
step, so the ring can be opened under the banner there. A paused `PrankController` gets no
input, so the port's cannot. `tests/check_catch_trigger.gd` proves the freeze, and fails three
ways without it.

**The hand-off is wired.** `hands_off_to_minigame` defaults on, and survives only so a check
can drive the trigger without the duel opening over it. A win unpauses the level that is
still in memory; a loss calls `LevelSession.lose()`, which raises the same `finished` the
clock raises, so the theme and the warning loop stop and the run's own score and time reach
`ScreenManager.report_level_finished` before screen 8. Neither path touches the score or the
aggression meter.
