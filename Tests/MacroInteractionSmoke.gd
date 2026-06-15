extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var game_director: Node = await _spawn_game()
	if game_director == null:
		return

	var macro_map := game_director.get_node("MainWorld") as MacroGameManager
	var player_core := macro_map.player_token.get_humanoid_core()
	var world_state := root.get_node("WorldState") as RuntimeStateStore
	if (
		macro_map.player_token.humanoid_token.get_animation()
		!= "Idle"
	):
		_fail("The macro player did not use the neutral idle.")
		return
	for enemy_token in macro_map.active_enemies.values():
		if enemy_token.humanoid_token.get_animation() != "Idle2":
			_fail("A hostile macro NPC did not use the aggressive idle.")
			return
	var disposition_probe: MacroEnemy = macro_map.active_enemies.values()[0]
	var hostile_record := world_state.get_entity(
		disposition_probe.entity_id
	)
	var passive_record := hostile_record.duplicate(true)
	passive_record["world_status"] = GameEnums.EntityWorldStatus.CEASEFIRE
	disposition_probe.setup_from_record(passive_record)
	if disposition_probe.humanoid_token.get_animation() != "Idle3":
		_fail("A passive macro NPC did not use the friendly idle.")
		return
	disposition_probe.setup_from_record(hostile_record)
	var starting_time := world_state.world_time_minutes
	var poi_coords := Vector2i(1, 0)
	macro_map._execute_player_step(poi_coords)
	await process_frame
	if (
		macro_map.player_token.humanoid_token.get_animation()
		!= "Walk"
	):
		_fail("Normal macro travel did not use Walk.")
		return
	if (
		world_state.world_time_minutes
		!= starting_time + GameTimeRules.MOVE_MINUTES
	):
		_fail("Macro movement did not advance authoritative world time.")
		return

	if (
		macro_map._pending_interaction.get("type")
		!= GameEnums.MacroInteractionType.POI
	):
		_fail("The guaranteed demo POI did not open the POI interaction.")
		return
	if not macro_map.interaction_panel.is_open():
		_fail("The macro interaction panel did not become visible.")
		return
	await create_timer(MacroPlayer.WALK_DURATION_SECONDS + 0.05).timeout
	if (
		macro_map.player_token.humanoid_token.get_animation()
		!= "Taunt"
	):
		_fail("The queued POI interaction did not use Taunt after walking.")
		return

	var sleeping_bag := _find_inventory_item(player_core, "sleeping_bag")
	var tarp := _find_inventory_item(player_core, "tentkit")
	var noise_trap := _find_inventory_item(player_core, "trap_makeshift")
	var crowbar := _find_inventory_item(player_core, "crowbar")
	var lockpick := _find_inventory_item(player_core, "multitool")
	if (
		sleeping_bag == null
		or tarp == null
		or noise_trap == null
		or crowbar == null
		or lockpick == null
	):
		_fail("The demo loadout is missing interaction equipment.")
		return

	var hex_data := macro_map.world_generator.get_hex_at(poi_coords)
	var loot_catalog := root.get_node("LootCatalog")
	var loot_profile: Dictionary = loot_catalog.call(
		"get_profile_descriptor",
		WorldRules.get_loot_profile_id(hex_data.biome, hex_data.poi_id)
	)
	var profile := MacroInteractionResolver.build_poi_profile(
		"DEMO_WASTELAND_01",
		poi_coords,
		hex_data.biome,
		hex_data.poi_id
	)
	if (
		not _metrics_use_base_twelve(profile["search"])
		or not _metrics_use_base_twelve(profile["camp"])
	):
		_fail("Generated POI metrics escaped the 0-12 scale.")
		return

	var camp_descriptors := [
		sleeping_bag.to_interaction_descriptor(),
		tarp.to_interaction_descriptor(),
		noise_trap.to_interaction_descriptor(),
	]
	var camp_metrics := MacroInteractionResolver.calculate_camp_metrics(
		profile["camp"],
		camp_descriptors
	)
	if not _metrics_use_base_twelve(camp_metrics):
		_fail("Camp equipment produced metrics outside the 0-12 scale.")
		return
	hex_data.camp_rest_count = _find_safe_camp_attempt(
		poi_coords,
		camp_metrics
	)
	player_core.body.fatigue = 10.0
	var fatigue_before := player_core.body.fatigue
	var time_before_camp := world_state.world_time_minutes
	macro_map.resolve_poi_action(
		GameEnums.PoiAction.CAMP,
		[sleeping_bag.instance_id, tarp.instance_id, noise_trap.instance_id]
	)
	await process_frame

	if (
		world_state.world_time_minutes
		!= time_before_camp + GameTimeRules.CAMP_MINUTES
	):
		_fail("CAMP did not advance authoritative world time.")
		return
	if hex_data.camp_item_states.size() != 3:
		_fail("Camp gear was not persisted into the three campsite slots.")
		return
	if player_core.body.fatigue >= fatigue_before:
		_fail("Resting at camp did not recover fatigue.")
		return
	if player_core.inventory.find_item_by_instance_id(sleeping_bag.instance_id) != null:
		_fail("Installed camp gear remained duplicated in the player inventory.")
		return
	macro_map.open_inventory()
	await process_frame
	if not macro_map.inventory_panel.is_open():
		_fail("Inventory was not accessible during the active CAMP session.")
		return
	macro_map.inventory_panel.close_panel()
	await process_frame
	if not macro_map.interaction_panel.is_open():
		_fail("Closing CAMP inventory did not restore the POI session.")
		return

	macro_map.interaction_panel.close_panel()
	await process_frame
	macro_map._begin_poi_interaction(poi_coords, hex_data)
	await process_frame

	var search_descriptors := [
		crowbar.to_interaction_descriptor(),
		lockpick.to_interaction_descriptor(),
	]
	var search_metrics := MacroInteractionResolver.calculate_search_metrics(
		profile["search"],
		search_descriptors,
		hex_data.search_count,
		loot_profile.get("max_searches", 4)
	)
	if not _metrics_use_base_twelve(search_metrics):
		_fail("Search tools produced metrics outside the 0-12 scale.")
		return
	hex_data.search_count = _find_quiet_search_attempt(
		poi_coords,
		profile["search"],
		search_descriptors,
		loot_profile
	)
	var search_count_before := hex_data.search_count
	var time_before_search := world_state.world_time_minutes
	macro_map.resolve_poi_action(
		GameEnums.PoiAction.SEARCH,
		[crowbar.instance_id, lockpick.instance_id]
	)
	await process_frame

	if (
		world_state.world_time_minutes
		!= time_before_search + GameTimeRules.SEARCH_MINUTES
	):
		_fail("SEARCH did not advance authoritative world time.")
		return
	if hex_data.search_count != search_count_before + 1:
		_fail("POI search depletion state was not persisted.")
		return
	if search_metrics.is_empty():
		_fail("Search metrics could not be calculated from slotted tools.")
		return
	if not world_state.has_ground_items(poi_coords):
		_fail("SEARCH loot was not placed in persistent ground inventory.")
		return

	macro_map.interaction_panel.close_panel()
	await process_frame
	var enemy_coords := _nearest_enemy_coords(
		poi_coords,
		macro_map.active_enemies.keys()
	)
	for step in _build_hex_path(poi_coords, enemy_coords):
		macro_map._execute_player_step(step)
		await process_frame

	if (
		macro_map._pending_interaction.get("type")
		!= GameEnums.MacroInteractionType.ENTITY_COLLISION
	):
		_fail("Moving into a hostile entity did not open collision choices.")
		return

	macro_map.resolve_entity_ambush(GameEnums.AmbushPosition.CLOSE)
	await process_frame
	await process_frame
	var arena = game_director.get("_active_arena")
	if arena == null:
		_fail("Ambush selection did not create combat.")
		return
	if arena.lane_manager._find_entity_lane(arena.player_core) != 4:
		_fail("The selected close ambush position was not honored.")
		return
	if arena.lane_manager._find_entity_lane(arena.enemy_core) != 7:
		_fail("The ambushed enemy did not use its ambush deployment lane.")
		return
	if arena.turn_manager.get_active_entity() != arena.player_core:
		_fail("The colliding player did not receive first initiative.")
		return

	arena.turn_manager.halt_loop()
	game_director.queue_free()
	await process_frame
	await process_frame

	if not await _verify_failed_talk_deployment():
		return

	print(
		"[TEST PASS] POI Search/Camp UI and entity collision setup preserve "
		+ "persistent state, placement, and collider initiative."
	)
	quit(0)

func _verify_failed_talk_deployment() -> bool:
	var game_director: Node = await _spawn_game()
	if game_director == null:
		return false
	var macro_map := game_director.get_node("MainWorld") as MacroGameManager
	var origin := macro_map.player_token.current_hex_coords
	var enemy_coords := _nearest_enemy_coords(origin, macro_map.active_enemies.keys())
	var enemy_id: String = macro_map.active_enemies[enemy_coords].entity_id
	var world_state := root.get_node("WorldState") as RuntimeStateStore
	var enemy_record := world_state.get_entity(enemy_id)
	var definition: Dictionary = enemy_record.get("definition", {})
	definition["will"] = 12
	world_state.patch_entity_record(enemy_id, {"definition": definition})

	for step in _build_hex_path(origin, enemy_coords):
		macro_map._execute_player_step(step)
		await process_frame

	macro_map.resolve_talk_action(GameEnums.TalkAction.CEASEFIRE)
	await process_frame
	await process_frame
	var arena = game_director.get("_active_arena")
	if arena == null:
		_fail("Guaranteed failed negotiation did not start combat.")
		return false
	if arena.lane_manager._find_entity_lane(arena.player_core) != 2:
		_fail("Failed negotiation did not use the ordinary player deployment.")
		return false
	if arena.lane_manager._find_entity_lane(arena.enemy_core) != 9:
		_fail("Failed negotiation did not use the ordinary enemy deployment.")
		return false
	if arena.turn_manager.get_active_entity() != arena.player_core:
		_fail("The colliding player lost initiative after negotiation failed.")
		return false

	arena.turn_manager.halt_loop()
	arena.queue_free()
	await process_frame
	var duel_scene := load("res://CombatCore/MainDuelScene.tscn") as PackedScene
	var enemy_initiated_arena = duel_scene.instantiate()
	game_director.add_child(enemy_initiated_arena)
	enemy_initiated_arena.setup_duel(
		macro_map.player_token.get_humanoid_core(),
		world_state.get_entity(enemy_id),
		{
			"context": GameEnums.EncounterContext.ENEMY_AMBUSH,
			"initiator_id": enemy_id,
		}
	)
	await process_frame
	if (
		enemy_initiated_arena.turn_manager.combatants[0]
		!= enemy_initiated_arena.enemy_core
	):
		_fail("An enemy collider did not receive first initiative.")
		return false
	return true

func _spawn_game() -> Node:
	var main_scene := load("res://SystemCore/game_director.tscn") as PackedScene
	if not main_scene:
		_fail("Could not load the game director scene.")
		return null
	var game_director := main_scene.instantiate()
	root.add_child(game_director)
	await process_frame
	await process_frame
	return game_director

func _find_safe_camp_attempt(
	coords: Vector2i,
	metrics: Dictionary
) -> int:
	for attempt in range(32):
		var result := MacroInteractionResolver.resolve_camp(
			"DEMO_WASTELAND_01",
			coords,
			attempt,
			metrics
		)
		if not result.get("interrupted", false):
			return attempt
	return 0

func _find_quiet_search_attempt(
	coords: Vector2i,
	base_metrics: Dictionary,
	descriptors: Array,
	loot_profile: Dictionary
) -> int:
	var max_searches := int(loot_profile.get("max_searches", 4))
	for attempt in range(max_searches):
		var metrics := MacroInteractionResolver.calculate_search_metrics(
			base_metrics,
			descriptors,
			attempt,
			max_searches
		)
		var result := MacroInteractionResolver.resolve_search(
			"DEMO_WASTELAND_01",
			coords,
			attempt,
			metrics,
			loot_profile
		)
		if not result.get("attracted_enemy", false):
			return attempt
	return 0

func _find_inventory_item(core: HumanoidCore, item_id: String) -> ItemData:
	for item in core.inventory.get_all_items():
		if item.id == item_id:
			return item
	return null

func _metrics_use_base_twelve(metrics: Dictionary) -> bool:
	for value in metrics.values():
		var numeric_value := float(value)
		if numeric_value < 0.0 or numeric_value > GameEnums.SCALE_MAX:
			return false
	return true

func _nearest_enemy_coords(origin: Vector2i, candidates: Array) -> Vector2i:
	var nearest: Vector2i = candidates[0]
	var nearest_distance := _hex_distance(origin, nearest)
	for coords in candidates:
		var distance := _hex_distance(origin, coords)
		if distance < nearest_distance:
			nearest = coords
			nearest_distance = distance
	return nearest

func _build_hex_path(origin: Vector2i, destination: Vector2i) -> Array[Vector2i]:
	var path: Array[Vector2i] = []
	var current := origin
	while current != destination:
		var best_step := current
		var best_distance := _hex_distance(current, destination)
		for direction in MacroGameManager.HEX_NEIGHBORS:
			var candidate: Vector2i = current + direction
			var distance := _hex_distance(candidate, destination)
			if distance < best_distance:
				best_step = candidate
				best_distance = distance
		current = best_step
		path.append(current)
	return path

func _hex_distance(from_coords: Vector2i, to_coords: Vector2i) -> int:
	var delta := to_coords - from_coords
	return maxi(abs(delta.x), maxi(abs(delta.y), abs(delta.x + delta.y)))

func _fail(message: String) -> void:
	push_error("[TEST FAIL] " + message)
	quit(1)
