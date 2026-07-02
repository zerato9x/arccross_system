extends SceneTree

const SAVE_PATH: String = "user://phase_1_vertical_slice_smoke.json"
const WALK_PATH: Array[Vector2i] = [
	Vector2i(4, 0),
	Vector2i(4, -1),
	Vector2i(5, -1),
	Vector2i(5, 0),
	Vector2i(6, 0),
]

var world_state: RuntimeStateStore
var expected: Dictionary = {}

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	world_state = root.get_node("WorldState") as RuntimeStateStore
	world_state.delete_save_file(SAVE_PATH)
	world_state.begin_new_world("CLEAN_PHASE_1_TEST")

	var director: GameDirector = await _spawn_game()
	if director == null:
		return
	var macro_map := director.macro_map

	if not await _walk_five_hexes(macro_map):
		return
	if not await _defeat_and_loot_enemy(director):
		return
	if not await _search_and_camp(macro_map):
		return

	var player := macro_map.player_token.get_humanoid_core()
	var poi_coords := macro_map.player_token.current_hex_coords
	var poi_hex := macro_map.world_generator.get_hex_at(poi_coords)
	expected["coords"] = poi_coords
	expected["world_time"] = world_state.world_time_minutes
	expected["arm_hp"] = player.body.limb_hp[GameEnums.LimbRegion.LEFT_ARM]
	expected["search_count"] = poi_hex.search_count
	expected["camp_rest_count"] = poi_hex.camp_rest_count
	expected["camp_item_count"] = poi_hex.camp_item_states.size()

	if not director.save_game(SAVE_PATH):
		_fail("Vertical slice save failed: " + world_state.get_last_persistence_error())
		return
	director.queue_free()
	await process_frame
	await process_frame

	world_state.begin_new_world("SCRAMBLED_VERTICAL_SLICE")
	if not world_state.load_from_disk(SAVE_PATH):
		_fail("Vertical slice load failed: " + world_state.get_last_persistence_error())
		return

	var restored_director: GameDirector = await _spawn_game()
	if restored_director == null:
		return
	if not _verify_reloaded_slice(restored_director.macro_map):
		return

	restored_director.queue_free()
	world_state.delete_save_file(SAVE_PATH)
	print(
		"[TEST PASS] Clean Phase 1 flow crossed five Hexes, won via a player "
		+ "command, looted, searched, camped, saved, and reloaded."
	)
	quit(0)

func _walk_five_hexes(macro_map: MacroGameManager) -> bool:
	var previous := macro_map.player_token.current_hex_coords
	for coords in WALK_PATH:
		if not MacroGameManager.HEX_NEIGHBORS.has(coords - previous):
			return _fail("The demonstration path contains a non-adjacent step.")
		if world_state.has_entity_at(coords):
			return _fail("The five-Hex demonstration path is not collision-free.")
		macro_map.debug_step_player_to(coords)
		await process_frame
		previous = coords

	if macro_map.player_token.current_hex_coords != WALK_PATH[-1]:
		return _fail("The player did not complete the five-Hex walk.")
	return true

func _defeat_and_loot_enemy(director: GameDirector) -> bool:
	var macro_map := director.macro_map
	var origin := macro_map.player_token.current_hex_coords
	var enemy_coords := _nearest_enemy_coords(origin, macro_map.active_enemies.keys())
	if _hex_distance(origin, enemy_coords) != 1:
		var spawn_coords := origin + Vector2i(1, 0)
		if not macro_map.world_generator.get_hex_at(spawn_coords).is_passable():
			spawn_coords = origin + Vector2i(0, 1)
		macro_map.spawn_procedural_enemy(
			spawn_coords,
			GameEnums.Faction.SCAVENGER_CELL,
			0
		)
		await process_frame
		enemy_coords = spawn_coords
	if _hex_distance(origin, enemy_coords) != 1:
		return _fail("The demonstration enemy is not adjacent after the five-Hex walk.")
	var enemy_id: String = macro_map.active_enemies[enemy_coords].entity_id

	macro_map.debug_step_player_to(enemy_coords)
	await process_frame
	if (
		macro_map.get_pending_interaction_type()
		!= GameEnums.MacroInteractionType.ENTITY_COLLISION
	):
		return _fail("The demonstration did not enter an entity collision.")

	macro_map.resolve_entity_ambush(GameEnums.AmbushPosition.CLOSE)
	await process_frame
	await process_frame
	var arena = director.get_active_arena()
	if arena == null:
		return _fail("The demonstration collision did not create combat.")

	var taken_loot := _new_zero_size_item("vertical_taken_loot")
	var remaining_loot := _new_zero_size_item("vertical_remaining_loot")
	arena.enemy_core.inventory.add_to_backpack(taken_loot)
	arena.enemy_core.inventory.add_to_backpack(remaining_loot)

	var weapon: ItemData = arena.player_core.inventory.get_active_weapon(false)
	if weapon == null:
		return _fail("The player has no firearm for the demonstration.")
	weapon.flesh_damage = GameEnums.SCALE_MAX * 10.0
	weapon.armor_penetration = GameEnums.SCALE_MAX
	var enemy_lane: int = arena.lane_manager._find_entity_lane(arena.enemy_core)
	var target_slot: CombatLaneSlot = arena.lane_manager.lane_slots[enemy_lane]
	target_slot.background = CombatRules.TileBackground.NONE
	target_slot.current_cover = CombatRules.TileObject.NONE
	_seed_for_hit(0.75)
	arena.command_adapter.request_player_action(
		GameEnums.ActionType.AIMED_SHOT,
		GameEnums.LimbRegion.HEAD
	)

	for _frame in range(300):
		if director.get_active_arena() == null:
			break
		if not world_state.is_entity_alive(enemy_id):
			break
		await process_frame
	if director.get_active_arena() != null and not world_state.is_entity_alive(enemy_id):
		var lingering_arena = director.get_active_arena()
		if lingering_arena and lingering_arena.turn_manager:
			lingering_arena.turn_manager.halt_loop()
		for _frame in range(120):
			if director.get_active_arena() == null:
				break
			await process_frame
	if director.get_active_arena() != null:
		return _fail("The player-issued aimed shot did not resolve combat.")
	if world_state.is_entity_alive(enemy_id):
		return _fail("The player-issued victory did not persist enemy death.")
	if not _ground_has(enemy_coords, taken_loot.instance_id):
		return _fail("Defeated enemy loot did not reach the combat Hex.")

	macro_map.open_inventory()
	await process_frame
	if not macro_map.inventory_panel.is_open():
		return _fail("Combat loot did not open the detached inventory panel.")
	macro_map.resolve_inventory_action(
		InventoryPanel.ACTION_TAKE,
		taken_loot.instance_id,
		GameEnums.EquipmentSlot.NONE
	)
	await process_frame
	if (
		macro_map.player_token.get_humanoid_core().inventory
		.find_item_by_instance_id(taken_loot.instance_id) == null
	):
		return _fail("The player could not transfer defeated-enemy loot.")
	if not _ground_has(enemy_coords, remaining_loot.instance_id):
		return _fail("The uncollected enemy loot did not remain on the ground.")
	macro_map.inventory_panel.close_panel()

	expected["dead_enemy_id"] = enemy_id
	expected["taken_loot_id"] = taken_loot.instance_id
	expected["remaining_loot_id"] = remaining_loot.instance_id
	expected["combat_coords"] = enemy_coords
	return true

func _search_and_camp(macro_map: MacroGameManager) -> bool:
	var poi_coords := Vector2i(4, 0)
	var origin := macro_map.player_token.current_hex_coords
	for step in _build_hex_path(origin, poi_coords):
		macro_map.debug_step_player_to(step)
		await process_frame

	if macro_map.get_pending_interaction_type() == GameEnums.MacroInteractionType.POI:
		return _fail("Landmark POI auto-opened on step instead of Act entry.")

	var hex_data := macro_map.world_generator.get_hex_at(poi_coords)
	if not hex_data.has_landmark():
		return _fail("The demonstration landmark was not present at (4, 0).")
	macro_map.debug_begin_poi_interaction(poi_coords, hex_data)
	await process_frame
	if (
		macro_map.get_pending_interaction_type()
		!= GameEnums.MacroInteractionType.POI
	):
		return _fail("The demonstration POI did not open via Act entry.")
	if not macro_map.exploration_window.is_open():
		return _fail("The exploration window did not open for the demonstration POI.")

	var player := macro_map.player_token.get_humanoid_core()
	var crowbar := _find_item(player, "crowbar")
	var lockpick := _find_item(player, "multitool")
	var sleeping_bag := _find_item(player, "sleeping_bag")
	var tarp := _find_item(player, "tentkit")
	var noise_trap := _find_item(player, "trap_makeshift")
	if (
		crowbar == null
		or lockpick == null
		or sleeping_bag == null
		or tarp == null
		or noise_trap == null
	):
		return _fail("The demonstration loadout is missing POI tools.")

	hex_data = macro_map.world_generator.get_hex_at(poi_coords)
	var profile := MacroInteractionResolver.build_poi_profile(
		world_state.world_seed,
		poi_coords,
		hex_data.biome,
		hex_data.poi_id
	)
	var loot_catalog := root.get_node("LootCatalog")
	var loot_profile: Dictionary = loot_catalog.call(
		"get_profile_descriptor",
		WorldRules.get_loot_profile_id(hex_data.biome, hex_data.poi_id)
	)
	var search_descriptors := [
		crowbar.to_interaction_descriptor(),
		lockpick.to_interaction_descriptor(),
	]
	var search_attempt := _find_loot_search_attempt(
		poi_coords,
		profile["search"],
		search_descriptors,
		loot_profile
	)
	if search_attempt < 0:
		return _fail("No deterministic quiet SEARCH result produced loot.")
	hex_data.search_count = search_attempt

	var before_ids := _ground_ids(poi_coords)
	macro_map.resolve_poi_action(
		GameEnums.PoiAction.SEARCH,
		[crowbar.instance_id, lockpick.instance_id]
	)
	await process_frame
	var search_loot_id := _first_new_ground_id(poi_coords, before_ids)
	if search_loot_id.is_empty():
		return _fail("SEARCH did not create persistent ground loot.")

	macro_map.open_inventory()
	await process_frame
	macro_map.resolve_inventory_action(
		InventoryPanel.ACTION_TAKE,
		search_loot_id,
		GameEnums.EquipmentSlot.NONE
	)
	await process_frame
	if player.inventory.find_item_by_instance_id(search_loot_id) == null:
		return _fail("The player could not collect the SEARCH result.")

	var camp_descriptors := [
		sleeping_bag.to_interaction_descriptor(),
		tarp.to_interaction_descriptor(),
		noise_trap.to_interaction_descriptor(),
	]
	var camp_metrics := MacroInteractionResolver.calculate_camp_metrics(
		profile["camp"],
		camp_descriptors
	)
	hex_data.camp_rest_count = _find_safe_camp_attempt(
		poi_coords,
		camp_metrics
	)
	player.body.fatigue = 10.0
	var fatigue_before := player.body.fatigue
	var time_before := world_state.world_time_minutes
	macro_map.resolve_poi_action(
		GameEnums.PoiAction.CAMP,
		[
			sleeping_bag.instance_id,
			tarp.instance_id,
			noise_trap.instance_id,
		]
	)
	await process_frame

	if world_state.world_time_minutes <= time_before:
		return _fail("CAMP did not advance authoritative time.")
	if (
		(world_state.world_time_minutes - time_before) % GameTimeRules.CAMP_MINUTES
		!= 0
	):
		return _fail("CAMP advanced world time in non-camp increments.")
	if player.body.fatigue >= fatigue_before:
		return _fail("CAMP did not improve the player's fatigue.")
	if hex_data.camp_item_states.size() != 2:
		return _fail("CAMP did not persist its installed camp gear.")
	if hex_data.camp_traps.size() != 1:
		return _fail("CAMP did not persist its installed trap.")

	expected["search_loot_id"] = search_loot_id
	return true

func _verify_reloaded_slice(macro_map: MacroGameManager) -> bool:
	var player := macro_map.player_token.get_humanoid_core()
	var coords: Vector2i = expected["coords"]
	if macro_map.player_token.current_hex_coords != coords:
		return _fail("Reload changed the final player position.")
	if world_state.world_time_minutes != int(expected["world_time"]):
		return _fail("Reload changed final world time.")
	if not is_equal_approx(
		player.body.limb_hp[GameEnums.LimbRegion.LEFT_ARM],
		float(expected["arm_hp"])
	):
		return _fail("Reload changed the final player injury.")
	if world_state.is_entity_alive(expected["dead_enemy_id"]):
		return _fail("Reload resurrected the defeated enemy.")
	if player.inventory.find_item_by_instance_id(expected["taken_loot_id"]) == null:
		return _fail("Reload lost transferred enemy loot.")
	if player.inventory.find_item_by_instance_id(expected["search_loot_id"]) == null:
		return _fail("Reload lost collected SEARCH loot.")
	if not _ground_has(expected["combat_coords"], expected["remaining_loot_id"]):
		return _fail("Reload lost remaining ground loot.")

	var hex_data := macro_map.world_generator.get_hex_at(coords)
	if hex_data.search_count != int(expected["search_count"]):
		return _fail("Reload changed SEARCH depletion.")
	if hex_data.camp_rest_count != int(expected["camp_rest_count"]):
		return _fail("Reload changed CAMP history.")
	if hex_data.camp_item_states.size() != int(expected["camp_item_count"]):
		return _fail("Reload changed installed CAMP gear.")
	return true

func _spawn_game() -> GameDirector:
	var main_scene := load(
		"res://SystemCore/game_director.tscn"
	) as PackedScene
	if main_scene == null:
		_fail("Could not load the configured main scene.")
		return null
	var director := main_scene.instantiate() as GameDirector
	root.add_child(director)
	await process_frame
	await process_frame
	return director

func _new_zero_size_item(item_id: String) -> ItemData:
	var definition := ItemData.new()
	definition.id = item_id
	definition.display_name = item_id.capitalize()
	definition.size_cost = 0
	return definition.create_runtime_instance()

func _seed_for_hit(hit_chance: float) -> void:
	for candidate in range(1000):
		seed(candidate)
		if randf() <= hit_chance:
			seed(candidate)
			return

func _find_item(core: HumanoidCore, item_id: String) -> ItemData:
	for item in core.inventory.get_all_items():
		if item.id == item_id:
			return item
	return null

func _find_loot_search_attempt(
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
			world_state.world_seed,
			coords,
			attempt,
			metrics,
			loot_profile
		)
		if (
			not result.get("attracted_enemy", false)
			and not result.get("loot_ids", []).is_empty()
		):
			return attempt
	return -1

func _find_safe_camp_attempt(coords: Vector2i, metrics: Dictionary) -> int:
	for attempt in range(32):
		var result := MacroInteractionResolver.resolve_camp(
			world_state.world_seed,
			coords,
			attempt,
			metrics
		)
		if not result.get("interrupted", false):
			return attempt
	return 0

func _ground_ids(coords: Vector2i) -> Array:
	var ids: Array = []
	for item_state in world_state.get_ground_items(coords):
		ids.append(item_state.get("instance_id", ""))
	return ids

func _first_new_ground_id(coords: Vector2i, previous_ids: Array) -> String:
	for item_state in world_state.get_ground_items(coords):
		var instance_id: String = item_state.get("instance_id", "")
		if not previous_ids.has(instance_id):
			return instance_id
	return ""

func _ground_has(coords: Vector2i, instance_id: String) -> bool:
	for item_state in world_state.get_ground_items(coords):
		if item_state.get("instance_id", "") == instance_id:
			return true
	return false

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

func _fail(message: String) -> bool:
	if world_state:
		world_state.delete_save_file(SAVE_PATH)
	push_error("[TEST FAIL] " + message)
	quit(1)
	return false
