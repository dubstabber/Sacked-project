extends SceneTree

# What the editor tells a designer about a map (docs/map-authoring.md):
#
# - a MapObject warns when it would draw wrongly or do nothing, and a prefab warns of nothing;
# - an object offers its anchor in tiles beside its position, which moves it on the grid and
#   is never saved;
# - the world compositor warns of what a level is missing and of a second boss;
# - a character's EditorPreview finds its idle frame from the profile, and frees itself in
#   play;
# - an InteractionPoint is marked by what uses it.

const LEVEL := "res://scenes/level_1.tscn"
const PREFAB := "res://scenes/objects/aktiv-colamat-000.tscn"
const MapObjectScript := preload("res://scenes/shared/map_object.gd")

var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_check_object_warnings()
	_check_tile_position()
	_check_world_warnings()
	await _check_character_preview()
	if _failures == 0:
		print("Editor feedback: object and map warnings, the tile position, the character preview and its exit in play passed")
	quit(1 if _failures else 0)


func _check_object_warnings() -> void:
	var prefab := (load(PREFAB) as PackedScene).instantiate() as MapObject
	_expect(prefab._get_configuration_warnings().is_empty(), "a prefab warns of nothing, got %s" % prefab._get_configuration_warnings())
	prefab.rotation = 0.5
	_expect(_has(prefab._get_configuration_warnings(), "Rotated"), "a rotated object warns that the masks cannot turn")
	prefab.free()
	var bare := MapObjectScript.new() as MapObject
	var warnings := bare._get_configuration_warnings()
	_expect(_has(warnings, "No Color Texture"), "an object with no image says so")
	_expect(_has(warnings, "No InteractionPoint"), "and that it is only a decoration")
	bare.free()


func _check_tile_position() -> void:
	var level := (load(LEVEL) as PackedScene).instantiate()
	var object := level.get_node("World/Objects/Object036Colamat") as MapObject
	var tile: Vector2 = object.get(&"tile_position")
	var original: Vector2 = object.get_meta("original_tile_position")
	_expect(tile.is_equal_approx(original), "an imported object's tile position is its manifest tile, %s against %s" % [tile, original])
	object.set(&"tile_position", tile + Vector2(1, 0))
	var layer := level.get_node("World/CollisionTileMapLayer") as TileMapLayer
	var step := layer.map_to_local(Vector2i(1, 0)) - layer.map_to_local(Vector2i.ZERO)
	_expect(object.position.is_equal_approx(layer.map_to_local(Vector2i.ZERO) + step * (tile.x + 1.0) + (layer.map_to_local(Vector2i(0, 1)) - layer.map_to_local(Vector2i.ZERO)) * tile.y), "setting it moves the object one tile along x")
	var stored := false
	for property in object.get_property_list():
		if property["name"] == "tile_position":
			stored = int(property["usage"]) & PROPERTY_USAGE_STORAGE != 0
	_expect(not stored, "and it is never saved into the scene")
	level.free()


func _check_world_warnings() -> void:
	var level := (load(LEVEL) as PackedScene).instantiate()
	var compositor := level.get_node("World/WorldDepthCompositor")
	_expect(compositor._get_configuration_warnings().is_empty(), "level 1 is a whole map, got %s" % compositor._get_configuration_warnings())
	var second := (load("res://scenes/npc/coworker.tscn") as PackedScene).instantiate()
	second.set("profile", load("res://scenes/npc/profiles/boss.tres"))
	level.get_node("World").add_child(second)
	var player := level.get_node("World/Player")
	player.get_parent().remove_child(player)
	var warnings: PackedStringArray = compositor._get_configuration_warnings()
	_expect(_has(warnings, "no Player"), "a map without its player says so")
	_expect(_has(warnings, "boss profile"), "and a second boss is pointed out")
	player.free()
	level.free()


func _check_character_preview() -> void:
	var level := (load(LEVEL) as PackedScene).instantiate()
	for path in ["World/Npc079MaleEmployee1/EditorPreview", "World/Player/EditorPreview"]:
		var preview := level.get_node_or_null(path)
		_expect(preview != null, "%s exists" % path)
		if preview != null:
			var frame: Dictionary = preview._frame()
			_expect(frame.get("texture") is Texture2D, "%s finds its character's idle frame" % path)
	root.add_child(level)
	await process_frame
	await process_frame
	_expect(level.get_node_or_null("World/Player/EditorPreview") == null, "in play the preview frees itself")
	root.remove_child(level)
	level.free()


func _has(warnings: PackedStringArray, text: String) -> bool:
	for warning in warnings:
		if warning.contains(text):
			return true
	return false


func _expect(condition: bool, label: String) -> void:
	if not condition:
		_failures += 1
		push_error(label)
