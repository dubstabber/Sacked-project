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

**The count belongs to one attempt at a level.** A byte search for the displacement finds
seven references. `sub_401000` zeroes it at start-up (read as the game's constructor from its
run of zero stores, not traced further), `sub_406430` increments and clamps it, and case 5
reads it. The other two are resets:

- `sub_406AF0`, the level setup, zeroes it at `0x406CBD` on every fresh load, just before it
  picks the theme. Case 1 runs it from the description screen's `Kontynuuj`, and the
  restart `sub_407320` runs it too.
- The teardown `sub_407140` zeroes it at `0x407267` on every way out: the win screen
  (`sub_406E70`), the lose screen (`sub_4070A0`), the restart, and case 3 when it leaves
  screen 7, 8 or 10 for the menu.

Only a won duel goes back into the level without either (`0x402832`, screen 1 from screen 5
with no reload). So the casts grow 2, 3, 4 … across the duels one attempt survives, and every
new attempt starts again from two. A lost duel ends the attempt.

So the two numbers that shape a duel are:

| Argument | Meaning |
| --- | --- |
| 7 for the boss, 4 for anyone else | how many **distinct icons** the round draws from |
| `game+19052 + 2` | how many **casts** are in the round, growing 2, 3, 4 … within one attempt, capped at 11 |
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
| **5** | the player answers, with `m_pTime` counting down from **3.999 s**; each accepted click resets it to **4.0 s** |
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
`m_iJoBlessSpellPos` (the click handler is below); the answer is shown in the right bubble for
the same 1.0 s. When that second elapses the answer is judged:

```c
if (m_iJoBlessSpellPos >= castCount)         state = 7;   // the round is won
if (m_acSerial[m_iJoBlessSpellPos - 1] != m_iJoBlessSpell) state = 6;   // wrong
```

Note the order: reaching the end sets 7 first, and a wrong final answer then overwrites it
with 6, so the last answer still counts. Letting `m_pTime` run past zero is a miss as well.
Answer *k* matches cast *k*: the icons pair index for index, `SPELL_1`–`7` against
`SPELL_8`–`14`.

**The answer clock** is `+204`. The constructor sets it to 0 (`0x413DE3`). State 1 and the end
of the casts both set it to **3.999** (`0x414932`, `0x414B65`), which `m_pTime` shows as `03`.
State 5 takes the frame time off it before anything else. Gefeuert.exe stores the same bytes
at `0x415192` and `0x4153C5`, and neither build holds a 4.3 anywhere.

**The click handler** is `sub_413C80`, slot +76 of `CGUIMiniGameButton`'s vtable (`0x46571C`,
entry `0x465768`). `sub_459AE0` calls that slot on a button that is pressed with the mouse
inside it (`0x459CC3`). The handler acts only when the state is 5, `+312` is set, and the
button's index (`+1168`) is 7 or more, which makes it an answer button. It then:

- plays `S%04i` of index + 997 through `sub_42A6A0` (`0x413D27`). That is `S1004`–`S1010`, the
  same sound as the cast it answers;
- sets `m_iJoBlessSpell` (`+284`) to index % 7;
- zeroes the step timer `+184` (`0x413CEF`), so the answer is on show for a full second;
- puts the answer clock back to **4.0** (`0x413CFF`);
- increments `m_iJoBlessSpellPos` (`+288`).

`+312` is the tick's "no answer on show" flag. It is set at `0x414DB3` while no answer has
been given and at `0x414D57` once one has been judged, and cleared at `0x414D41` while one is
on show. So a click does nothing outside state 5 or while an answer is showing, and each
accepted click gives the next answer four seconds of its own. A round of *n* casts therefore
needs about *n* seconds of answers and never runs out on a player who keeps up.

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

## What the duel plays

Every duel sound goes through `sub_42A6A0` on the game's own sound handler, `game+15136`.
`sub_406430` passes it to the constructor as the last argument (`0x4064A8`), and the
constructor keeps it at `+0` (`0x413DB1`). Every call passes loop 0 and quiet 0, which means
a one-shot at the full effects volume. These four are the only duel call sites among
`sub_42A6A0`'s cross-references:

| When | Sound | Where |
| --- | --- | --- |
| each cast, once as it appears (`+192` guards it) | `S%04i` of serial value + 1004, `S1004`–`S1010` | `sub_414870`, `0x414BEE` |
| each accepted answer click | `S%04i` of button index + 997: the same `S1004`–`S1010` as the cast it answers | `sub_413C80`, `0x413D27` |
| the duel won, entering state 8 | `S1002` | `0x414EA0` |
| the duel lost, entering state 9 | `S1001` | `0x414F1E` |

Nothing plays for get ready, your turn, or a round won or lost. The constructor `sub_413D40`
and the destructor `sub_414820` neither play nor stop anything. On the way in, `sub_407370`
case 5 pauses the music stream (`sub_42AC30` at `0x407571`) and leaves every effect slot
alone. `sub_4027B0` resumes the music after either outcome (`0x402839`, `0x40284D`). The
handler outlives the screen, so `S1001`, which runs 7.5 s, keeps playing into the lose screen
after the 3.0 s banner.

## Not recovered

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
pauses the tree as the banner goes up, holds it for its two seconds, opens the duel, and on
the way out either unpauses or ends the level through `LevelSession.lose()`. That raises the same
`finished` the clock raises, so the run's own score and time reach the result screen. The
port also stops the theme there, which the original does not do (see
[sound-reference.md](sound-reference.md)).

The duel finds `LevelAudio` through the `level_audio` group and plays its sounds through it.
`LevelAudio` hands each one-shot to `ScreenManager.play_effect`, the port's copy of the
game's handler, so `S1001` also plays on into the lose screen. `CatchWatch` holds only the
theme for the duel. A countdown warning that has already started keeps looping.

Every constant above is used as recovered: the two-second banner, the one-second step and its
quarter-second gap, the 3.999-second answer clock and its reset to 4.0 on every click, eight
energy in steps of three, and the sequence length growing by one per duel to a cap of
eleven. `CatchMinigame.answer()` is `sub_413C80`. It has the same gate, plays the same sound,
and restarts the step and the clock. `ScreenManager.duels_fought` is `game+19052`.
`change_to` zeroes it whenever it enters a level, which covers every fresh start and every
restart. A won duel is an overlay and never passes through it, so the count grows only
within one attempt.

Two port decisions worth naming:

- **The backdrop.** The original spins the texture coordinates of a quad pinned to the
  screen, so it never shows an edge. The port spins the sprite and scales it by 1.25, which
  is enough for the frame's corners to stay covered at every angle. The pattern is therefore
  slightly larger than the original's.
- **The banners** use each retail build's own painted art, and a drawn label for any language
  that has none. The Polish build's `YOURTURN` and `WIN` are swapped relative to what their
  names say, which the port reproduces by showing that build's art where its name belongs.
  See [strings-reference.md](strings-reference.md).
