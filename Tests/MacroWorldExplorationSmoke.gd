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
	if macro_map == null or world_state == null or macro_map.world_hud == null:
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
	var snapshot: Dictionary = macro_map.world_hud.get("_snapshot")
	var selected_hex: Dictionary = snapshot.get("selected_hex", {})
	if selected_hex.get("coords", Vector2i.ZERO) != target:
		_fail("World HUD did not receive the selected hex descriptor.")
		return
	if not selected_hex.get("can_travel", false):
		_fail("Adjacent passable selected hex was not travel-enabled.")
		return

	macro_map.begin_poi_interaction(origin, origin_hex)
	await process_frame
	var session: Dictionary = macro_map.interaction_panel.get("_session")
	if session.get("search_options", []).size() < 3:
		_fail("SEARCH did not expose multiple target options.")
		return
	if session.get("camp_interactions", []).size() < 4:
		_fail("CAMP did not expose hex interaction rows.")
		return
	if macro_map.debug_requirements_met({"any_item_ids": ["not_a_real_key"]}):
		_fail("Missing item requirements incorrectly unlocked a target.")
		return
	macro_map.interaction_panel.close_panel()
	await process_frame

	var movement_origin := Vector2i(3, 0)
	macro_map.player_token.snap_to_hex(
		movement_origin,
		macro_map.map_visualizer.map_to_local(movement_origin)
	)
	world_state.update_player_runtime(
		macro_map.player_token.get_humanoid_core().capture_runtime_state().to_dict(),
		movement_origin
	)
	macro_map.refresh_proximity(movement_origin)
	if macro_map.active_enemies.size() > macro_map.max_visible_npc_tokens:
		_fail("Macro map projected more than 3 NPC tokens.")
		return

	var npc_record := _create_clear_pursuer(
		macro_map,
		world_state,
		movement_origin
	)
	if npc_record == null:
		_fail("Could not create a clear NPC movement probe.")
		return
	if str(npc_record.runtime.get("macro_purpose", "")).is_empty():
		_fail("NPC movement probe did not receive a macro purpose.")
		return

	var before_coords := npc_record.coords
	var before_distance := macro_map.hex_distance(before_coords, movement_origin)
	macro_map.load_enemy_token(npc_record.entity_id)
	if not macro_map.active_enemies.has(before_coords):
		_fail("NPC movement probe did not project a token.")
		return
	if macro_map.active_enemies.size() > macro_map.max_visible_npc_tokens:
		_fail("Forced NPC projection exceeded the visible token cap.")
		return

	macro_map.debug_advance_npc_macro_turn()
	await process_frame
	var moved_record := world_state.get_entity(npc_record.entity_id)
	var after_coords := moved_record.coords
	var after_distance := macro_map.hex_distance(after_coords, movement_origin)
	if after_coords == before_coords:
		_fail("NPC evaluation did not move the pursuit probe.")
		return
	if after_distance >= before_distance:
		_fail("Hostile NPC did not move closer to the player.")
		return
	if world_state.get_entity_at(after_coords).entity_id != npc_record.entity_id:
		_fail("NPC movement did not update the coordinate index.")
		return
	if not macro_map.active_enemies.has(after_coords):
		_fail("Visible NPC token did not follow the persistent record.")
		return
	if macro_map.active_enemies.size() > macro_map.max_visible_npc_tokens:
		_fail("NPC turn exceeded the visible token cap.")
		return

	snapshot = macro_map.world_hud.get("_snapshot")
	var activity: Dictionary = snapshot.get("macro_activity", {})
	if int(activity.get("hostile_count", 0)) <= 0:
		_fail("World HUD did not report hostile macro activity.")
		return

	print("[TEST PASS] Macro exploration HUD, search/camp options, and NPC movement update together.")
	quit(0)

func _create_clear_pursuer(
	macro_map: MacroGameManager,
	world_state: RuntimeStateStore,
	origin: Vector2i
) -> EntityRecord:
	var starts := [
		origin + Vector2i(2, 0),
		origin + Vector2i(2, -1),
		origin + Vector2i(2, 1),
		origin + Vector2i(3, -1),
		origin + Vector2i(3, 0),
	]
	for start in starts:
		if macro_map.hex_distance(origin, start) > macro_map.active_radius:
			continue
		if world_state.has_entity_at(start):
			continue
		var hex := macro_map.world_generator.get_hex_at(start)
		if not hex.is_passable():
			continue
		var record := macro_map.mob_spawner.generate_mob_record(
			start,
			GameEnums.Faction.CRAVEN_HIVE,
			0,
			"macro_world_exploration_probe:" + str(start)
		)
		macro_map.debug_initialize_npc_runtime(record)
		var target := macro_map.debug_evaluate_npc_step(record, origin)
		if target == start or world_state.has_entity_at(target):
			continue
		if not macro_map.world_generator.get_hex_at(target).is_passable():
			continue
		world_state.register_entity(record)
		hex.encounter_evaluated = true
		hex.encounter_entity_id = record.entity_id
		world_state.set_hex_record(start, hex.to_state())
		return record
	return null

func _fail(message: String) -> void:
	push_error("[TEST FAIL] " + message)
	quit(1)
