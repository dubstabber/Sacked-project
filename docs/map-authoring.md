# Making a map in Godot

A custom map is a level scene built from the game's own art and played from the main menu's
**Custom levels** button. Everything below is done in the Godot editor; no import step and no
tool run is needed.

## 1. Start from the template

Open `scenes/custom_level_template.tscn` and use **Scene → Save Scene As** to save a copy in
`res://custom_levels/`, for example `res://custom_levels/my_office.tscn`. The template is level 1's
office:

- its floor, walls, movement cells, rooms and sight blockers, and the player's spawn;
- one furnished desk, the cola machine and the windows;
- one coworker, who finds the desk himself when the level starts.

Copying a campaign scene (`scenes/level_N.tscn`) works just as well. Never edit the campaign
scenes themselves: `tools/import_original_level.py` regenerates them.

Then give the map an entry on the Custom levels screen. In the FileSystem dock, right-click
`custom_levels/`, choose **New Resource… → CustomLevelInfo**, and fill in:

- **Title** and **Description**, shown as written in every language;
- **Scene**, your `.tscn`;
- **Author**, optional.

The screen lists every `CustomLevelInfo` in that folder. `custom_levels/sample_office.tres`
is the template's own entry.

## 2. The layers under `World`

The grid is 96 × 48 pixels; floor images stay their original 94 × 48. Select a layer, then
paint with its TileSet palette. The room and sight layers open hidden so the art stays
readable; click the eye beside one in the Scene dock to show it while you paint.

| Layer | What it is | In play |
| --- | --- | --- |
| `FloorTileMapLayer` | the floor | drawn as one baked image, so a cell changed at run time would not show ([map-rendering.md](map-rendering.md)) |
| `WallTileMapLayer` | the walls | depth-tested against everything per pixel |
| `CollisionTileMapLayer` | red diamonds: cells nobody can walk on | hidden; its `Enabled` property turns collision off |
| `RoomTileMapLayer` | the room each cell belongs to | hidden |
| `SightTileMapLayer` | blue diamonds: cells that block sight | hidden |

**Movement.** Collision is painted separately from the art, as in the original. Unpainted
space is walkable, including outside the floor, so paint a blocked perimeter. When you move
furniture or walls, move their red cells too. Characters have a 0.35-tile footprint and slide
along walls. Some objects in the original are meant to be walked through. See
[collision-reference.md](collision-reference.md).

**Rooms.** Each room diamond's alternative tile is a room number from 0 to 31. The editor
writes the number on every painted cell, and the TileSet's `room_name` custom data names the
known ones. An unpainted cell is room 0. Rooms decide two things:

- **Which objects a colleague uses for which need.** Each archetype has a room mask per goal
  ([npc-reference.md](npc-reference.md)). For example, a coworker drinks and eats in rooms 0,
  1 and 3, and works in rooms 0 and 2. An object counts as being in the room painted under its
  anchor.
- **What smoking pays.** Room 3 (waiting room), 4 (server room) and 8 (boss office) each pay
  their own score; anywhere else pays the general one
  ([player-ability-reference.md](player-ability-reference.md)).

**Sight.** Blue cells stop line of sight: a colleague cannot see you through them, and your
reach to an object is checked across them. Put them under walls. A few cells in the original
block sight but not movement, or the other way round, which is why the two are separate
layers.

**Map size.** `CollisionTileMapLayer`'s `Map Size` bounds the rooms, the sight grid and the
field of view. Leave it at zero and it follows the floor's painted extent.

## 3. Objects

Drag any scene from `scenes/objects/` onto `World/Objects`, or duplicate an object already
there. Each prefab is a complete object: its image, its depth mask, its pivot and its
`InteractionPoint`. The `InteractionPoint` holds the object's record: its type, its pranks
and where a person stands to use it. So a dropped object can be pranked and used by
colleagues as it is. Its room is read off the room layer wherever it stands.

- **Placing.** Move the object's root; its position is the object's ground anchor. Rotation,
  scaling and flipping are not supported by the depth masks. For another direction, use the
  prefab with the other angle in its name (`-000`, `-090`, `-180`, `-270`).
- **Order.** The order of `World/Objects`' children breaks depth ties, with later children
  drawn in front, and is the order objects are searched in.
- **Names.** A prefab's file name is its sprite. Its `display_name` metadata is the object's
  name in the original's object database.
- **Leave the textures alone.** `Color Texture`, `Depth Texture` and `Pivot` belong together,
  as the prefab supplies them.

## 4. Coworkers and the player

Drag `scenes/npc/coworker.tscn` under `World` and set its **Profile** to one of the seven in
`scenes/npc/profiles/`: boss, secretary, janitor, male employee 1 or 2, female employee 1 or 2.

When the level starts, every coworker without a desk searches for one as the original does
(`scenes/npc/npc_startup.gd`):

- the first free workstation monitor within growing radii of where it stands;
- then a chair within 3 tiles of that.

The boss and the janitor never take a desk, and a colleague who finds none works only at other
equipment. Place at most one boss, one secretary and one janitor. The original never creates
a second of any of them, and a second one placed here gets no desk.

Move `World/Player` to where the player starts.

## What the editor shows you

- **The Objects dock** (`addons/sacked_map_tools`, beside Scene and Import) lists every
  prefab with its picture and its name from the original's object database. Search it by
  name, or filter it by the database's category: General, Office, Kitchen, WC, Boss, Active,
  Lounge, Foyer, Janitor or Meeting.
  - Drag an entry into the 2D view to place it where you drop it.
  - Double-click an entry to drop it into `World/Objects` at the centre of the view. This can
	be undone.
- **Characters** show their idle frame from their profile and initial direction, where the
  game will draw them. It is drawn by an `EditorPreview` child that frees itself in play and
  saves nothing.
- **Each `InteractionPoint`** is marked:
  - orange where the player can prank;
  - green where only colleagues go;
  - grey for a decoration nobody uses.
- **An object's Inspector** offers a `Tile Position` beside its `Position`: its anchor in
  tiles, the grid the original places items on. Editing it moves the object, and it is never
  saved.
- **Warnings** (the yellow triangle in the Scene dock):
  - an object warns when it has no image, no depth mask or no `InteractionPoint`, or when it
    is rotated or scaled;
  - `WorldDepthCompositor` warns for the whole map, when a layer, the player or
    `LevelRuntime` is missing, or when there is more than one boss, secretary or janitor.

## 5. The level's goal

Select `LevelRuntime`. Its four exported values are the time limit and score target of the
time game and of the points game. A value left at 0 falls back to the original's defaults:
1200 s and 10000 points. See [game-rules-reference.md](game-rules-reference.md).

## 6. Try it

- **F6** runs the scene on its own. It shows its result but records nothing, as it is no
  campaign level.
- **`python3 tools/run_checks.py --filter custom`** checks every map in `custom_levels/`:
  - it loads, and every resource it depends on exists;
  - it has every layer, compositor and node a level needs;
  - every object carries its `InteractionPoint`, and every coworker a known profile;
  - it plays for twenty seconds with nothing failing.
- **The main menu's Custom levels button** plays it as a player will. A win records the map's
  own best time or score and leaves the campaign's progress alone.

## What not to do

- Do not run the original-level importer or scene builder over a map of your own. They only
  rebuild the campaign from the original game's data, and replace what they generate.
- Do not remove `WorldDepthCompositor` or `CharacterDepthCompositor`. They draw every wall,
  object and character with its per-pixel depth, rebuilt from the scene, so edits made in the
  editor show too.
- `GlassTileMapLayer` is an ordinary overlay without depth masks, and is empty in the
  campaign.
