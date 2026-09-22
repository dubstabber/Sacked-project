# The catch minigame, screen 5

What the original does after a colleague catches the player. Recovered from `sacked.exe`;
the source file it was compiled from is `D:\Projects\CrazyOffice\MiniGame.cpp`, and the
assertions in it hand back the original field names, which this document uses.

The trigger and the hand-off into this screen are in [catch-reference.md](catch-reference.md).

## Getting here

`sub_407370`'s case 5 chooses a difficulty and a portrait, then builds the object:

```c
ebx = 1;                                       // the boss's agent type
difficulty = (catcher && catcher+1740 == 1) ? 7 : 4;
portrait   = sub_407840(game, catcher);        // the ENEMY_* sprite name
sub_406430(game, difficulty, game+19052 + 2, 8, 8, portrait);
```

`sub_406430` is only an allocator. It refuses to build a second one while `game+14712` is
set, allocates 0x144 bytes, stores the object at `game+14716`, and calls the real constructor
`sub_413D40`. **Afterwards it increments `game+19052` and clamps it to 9**, so that counter is
"how many duels have happened", and the constructor receives it **plus two**.

So the two numbers that shape a duel are:

| Argument | Meaning |
| --- | --- |
| 7 for the boss, 4 for anyone else | how many **distinct icons** the round draws from |
| `game+19052 + 2` | how many **casts** are in the round, growing 2, 3, 4 … capped at 11 |
| 8, 8 | starting energy for the opponent and the player |
| the `ENEMY_*` name | the opponent's portrait |
| `game+20686` | the player's own character, 0 Jo Bless and 1 Anne |

## Layout

Every element is the same GUI object the HUD uses, so `+8`/`+12` is its position, `+16` its
layer and `+1140` its alignment flag; see [hud-reference.md](hud-reference.md). Built in this
order by `sub_413D40`:

| Field | Sprite | Position | Layer | Notes |
| --- | --- | --- | --- | --- |
| `m_pBackground` | `MINIGAME_BACKGROUND` | (0, 0) | 32868 | the 800 × 800 swirl, rotated every frame by `sub_4138A0` |
| `m_pBubbleLeft` | `MINIGAME_BUBBLE2` | (120, 150) | 0x7FFF | the opponent's |
| `m_pBubbleRight` | `MINIGAME_BUBBLE` | (410, 150) | 0x7FFF | the player's |
| `m_pConsole` | `MINIGAME_CONSOLE` | (0, 0), flag 8 | 32766 | bottom docked |
| `m_pJoBless` | `MINIGAME_ENEMY_JOBLESS` or `_ANNE` | (641, 227), flag 12 | 0x7FFF | the **player**, on the right |
| `m_pEnemy` | the passed `ENEMY_*` | (0, 253), flag 9 | 0x7FFF | the catcher, on the left |
| `m_pButton[14]` | `MINIGAME_ICON_%i` | y 550 | 32758 | see below |
| `m_pSpell[14]` | `MINIGAME_SPELL_%i` | placed when shown | 32766 | 0–6 casts, 7–13 answers |
| `m_pBarEnemy` | `MINIGAME_BAR_ENEMY` | (20, 20) | 0x7FFF | |
| `m_pBarJoBless` | `MINIGAME_BAR_JOBLESS` | (410, 20) | 0x7FFF | |
| `m_pTime` | a number, `"%02i"` | (370, 60) | 0 | the countdown between the bars |
| `m_pGetReady`, `m_pYourTurn`, `m_pLoose`, `m_pWin` | the four banners | flag 16 | | centred; all start hidden |
| `m_pMouse` | `CGUIMiniGameMouse` | | | |

A cast spell is shown at **(190, 175)** and an answered one at **(495, 175)**, which is what
puts each inside its own bubble.

### The two rows of buttons

Fourteen buttons are laid out from x 66 in steps of 52, stopping before 794, at y 550. Which
row a button lands in is decided by the difficulty:

- **index < difficulty** — a **sequence slot**. Drawn 46 pixels further left, at x 20 + 52·i,
  showing `ICON_{m_acSequence[i] + 1}`.
- **index ≥ difficulty** — an **answer button**, but only if its x has reached 430. Shown at
  x 66 + 52·i with `ICON_{i + 1}`, so the answer row is always icons 8 to 14.

At difficulty 4 that gives four sequence slots at x 20, 72, 124, 176 and seven answer buttons
at x 430 … 742, with indices 4, 5 and 6 falling in the gap and never built. A screenshot of a
difficulty-4 duel matches exactly: four icons on the left of the console and seven on the
right.

Each answer button keeps its index at `+1168` and the minigame at `+1164`.

## The rules

`sub_414870` is the whole of it, a state machine on `m_iState` at `+176`. It runs only while
`+308` is set.

| State | What happens |
| --- | --- |
| 0 | first tick: step interval `+180` = 1.0, then state 2 |
| **2** | show `m_pGetReady` for **2.0 s**, then hide it and go to state 1 |
| **1** | fill `m_acSerial[64]`, each entry `m_acSequence[rand() % difficulty]`, then state 3 |
| **3** | the opponent casts: see below |
| **4** | show `m_pYourTurn` for **1.0 s**, then state 5 |
| **5** | the player answers, with `m_pTime` counting **4.3 s** down |
| **6** | a miss: player energy − 3, reset, back to state 1 |
| **7** | the round won: opponent energy − 3, reset, back to state 1 |
| **8** | won: show `m_pWin` for 3.0 s, play `S1002`, then clear `+308` |
| **9** | lost: show `m_pLoose` for 3.0 s, play `S1001`, then clear `+308` |

**`m_acSequence`** is built once in the constructor: a random permutation of 0…6, seven
distinct values. `m_acSerial` is then drawn from its first `difficulty` entries, so the round
only ever uses that many of the seven icons.

**Casting (state 3).** Each spell is shown for **1.0 s** and then blanked for a quarter of
that, **0.25 s**, before `m_iSpellPos` advances. While a spell is up, `m_pSpell[serial value]`
is placed in the left bubble and the sound `S%04i` of `serial value + 1004` plays, so the
seven casts are **S1004 to S1010**. When `m_iSpellPos` reaches the cast count, everything is
hidden and the turn passes.

**Answering (state 5).** Clicking an answer button sets `m_iJoBlessSpell` and advances
`m_iJoBlessSpellPos`; the answer is shown in the right bubble for the same 1.0 s. When that
second elapses the answer is judged:

```c
if (m_iJoBlessSpellPos >= castCount)         state = 7;   // the round is won
if (m_acSerial[m_iJoBlessSpellPos - 1] != m_iJoBlessSpell) state = 6;   // wrong
```

Note the order: reaching the end sets 7 first, and a wrong final answer then overwrites it
with 6, so the last answer still counts. Letting `m_pTime` run past zero is a miss as well.
Answer *k* matches cast *k*: the icons pair index for index, `SPELL_1`–`7` against
`SPELL_8`–`14`.

**Energy.** Both sides start at 8 and move in steps of 3, and a side loses when its energy
goes **below** zero, so 8 → 5 → 2 → −1. **Three good rounds win and three bad ones lose**,
whatever the difficulty. Each bar is cropped by `energy / max` of its own width.

## The exits

`sub_415010` reports the outcome and `sub_4027B0` acts on it:

```c
if (+308)            return 1;    // still playing
if (+176 == 8)       return 3;    // won
return (+176 == 9) ? 2 : 4;       // lost, or neither
```

Anything other than 1 destroys the object, clears `game+14712`, and switches screen: **3 goes
to screen 1**, back into the level that is still in memory, and **everything else to screen
8**, the lose screen. Nothing here touches the level's score or the office's aggression, so
winning costs only the interrupted prank and the time.

## Not recovered

- The button's own click handler. Everything it must do is pinned by how the tick reads
  `m_iJoBlessSpell` and `m_iJoBlessSpellPos`, but the code that writes them has not been read,
  so whether a click is ignored outside state 5 is an assumption. The port ignores it.
- What `+312` gates. It is set while no answer is being displayed and cleared while one is,
  which reads like "the buttons accept input now", but nothing that consumes it has been read.
- `m_pTime`'s `+104 = 3` and `+120 = 4.0`, presumably a digit count and a scale.

## Sizing

The screen itself is small: four banners, two bubbles, two portraits, two bars, a number and
fourteen buttons, all at fixed coordinates, driven by a ten-state machine with three
constants. The work is in the assets, 48 sprites including an 800 × 800 background, and in
the four banners, which carry their text painted into the art and so need the same treatment
the console labels got.

## What the port implements

`scenes/level/catch_minigame.tscn` and `.gd` are the screen and its state machine, with the
sprite tables and the button layout split into `catch_minigame_art.gd` so each can be checked
on its own. It is an **overlay inside the level**, not a separate scene: a win resumes the
level that is still in memory, which changing scene would have thrown away. `CatchWatch`
holds the banner for its two seconds, opens the duel, pauses the tree, and on the way out
either unpauses or reports the level lost.

Every constant above is used as recovered: the two-second banner, the one-second step and its
quarter-second gap, the 4.3-second answer clock, eight energy in steps of three, and the
sequence length growing by one per duel to a cap of eleven. `ScreenManager.duels_fought` is
`game+19052`.

Three port decisions worth naming:

- **The backdrop.** The original spins the texture coordinates of a quad pinned to the
  screen, so it never shows an edge. The port spins the sprite and scales it by 1.25, which
  is enough for the frame's corners to stay covered at every angle. The pattern is therefore
  slightly larger than the original's.
- **The banners** use each retail build's own painted art, and a drawn label for any language
  that has none. The Polish build's `YOURTURN` and `WIN` are swapped relative to what their
  names say, which the port reproduces by showing that build's art where its name belongs.
  See [strings-reference.md](strings-reference.md).
- **The console is inert outside the answering state**, and a second click is ignored while
  an answer is still on show. The original's click handler has not been read, so this is the
  port's reading of what the tick requires rather than something recovered.
