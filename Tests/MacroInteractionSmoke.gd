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
	var disposition_probe_id := _ensure_collision_probe(
		macro_map,
		world_state,
		macro_map.player_token.current_hex_coords
	)
	if disposition_probe_id.is_empty():
		_fail("Could not create a controlled macro NPC disposition probe.")
		return
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
	var disposition_record := world_state.get_entity(disposition_probe_id)
	var disposition_probe: MacroEnemy = macro_map.active_enemies[
		disposition_record.coords
	]
	var hostile_record := world_state.get_entity(
		disposition_probe.entity_id
	)
	var passive_record := hostile_record.to_dict()
	passive_record["world_status"] = GameEnums.EntityWorldStatus.CEASEFIRE
	disposition_probe.setup_from_record(passive_record)
	if disposition_probe.humanoid_token.get_animation() != "Idle3":
		_fail("A passive macro NPC did not use the friendly idle.")
		return
	disposition_probe.setup_from_record(hostile_record)
	var starting_time := world_state.world_time_minutes
	var poi_coords := _ensure_demo_homestead(macro_map, world_state)
	macro_map.debug_teleport_player(poi_coords + Vector2i(-1, 0))
	await process_frame
	macro_map.debug_step_player_to(poi_coords)
	await process_frame
	if str(macro_map.get("_last_macro_event")).is_empty():
		_fail("Hex step did not write exploration log feedback.")
		return
	if (
		macro_map.get_pending_interaction_type()
		== GameEnums.MacroInteractionType.POI
	):
		_fail("Landmark POI auto-opened on step instead of Act entry.")
		return
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

	var hex_data := macro_map.world_generator.get_hex_at(poi_coords)
	if not hex_data.has_landmark():
		_fail("The guaranteed demo landmark was not present at (4, 0).")
		return
	macro_map.debug_begin_poi_interaction(poi_coords, hex_data)
	await process_frame
	if (
		macro_map.get_pending_interaction_type()
		!= GameEnums.MacroInteractionType.POI
	):
		_fail("Act entry did not open the landmark POI interaction.")
		return
	if not macro_map.exploration_window.is_open():
		_fail("The macro exploration window did not become visible.")
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

	hex_data = macro_map.world_generator.get_hex_at(poi_coords)
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
	player_core.body.fatigue = 3.0
	var fatigue_before := player_core.body.fatigue
	var time_before_camp := world_state.world_time_minutes
	macro_map.resolve_poi_action(
		GameEnums.PoiAction.CAMP,
		[sleeping_bag.instance_id, tarp.instance_id, noise_trap.instance_id]
	)
	await process_frame

	if world_state.world_time_minutes <= time_before_camp:
		_fail("CAMP did not advance authoritative world time.")
		return
	if (
		(world_state.world_time_minutes - time_before_camp) % GameTimeRules.CAMP_MINUTES
		!= 0
	):
		_fail("CAMP advanced world time in non-camp increments.")
		return
	if hex_data.camp_item_states.size() != 2:
		_fail("Camp gear was not persisted into the two campsite slots.")
		return
	if hex_data.camp_traps.size() != 1:
		_fail("Trap gear was not persisted on the landmark hex.")
		return
	if player_core.body.fatigue >= fatigue_before:
		_fail("Resting at camp did not recover fatigue.")
		return
	if player_core.inventory.find_item_by_instance_id(sleeping_bag.instance_id) != null:
		_fail("Installed camp gear remained duplicated in the player inventory.")
		return
	if player_core.inventory.find_item_by_instance_id(noise_trap.instance_id) != null:
		_fail("Installed trap gear remained duplicated in the player inventory.")
		return
	macro_map.open_inventory()
	await process_frame
	if not macro_map.inventory_panel.is_open():
		_fail("The detached inventory panel was not accessible during the active CAMP session.")
		return
	macro_map.inventory_panel.close_panel()

	macro_map.exploration_window.close_window()
	await process_frame
	macro_map.debug_begin_poi_interaction(poi_coords, hex_data)
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

	macro_map.exploration_window.close_window()
	await process_frame
	var collision_enemy_id := _ensure_collision_probe(
		macro_map,
		world_state,
		poi_coords
	)
	if collision_enemy_id.is_empty():
		_fail("Could not create a controlled hostile collision probe.")
		return
	var collision_record := world_state.get_entity(collision_enemy_id)
	macro_map.begin_entity_collision(collision_enemy_id, collision_record.coords)
	await process_frame
	if (
		macro_map.get_pending_interaction_type()
		!= GameEnums.MacroInteractionType.ENTITY_COLLISION
	):
		_fail("Opening a hostile entity collision did not show collision choices.")
		return
	if macro_map.macro_hud == null or not macro_map.macro_hud.is_event_open():
		_fail("Entity collision did not open through MacroExplorationStage.")
		return

	macro_map.resolve_entity_collision_choice(
		MacroEntityCollisionResolver.CHOICE_AMBUSH
	)
	await process_frame
	if not macro_map.macro_hud.is_event_open():
		_fail("Ambush branch did not stay on MacroExplorationStage.")
		return
	macro_map.resolve_entity_collision_choice(
		MacroEntityCollisionResolver.CHOICE_AMBUSH_CLOSE
	)
	await process_frame
	await process_frame
	var arena = game_director.get_active_arena()
	if arena == null:
		_fail("Ambush selection did not create combat.")
		return
	var exploration_stage := macro_map.macro_hud.get_exploration_stage()
	if (
		exploration_stage.is_open()
		or exploration_stage.get_node("%DimOverlay").visible
		or (
			exploration_stage.get_node("%Root") as Control
		).mouse_filter != Control.MOUSE_FILTER_IGNORE
	):
		_fail("Collision overlay or its input blocker survived the combat handoff.")
		return
	for child in macro_map.get_children():
		if child is CanvasLayer and (child as CanvasLayer).visible:
			_fail(
				"Macro CanvasLayer survived the combat handoff: %s"
				% child.name
			)
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
	if not await _verify_ceasefire_ask_trade_tree():
		return
	if not await _verify_threat_surrender_drops():
		return

	print(
		"[TEST PASS] POI Search/Camp UI and entity collision setup preserve "
		+ "persistent state, placement, Event HUD collision tree, and collider initiative."
	)
	quit(0)

func _verify_failed_talk_deployment() -> bool:
	var game_director: Node = await _spawn_game()
	if game_director == null:
		return false
	var macro_map := game_director.get_node("MainWorld") as MacroGameManager
	var world_state := root.get_node("WorldState") as RuntimeStateStore
	var origin := macro_map.player_token.current_hex_coords
	var enemy_id := _ensure_collision_probe(macro_map, world_state, origin)
	if enemy_id.is_empty():
		_fail("Could not create a controlled hostile collision probe.")
		return false
	var enemy_record := world_state.get_entity(enemy_id)
	var definition: Dictionary = enemy_record.definition.duplicate(true)
	definition["will"] = 12
	world_state.patch_entity_record(enemy_id, {"definition": definition})
	macro_map.begin_entity_collision(enemy_id, enemy_record.coords)
	await process_frame

	macro_map.resolve_talk_action(GameEnums.TalkAction.CEASEFIRE)
	await process_frame
	await process_frame
	var arena = game_director.get_active_arena()
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
	var duel_scene := load(PresentationSceneRegistry.TURN_BASED_DUEL_SCENE) as PackedScene
	var enemy_initiated_arena = duel_scene.instantiate()
	game_director.add_child(enemy_initiated_arena)
	enemy_initiated_arena.setup_duel(
		macro_map.player_token.get_humanoid_core(),
		world_state.get_entity(enemy_id).to_dict(),
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
	enemy_initiated_arena.turn_manager.halt_loop()
	enemy_initiated_arena.queue_free()
	game_director.queue_free()
	await process_frame
	return true


func _verify_ceasefire_ask_trade_tree() -> bool:
	var game_director: Node = await _spawn_game()
	if game_director == null:
		return false
	var macro_map := game_director.get_node("MainWorld") as MacroGameManager
	var world_state := root.get_node("WorldState") as RuntimeStateStore
	var origin := macro_map.player_token.current_hex_coords
	var enemy_id := _ensure_collision_probe(macro_map, world_state, origin)
	if enemy_id.is_empty():
		_fail("Could not create a ceasefire collision probe.")
		return false
	var enemy_record := world_state.get_entity(enemy_id)
	var definition: Dictionary = enemy_record.definition.duplicate(true)
	definition["will"] = 1
	definition["allows_trade"] = true
	world_state.patch_entity_record(enemy_id, {"definition": definition})
	macro_map.begin_entity_collision(enemy_id, enemy_record.coords)
	await process_frame
	macro_map.resolve_entity_collision_choice(
		MacroEntityCollisionResolver.CHOICE_TALK
	)
	await process_frame
	macro_map.resolve_talk_action(GameEnums.TalkAction.CEASEFIRE)
	await process_frame
	if world_state.get_entity(enemy_id).world_status != GameEnums.EntityWorldStatus.CEASEFIRE:
		_fail("Successful ceasefire did not set CEASEFIRE world status.")
		return false
	if not macro_map.macro_hud.is_event_open():
		_fail("Successful ceasefire did not open the peaceful Event HUD session.")
		return false
	if game_director.get_active_arena() != null:
		_fail("Successful ceasefire incorrectly started combat.")
		return false

	macro_map.resolve_entity_collision_choice(
		MacroEntityCollisionResolver.CHOICE_ASK
	)
	await process_frame
	macro_map.resolve_entity_collision_choice("ask_intent")
	await process_frame
	if not macro_map.macro_hud.is_event_open():
		_fail("Ask choice did not show a result on MacroExplorationStage.")
		return false
	macro_map.macro_hud.close_event(true)
	await process_frame
	if not macro_map.macro_hud.is_event_open():
		_fail("Ask result continue did not resume the Ask session.")
		return false

	macro_map.resolve_entity_collision_choice(
		MacroEntityCollisionResolver.CHOICE_BACK
	)
	await process_frame
	macro_map.resolve_entity_collision_choice(
		MacroEntityCollisionResolver.CHOICE_TRADE
	)
	await process_frame
	if not macro_map.macro_hud.is_event_open():
		_fail("Trade placeholder did not open a result panel.")
		return false
	macro_map.macro_hud.close_event(true)
	await process_frame
	if not macro_map.macro_hud.is_event_open():
		_fail("Trade placeholder continue did not resume the peaceful session.")
		return false

	macro_map.resolve_entity_collision_choice(
		MacroEntityCollisionResolver.CHOICE_LEAVE
	)
	await process_frame
	if macro_map.get_pending_interaction_type() != GameEnums.MacroInteractionType.NONE:
		_fail("Leave did not close the entity collision interaction.")
		return false
	if world_state.get_entity(enemy_id).world_status != GameEnums.EntityWorldStatus.CEASEFIRE:
		_fail("Leave cleared ceasefire status.")
		return false

	game_director.queue_free()
	await process_frame
	return true


func _verify_threat_surrender_drops() -> bool:
	var game_director: Node = await _spawn_game()
	if game_director == null:
		return false
	var macro_map := game_director.get_node("MainWorld") as MacroGameManager
	var world_state := root.get_node("WorldState") as RuntimeStateStore
	var origin := macro_map.player_token.current_hex_coords
	var enemy_id := _ensure_collision_probe(macro_map, world_state, origin)
	if enemy_id.is_empty():
		_fail("Could not create a threat collision probe.")
		return false
	var enemy_record := world_state.get_entity(enemy_id)
	var definition: Dictionary = enemy_record.definition.duplicate(true)
	definition["will"] = 1
	world_state.patch_entity_record(enemy_id, {"definition": definition})
	macro_map.begin_entity_collision(enemy_id, enemy_record.coords)
	await process_frame
	macro_map.resolve_talk_action(GameEnums.TalkAction.THREAT)
	await process_frame
	if world_state.get_entity(enemy_id).world_status != GameEnums.EntityWorldStatus.WITHDRAWN:
		_fail("Successful threat did not withdraw the opponent.")
		return false
	if game_director.get_active_arena() != null:
		_fail("Successful threat incorrectly started combat.")
		return false
	# Threat should dump non-clothes gear when the loadout has droppable items.
	var kept_loadout: Dictionary = world_state.get_entity(enemy_id).definition.get(
		"loadout",
		{}
	)
	if not str(kept_loadout.get("weapon", "")).is_empty():
		_fail("Successful threat kept the opponent weapon equipped in loadout.")
		return false
	if not world_state.has_ground_items(macro_map.player_token.current_hex_coords):
		var original_loadout: Dictionary = definition.get("loadout", {})
		var had_droppable: bool = (
			not str(original_loadout.get("weapon", "")).is_empty()
			or not str(original_loadout.get("offhand", "")).is_empty()
			or not str(original_loadout.get("vest", "")).is_empty()
			or not str(original_loadout.get("backpack_gear", "")).is_empty()
			or not (original_loadout.get("starting_items", []) as Array).is_empty()
		)
		if had_droppable:
			_fail("Successful threat did not leave dropped gear on the ground.")
			return false

	game_director.queue_free()
	await process_frame
	return true


func _spawn_game() -> Node:
	# Collision initiative assertions use CombatTurnManager.get_active_entity().
	var settings := Engine.get_main_loop().root.get_node_or_null("GameSettings") as GameSettingsStore
	if settings != null:
		settings.combat_mode = GameSettingsStore.COMBAT_TURN_BASED
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

func _ensure_collision_probe(
	macro_map: MacroGameManager,
	world_state: RuntimeStateStore,
	origin: Vector2i
) -> String:
	var candidates := [
		Vector2i(3, 0),
		Vector2i(3, -1),
		Vector2i(3, 1),
		origin + Vector2i(2, 0),
	]
	for coords in candidates:
		var hex := macro_map.world_generator.get_hex_at(coords)
		if not hex.is_passable():
			continue
		var record := world_state.get_entity_at(coords)
		if record != null:
			if (
				world_state.is_entity_alive(record.entity_id)
				and world_state.is_entity_hostile(record.entity_id)
			):
				macro_map.load_enemy_token(record.entity_id)
				return record.entity_id
			continue
		macro_map.spawn_procedural_enemy(
			coords,
			GameEnums.Faction.SCAVENGER_CELL,
			0
		)
		record = world_state.get_entity_at(coords)
		if record != null:
			return record.entity_id
	return ""

func _walk_to_nearest_collision(
	macro_map: MacroGameManager,
	max_steps: int = 48
) -> bool:
	for _step_index in range(max_steps):
		if (
			macro_map.get_pending_interaction_type()
			== GameEnums.MacroInteractionType.ENTITY_COLLISION
		):
			return true
		if macro_map.active_enemies.is_empty():
			return false
		var origin := macro_map.player_token.current_hex_coords
		var enemy_coords := _nearest_enemy_coords(
			origin,
			macro_map.active_enemies.keys()
		)
		var enemy_path := _build_hex_path(
			origin,
			enemy_coords,
			macro_map.world_generator
		)
		if enemy_path.is_empty():
			return false
		macro_map.debug_step_player_to(enemy_path[0])
		await process_frame
	return (
		macro_map.get_pending_interaction_type()
		== GameEnums.MacroInteractionType.ENTITY_COLLISION
	)

func _build_hex_path(
	origin: Vector2i,
	destination: Vector2i,
	generator: HexWorldGenerator = null
) -> Array[Vector2i]:
	if origin == destination:
		return []

	var frontier: Array[Vector2i] = [origin]
	var came_from: Dictionary = {}
	var max_search_distance := maxi(_hex_distance(origin, destination) + 24, 32)
	came_from[origin] = origin

	var frontier_index := 0
	while frontier_index < frontier.size():
		var current := frontier[frontier_index]
		frontier_index += 1
		if current == destination:
			break

		for direction in MacroGameManager.HEX_NEIGHBORS:
			var candidate: Vector2i = current + direction
			if came_from.has(candidate):
				continue
			if _hex_distance(origin, candidate) > max_search_distance:
				continue
			if (
				candidate != destination
				and generator != null
				and not generator.get_hex_at(candidate).is_passable()
			):
				continue
			came_from[candidate] = current
			frontier.append(candidate)

	if not came_from.has(destination):
		return []

	var path: Array[Vector2i] = []
	var step := destination
	while step != origin:
		path.push_front(step)
		step = came_from[step]
	return path

func _hex_distance(from_coords: Vector2i, to_coords: Vector2i) -> int:
	var delta := to_coords - from_coords
	return maxi(abs(delta.x), maxi(abs(delta.y), abs(delta.x + delta.y)))


func _ensure_demo_homestead(
	macro_map: MacroGameManager,
	world_state: RuntimeStateStore,
	coords: Vector2i = Vector2i(4, 0)
) -> Vector2i:
	var hex := macro_map.world_generator.get_hex_at(coords)
	hex.terrain_tile = GameEnums.MacroTerrainTile.PLAINS_GRASS
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
