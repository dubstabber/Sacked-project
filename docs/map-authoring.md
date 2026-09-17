# Making a map in Godot

Open `scenes/level_1.tscn` and use **Scene → Save Scene As** to create your own scene. The saved scene is the map: moving objects or painting tiles does not require an import step. Run the current scene with **F6**.

1. Select `World/FloorTileMapLayer` and paint with its TileSet palette. Select `World/WallTileMapLayer` to paint walls. The grid is 96 × 48 pixels; floor images remain their original 94 × 48 pixels.
2. Drag a scene from `scenes/objects/` onto `World/Objects`, or duplicate an existing object. Move the object root to place its original ground anchor. The prefab carries its image, depth mask, and original pivot.
3. Move `World/Player` to set the starting position. Save and run the scene to check placement and movement.

Objects and wall tiles use the original per-pixel depth masks, so parts of intersecting images can cover one another. Keep `WorldDepthCompositor` and `CharacterDepthCompositor` in the scene. Their output is rebuilt from the nodes and tiles in that scene, including changes in the editor.

`GlassTileMapLayer` is an ordinary overlay without depth masks. It is empty in the imported level; glass intersections still need their original behavior established.

Place objects by translation. Rotation, scaling, and sprite flipping are not supported by the depth masks. To choose a different direction, use the corresponding object prefab. The `Color Texture`, `Depth Texture`, and `Pivot` fields on an object should normally stay paired as supplied by its prefab.

The `original_*` metadata records where imported objects came from; it does not override changes made in Godot. The JSON files in `resources/levels/` and the builders in `tools/` are only for reconstructing the reference level from the extracted game data. Do not run the original-level importer or scene builder over a map you have authored: those tools replace generated outputs. Custom scenes do not need them.
