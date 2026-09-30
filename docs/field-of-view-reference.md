# The selected coworker's field of view

Verified on 2026-09-25 against a disposable copy of `sacked.exe.i64` and the shipped
`sacked.exe` (479232 bytes, SHA-256 `6404096c…`). The original executable and database were
not modified. Addresses are virtual addresses in that build, where RVA equals file offset.

The table builder `sub_427DC0`, the cone `sub_428270` and the whole per-frame build were
also run under emulation (unicorn). A Python replay matched the emulated original byte for
byte: the tables exactly, the cone in 492 cases and again in 958 in an independent check,
and the whole build on 492 random maps and again on 350. The draw was emulated with a coded
texture.

Clicking a coworker selects them (see [names-reference.md](names-reference.md)). While the
selected coworker is near the player, the floor they can see is tinted blue. The tint is a
wedge around their notice heading (see [npc-reference.md](npc-reference.md)), reaching out
to their notice radius and cut off by sight-blocking cells. It is built as a 113 × 113 mask
at eight texels per tile and painted onto the floor. It approximates the notice test in
[catch-reference.md](catch-reference.md), but nothing reads it back.

## The trigger

`Main_RenderUpdate` calls `sub_402260` (`0x402993`), and nothing else does.
`sub_403710` runs `Main_RenderUpdate` on screens 1, 4 and 10 (`0x40372B`).
`sub_402260` visits every entity with `+112 == 2` (`0x4022A5`):

```c
p = position of game+0x3954, the player (sub_42B370)
a = position of the agent
dx = a.x - p.x;  dz = a.z - p.z
if (dx < 12.0 && dz < 12.0 && agent+1788 == 1) {       // flt_4652CC; 0x4022CF, 0x4022E0, 0x4022ED
    sub_4179B0(agent, 1);                               // ease the heading, build the mask (0x4022FA)
    sub_417440(agent, game+12744, game+1996);           // draw: camera, back buffer (0x40230F)
} else
    sub_4179B0(agent, 0);                               // ease only (0x40231A)
```

- **The gate is signed and strict.** Each comparison is `fcomp` / `test ah, 1`, with no
  `fabs` and no lower bound. So an agent 50 tiles away toward −x or −z passes the gate. A NaN
  would pass too, because C0 is set on an unordered compare.
- **Nothing tests whether the agent is visible.** Neither `+84` nor the agent's screen
  rectangle is checked. A selected agent that is off screen still draws its tint, which is
  then clipped.
- **At most one agent is drawn.** `agent+1788` is the selection flag. `sub_403780` clears it
  on every other entity (`0x403A18`) and sets it on the clicked one (`0x403A3F`), so at most
  one field of view is drawn per frame.
- **Nothing turns it off.** There is no option for it. Each function in the chain has exactly
  one caller:
  - `sub_4298E0` from `0x417458`;
  - `sub_417440` from `0x40230F`;
  - `sub_428BC0` from `0x417AEC`;
  - `sub_402260` from `0x402993`;
  - `sub_429800` from `0x42974A`;
  - `sub_429830` from `0x429751`.

  `sub_4179B0` is the exception, with two call sites, `0x4022FA` and `0x40231A`, both in
  `sub_402260`.
- **It still runs while the office is frozen.** `Main_RenderUpdate` runs on the caught banner
  (screen 4), behind the quit prompt (screen 10) and under the pause panel. So the heading
  keeps easing and the tint keeps drawing on all three.
  - The sway's clock, `agent+72`, is the level clock, and that does not advance on those
    screens (see [player-ability-reference.md](player-ability-reference.md)).
  - Under the pause and the quit prompt no agent tick runs at all, so the target holds still
    and the heading settles onto it.
  - **On the caught banner a standing agent still turns, and the heading follows it.**
    `sub_402860` routes screens 1, 4 and 10 to `sub_402590` (jump table, `0x40287B`). The only
    gate in `sub_402590` is the pause bit, `test [ebp+31C4h], 20h` at `0x4025B0`, and the
    banner does not set it. So the agent ticks run at a zero time step. Each of the four calls
    the look-around `sub_4187A0` for a standing agent, with no time test before it: the boss
    at `0x41983B`, the coworkers at `0x419EBF`, the janitor at `0x41A99C` and the secretary at
    `0x41E4FE`. On every call it rolls `rand() & 0xFFF > 4000` (95 in 4096) and, on a hit,
    turns `+124` one view either way. The new view moves the target, and the heading eases
    toward it with the sway frozen.
  - The coworkers' and the secretary's `IDLE#2` roll fires there too (`0x419E97` in
    `sub_419CE0`, and the same branch in `sub_41E360`). It sets the clip's start to the frozen
    clock, so the clip holds on its frame 0 until the level clock runs again.

## The heading

`sub_4179B0` eases `agent+1848` toward the agent's view plus a sway. That is described in
"The notice heading" in [npc-reference.md](npc-reference.md):

```c
target = 45.0 * int16 agent+124 + 10.0 * sin(agent+1844 + agent+72);  // wrapped to [0, 360)
agent+1848 -= 0.125 * sub_45E270(agent+1848, target);                 // short way round, wrapped
```

The constants are the double 10.0 at `0x465888`, 45.0 at `0x465548`, 360.0 at `0x465880` and
0.125 at `0x465854`. The easing is the same for both values of the argument, which is tested
only afterwards (`0x417AB6`). With 1, the function then does two more things:

- it copies `agent+896`, the level map `game+0x3208`, into the field-of-view object's map
  pointer (`0x417ABD`–`0x417AC3`);
- it calls `sub_428BC0(x = agent+20, z = agent+28, radius = agent+1068, heading = agent+1848,
  cone = agent+1072)` with `ecx = agent+1128` (`0x417AE6`, `0x417AEC`).

`agent+896` is zeroed by the constructor (`0x415D90`) and set by the spawners (`0x404B0D`,
`0x404C58`, `0x404DF0`, `0x404F74`, `0x405105`, `0x4052C5`). The radius and the cone are the
profile's notice radius and cone, widened by the aggression band (see
[catch-reference.md](catch-reference.md)). The widest reachable cone is 85°: the janitor's
70 plus the band's 15. The boss's band does not apply, so he keeps 75. The largest radius is
5.9 tiles.

## The field-of-view object

The object is embedded in every agent at `agent+1128` (`0x468`). The `CAgent` constructor
builds it through `sub_428140` (`0x415D9B`, `0x415DA5`).

| Object offset | Agent offset | Meaning |
| --- | --- | --- |
| `+4` | `+1132` | A 113 × 113 32-bit image, from `sub_42D450(113, 113, 0, 32)` → `sub_42BFB0` (zeroed at `0x42C091`). Its width is at `+0x14`, its height at `+0x18` and its bit depth at `+0x1C` |
| `+0x240` | `+1704` | The cone and shadow mask: `new(0x35E1)`, of which 113 × 113 bytes are used |
| `+0x244` | `+1708` | The radius mask: `new(0x35E1)` |
| `+0x248` | `+1712` | The map pointer, copied from `agent+896` before each build |
| `+0x24C` | `+1716` | The cached `radius * 8`. It starts at 5.0 (`0x4281D5`), with `sub_429770(5.0)` at `0x4281E4`. That draws a 5-texel disc, which the first build replaces |

## The mask

### Conventions

- **Layout.** The mask is 113 × 113 bytes, indexed `113 * row + col`. The row follows logical
  z and the column follows logical x, at 8 texels per tile.
- **Centre.** Texel (56, 56) is the agent. The cell tests use the agent's position plus 0.5.
- **Values.** **1 means hidden and 0 means visible.**
- **Heading.** A heading h, in degrees, points along `(dx, dz) = (sin h, −cos h)`. So 0 is −z
  (view `_000`), 90 is +x (`_090`), 180 is +z and 270 is −x. This is `sub_418310`'s
  `180 − atan2(dx, dz)` convention.

The cone is chosen in eighths. Bit s covers the heading sector that starts at
`45.00045 * s` degrees (see below):

| Bit | Sector | Region, as (dx, dz) from the agent |
| --- | --- | --- |
| `0x01` | 0 | `dx ≥ 0`, `dz < 0`, `abs(dx) ≤ abs(dz)` |
| `0x02` | 1 | `dx > 0`, `dz < 0`, `abs(dx) ≥ abs(dz)` |
| `0x04` | 2 | `dx > 0`, `dz > 0`, `abs(dx) ≥ abs(dz)` |
| `0x08` | 3 | `dz > 0`, `dx ≥ 0`, `abs(dz) ≥ abs(dx)` |
| `0x10` | 4 | `dz > 0`, `dx ≤ 0`, `abs(dz) ≥ abs(dx)` |
| `0x20` | 5 | `dx < 0`, `dz > 0`, `abs(dx) ≥ abs(dz)` |
| `0x40` | 6 | `dx < 0`, `dz < 0`, `abs(dx) ≥ abs(dz)` |
| `0x80` | 7 | `dz < 0`, `dx ≤ 0`, `abs(dz) ≥ abs(dx)` |

### The cone, `sub_428270`

```text
clear all 12769 bytes (0xC78 dwords and one byte, 0x428289–0x4282B6)
lo = f32(h - cone * 0.5);  hi = f32(h + cone * 0.5)               // 0.5 at 0x4652B4
s_lo = lo < 0 ? -1 - trunc(lo * -0.022222) : trunc(lo * 0.022222) // 0x4667D0, 0x4667D4
s_hi = trunc(hi * 0.022222)
n = s_hi - s_lo                                                   // taken before the wrap
s_lo &= 7;  s_hi &= 7
bits = 1 << s_lo;  e = s_lo;  repeat n times: e = (e + 1) & 7; bits |= 1 << e
clip the partial sectors s_lo and s_hi (below)
fill every octant not in bits (below)
return bits
```

**The constant is not 1/45.** It is `f32(0.022222)` (`0x3CB60AE9`), and `f32(1/45)` would be
`0x3CB60B61`. So sector boundaries fall at multiples of 45.00045°, and an exact multiple of
45° lands one sector low: 45 goes to sector 0, 90 to sector 1, 360 to 7 and −45 to 7. `hi`
may exceed 360.

**The partial sectors.** Each is clipped by one filled triangle. The low sector's triangle
comes from jump table `0x428B78` (targets `0x42836B`–`0x428487`). The high sector's comes from
`0x428B98` (targets `0x4285DA`–`0x428737`). Each triangle has three vertices:

- A, the sector's boundary corner on the mask edge;
- B, where the angle's line meets the sector's edge;
- the centre, (56, 56).

```text
t   = angle * 0.017453                                // 0x465540, f32(0.017453), not pi/180
dir = (f32(-sin t), f32(cos t))
(ix, iy) = sub_427C80((0, 0), dir, C, D)              // the sector's edge line, below
X = f32(ix + 56);  Y = iy + 56                        // 56.0 at 0x4667C8
each of X, Y: < 0 -> 0;  >= 113 -> 112               // 0x4667C4, 0x4667C0
triangle(A, (trunc X, trunc Y), (56, 56))
```

The edge lines are given as C–D in texel offsets from the centre, using ±56.0 (`0x4667C8`,
`0x4667CC`). The A corners are (col, row):

| Sector | Edge line C–D | A for the low sector | A for the high sector |
| --- | --- | --- | --- |
| 0 | (−56, −56)–(56, −56) | (56, 0) | (112, 0) |
| 1 | (56, −56)–(56, 56) | (112, 0) | (112, 56) |
| 2 | (56, −56)–(56, 56) | (112, 56) | (112, 112) |
| 3 | (−56, 56)–(56, 56) | (112, 112) | (56, 112) |
| 4 | (−56, 56)–(56, 56) | (56, 112) | (0, 112) |
| 5 | (−56, −56)–(−56, 56) | (0, 112) | (0, 56) |
| 6 | (−56, −56)–(−56, 56) | (0, 56) | (0, 0) |
| 7 | (−56, −56)–(56, −56) | (0, 0) | (56, 0) |

`sub_427990` fills the triangle with 1. It uses `sub_427930` for the edges and `sub_427900`
for floor division:

```text
sort the vertices by row: v0 (top), v1, v2
cross = (x2 - x0)(y1 - y0) - (y2 - y0)(x1 - x0)
L, R  = cross >= 0 ? (edge(v0, v1), edge(v0, v2)) : (edge(v0, v2), edge(v0, v1))
for y = v0.y + 1 while y <= min(L.end, R.end):  fill row y, cols step(L) + 1 .. step(R) + 1
replace edge(v0, v1) by edge(v1, v2)       // a flat v1-v2 keeps the old stepping state
for y = max(L.start, R.start) + 1 while y <= L.end:  the same

edge(x0, y0, x1, y1): start = y0, end = y1; if y1 != y0:
    q = floor((x1 - x0) / (y1 - y0));  r = (x1 - x0) - (y1 - y0) q
    x = x0 + q;  err = 2r - (y1 - y0)
step(): return x, then  if err < 0: x += q, err += r   else: x += q + 1, err += r - (y1 - y0)
```

So the fill skips the top vertex's row and fills columns `xl + 1` to `xr + 1`.

**The absent octants** are filled after the clips (`0x428856`–`0x428B67`). They work in
quadrant pairs: `0x03` is 0x01 with 0x02, `0x0C` is 0x04 with 0x08, `0x30` is 0x10 with 0x20,
and `0xC0` is 0x40 with 0x80.

If both octants of a pair are absent, a 56 × 56 block is filled with `rep stosd`, 14 dwords
per row:

| Pair | Rows | Columns |
| --- | --- | --- |
| `0x03` | 1–56 | 56–111 |
| `0x0C` | 56–111 | 56–111 |
| `0x30` | 56–111 | 1–56 |
| `0xC0` | 1–56 | 1–56 |

Otherwise each absent octant gets an inclusive triangle, for m = 0 to 55:

| Bit | Filled |
| --- | --- |
| `0x01` | row 56 − m, cols 56 … 56 + m |
| `0x02` | col 56 + m, rows 56 − m … 56 |
| `0x04` | col 56 + m, rows 56 … 56 + m |
| `0x08` | row 56 + m, cols 56 … 56 + m |
| `0x10` | row 56 + m, cols 56 − m … 56 |
| `0x20` | col 56 − m, rows 56 … 56 + m |
| `0x40` | col 56 − m, rows 56 − m … 56 |
| `0x80` | row 56 − m, cols 56 − m … 56 |

Two consequences follow:

- **The centre is always hidden.** Every fill includes the centre row or column it touches,
  and a cone of at most 85° always leaves an octant absent. So texel (56, 56) is always set.
- **The outer ring is never filled here.** Neither the block fills nor the octant fills reach
  row 0, row 112, column 0 or column 112. Only the clip triangles and the radius mask set
  them.

### The shadows, `sub_428BC0`

```text
bits = sub_428270(heading, cone)                      // 0x428BD5
x' = f32(x + 0.5);  z' = f32(z + 0.5);  R8 = f32(radius * 8.0)
for bit in 0x01, 0x80, 0x08, 0x10, 0x02, 0x04, 0x40, 0x20:
    if !(bits & bit): continue
    reset the per-cell cache (sentinel -1000, 0x428C18)
    idx = 0
    for r = 1 .. 56:   fr = (r - 1) / 8
        for j = 0 .. r - 1:   fj = j / 8
            (cx, cz) = this octant's cell, below; trunc rounds toward zero
            if sub_412AE0(map, cx, cz, 2):            // INFODATA bit 1; 0 off the map
                for {a, b, k} in samples[idx]: stamp it, below
            idx += 1
```

The order of the octants is the order of the guards (`0x428D5C`, `0x428EB7`, `0x429006`,
`0x42915B`, `0x4292D1`, `0x42943A`). Only 1s are written, so the order does not change the
result.

`sub_412AE0` mode 2 is the sight bit from [collision-reference.md](collision-reference.md). It
returns 0 for a cell off the map, so such cells never block. The walk starts at the agent's
own cell (r = 1, `fr = 0`). A sample in (−1, 0) truncates to cell 0 rather than leaving the
map.

| Bit | Cell tested | Stamp for each `{a, b, k}` |
| --- | --- | --- |
| `0x01` | `(trunc(x' + fj), trunc(z' − fr))` | row 56 − k, cols 56 + a … 56 + b − 1 |
| `0x80` | `(trunc(x' − fj), trunc(z' − fr))` | row 56 − k, cols 56 − b … 56 − a − 1 |
| `0x08` | `(trunc(x' + fj), trunc(z' + fr))` | row 56 + k, cols 56 + a … 56 + b − 1 |
| `0x10` | `(trunc(x' − fj), trunc(z' + fr))` | row 56 + k, cols 56 − b … 56 − a − 1 |
| `0x02` | `(trunc(x' + fr), trunc(z' − fj))` | col 56 + k, rows 56 − b … 56 − a − 1 |
| `0x04` | `(trunc(x' + fr), trunc(z' + fj))` | col 56 + k, rows 56 + a … 56 + b − 1 |
| `0x40` | `(trunc(x' − fr), trunc(z' − fj))` | col 56 − k, rows 56 − b … 56 − a − 1 |
| `0x20` | `(trunc(x' − fr), trunc(z' + fj))` | col 56 − k, rows 56 + a … 56 + b − 1 |

**The two axes are not symmetric.**

- On the minor axis, texel `56 + o` covers `[o/8, (o+1)/8)`, and the mirrored side uses
  `56 − o − 1`.
- On the major axis, row or column 56 is `k = 0` on both sides, so the centre line belongs to
  both.

Reproduce each octant's formula as listed. Do not mirror one octant into the others.

### The shadow tables, `sub_427DC0`

Nothing is loaded from a file. `sub_427DC0` builds the tables at run time. It is called only
from the field-of-view constructor `sub_428140` (`0x42817D`), and only on the first
construction:

- The flag `dword_47F038` is set at `0x428173`.
- The reference count `dword_47F03C` is incremented at `0x42818A` and decremented in the
  destructor `sub_428200` (`0x428206`).
- When the count reaches 0, `sub_427D70` frees `0x47F02C`, `0x47F030` and `0x47F034`. It does
  not free the row table, which leaks and is allocated again on each rebuild.

| Global | Allocation | Content |
| --- | --- | --- |
| `0x47F02C` | `new(0x33C0)`, 1656 pairs | `[start, count]` per sample, 1596 used; sample `idx = r(r − 1)/2 + j` |
| `0x47F030` | `malloc(0x2EE00)`, 48000 entries, grown by `realloc` in steps of 1000 (`0x4280AB`) | `{u8 a, u8 b, u8 k, u8 0}`, 30856 used |
| `0x47F034` | `new(0xC804)` | 57 × 57 `f32` distances, `dist[57i + j] = sqrt(i² + j²)` (`0x4280F9`–`0x428134`) |
| `0x47F040` | `new(0x244)` | 114 row offsets, `113 * i` for i = 0 to 113 (`0x427E1D`–`0x427E32`) |

The builder, written as a replay that reproduces the tables exactly. `f32` means rounding to
float32 at the points the original stores. Everything else is double, because the x87 runs
at 53-bit precision:

```python
for r in range(1, 57):
    fA = f32(r / 8);  fB = f32((r - 1) / 8)
    for j in range(r):
        fj = f32(j / 8);  fj1 = f32((j + 1) / 8)
        inv = 1.0 / sqrt(fA * fA + fj * fj)
        P1 = (f32(f32(inv * fj) + fj), f32(inv * fA + fA))       # (fj, fA), one unit on along its ray
        inv = 1.0 / sqrt(fj1 * fj1 + fB * fB)
        P2 = (f32(f32(inv * fj1) + fj1), f32(inv * fB + fB))     # (fj1, fB), likewise
        start = len(block); count = 0
        yk = f32(0.0625)                                         # 0x4667BC
        for k in range(56):
            x1, y1 = isect((0, yk), (f32(10.0), yk), (fj, fA), P1)   # 10.0 immediate at 0x427F75
            x2, _  = isect((0, yk), (f32(10.0), yk), (fj1, fB), P2)
            if x1 < fj: x1 = fj
            if x2 < 0.0 or x2 > 7.0: x2 = 7.0                    # 0x4667B8; parallel lines give -1000
            if not (y1 < fB):
                block.append((ceil(x1 * 8.0), ceil(x2 * 8.0), k, 0))  # 8.0 at 0x465878; MSVCRT ceil
                count += 1
            yk = f32(yk + 0.125)                                 # 0x465854
        samples.append((start, count))

def isect(A, B, C, D):                                           # sub_427C80: line A-B against line C-D
    bx = f32(B.x - A.x);  by = f32(B.y - A.y)
    det = bx * (C.y - D.y) - (C.x - D.x) * by
    if det == 0.0: return (-1000.0, -1000.0)                     # 0xC47A0000, 0x427CED
    det = f32(det)
    t = f32(((C.x - A.x) * (C.y - D.y) - (C.y - A.y) * (C.x - D.x)) / det)
    u = f32((C.y - A.y) * bx - (C.x - A.x) * by) / det           # u itself is not rounded
    return (f32((B.x - A.x) * t + A.x), f32(u * (D.y - C.y) + C.y))
```

So sample (r, j) is the square `[j/8, (j+1)/8] × [(r−1)/8, r/8]` in the octant's (minor,
major) frame. Its entries are that square's angular shadow as seen from the origin, one span
of minor texels `[a, b)` for each major row k from r − 1 to 55, including its own row.

**Precision matters.** The C runtime sets 53-bit precision (`__setdefaultprecision` at
`0x461CEE`, reached from start-up at `0x461B09`). No game code touches the FPU control word:
there is no `fldcw` or `fninit` in `.text`.

- Control word `0x27F` and `0x37F` give the same tables. 24-bit precision (`0x07F`) does not.
- A closed form, `a = ceil(8 max(j yk / r, j/8))` and `b = ceil(8 (j+1) yk / (r−1))`, gets 237
  of the 30856 spans wrong by one texel.

An exporter must replay the builder as above.

**The result has 1596 samples and 30856 entries.** Every pad byte is 0, and every sample owns
exactly the rows k = r − 1 to 55. Serialised little-endian and concatenated in this order,
the SHA-1 is `ce708fa9a3190076ec37df25bd7369435c875c13`:

1. the 1596 `[start, count]` pairs as `int32`;
2. the 30856 four-byte entries;
3. the 3249 `float32` distances;
4. the 114 `uint32` row offsets.

### The radius and the finish

`sub_428BC0` ends with three calls (`0x429723`–`0x429751`).

**`sub_429770(R8)`** runs only when `R8 != +0x24C`, and then updates the cache (`0x429723`,
`0x429743`):

```text
fill 0xC78 dwords of +0x244 with 0x01                  // 12768 bytes; byte 12768 is never set
base = 0x18F1                                           // row 56, col 57 (0x429797)
for i in 0..56, j in 0..56:
    if dist[57 i + j] <= R8:                            // test ah, 41h: equal counts as inside
        clear base - 113 i - j, base - 113 i + j, base + 113 i - j, base + 113 i + j
```

**The disc is centred one texel toward +x of the cone's centre.** It is at row 56, column
57, while the cone and the shadows use row 56, column 56. Where j = 56, the rightmost write wraps into the next
row's column 0. That needs `R8 ≥ 56`, a radius of 7 tiles or more, which no agent reaches:
the largest is 5.9 tiles, `R8 = 47.2`.

**`sub_429800`** ORs the radius mask into the cone mask over `0xC78` dwords.

**`sub_429830`** writes the image, for rows and columns 1 to 111 (`0x429871`–`0x42989B`):

```text
image[r][c] = 0x400000 - (m[r][c] << 21) - ((m[r-1][c] + m[r+1][c] + m[r][c-1] + m[r][c+1]) << 19)
```

It reads the outer ring as neighbours but never writes it, so the ring stays 0 from the
constructor's memset. It never reads the four corners.

## What the mask means

Only byte 2 of each image dword is ever non-zero:

```text
byte2 = 32 * visible(centre) + 8 * (number of visible 4-neighbours)     // 0, 8, 16, ... 64
```

**So the tint marks the visible floor.**

- A visible texel inside the visible area gets +64.
- A hidden texel next to visible ones gets 8 to 32. That makes a one-texel soft edge.
- A hidden texel inside the hidden area gets 0, and the draw skips it.

In emulation, with radius 5 and a 44° cone, 479 of 567 visible texels came out at `0x400000`
and 11662 of 11754 hidden texels at 0.

**If the agent's own cell blocks sight, nothing is drawn.** Sample 0 (r = 1, j = 0) holds
`{a = 0, b = 56}` for every k from 0 to 55. So a blocking agent cell stamps the whole
quadrant of each walked octant. Every walked octant starts at that same cell, so the whole
cone is hidden.

The overlay only approximates `sub_418310`'s notice test:

- it does not show the 2-tile circle within which an agent always notices;
- its occlusion comes from the 1/8-tile shadow table, not from `sub_412E30`'s quarter-cell
  ray;
- its disc is offset by 1/8 tile.

It is a picture of the test, not the test itself.

**Cost.** An 85° cone walks at most three octants; four would need `hi − lo > 90.0009`.
Each walked octant makes at most 1596 cell lookups, cached per cell, plus the span stamps.
This happens for one agent per frame.

## The draw, `sub_4298E0`

`sub_417440` (`ecx` = the agent) calls `sub_4298E0` with `ecx = agent+1128` and four
arguments (`0x417440`–`0x41745D`, `retn 8`):

- `x = agent+20` and `z = agent+28`, the agent's raw position, without the +0.5 the cell
  tests add;
- the camera, `game+12744`;
- the renderer, `game+1996`.

The pixels are the renderer's back-buffer image. `sub_4298E0` reads only its colour pointer
`+4` and its width `+0x14`, which also serves as the pitch.

**The projection** is the floor's, from `sub_4120A0`. The camera's `+4` and `+12` are its
logical x and z. Its `+0x2C` and `+0x30` are −400 and −300: `sub_405750` sets the extents to
800, 600, 400 and 300 (`0x405870`–`0x405885`), and the virtual at `0x409240` negates the half
extents.

```text
P(X, Z) = (trunc(48 (X - cam.x) - 48 (Z - cam.z) + 400), trunc(24 ((X - cam.x) + (Z - cam.z)) + 300))
T = P(x - 7, z - 7)   top          R = P(x + 7, z - 7)   right      // 7.0 at 0x4667B8
B = P(x + 7, z + 7)   bottom       L = P(x - 7, z + 7)   left
```

In port terms the corners are the ground points `(x ± 7, z ± 7)` under
`screen = (48 (x − z), 24 (x + z))`. Relative to the agent's anchor they sit at (0, −336),
(+672, 0), (0, +336) and (−672, 0), a 1344 × 672 diamond. `_ftol` truncates toward zero, not
down, so an off-screen vertex with a negative coordinate can sit up to one pixel from where
`floor` would put it.

**The raster** has two halves.

The top half covers rows from `Ty` to `Ry − 1`, between the edges T→L and T→R. The bottom
half covers rows from `Ry` to `By − 1`, between L→B and R→B. Rows are clipped to
`[top, bottom)`. The edges step in 20.12 fixed point with slope `(dx << 12) / dy`. Each span
covers pixels `xl >> 12` to `min(xr >> 12, 799)`. When `xl < 0`, the start is clamped to 0
and u and v are advanced to match. The texel is `image[dword_47F040[v >> 12] + (u >> 12)]`
(`0x429B70`–`0x429B88`). u follows +x and v follows +z. Sampling is nearest.

```text
top half, row k from the top vertex:   n = Ry - Ty + 1 (before clipping)
    left end (u, v)  = (0, k * (113 << 12) / n)          on T-L
    right end (u, v) = (k * (113 << 12) / n, 0)          on T-R
    along the span:  du = u_right / span,  dv = -v_left / span,  span = ((xr - xl) >> 12) + 1
bottom half, row k from Ry:            n2 = By - Ry + 1
    left end (u, v)  = (k * (113 << 12) / n2, 112 << 12) on L-B
    right end (u, v) = (112 << 12, k * (113 << 12) / n2) on R-B
```

**How the mask maps onto the floor (measured by emulation).** The divisors are the row count
plus 1 and the span width plus 1, so the steps fall short of the far edge. The top half
reaches only about texel 112.3 at R and L, and the bottom half is pinned at 112.0. Texel 113
is never sampled.

A fit over the emulated output gives `t ≈ 8.0 d + 56` on each axis, where t is the texel and
d the offset in tiles from the agent's position. So:

- texel c covers about `[(c − 56)/8, (c − 55)/8)` tiles;
- the pixel at the agent's own position samples texel (u 55, v 56);
- the mean signed bias is −0.47 texel in u and −0.23 in v.

The best affine reproduction maps UV (0, 0) to the top corner, (112/113, 0) to the right,
(112/113, 112/113) to the bottom and (0, 112/113) to the left. It matched 68–70 % of pixels
exactly at the two placements emulated here, with a mean |u error| of 0.09–0.14 texel; over
sub-pixel placements the share ranges from about 61 % to 80 % (see "The raster" under "In the
port"). Mapping UV 0 to 1 over the whole diamond matches only 31–45 %. The rest is per-row fixed-point jitter, which only a CPU rasteriser
reproduces. Together with the disc centred on column 57, the drawn disc sits about one
texel, 1/8 tile, toward +x of the cone's origin.

**Colour and blend.** A texel of 0 is skipped (`0x429B8B`). Any other texel is added to the
pixel with `paddusb` (`0x429B9D`), a saturating add on each of the four bytes. Only byte 2 is
non-zero.

**Byte 2 is blue.** The back buffer holds each pixel as the bytes `R, G, B, X`, that is the
dword `0x00BBGGRR`. Several things show it:

- `sub_42C460` hands the device's pixel format to `sub_456D50`, which picks the converter.
  For an `X8R8G8B8` surface, `sub_456C70` → `sub_456B40` swaps bytes 0 and 2. For
  `X8B8G8R8`, `sub_456C50` → `sub_456AB0` copies unchanged.
- The RGB565 converter `sub_459240` puts byte 0 into the red bits.
- `sub_42D1E0(r, g, b)` stores its arguments at bytes 0 to 2, and a name drawn with
  `(250, 180, 40)` comes out gold in the reference screenshot.

So **the tint adds 0 to 64 to blue only**, saturating, and leaves red and green alone.
`extract-sacked-assets/docs/graphics/pipeline.md` has the internal format and the converters
the other way round. An earlier reading of this overlay as red rested on that page and is
wrong.

The sprite payloads agree. [gui-assets.md](gui-assets.md) settles 32-bpp `SPRITECB` as
`(R, G, B, A)`: read that way, `CO_EFFECT_FEUER_PALETTE` runs from red through yellow to white,
and any other order turns it blue. So `pipeline.md`'s `B, G, R, 0` for those payloads is stale
too.

The reference screenshot `Zemsta-Urzedasa-3_wynik.jpg` has Klara Fall selected with the
player nearby. The corridor carpet averages (9, 69, 127) and (83, 109, 163) outside her cone,
and (7, 68, 189) and (83, 109, 226) inside it: +62 or +63 blue, with red and green unchanged.
Those are area averages of a JPEG rescaled to 640 × 480, so they are evidence of the tint, not
exact values. On a 16-bit display nothing is lost, because every addend is a multiple of 8.

**No Z.** `sub_4298E0` neither reads nor writes the Z plane at image `+8`, and it ignores the
blend mode at `a5[6]`.

**Clipping.**

- **x.** Hard-coded to 0 to 799 (`0x429B4C`/`0x429B54`, `0x429D36`/`0x429D3E`). This ignores
  the clip rectangle's left edge of 1, so column 0 can be tinted even though the world blits
  leave it as the backdrop. It also never goes past 799, even on a wider buffer.
- **y.** Clipped to `[a5[15], a5[17])`. For the world pass `Main_RenderUpdate` sets these to 1
  and `h − 91` (`0x402947`–`0x402989`). At 600 pixels high that is rows 1 to 508.
- **The console below.** The console frame is docked at y 400. In
  `images/gui/hud/console.png` the lowest pixel that is not fully opaque is on its row 109,
  screen y 509: 2 pixels there, 4 on row 108, and none from row 110 down. So every pixel the
  wavy edge uncovers has been painted by the 800 × 510 backdrop fill or the world pass, and
  nothing below y 510 is ever uncovered. That closes the question
  [hud-reference.md](hud-reference.md) had left open.

### Where it sits in the frame

`Main_RenderUpdate` (`0x4028C0`) draws in this order:

1. Clears Z to `0xFFFF` (`0x402906`).
2. Fills 800 × 510 pixels with the backdrop `0x4F1010`, which is (16, 16, 79)
   (`0x40291B`, `0x402923`).
3. Sets blend mode 5 and the world clip `(1, 1, w − 1, h − 91)` (`0x40292E`–`0x402989`).
4. **The floor**, `sub_4120A0(camera, 0)` (`0x40298C`). It goes through `sub_42D210` /
   `sub_458DC0`, which write no Z.
5. **`sub_402260`: the heading easing, and this tint** (`0x402993`).
6. The walls, `sub_4120A0(camera, 1)` (`0x40299C`). They are drawn in mode 5, which writes Z.
7. The items, `sub_411E20` (`0x4029A4`).
8. The characters, in mode 7 (`0x4029AF`–`0x402B2C`). Each agent's draw `sub_417460` adds its
   bubble, name and shadow.
9. The effects list, in mode 14 (`0x402B38`–`0x402CB2`).
10. Resets the clip (`0x402CB8`–`0x402CD1`), then draws the GUI (`0x402CDE`), the rising scores
    and the cursor.

**So only the backdrop and the floor lie under the tint.** Everything drawn later overwrites
it wherever it is opaque: walls, items, character shadows and sprites, bubbles, names,
effects and the whole GUI. The tint shows only on floor that nothing covers, which makes it
read as a floor decal. The Matrix overlay in
[player-ability-reference.md](player-ability-reference.md) is painted later, in the character
loop, so it also tints this.

The port's `default_clear_color`, (16, 16, 74), is the backdrop's 79 after a trip through 5
bits (`79 >> 3 = 9`, `9 * 255 / 31 = 74`). The screenshot it was sampled from was probably
taken in an RGB565 mode; that is inferred.

## Not recovered

- **An exact raster.** A pixel-exact copy of `sub_4298E0` needs a CPU rasteriser. The affine
  UV mapping above matches 68–70 % of pixels at the two placements emulated here, and about
  61 % to 80 % over sub-pixel placements (see "The raster" under "In the port").
- **Sine and cosine precision.** Real x87 `fsin`/`fcos` can differ from the emulator's host
  `sin`/`cos` by one float32 ulp in rare cases. That could move a clip-triangle vertex by one
  texel, but only when `X` or `Y` sits exactly on an integer. It was not observed.
- **The retail display depth.** The display bit depth the retail game ran at is not known. The
  reference screenshots look like RGB565 captures.

## In the port

The `FieldOfView` node of `scenes/level/level_runtime.tscn` draws the tint, with the script
`scenes/level/field_of_view.gd`. Every generated level instances that scene, so no level had
to be regenerated.

### The tables

`tools/export_fov_tables.py` replays `sub_427DC0` as written above. It reads the builder's
constants from the executable:

- 0.125 at `0x465854`, 1.0 at `0x4652B8`, 0.0625 at `0x4667BC`, 7.0 at `0x4667B8` and 8.0 at
  `0x465878`;
- the immediates 10.0 at `0x427F79` (the `mov` at `0x427F75`) and −1000.0 at `0x427CEF` (the
  `mov` at `0x427CED`).

It writes `resources/original/fov_tables.json`: the 57 × 57 distances, the 114 row offsets,
and one line per sample, `[r, j, start, [a, b, …]]`, whose spans cover rows k = r − 1 to 55
in order.

Beside the tables the file carries five of the float32 constants the rest of the field of view
reads, each pinned at every instruction that reads it, opcode and operand:

- `gate_tiles`, the gate's 12.0 at `flt_4652CC` (`0x4022CF`, `0x4022E0`);
- `reach_tiles`, the 7.0 at `0x4667B8`: the builder's far edge (`0x427FF8`) and the diamond's
  corners `x ∓ 7`, `z ∓ 7` in `sub_4298E0` (`0x42991F`, `0x429944`, `0x429962`, `0x42996D`);
- `sector_scale`, the 0.022222 at `0x4667D4` (`0x4282BE`, `0x4282E1`). A negative `lo` is
  multiplied by `0x4667D0` instead (`0x4282CD`), which the tool checks is its exact negation;
- `texels_per_tile`, the 8.0 at `0x465878`: the builder's two `ceil(x * 8)` (`0x428024`,
  `0x42803F`) and `sub_428BC0`'s radius in texels (`0x428C00`);
- `sample_step`, the 0.125 at `0x465854`: the builder's four `fmul`s and its row step
  (`0x427E56`, `0x427E64`, `0x427E7F`, `0x427EE3`, `0x4280BD`), and the sixteen `fadd`s of
  `sub_428BC0`'s shadow walk, the minor and the major offset of each octant (`0x428D19`
  to `0x429708`).

The cone's degree constant, 0.017453 at `0x465540` (`0x428329`, `0x4285A1`), is the one the
smoke and the puddle aim with, so it is exported once, by `tools/export_view_angles.py` into
`resources/original/view_angles.json`, pinned at all of those readers.
`scenes/shared/field_of_view_mask.gd`'s `load_tables()` reads all six into `INVERSE_45`,
`DEGREES`, `GATE_TILES`, `REACH_TILES`, `TEXELS_PER_TILE` and `SAMPLE_STEP`, each rounded to
its float32, and `scenes/level/field_of_view.gd` takes the gate and the reach from there, so
none of them is typed into GDScript.

The mask's other constants stay literals: the 0.5 of `flt_4652B4` (the half cone at
`0x428277`, the near cell at `0x428BDE` and `0x428BF2`), the frame's 56.0, −56.0, 112.0 and
113.0 (`0x4667C8`, `0x4667CC`, `0x4667C0` and `0x4667C4`, 28 reads in `sub_428270`), its 0.0
(`0x4652E0`, 7 reads), and the −1000.0 `sub_427C80` answers for parallel lines (`0x427CED`,
`0x427CF3`), which the exporter reads only to replay the builder. Each is exact in float32,
and the goldens below pin the mask they build bit for bit.

`--check`, which `tools/run_checks.py` runs, pins `sacked.exe` by size and SHA-256. It
expects 1596 samples, 30856 entries and the SHA-1 `ce708fa9…` given above, taken over the four
tables serialised as listed there. `tests/test_fov_tables.py` rebuilds that serialisation
from the file alone, so the hash is checked even without the executable.

### The goldens

`tools/export_fov_goldens.py` runs the original's own build under unicorn. It calls
`sub_427DC0` once, then for each case `sub_428270` for the octants and `sub_428BC0` for the
mask and texels. It is run by hand, not by `run_checks.py`, and it skips when unicorn or the
executable is missing.

`tests/fixtures/fov_golden_masks.json` holds 76 cases:

- every radius and cone the profiles reach across the aggression band (25);
- headings around the circle at a cone of 60, with `lo` below 0 and `hi` past 360, plus
  −10, −45, −200, 365 and 720.5, which the eased heading never holds but the build accepts
  (19);
- `lo` or `hi` on a sector boundary, since `sub_428270` sectors those and not the heading
  (14). Six sit exactly on a multiple of 45 (`lo` 90, 0 and −45, `hi` 135, 360 and 45), which
  lands one sector low (see "The cone"). Eight sit on the first float32 of a sector and on the
  float32 just short of it: `lo` at 180.0018 and −45.00045, `hi` at 90.0009 and 360.0036. The
  tool finds those from the constant at `0x4667D4` and solves each heading so that `lo` or
  `hi` comes out exactly there;
- a blocking own cell, sight-blocking cells at every map edge, and agents off the map,
  including `x + 0.5` in (−1, 0), which truncates to cell 0;
- level 1's real sight cells at five positions and level 13's at four.

### The build

`scenes/shared/field_of_view_mask.gd` builds the mask and the texels bit for bit.
`tests/check_field_of_view.gd` compares it with every golden, forwards and then backwards
through one build object, so every cache is crossed.

Its inputs are rounded to the float32 the original keeps:

- **x and z**: the agent's raw position, from `CollisionMapLayer.to_grid_position`, without
  the +0.5;
- **the radius and the cone**: `NPCBrain.notice_radius_tiles()` and `notice_cone_degrees()`,
  widened by the band, the boss's unwidened;
- **the heading**: `npc.gd`'s `notice_heading`, which already eases `agent+1848` once per
  original frame (see [npc-reference.md](npc-reference.md));
- **the sight cells**: `CollisionMapLayer.sight_grid()`, `sight_blocked_cells` laid out over
  the map's own width and height (`room_grid_size`, the manifest's). That is INFODATA bit 1,
  the same cells the port's sight ray reads. Every other cell, on or off the map, is clear.

The port sums the band in doubles before rounding. In four of the 25 radius combinations that
lands one float32 step away from a float32 sum. No distance in the table lies between the
two, so the disc is the same.

A direct port took about 10 ms per build, because GDScript is far too slow to walk the bytes
the way the original does. So the port reaches the same bytes another way:

- The clear, the fills of the absent octants and the radius disc only ever set texels, and
  they depend only on the set of absent octants and on the radius. So they are one cached
  image per set of absent octants, dropped when the radius changes.
- Spans are written with `Image.fill_rect`. That includes a clip-triangle span that runs from
  column 112 into the next row's column 0, as the original's does.
- The walk looks each cell up once, not once per sample.
- The samples of a blocked stretch of cells are stamped together, as one span per row k. That
  is exact because no span is empty, a and b never shrink as j grows or grow as r grows, and
  the spans of neighbouring samples overlap, along j and along r. `tests/test_fov_tables.py`
  checks these properties on the tables, in both directions.
- An octant's shadows do not depend on the heading, so they are kept while the agent's
  position stays the same.
- The texels are computed eight at a time, one per byte of a 64-bit integer.

None of this changes a byte. The node builds only when an input has changed.

Measured in the running game (levels 1 and 13, at 800 × 600 and 1067 × 600), by timing
`mask.build` and the upload from a script outside the node; `tests/check_field_of_view.gd`
prints the mean over its golden builds:

- a build takes 0.56–0.76 ms on average, with a 95th percentile of 1.0–1.4 ms;
- the first builds, which fill the caches, take up to 3.3 ms;
- the texture upload takes about 9 µs.

### The gate

`FieldOfView.passes_gate` subtracts the player from the agent on each axis and compares with
`GATE_TILES`, signed and strict. It is written so that a NaN passes, as the unordered `fcomp` does. There is no
visibility test.

Level 1 shows what the sign does. The boss spawns at (1, 12), and no walkable cell lies 12
tiles toward −x or −z of him. So walking away from him never hides his tint.

### The draw

The tint is one polygon through the ground points `(x ∓ 7, z ∓ 7)` around the agent's raw
position (`REACH_TILES`), placed through the map's own axes by
`CollisionMapLayer.from_grid_position`.

- The UVs are (0, 0), (112/113, 0), (112/113, 112/113) and (0, 112/113). Sampling is
  nearest, with no repeat.
- The texture is R8 and holds each texel's blue.
- `scenes/shared/field_of_view.gdshader` discards a texel of 0 and adds (0, 0, blue) with
  `blend_add`. `hdr_2d` is off, so the 8-bit canvas saturates as `paddusb` does.
- Nothing tests or writes depth.

**The layer.** The node draws at `z_index` −10, absolute. That is above the floor bake at −20
(see [map-rendering.md](map-rendering.md)). It is below:

- the walls (−5) and the glass (−4);
- the objects and the world composite (0);
- every character and its shadow, the thought bubbles, the names and the score pop-ups;
- the HUD's canvas layers.

That is the original's order: the floor, then the tint, then everything else.

**Clipping.** The tint is not clipped, and this is a port choice. The original clips it to
rows [1, h − 91) and columns 0 to 799, but the port clips none of its world to the
original's `(1, 1, w − 1, h − 91)`: the floor, walls, items, characters and effects all run
to the canvas edges (see "The world is not clipped" in [widescreen.md](widescreen.md)). The
tint lies on that floor, so it stops wherever the floor stops.

- **At 800 × 600** the console is opaque from y 510 down, so below row 508 the tint can show
  only through the two pixels of row 509 the console does not fully cover (see "Clipping" in
  "The draw"). There the port tints the floor, where the original shows it untinted: the
  world's blits reach row 509 and the tint stops at 508. On row 0 the port draws the floor, and
  so the tint, where the original shows the backdrop.
- **On a wider canvas** the console covers only its centred 800-wide band. Beside it the floor
  shows down to the bottom of the canvas, and so does the tint on it. A clip at h − 91 would
  cut the tint there in a straight line across floor that is still drawn.

**The raster.** The corners are not truncated to whole pixels relative to the camera, as
`_ftol` does. Together with the affine UVs, this is the approximation described in "The draw"
above. How many pixels pick the same texel as the original's CPU raster depends on where the
agent and the camera fall within a pixel. It is between about 61 % and 80 %, usually two
thirds to three quarters:

- 65.8 % for level 1's boss and 67.8 % for its coworker, at their spawns at 800 × 600;
- 79.8 % and 78.5 % for the same two at 1067 × 600, where the diamond's corners fall on half
  pixels;
- 61.4 % to 78.1 % over twelve random sub-pixel placements.

Every other pixel is one texel off, never more. That is the original's per-row fixed-point
jitter. These figures replay `sub_4298E0` over the port's own texels and camera.

**Checked in the running game.** On a paused frame the tint was drawn, then hidden, and the
two frames compared:

- every pixel the tint changed, changed in blue only;
- each equals its texel through the affine mapping, apart from two groups:
  - pixels whose centre sits on a texel edge (24 at 800 × 600, 225 at 1067 × 600);
  - about 2,300 pixels under a character's translucent shadow, which is drawn over the tint
    and dims it.

On level 13 at 1067 × 600, with the agent 11.6 tiles toward +x of the player, the tint runs on
below row 509 in the strip right of the console band: about 3,500 pixels there, each its
texel, apart from about 130 under a chair's faint shadow. It changes no pixel under the band.
At 800 × 600 the same frame changes nothing below row 508.

### Divergences

- **The frozen office.** On the caught banner, behind the quit prompt and under the pause
  panel, the original keeps easing the heading and drawing the tint. On the banner a standing
  agent can even turn (see "The trigger"). The port pauses its tree on all three (see
  [catch-reference.md](catch-reference.md)), so the node keeps the last mask it drew: the tint
  stays on the floor, frozen, until the tree runs again. The duel hides the world behind an
  opaque canvas layer, much as screen 5 draws no world.
- **The raster**: the affine UV mapping above, which picks the original's texel for about
  61–80 % of pixels, and is one texel off on the rest.
- **The clip**: none, where the original clips to rows [1, h − 91) and columns 0 to 799 (see
  "Clipping" above).

### Tests

`tests/check_field_of_view.gd` also covers:

- the six constants the mask and the node load: the bit patterns of the sector constant and
  the degree constant, the gate's 12.0, the diamond's 7.0, the 8.0 texels a tile and the
  shadow walk's 0.125;
- the gate at exactly 12.0 on each axis;
- no tint without a selection or past the gate, and a tint 40 tiles off toward −x and −z;
- the node's mask equal to a direct build from the boss's heading, radius and cone and level
  1's sight cells;
- the diamond's corners at (0, −336), (672, 0), (0, 336) and (−672, 0) from the anchor;
- the shader, which takes no clip, the nearest sampling and `hdr_2d`;
- the draw order against:
  - the floor bake, the walls and the glass;
  - the objects and the world composite;
  - every child of every character;
  - the score pop-ups and the console's layer;
- no rebuild while nothing moves, and one rebuild per change of heading;
- the last mask kept while the tree is paused;
- no use of the player's data: neither script refers to it, and the check's own stores stay
  unwritten.
