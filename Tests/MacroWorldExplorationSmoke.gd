extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var main_scene := load("res://SystemCore/game_director.tscn") as PackedScene
	var game_director := main_scene.instantiate()
	root.add_child(game_director)
	await process_frame
	await process_frame

	var macro_map := game_director.get_node("MainWorld") as MacroGameManager
	var world_state := root.get_node("WorldState") as RuntimeStateStore
	if macro_map == null or world_state == null or macro_map.macro_hud == null:
		_fail("Macro world systems did not initialize.")
		return

	var origin := macro_map.player_token.current_hex_coords
	var origin_hex := macro_map.world_generator.get_hex_at(origin)
	if not origin_hex.is_explored:
		_fail("Initial macro hex was not marked explored.")
		return

	var target := origin + Vector2i(1, 0)
	macro_map._select_hex_for_hud(target)
	await process_frame
	var snapshot: Dictionary = macro_map.macro_hud.get("_snapshot")
	var selected_hex: Dictionary = snapshot.get("selected_hex", {})
	if selected_hex.get("coords", Vector2i.ZERO) != target:
		_fail("World HUD did not receive the selected hex descriptor.")
		return
	for detail_key in [
		"feature_title",
		"environment_summary",
		"movement_note",
		"visibility",
		"cover",
		"resource_hint",
		"water",
	]:
		if str(selected_hex.get(detail_key, "")).is_empty():
			_fail("Selected hex detail is missing: %s" % detail_key)
			return
	if not selected_hex.get("can_travel", false):
		_fail("Adjacent passable selected hex was not travel-enabled.")
		return

	var poi_coords := Vector2i(4, 0)
	_ensure_demo_homestead(macro_map, world_state, poi_coords)
	macro_map.debug_teleport_player(poi_coords + Vector2i(-1, 0))
	await process_frame
	macro_map.debug_step_player_to(poi_coords)
	await process_frame
	if str(macro_map.get("_last_macro_event")).is_empty():
		_fail("Hex step did not write exploration log feedback.")
		return
	var poi_hex := macro_map.world_generator.get_hex_at(poi_coords)
	if not poi_hex.has_landmark():
		_fail("Demonstration landmark was not present at (4, 0).")
		return
	macro_map.begin_poi_interaction(poi_coords, poi_hex)
	await process_frame
	if not macro_map.exploration_window.is_open():
		_fail("Exploration window did not open for the demonstration landmark.")
		return
	if not macro_map.macro_hud.is_event_open():
		_fail("Exploration stage did not enter POI presentation mode.")
		return
	var exploration_panel := macro_map.exploration_window.get("_panel") as Control
	if exploration_panel == null or not exploration_panel.visible:
		_fail("POI exploration panel was not visible on the stage overlay.")
		return
	if exploration_panel.get_parent() != macro_map.exploration_window:
		_fail("Exploration panel should remain owned by MacroExplorationWindow.")
		return
	var session: Dictionary = macro_map.exploration_window.get("_session")
	if session.get("search_options", []).size() < 2:
		_fail("SEARCH did not expose multiple landmark target options.")
		return
	if not session.get("camp_allowed", false):
		_fail("CAMP was not allowed at the demonstration landmark.")
		return
	if macro_map.debug_requirements_met({"any_item_ids": ["not_a_real_key"]}):
		_fail("Missing item requirements incorrectly unlocked a target.")
		return
	macro_map.close_macro_interaction()
	await process_frame

	var movement_origin := Vector2i(0, 0)
	macro_map.debug_teleport_player(movement_origin)
	await process_frame
	var travel_target := movement_origin + Vector2i(1, 0)
	if not macro_map.world_generator.get_hex_at(travel_target).is_passable():
		travel_target = movement_origin + Vector2i(0, 1)
	macro_map._execute_player_step(travel_target)
	await process_frame
	if str(macro_map.get("_last_macro_event")).is_empty():
		_fail("Hex step did not write exploration log feedback.")
		return

	print("[TEST PASS] Macro exploration HUD, travel beats, and stage POI update together.")
	quit(0)


func _ensure_demo_homestead(
	macro_map: MacroGameManager,
	world_state: RuntimeStateStore,
	coords: Vector2i = Vector2i(4, 0)
) -> Vector2i:
	var hex := macro_map.world_generator.get_hex_at(coords)
	hex.rock_layer = GameEnums.MacroRockLayer.NONE
	hex.water_layer = GameEnums.MacroWaterLayer.NONE
	hex.structure_layer = GameEnums.MacroStructureLayer.STRUCTURES
	hex.is_poi = true
	hex.landmark_id = "homestead_b"
	hex.poi_id = "plains_homestead"
	hex.poi_name = "Abandoned Homestead"
	hex.sleep_anchor = "ground"
	macro_map.world_generator.world_hex_cache[coords] = hex
	world_state.set_hex_record(coords, hex.to_state())
	return coords


func _fail(message: String) -> void:
	push_error("[TEST FAIL] " + message)
	quit(1)
