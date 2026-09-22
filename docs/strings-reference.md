# Strings and language selection

The original ships in one language per build, with every string compiled in. Two retail
builds are in hand, so two of the port's three languages are **generated**:

| Language | Source |
| --- | --- |
| Polish | `sacked/sacked.exe`, the Polish release |
| German | `Gefeuert/Gefeuert.exe`, the German original it was localised from |
| English | authored, in `resources/i18n/translations.json` |

Nothing is typed by hand where a build already holds it, and the exporter rejects an
authored string for a language a build provides, so the two cannot drift apart.

## The text table

One `char*` table holds every string a build draws: **`0x46BD04`** in the Polish image, where
it ends exactly at the icon-name table at `0x46C100`, and **`0x46DD1C`** in the German one.
Each is **255 slots**.

| Slots | Contents |
| --- | --- |
| 0–155 | prank action names |
| 156–253 | every UI string, grouped per screen |
| 254 | NULL |

The code reads slots as globals rather than referencing the literals, so the slot index is
the stable identity. A NULL slot closes each screen's group, and those NULLs are the table's
own punctuation: **189, 192, 199, 208, 212, 220, 224, 232, 254**. `tests/test_strings.py`
pins them, because losing one means the walk has drifted.

**The slot index means the same thing in both builds.** The nine NULLs fall in the same
places, and the three strings the Polish translator missed — `Nullnummer`, and action names
127 and 143 — sit at the same slots in each. That is what lets one key read both tables.

`tools/export_strings.py` walks the table and requires every slot from 156 up to be claimed
exactly once, by a key or by the unused list. A build with one more string fails the export
rather than silently dropping it.

### Groups, by slot

| Slots | Screen | Keys |
| --- | --- | --- |
| 156–161 | pause panel and quit prompt | `prompt.*` |
| 162–165 | best score and time formats | `highscore.best_*` |
| 166–167 | thermometer banner, pause label | `hud.thermo_warning`, `prompt.paused` |
| 168–171 | **unused** press-demo leftovers | — |
| 172–178 | result and pause buttons | `result.*`, `common.*` |
| 179–182 | the catch exclamations, in `rand() & 3` order | `catch.exclaim.0..3` |
| 183–188 | main menu | `menu.*` |
| 190–191 | level tree | `level_tree.title`, `common.main_menu` |
| 193–198 | level description | `description.*` |
| 200–207 | highscore screen, including its four page tabs | `highscore.*` |
| 209–211 | coworker names screen | `names.title` |
| 213–219 | player setup, and the highscore name prompt | `character_select.*`, `character.*` |
| 221–223 | sound setup | `sound.title` |
| 225–231 | seven difficulty labels, easiest first | `difficulty.0..6` |
| 233–253 | **21 level titles** | `level.<n>.title` |

Slots 168–171 (`Rozpocznij poziom 1..3`, `Gamestar Redaktion`) are left over from a press
build for a German games magazine. No screen reaches them; the exporter asserts their
contents and then ignores them.

A handful of strings are reused across screens — `Główne menu` on seven, `Kontynuuj` on
three, `Domyślne` on three. Those share one key, and the exporter asserts the slots really
do decode identically rather than trusting the layout.

### Level titles run upward from slot 233

`level.<n>.title = slot 232 + n`, so level 1 is `Pierwszy ostatni dzień` and level 21 is
`Biuro Paradiso`. The direction is not an assumption: four titles run straight into their own
description and would be nonsense reversed.

| Level | Title | Description begins |
| --- | --- | --- |
| 4 | `Tyle pracy...` | `...i tak mało czasu!` |
| 6 | `Jak wół w polu...` | `...tak twoi byli koledzy zaharowują się` |
| 9 | `By zagrać na nerwach byłym kolegom...` | `...niezbędne mogą okazać się niezwykłe metody.` |

### Action names come from the records, not the slots

Slots 0–155 hold the action names, but a record's name pointer is not always its own slot.
Thirty of the 156 alias another: twenty-seven share the `...` placeholder at slot 64, and a
handful genuinely reuse a neighbour's wording — 136 takes slot 135, 151 and 152 take slot
150, 154 takes slot 84 and 155 takes slot 92.

`export_strings.py` traces that record-to-slot map out of the Polish initializer, through
`export_action_table.py`, and then applies the same map to **both** tables. That is how the
German names are read by record id without tracing a second initializer, and it is checked:
the two German leftovers must come back identical to their Polish counterparts. The 27
actions whose name is the placeholder get no key, and neither does action 0, which is never
drawn.

### Level descriptions

Each build carries its own: `sacked/Levels/Level_XX.txt` in cp1250 and
`Gefeuert/Levels/Level_XX.txt` in cp1252, both CRLF. The Polish files are all exactly six
lines; the German ones vary, two wrapping the description over two lines and several carrying
trailing blanks. So the split is made on the `%s` rather than on line numbers: everything
before it is the description, everything after it the hint. The Polish shape is:

```
<description paragraph>
<blank>
%s
<blank>
<blank>
<hint paragraph>
```

The `%s` is where the game writes the level's objective, in the same wording the pause panel
uses. A screenshot of the description screen confirms it: level 1 shows
`Aby ukończyć ten poziom, musisz zdobyć 4000 punktów w ciągu 6 minut.` between its two
paragraphs, which is slots 158 and 159 run together. The `%s` is therefore structure rather
than text, so only the two paragraphs are exported, as `level.<n>.description` and
`level.<n>.hint`, and the screen composes the middle line from `prompt.time_goal` and
`prompt.time_goal_format`. The exporter asserts the layout.

## What is German already

The Polish release is a localisation of a German original, and three strings were missed.
They are the cheapest proof that the slot index lines up across the two builds, so the
exporter checks them rather than merely noting them:

| Key / address | Text |
| --- | --- |
| `app.window_title` @ `0x46E004` | `Gefeuert! - Dein letzter Tag` |
| `action.127.name` | `Unendlich viele Kopien des Adonishinterns anfertigen` |
| `action.143.name` | `Globus mit Klopapier umwickeln` |

Those keep their German verbatim in the German column. `NAMES.DAT`'s fifteen coworker names
are German puns the Polish release also left alone; when that screen is built they are proper
nouns, not translatable text.

## Keys the original has no wording for

Four, each declared in `PORT_STRINGS` with its reason:

| Key | Polish | Why |
| --- | --- | --- |
| `hud.console.time_label` | `czas` | painted into the console art |
| `hud.console.score_label` | `wynik` | painted into the console art |
| `character_select.name_label` | `Imię gracza` | the original's name box is unlabelled art |
| `level_tree.level_n` | `Poziom %d` | the interim tree names levels the original draws as nodes |

The port previously invented `Wybierz poziom` and `Wstecz` for the tree. Both are gone: the
original's own screen-15 wording is slots 190 and 191, `Wybór poziomu` and `Główne menu`.

## The two painted words

`console.png` has `czas` and `wynik` painted into it, each over the *other* field — the
original's own mistake, which the port keeps. They are the only Polish baked into a sprite
the port ships. `export_gui_assets.py` derives `console-unlabelled.png` from the same decoded
sprite by flooding two measured boxes with the frame's flat blue `(74, 109, 230)`:

| Word | Box |
| --- | --- |
| `czas` | `(91, 72)`–`(134, 88)` |
| `wynik` | `(236, 67)`–`(293, 98)` |

Those boxes contain nothing but the lettering and that flat blue, so the fill leaves no seam.
Polish draws the original art; every other language draws the erased copy plus two Labels at
the same places, keeping the swap.

The German build ships its own console sprite in its own `CO_GUI.OGD`, with whatever German
words it paints there. Extracting that container would replace the two authored German
labels with the build's own and settle whether the German release repeats the swapped-labels
bug. It is not done: the only gain is two short strings, against extracting a 15 MB archive.

`loading.png` also carries Polish, the hand-lettered title `zemsta urzędasa`. That is the
Polish edition's box art rather than a UI string, so it stays as a logo in every language.

## How it loads

`resources/original/strings.json` is generated and holds Polish and German.
`resources/i18n/translations.json` is authored and holds **only what neither build has
wording for**: English throughout, plus German for the four port strings. The exporter fails
if the authored file names a language a build already provides, which is what stops the two
drifting apart.

The `I18n` autoload builds one `Translation` per language at boot and registers it with
`TranslationServer`, so `tr()` and a Control's own auto-translation both work. Scenes put the
key straight in `text`; scripts call `tr()` and then format. `project.godot` sets
`locale/fallback="pl"`, so a key an authored language happens to miss shows Polish rather
than the raw key.

Godot's CSV translation importer is deliberately **not** used: a `.csv` under `res://` is
imported into binary `.translation` siblings that are regenerated on every `--import` and are
neither tracked nor ignored by this repo.

### Resolution order

1. `--lang=xx` after `--` on the command line, e.g. `./Godot_v4.7.2-stable_linux.x86_64 . -- --lang=en`
2. `[locale] language` in `user://settings.cfg`
3. `OS.get_locale_language()`
4. Polish

There is no language screen yet. It belongs on the original's sound-setup screen, which is
the first item of the backlog. In a debug build **F2** cycles the languages, which is the
only way to watch a running level change language.

### Fonts are not a constraint

The port draws every string with Godot's default font, which covers Polish, German and
English. `tests/check_i18n.gd` turns that from an assumption into a fact by asking the
fallback font for every character of every string in every language.

The original bundles `International.ttf` and registers it, then builds all five of its fonts
from Arial. That is not an oversight: the bundled face has no Polish diacritics at all and no
`ß`, so it could not have drawn the UI of the very release that ships it.

## The quit prompt's answer keys

The prompt reads `(T)ak lub (N)ie` and answers to the initials it names. Those initials are
therefore part of the translation, not constants: `prompt.quit_yes_key` and
`prompt.quit_no_key` are **derived** by the exporter from the answer text, and the check
rejects an initial the answer does not name.

| Language | Answer | Yes | No | Source |
| --- | --- | --- | --- | --- |
| pl | `(T)ak lub (N)ie` | T | N | generated |
| en | `(Y)es or (N)o` | Y | N | authored |
| de | `(J)a oder (N)ein` | J | N | generated |

The German row was authored before the German build arrived, and the build turned out to
say it character for character — a useful accident, and the reason the rule is checked rather
than trusted.

`level_prompts.gd` binds them with `OS.find_keycode_from_string` and rebinds on a language
change. It matches on `keycode`, the label a key carries, not `physical_keycode`, so a German
player presses the J their own prompt names.

## Rules for anything built later

- A screen shows text only through a key that exists in `export_strings.py`, either as a slot
  mapping or as a `PORT_STRINGS` entry with a reason recorded here. A slot mapping gives
  Polish and German for free; anything else has to be authored in `translations.json`.
  `--check` fails otherwise, in both directions: a missing authored string and an authored
  string that duplicates a build's own.
- Scenes put keys in `text`; scripts `tr()` then format. A formatted string cannot
  auto-translate, so its owner rebuilds it on `NOTIFICATION_TRANSLATION_CHANGED`.
- Painted words follow the console recipe: original art for the language it is painted in,
  an exporter-derived erased copy plus a keyed Label for the rest. The catch minigame's four
  banners are the next case.
- A translation keeps the same `%` tokens in the same order; Godot's `%` is positional. The
  token pattern deliberately rejects printf's space flag, because one German action name
  reads `85% der Menschheit leben ohne Klopapier` and that literal percent is not a
  conversion.
- A test that reads text pins the language first.
