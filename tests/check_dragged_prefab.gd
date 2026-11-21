extends SceneTree

# A prefab dragged out of scenes/objects/ into a map is a working object, because the prefab
# carries its InteractionPoint: the kind, the actions and the offset its CO_OBJECTS.DAT record
# gives it. Its room is read off the level's painted rooms wherever it stands. So a second
# Colamat dropped into level 1 beside the first:
#
# - carries the same record as the level's own Colamat;
# - is in the room painted under it, and follows it when moved;
# - is picked under the cursor like any other object;
# - joins every colleague's goal list the first Colamat is on.

const LEVEL := "res://scenes/level_1.tscn"
const PREFAB := "res://scenes/objects/aktiv-colamat-000.tscn"
const ORIGINAL := "World/Objects/Object036Colamat"

var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var level := (load(LEVEL) as PackedScene).instantiate()
	var runtime := level.get_node_or_null("LevelRuntime")
	if runtime != null:
		runtime.enabled = false
	var original: Node2D = level.get_node(ORIGINAL)
	var dropped := (load(PREFAB) as PackedScene).instantiate() as Node2D
	dropped.name = "DroppedColamat"
	# One tile to the side, on the same room's floor, as a designer would place it.
	dropped.position = original.position + Vector2(48, 24)
	level.get_node("World/Objects").add_child(dropped)
	root.add_child(level)
	for frame in range(4):
		await process_frame

	var point := dropped.get_node_or_null("InteractionPoint")
	var original_point := original.get_node("InteractionPoint")
	_expect(point != null, "a dropped prefab carries its InteractionPoint")
	if point == null:
		quit(1)
		return
	for field in ["category", "item_type", "group", "active", "orientation", "action_ids"]:
		_expect(point.get(field) == original_point.get(field), "it carries the record's %s, %s" % [field, original_point.get(field)])
	_expect(not (point.get("action_ids") as PackedInt32Array).is_empty(), "the Colamat offers pranks")

	var layer: CollisionMapLayer = level.get_node("World/CollisionTileMapLayer")
	var tile := layer.to_grid_position(dropped.global_position)
	var cell := Vector2i(floori(tile.x + 0.5), floori(tile.y + 0.5))
	var painted := int(layer.room_ids[cell.y * layer.room_grid_size.x + cell.x])
	_expect(int(point.get("room_id")) == -1, "the prefab leaves its room to the map")
	_expect(int(point.call("room")) == painted, "its room is the one painted under it, %d (got %d)" % [painted, int(point.call("room"))])
	_expect(int(point.call("room")) == int(original_point.call("room")), "the same room as the Colamat beside it")

	var prank: Node = level.get_node("World/Player/PrankController")
	var sprite := dropped.get_node("Sprite2D") as Sprite2D
	var centre := sprite.to_global(sprite.offset) + sprite.texture.get_size() * 0.5
	_expect(prank.call("_front_at", centre) == dropped, "the cursor over it picks it")

	var colleagues := 0
	for npc in get_nodes_in_group("npc_agents"):
		var brain := npc.get_node_or_null("Brain")
		if brain == null or not brain.has_method("is_initialized") or not brain.is_initialized():
			continue
		for goal in range(8):
			var candidates: Array = brain.get("_goal_candidates")[goal]
			if candidates.has(original_point):
				colleagues += 1
				_expect(candidates.has(point), "%s's goal %d lists the dropped Colamat beside the first" % [npc.name, goal])
	_expect(colleagues > 0, "some colleague's goal lists the level's own Colamat at all")

	# Moved into another room, it is in that room: nothing about the room is baked into it.
	var another := _cell_in_other_room(layer, painted)
	if another != Vector2i(-1, -1):
		var fresh := (load(PREFAB) as PackedScene).instantiate() as Node2D
		fresh.position = layer.to_local(layer.from_grid_position(Vector2(another)))
		level.get_node("World/Objects").add_child(fresh)
		var expected := int(layer.room_ids[another.y * layer.room_grid_size.x + another.x])
		_expect(int(fresh.get_node("InteractionPoint").call("room")) == expected, "dropped in room %d instead, it is in room %d" % [expected, expected])

	root.remove_child(level)
	level.free()
	if _failures == 0:
		print("Dragged prefab: a Colamat dropped into level 1 carries its record, finds its room, is picked and joins the colleagues' goal lists")
	quit(1 if _failures else 0)


func _cell_in_other_room(layer: CollisionMapLayer, room: int) -> Vector2i:
	var size := layer.room_grid_size
	for index in range(size.x * size.y):
		if int(layer.room_ids[index]) != room and int(layer.room_ids[index]) != 0:
			@warning_ignore("integer_division")
			return Vector2i(index % size.x, index / size.x)
	return Vector2i(-1, -1)


func _expect(condition: bool, label: String) -> void:
	if not condition:
		_failures += 1
		push_error(label)
