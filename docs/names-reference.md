# Coworker names: `NAMES.DAT`, the names screen, and the name over the head

Verified on 2026-09-22 against disposable copies of `sacked.exe.i64` and `Gefeuert.exe.i64`.
Addresses are virtual addresses in the Polish `sacked.exe` (479232 bytes, SHA-256
`6404096c…`) unless marked as the German `Gefeuert.exe` (487424 bytes, SHA-256 `f1ddc93d…`).
The source file is `D:\Projects\CrazyOffice\npc_names.cpp`, named by the assert in
`sub_4156E0`.

## The table

The names live in a singleton at `dword_473CE8`, fifteen fixed records long:

| offset | type | meaning |
|---:|---|---|
| `+0` | u32 | reset pending: when 1, the next dispense clears every used flag first |
| `+4` | u32 | 1 when the table came from the embedded defaults, 0 when it came from the file |
| `+8` | 15 × 22 bytes | the records |
| `+340` | u32 | record count |

Each 22-byte record is:

| offset | type | meaning |
|---:|---|---|
| `+0` | u16 | type, 1 to 7 |
| `+2` | u16 | used flag |
| `+4` | char[18] | the name, NUL-padded; every copy in or out is `strncpy(…, 16)` |

**The type column is informational.** Every function that reads or writes a name —
`sub_4156E0` (dispense), `sub_415B80` (read), `sub_415A60` (write), `sub_415CA0` (reset one
type) — addresses its pool by fixed record position, not by the stored type:

| type | enum (assert @ `0x46E734`) | portrait | records |
|---:|---|---|---|
| 1 | `NAME_BOSS` | `CO_GUI_MENU_COWORKER_PORTAIT_CHEF` | 0 |
| 2 | | `…_CS` | 1 |
| 3 | | `…_HM` | 2 |
| 4 | | `…_KM1` | 3–5 |
| 5 | | `…_KM2` | 6–8 |
| 6 | | `…_KW1` | 9–11 |
| 7 | `NAME_COWORKER_FEMALE_2` | `…_KW2` | 12–14 |

The portrait names are the `char*[7]` table at `0x470518`, indexed by type − 1. The types
are the spawn types the level loader uses, so pool *n* belongs to spawn type *n*: boss,
secretary, janitor, then the two male and two female employees in the port's own
`NPC_PROFILES` order.

## `NAMES.DAT`

The file is **334 bytes: a u32 count, then the 330 bytes of records**, stored exactly as they
sit at `+8` in memory. Both halves:

- **Read**, once at start-up: `sub_405430` → `sub_426200` → `sub_415980(".")`, which builds
  `%s\NAMES.DAT`, reads the count into `+340` (`sub_460D90`), then `0x14A` bytes into `+8`,
  clears every used flag (`sub_4156B0`) and sets `+4 = 0`. A missing file falls back to
  `sub_415630`, which copies the embedded defaults and sets `+4 = 1`.
- **Written** by `sub_4158B0`, through `sub_4262E0`, with the count first and the 330 bytes
  after it. The used flags go to disk with the names, but every read clears them, so what is
  stored there never matters.

The shipped Polish file (SHA-256 `7536017a…dbd14`, count 15) is **byte-identical to the
embedded defaults**: the same 330 bytes, with every used flag zero.

The embedded defaults are 15 records in the same layout plus one all-zero terminator record,
since `sub_415630` walks until it reads type 0: the Polish build at `0x46E5C0`, the German at
`0x470A18` (read from `0x415E82`, `0x415E9C` and `0x41655D`). The 352 bytes are identical in
both builds. The German build ships no `NAMES.DAT` and builds its table from these defaults
on first run. So the names are the German originals' puns in both releases:

| # | type | name | # | type | name |
|---:|---:|---|---:|---:|---|
| 0 | 1 | Roy Behr | 8 | 5 | Mark Aber |
| 1 | 2 | Martha Pfahl | 9 | 6 | Cindy Doof |
| 2 | 3 | Don Mestos | 10 | 6 | Caro Muster |
| 3 | 4 | Tim Buktu | 11 | 6 | Hanne Büchen |
| 4 | 4 | Ernst Haft | 12 | 7 | Clare Grube |
| 5 | 4 | Bart Wux | 13 | 7 | Klara Fall |
| 6 | 5 | Bob Tale | 14 | 7 | Bette Nesser |
| 7 | 5 | Ernie Drigt | | | |

Every name is ASCII except the `ü` in `Hanne Büchen`, byte `0xFC`, which is `ü` in both
cp1250 and cp1252.

### Two things the extraction's notes get wrong

`extract-sacked-assets/docs/formats/dat_sidecars.md` (the `NAMES.DAT` section) and
`tools/names_parser.py` decode the file without its 4-byte count. That shifts every record
by four bytes, so they report a 16-byte name followed by a "u16 sentinel/next_type" field,
which is really the next record's type seen through the misalignment. They also say the
shipped file's names are zeroed, and that is false: the file carries all fifteen names.
The reference tree stays untouched. This document is the correction.

## Naming an agent

`sub_406AF0`, which sets a level up, calls `sub_4156B0` first, so **every level load, restart
included, starts with every name free again**. It then creates the agents in ascending spawn
type (see [npc-reference.md](npc-reference.md)). Each factory ends with the new agent's
vtable `+28` call, and each class's `+28` does
`strcpy(agent+1752, sub_4156E0(names, pool))`:

| class | factory | vtable | `+28` | pool |
|---|---|---|---|---|
| `CObj_Boss` | `sub_404B90` | `0x465310` | `sub_4196A0` | 1 |
| `CObj_Secretary` | `sub_404EC0` | `0x465378` | `sub_41E2C0` | 2 |
| `CObj_Housekeeper` | `sub_404D20` | `0x465344` | `sub_41A830` | 3 |
| `CObj_Coworker` | `sub_405010`, `sub_4051D0` | `0x4653AC` | `sub_419C10` | 4–7 |

`sub_419C10` picks the coworker's pool from `agent+1744` (0 male, set by `sub_405010`;
1 female, set by `sub_4051D0`) and `agent+1748` (the variant, 0 or 1): male 0 → 4, male 1 → 5,
female 0 → 6, female 1 → 7. The player is spawn type 0 and is never named.

`sub_4156E0(pool)` hands out the first record in the pool whose used flag is 0 and sets the
flag. Once a pool is empty it returns the literal **`DEFAULT NAME`** (`0x46E724`, through
the pointer at `0x46E720`; German `0x470B7C`). Types 1 to 3 are created at most once per level,
so only a fourth agent of one coworker type can ever see the placeholder. Names are therefore
dealt in creation order: by spawn type, then by `SPAWN` file order within a type.

## The names screen, 13

`CCoworkerSetup`. `sub_407370`'s case 13 calls `sub_4079C0`, which builds it with
`sub_41FFC0`, shows type index 0, loads the boss's name into the first box, and starts
`Menu2`. The background is `CO_GUI_MENU_BASE_BG_03`. The title is slot 209 in the rect
`(64, 16, 672, 64)`, drawn the way every menu screen draws its title. See
[shell-reference.md](shell-reference.md).

The element rects are the table at `0x470538` (German `0x472990`, identical):

| id | element | art | x | y | w | h |
|---:|---|---|---:|---:|---:|---:|
| — | title | slot 209 `Wybierz kolegów` | 64 | 16 | 672 | 64 |
| 2 | previous type | `CO_GUI_MENU_BASE_LARROW_{ACTIVE,PASSIVE}` | 226 | 194 | 64 | 48 |
| 1 | next type | `CO_GUI_MENU_BASE_RARROW_{ACTIVE,PASSIVE}` | 512 | 194 | 64 | 48 |
| — | portrait | `CO_GUI_MENU_COWORKER_PORTAIT_*` | 320 | 88 | 160 | 240 |
| — | name box 0 | `CO_GUI_MENU_BASE_TEXTINPUT_NAME` | 232 | 336 | 352 | 44 |
| — | name box 1 | same | 232 | 396 | 352 | 44 |
| — | name box 2 | same | 232 | 456 | 352 | 44 |
| 4 | slot 211 `Główne menu` | `CO_GUI_MENU_BASE_BUTTON_*` | 16 | 536 | 160 | 48 |
| 3 | slot 210 `Domyślne` | `CO_GUI_MENU_BASE_BUTTON_*` | 624 | 536 | 160 | 48 |

`sub_420870(index)` clamps the index to 0–6, points the portrait at the table entry, and shows
**only box 0 for the three single-name types** (boss, secretary, janitor), all three boxes
for the four coworker types.

**Names are editable.** Each box is a `CGUIInput` (`sub_45C5E0`), with its length cap set to
**16** at `+356` and its text drawn in the menu's Arial 32 (`+1168`): white, a
`(32, 32, 32)` copy two pixels right and down behind it, centred both ways in the box, and a
caret while the box has focus. The first box has focus when the screen opens. The key handler
`sub_45C880` edits with backspace, delete, home, end, the two arrows and an insert/overwrite
toggle. It ignores Enter, Tab and F1–F12, refuses `ß`, and types every other key through
`ToAsciiEx` on the current keyboard layout.

The buttons, from `sub_403F20` case 13. `sub_4082E0(save, load)` copies the shown boxes into
the table for type `save`, then fills the boxes from type `load`, where 0 means "none" for
either:

| id | effect |
|---:|---|
| 1 | index + 1, wrapping 6 → 0; `sub_4082E0(old type, new type)` |
| 2 | index − 1, wrapping 0 → 6; `sub_4082E0(old type, new type)` |
| 3 | `sub_415CA0(type)` puts the embedded defaults back for **the shown type only**, then `sub_4082E0(0, type)` reloads the boxes. Unsaved typing in them is discarded |
| 4 | `sub_4082E0(type, 0)` saves the shown type, then screen 3 |

**`sub_4082E0` always ends by writing `NAMES.DAT`.** So the file is rewritten on every
button press on this screen, and typing alone writes nothing. An empty box is saved as an
empty name, and an empty name is never drawn (below).

## The name over the head

`sub_417460` is `CAgent`'s overlay draw (vtable `+12` of the base `0x4657EC` and of all four
classes above). After the thought bubble it draws the name when **all** of these hold:

- `agent+84 == 1` (the agent is drawn at all);
- `agent+1788 == 1`, the selection flag, below;
- `agent+1752` is not empty;
- `agent+1728` is set. That is the font, `game+2008`, which `sub_405430` creates as
  **Arial 24**, so in practice it is always set.

The draw is two passes in blend mode 36 at depth **64000**, above any world depth, so walls
never hide it:

| pass | colour | position |
|---|---|---|
| shadow | `(40, 10, 0)` | `(x − w/2 + 2, y − 133)` |
| text | `(250, 180, 40)` | `(x − w/2, y − 135)` |

where `(x, y)` is the agent's screen anchor (`agent+8`, `+12`) and `w` the text width. So the
name is centred over the agent, 135 pixels above its feet, at the same height the bubble is
drawn from. The reference screenshot of `Klara Fall` in yellow is this draw.

### Selecting an agent

`agent+1788` is written in two places only:

- `sub_415D50`, the `CAgent` constructor, zeroes it.
- `sub_403780`, the level tick (`0x4039d7`–`0x403a3f`): **when input bit `0x400` arrives
  while `game+14696` holds an agent**, it clears the flag on every other agent, skipping the
  player, and sets it on that one.

Bit `0x400` is the act input, a left click or space (see
[player-action-reference.md](player-action-reference.md)). `game+14696` is the agent under
the cursor, picked each frame by `Main_RenderUpdate` (`sub_42BF20` at `0x4031f7`) and tinted
`(255, 255, 255, 200)` while hovered. So **clicking a coworker selects them, and the name
stays until another coworker is clicked**, for the rest of the level. Clicking empty floor or
an object changes nothing, and at most one agent carries the flag. The hover tint is
independent: it follows the cursor every frame and says nothing about selection.

The same flag feeds one more system, not recovered further here. `sub_402260` runs each frame
from `Main_RenderUpdate` and calls `sub_4179B0` for every agent, which eases the agent's
notice heading `agent+1848` (see [npc-reference.md](npc-reference.md)). It passes 0 for all
but the selected agent. For that one, when `agent − player` is below 12.0 (`flt_4652CC`) on
both logical axes, it passes 1 (`0x4022FA`), and `sub_4179B0` then also has `sub_428BC0`
rasterise a 113 × 113 field-of-view mask octant by octant around that heading. After that comes
`sub_417440` → `sub_4298E0`. The comparisons are signed, so there is no lower bound. This
is the selected coworker's line-of-sight overlay. It belongs with the camera and effects work,
not with names.

## In the port

`tools/export_names.py --check` reads all three copies of the table, `NAMES.DAT` and the two
builds' embedded defaults, each pinned by size and hash, and refuses to run unless they
agree. It also checks each record's type against its fixed position. It writes
`resources/original/names.json`: the fifteen names, the seven pools with the profile each
belongs to and the portrait sprite from `0x470518`, the `DEFAULT NAME` placeholder read from
both builds, and the 16-character cap. `scenes/shared/coworker_names.gd` (`CoworkerNames`)
reads that file once for everything else.

**Edited names live in `user://settings.cfg`, not in a `NAMES.DAT`.** `SettingsStore` keeps
one `[names] type_N` key per pool, written only once screen 13 has saved that pool, so a pool
never edited reads as the shipped defaults. Every name is cut to 16 characters and kept as
typed otherwise, spaces included. An empty name is kept empty.

`scenes/screens/coworker_names.tscn` is screen 13 at the rects above, reached from main-menu
button 3 with `Menu2` playing. It follows the button table exactly. The arrows and
`Główne menu` save the shown boxes first. `Domyślne` puts back the shown pool only and
discards what was typed, and typing alone saves nothing. It opens on the boss with the first
box focused, and a pool of one hides the other two boxes, frames included. The boxes refuse
`ß` as `sub_45C880` does. Three things differ from the original:

- **The box text is size 31, not Arial 32.** Godot's default font needs 45 pixels of line at
  32, one more than the box's 44, so 31 is the largest that fits.
- **The shadow is a second label.** A `LineEdit` draws no shadow, so a label behind each box
  mirrors its text two pixels down and right, in `(32, 32, 32)`.
- **Some keys behave as Godot's do.** Enter does nothing, as in the original. Tab moves the
  focus, where the original ignores it, and there is no overwrite mode.

`tests/check_coworker_names.gd` pins the table, the store's pools, the recovered rects, the
arrows' wrap, saving on each button, `Domyślne`, the empty name, the refused `ß` and `Menu2`.

**Deferred**: the field-of-view overlay that `sub_402260` drives.
