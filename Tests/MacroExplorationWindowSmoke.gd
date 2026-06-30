extends SceneTree

const DEMO_POI := Vector2i(4, 0)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var game_director: Node = await _spawn_game()
	if game_director == null:
		return

	var macro_map := game_director.get_node("MainWorld") as MacroGameManager
	var world_state := root.get_node("WorldState") as RuntimeStateStore
	var player_core := macro_map.player_token.get_humanoid_core()

	if macro_map.player_token.current_hex_coords != Vector2i(3, 0):
		_fail("Demo start did not move to the hub border.")
		return

	macro_map.debug_step_player_to(DEMO_POI)
	await process_frame
	if macro_map.get_pending_interaction_type() == GameEnums.MacroInteractionType.POI:
		_fail("Landmark POI auto-opened on step instead of Act entry.")
		return

	var hex_data := macro_map.world_generator.get_hex_at(DEMO_POI)
	if not hex_data.has_landmark():
		_fail("Demo landmark was not injected at (4, 0).")
		return

	macro_map.debug_begin_poi_interaction(DEMO_POI, hex_data)
	await process_frame
	if not macro_map.exploration_window.is_open():
		_fail("Act entry did not open the exploration window.")
		return

	var noise_trap := _find_inventory_item(player_core, "trap_makeshift")
	var sleeping_bag := _find_inventory_item(player_core, "sleeping_bag")
	if noise_trap == null or sleeping_bag == null:
		_fail("Demo loadout is missing trap or camp gear.")
		return

	hex_data = macro_map.world_generator.get_hex_at(DEMO_POI)
	var profile := MacroInteractionResolver.build_poi_profile(
		world_state.world_seed,
		DEMO_POI,
		hex_data.biome,
		hex_data.poi_id
	)
	var camp_metrics := MacroInteractionResolver.calculate_camp_metrics(
		profile["camp"],
		[sleeping_bag.to_interaction_descriptor()]
	)
	hex_data.camp_rest_count = _find_safe_camp_attempt(DEMO_POI, camp_metrics)

	macro_map.resolve_poi_action(
		GameEnums.PoiAction.REST,
		[noise_trap.instance_id, sleeping_bag.instance_id]
	)
	await process_frame

	hex_data = macro_map.world_generator.get_hex_at(DEMO_POI)
	if hex_data.camp_traps.is_empty():
		_fail("Trap gear was not persisted on the landmark hex.")
		return
	var trap_lane := int(hex_data.camp_traps[0].get("lane_index", 8))
	if player_core.inventory.find_item_by_instance_id(noise_trap.instance_id) != null:
		_fail("Installed trap gear remained in the player inventory.")
		return

	macro_map.exploration_window.close_window()
	await process_frame
	var enemy_id := _ensure_collision_probe(macro_map, world_state, DEMO_POI)
	if enemy_id.is_empty():
		_fail("Could not create a hostile collision probe for trap combat.")
		return

	macro_map.begin_entity_collision(
		enemy_id,
		world_state.get_entity(enemy_id).coords
	)
	await process_frame
	macro_map.resolve_entity_ambush(GameEnums.AmbushPosition.STANDARD)
	await process_frame
	await process_frame

	var arena = game_director.get_active_arena()
	if arena == null:
		_fail("Ambush during camp did not create combat.")
		return

	var trap_slot: CombatLaneSlot = arena.lane_manager.lane_slots[trap_lane]
	if trap_slot.current_cover != CombatRules.TileObject.TRAP:
		_fail("EncounterBuilder did not place the macro trap on the nominated lane.")
		return

	hex_data = macro_map.world_generator.get_hex_at(DEMO_POI)
	if not hex_data.camp_traps.is_empty():
		_fail("Trap was not consumed from the hex record when combat began.")
		return

	var enemy_lane_before: int = arena.lane_manager._find_entity_lane(arena.enemy_core)
	if enemy_lane_before == trap_lane:
		_fail("Enemy spawned directly on the trap lane; cannot verify entry trigger.")
		return
	if not arena.lane_manager.can_move_entity_to(
		arena.enemy_core,
		enemy_lane_before,
		trap_lane
	):
		_fail("Enemy could not enter the trapped lane for trigger verification.")
		return

	var leg_hp_before: float = arena.enemy_core.body.limb_hp[GameEnums.LimbRegion.LEFT_LEG]
	if not arena.lane_manager.move_entity(
		arena.enemy_core,
		enemy_lane_before,
		trap_lane
	):
		_fail("Enemy movement into the trapped lane failed.")
		return
	if trap_slot.trap_armed:
		_fail("Trap did not disarm after enemy entry.")
		return
	if (
		arena.enemy_core.body.limb_hp[GameEnums.LimbRegion.LEFT_LEG]
		>= leg_hp_before
	):
		_fail("Trap did not damage the enemy on lane entry.")
		return

	arena.turn_manager.halt_loop()
	game_director.queue_free()
	await process_frame
	print(
		"[TEST PASS] Exploration window Act entry, trap persistence, and lane trap trigger work."
	)
	quit(0)

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

func _find_inventory_item(core: HumanoidCore, item_id: String) -> ItemData:
	for item in core.inventory.get_all_items():
		if item.id == item_id:
			return item
	return null

func _ensure_collision_probe(
	macro_map: MacroGameManager,
	world_state: RuntimeStateStore,
	origin: Vector2i
) -> String:
	var candidates := [
		origin + Vector2i(1, 0),
		origin + Vector2i(1, -1),
		origin + Vector2i(0, 1),
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

func _fail(message: String) -> void:
	push_error("[TEST FAIL] " + message)
	quit(1)
