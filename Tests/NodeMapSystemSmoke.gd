extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var game_director: Node = await _spawn_game()
	if game_director == null:
		return

	var macro_map := game_director.get_node("MainWorld") as MacroGameManager
	if macro_map == null:
		_fail("Macro map did not initialize.")
		return

	await process_frame
	await process_frame

	var snapshot := macro_map.build_node_map_ui_snapshot()
	for key in [
		"active_node_id",
		"travel_mode",
		"pending_exit_direction",
		"available_nodes",
		"next_nodes",
		"advance_hint",
		"nodes",
		"edges",
		"blood",
		"hunger",
		"thirst",
		"fatigue",
		"pain",
		"shock",
		"consciousness",
		"morale",
		"emergencies",
		"equipment",
		"current_capacity",
		"maximum_capacity",
	]:
		if not snapshot.has(key):
			_fail("Node map snapshot missing key: %s" % key)
			return

	if str(snapshot.get("active_node_id", "")) != MacroGraphGenerator.HUB_ID:
		_fail("Expected campaign to start at hub.")
		return

	var nodes: Array = snapshot.get("nodes", [])
	if nodes.is_empty():
		_fail("Node map snapshot has no visible nodes.")
		return
	var hub_entry: Dictionary = {}
	for entry in nodes:
		if entry is Dictionary and str(entry.get("id", "")) == MacroGraphGenerator.HUB_ID:
			hub_entry = entry
			break
	if hub_entry.is_empty():
		_fail("Hub node missing from node map snapshot.")
		return
	if not bool(hub_entry.get("is_active", false)):
		_fail("Hub should be marked active in the snapshot.")
		return
	if bool(hub_entry.get("can_enter", false)):
		_fail("Active hub should not be enterable again.")
		return

	macro_map.open_node_map()
	await process_frame
	if not macro_map.is_node_map_open():
		_fail("open_node_map did not open NodeMapSystem.")
		return
	if macro_map.node_map_system == null:
		_fail("NodeMapSystem was not created.")
		return
	if macro_map.node_map_system.get_parent() != macro_map:
		_fail("NodeMapSystem must be owned by MacroGameManager, not MacroHudShell.")
		return
	if macro_map.node_map_system.layer != 30:
		_fail("NodeMapSystem layer should be 30 (below Event HUD).")
		return

	# Hex travel input must be gated while the map is open.
	var travel_key := InputEventKey.new()
	travel_key.pressed = true
	travel_key.keycode = KEY_T
	macro_map._unhandled_input(travel_key)
	await process_frame
	if not macro_map.is_node_map_open():
		_fail("Travel shortcut closed the node map unexpectedly.")
		return

	macro_map.close_node_map()
	await process_frame
	if macro_map.is_node_map_open():
		_fail("close_node_map did not close NodeMapSystem.")
		return

	# Directional travel becomes available only after an outward rim step.
	var north_rim := HexCoordUtils.rim_anchor(
		GameEnums.MacroTravelDirection.NORTH,
		GameEnums.MACRO_ZONE_RADIUS
	)
	macro_map.debug_teleport_player(north_rim)
	if not macro_map._try_begin_directional_exit(north_rim, north_rim + Vector2i(0, -1)):
		_fail("North rim step did not open directional travel.")
		return
	await process_frame
	var refreshed := macro_map.build_node_map_ui_snapshot()
	if not bool(refreshed.get("travel_mode", false)):
		_fail("Boundary-opened node map is not in travel mode.")
		return
	var next_nodes: Array = refreshed.get("next_nodes", [])
	if next_nodes != ["north_random_1"]:
		_fail("North exit exposed wrong destinations: %s" % str(next_nodes))
		return
	var next_id := str(next_nodes[0])
	macro_map.node_map_system.emit_signal("enter_node_requested", next_id)
	await process_frame
	await process_frame

	if macro_map.is_node_map_open():
		_fail("Successful Enter should auto-close the Node Map System.")
		return
	if macro_map.campaign == null or macro_map.campaign.active_node_id != next_id:
		_fail("Enter flow did not switch the active campaign node.")
		return

	if macro_map.player_token.current_hex_coords != HexCoordUtils.rim_anchor(
		GameEnums.MacroTravelDirection.SOUTH,
		GameEnums.MACRO_ZONE_RADIUS
	):
		_fail("North travel did not spawn on destination south rim.")
		return
	if macro_map.map_visualizer.boundary_preview_polygons.size() != 78:
		_fail("Radius-13 boundary preview did not render 78 cells.")
		return

	print("[TEST PASS] Node Map inspection, directional travel, and opposite-rim arrival.")
	quit(0)


func _spawn_game() -> Node:
	var main_scene := load("res://SystemCore/game_director.tscn") as PackedScene
	if main_scene == null:
		_fail("Could not load game director scene.")
		return null
	var game_director := main_scene.instantiate()
	root.add_child(game_director)
	await process_frame
	await process_frame
	return game_director


func _fail(message: String) -> void:
	push_error("[TEST FAIL] %s" % message)
	quit(1)
