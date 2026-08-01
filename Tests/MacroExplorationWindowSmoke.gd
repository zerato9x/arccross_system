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

	_ensure_demo_homestead(macro_map, world_state, DEMO_POI)
	macro_map.debug_teleport_player(Vector2i(3, 0))
	await process_frame

	if macro_map.player_token.current_hex_coords != Vector2i(3, 0):
		_fail("Demo start did not move to the hub border.")
		return

	macro_map.debug_step_player_to(DEMO_POI)
	await process_frame
	if str(macro_map.get("_last_macro_event")).is_empty():
		_fail("Hex step did not write exploration log feedback.")
		return
	if macro_map.get_pending_interaction_type() == GameEnums.MacroInteractionType.POI:
		_fail("Landmark POI auto-opened on step instead of Act entry.")
		return

	var hex_data := macro_map.world_generator.get_hex_at(DEMO_POI)
	if not hex_data.has_landmark():
		_fail("Demo landmark was not injected at (4, 0).")
		return

	macro_map.debug_begin_poi_interaction(DEMO_POI, hex_data)
	await process_frame
	if not macro_map.macro_hud.is_location_open():
		_fail("Act entry did not open the HERE location board.")
		return
	if macro_map.exploration_window.is_open():
		_fail("Routine Act entry still opened the retired exploration window.")
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
	world_state.set_hex_record(DEMO_POI, hex_data.to_state())
	macro_map._refresh_world_hud()

	var location: Dictionary = macro_map.macro_hud.get("_snapshot").get("current_location", {})
	var trap_fixture := _fixture_with_verb(location, SiteCatalog.VERB_TRAP)
	var sleep_fixture := _fixture_with_verb(location, SiteCatalog.VERB_SLEEP)
	if trap_fixture.is_empty() or sleep_fixture.is_empty():
		_fail("Homestead HERE is missing trap or sleep fixtures.")
		return
	macro_map.resolve_location_action({
		"coords": DEMO_POI,
		"location_revision": int(location.get("revision", 0)),
		"fixture_id": str(trap_fixture.get("id", "")),
		"verb": SiteCatalog.VERB_TRAP,
		"selected_item_ids": [noise_trap.instance_id],
	})
	await process_frame
	location = macro_map.macro_hud.get("_snapshot").get("current_location", {})
	macro_map.resolve_location_action({
		"coords": DEMO_POI,
		"location_revision": int(location.get("revision", 0)),
		"fixture_id": str(sleep_fixture.get("id", "")),
		"verb": SiteCatalog.VERB_SLEEP,
		"selected_item_ids": [sleeping_bag.instance_id],
	})
	await process_frame

	hex_data = macro_map.world_generator.get_hex_at(DEMO_POI)
	if hex_data.camp_traps.is_empty():
		_fail("Trap gear was not persisted on the landmark hex.")
		return
	var trap_sector_coords := Vector2i(
		int(hex_data.camp_traps[0].get("sector_x", 1)),
		int(hex_data.camp_traps[0].get("sector_y", 2))
	)
	if player_core.inventory.find_item_by_instance_id(noise_trap.instance_id) != null:
		_fail("Installed trap gear remained in the player inventory.")
		return

	macro_map.close_macro_interaction()
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

	var trap_sector := arena.board.arena_state.sector_at(trap_sector_coords)
	if trap_sector == null or trap_sector.trap_state.is_empty():
		_fail("TacticalEncounterBuilder did not place the macro trap in its authored sector.")
		return

	hex_data = macro_map.world_generator.get_hex_at(DEMO_POI)
	if hex_data.camp_traps.is_empty():
		_fail("Preparing combat consumed the persistent macro trap before resolution.")
		return

	var enemy_sector_before: int = arena.board.position_of(arena.enemy_core)
	var trap_index := arena.board.arena_state.index_for(trap_sector_coords)
	if enemy_sector_before == trap_index:
		_fail("Enemy spawned directly on the trap sector; cannot verify entry trigger.")
		return
	var path := arena.board.find_path(enemy_sector_before, trap_index, arena.enemy_core)
	if path.size() < 2:
		_fail("Enemy could not path into the trapped sector for trigger verification.")
		return

	var wound_count_before := arena.enemy_core.body.get_wounds_for_limb(GameEnums.LimbRegion.LEFT_LEG).size()
	if arena.board.commit_path(arena.enemy_core, path).is_empty():
		_fail("Enemy movement into the trapped sector failed.")
		return
	if bool(trap_sector.trap_state.get("armed", true)):
		_fail("Trap did not disarm after enemy entry.")
		return
	if (
		arena.enemy_core.body.get_wounds_for_limb(GameEnums.LimbRegion.LEFT_LEG).size()
		<= wound_count_before
	):
		_fail("Trap did not wound the enemy on sector entry.")
		return

	arena.turn_manager.halt_loop()
	game_director.queue_free()
	await process_frame
	print(
		"[TEST PASS] HERE Act entry, trap persistence, rest, and sector trap trigger work."
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


func _fixture_with_verb(location: Dictionary, verb: String) -> Dictionary:
	for fixture in location.get("session", {}).get("site", {}).get("fixtures", []):
		if fixture is Dictionary and fixture.get("verbs", []).has(verb):
			return fixture
	return {}

func _ensure_collision_probe(
	macro_map: MacroGameManager,
	world_state: RuntimeStateStore,
	origin: Vector2i
) -> String:
	var candidates := [
		origin + Vector2i(1, 0),
		origin + Vector2i(1, -1),
		origin + Vector2i(0, 1),
		origin + Vector2i(0, -1),
		origin + Vector2i(-1, 0),
		origin + Vector2i(-1, 1),
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
