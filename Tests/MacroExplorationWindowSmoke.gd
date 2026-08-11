extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var game_director := await _spawn_game()
	if game_director == null:
		return
	var macro_map := game_director.get_node("MainWorld") as MacroGameManager
	var coords := _ensure_physical_hex(macro_map)
	if coords == Vector2i(99999, 99999):
		return _fail("Generated zone contains no physical interaction target.")
	macro_map.debug_teleport_player(coords)
	await process_frame
	var hex := macro_map.world_generator.get_hex_at(coords)
	macro_map.debug_begin_poi_interaction(coords, hex)
	await process_frame
	if not macro_map.macro_hud.is_location_open():
		return _fail("HERE did not own routine exploration interaction.")
	if macro_map.exploration_window.is_open():
		return _fail("Retired routine exploration window still owns input.")
	var snapshot: Dictionary = macro_map.macro_hud.get("_snapshot")
	var location: Dictionary = snapshot.get("current_location", {})
	if location.is_empty():
		return _fail("HERE did not publish a current-location snapshot.")
	if location.get("session", {}).get("world_affordances", []).is_empty():
		return _fail("HERE did not publish component-derived affordances.")
	print("[MacroExplorationWindowSmoke] PASSED")
	game_director.queue_free()
	quit(0)


func _spawn_game() -> Node:
	var main_scene := load("res://SystemCore/game_director.tscn") as PackedScene
	if main_scene == null:
		return _fail("Could not load the game director scene.")
	var game_director := main_scene.instantiate()
	root.add_child(game_director)
	await process_frame
	await process_frame
	return game_director


func _ensure_physical_hex(macro_map: MacroGameManager) -> Vector2i:
	for coords_value in macro_map.world_generator.world_hex_cache.keys():
		var coords := coords_value as Vector2i
		var value = macro_map.world_generator.world_hex_cache.get(coords)
		var candidate := value as MacroHexData
		if candidate == null or candidate.poi_id == "central_core" or not candidate.is_passable():
			continue
		if candidate.world_objects.is_empty():
			var object := WorldObjectRecord.new()
			object.object_id = "smoke_rubble_%s_%s" % [coords.x, coords.y]
			object.node_id = str(macro_map.campaign.active_node_id)
			object.coords = coords
			object.definition_id = "rubble"
			object.components = {
				"rubble": {"material_units": 3, "depleted": false},
				"container": {"finite": true},
				"dismantlable": {"methods": ["hands", "crowbar", "multitool"]},
			}
			candidate.world_objects = [object.to_dict()]
			candidate.poi_id = ""
			candidate.is_poi = false
			macro_map.world_generator.world_hex_cache[coords] = candidate
			(root.get_node("WorldState") as RuntimeStateStore).set_hex_record(coords, candidate.to_state())
		return coords
	return Vector2i(99999, 99999)


func _fail(message: String) -> Node:
	push_error("[MacroExplorationWindowSmoke] " + message)
	quit(1)
	return null
