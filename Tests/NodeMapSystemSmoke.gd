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
		"available_nodes",
		"next_nodes",
		"advance_hint",
		"nodes",
		"edges",
		"blood",
		"hunger",
		"thirst",
		"fatigue",
		"stance",
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

	# Complete hub so the next plains node unlocks, then enter via node map flow.
	macro_map.mark_node_completed(MacroGraphGenerator.HUB_ID)
	await process_frame
	macro_map.open_node_map()
	await process_frame
	var refreshed := macro_map.build_node_map_ui_snapshot()
	var next_nodes: Array = refreshed.get("next_nodes", [])
	if next_nodes.is_empty():
		_fail("Completing hub did not expose a next node.")
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

	print("[TEST PASS] Node Map System snapshot, open/close, and enter flow.")
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
