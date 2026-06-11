extends SceneTree

const SAVE_PATH: String = "user://phase_1_save_load_smoke.json"

var world_state: RuntimeStateStore
var expected: Dictionary = {}

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	world_state = root.get_node("WorldState") as RuntimeStateStore
	world_state.delete_save_file(SAVE_PATH)

	var first_director: GameDirector = await _spawn_game()
	if first_director == null:
		return
	if not await _prepare_and_save(first_director):
		return

	first_director.queue_free()
	await process_frame
	await process_frame
	world_state.begin_new_world("SCRAMBLED_TEST_STATE")

	if not world_state.load_from_disk(SAVE_PATH):
		_fail("Loading failed: " + world_state.get_last_persistence_error())
		return

	var restored_director: GameDirector = await _spawn_game()
	if restored_director == null:
		return
	if not _verify_restored_state(restored_director):
		return

	restored_director.queue_free()
	world_state.delete_save_file(SAVE_PATH)
	print(
		"[TEST PASS] Versioned JSON save/load restored position, biology, "
		+ "inventory, firearm state, Hex changes, enemy death, and ground loot."
	)
	quit(0)

func _prepare_and_save(game_director: GameDirector) -> bool:
	var macro_map: MacroGameManager = game_director.macro_map
	var player_core: HumanoidCore = macro_map.player_token.get_humanoid_core()
	var save_coords := Vector2i(1, 0)
	macro_map._execute_player_step(save_coords)
	await process_frame

	player_core.body.apply_targeted_hit(
		GameEnums.LimbRegion.LEFT_ARM,
		0.75,
		0.0
	)

	var firearm: ItemData = player_core.inventory.get_active_weapon(false)
	if firearm == null:
		return _fail("The save fixture has no equipped firearm.")
	firearm.current_magazine = 1

	var carried := ItemData.new()
	carried.id = "save_round_trip_item"
	carried.display_name = "Save Round Trip Item"
	carried.size_cost = 0
	var carried_instance: ItemData = carried.create_runtime_instance()
	if not player_core.inventory.add_to_backpack(carried_instance):
		return _fail("Could not add the save round-trip item.")

	var hex_data: MacroHexData = macro_map.world_generator.get_hex_at(save_coords)
	hex_data.search_count = 2
	hex_data.camp_rest_count = 1
	hex_data.camp_item_states = [_runtime_item_state("tarp_shelter")]

	var enemy_records: Array = world_state.get_all_entity_records()
	if enemy_records.is_empty():
		return _fail("The save fixture generated no enemy records.")
	var enemy_record: Dictionary = enemy_records[0]
	var dead_enemy_id: String = enemy_record.get("entity_id", "")
	world_state.set_entity_life_state(
		dead_enemy_id,
		GameEnums.EntityLifeState.DEAD
	)

	var ground_state: Dictionary = _runtime_item_state("clean_water")
	world_state.add_ground_items(save_coords, [ground_state])
	world_state.advance_world_time(137)

	expected = {
		"coords": save_coords,
		"arm_hp": player_core.body.limb_hp[GameEnums.LimbRegion.LEFT_ARM],
		"firearm_id": firearm.instance_id,
		"carried_id": carried_instance.instance_id,
		"dead_enemy_id": dead_enemy_id,
		"ground_item_id": ground_state.get("instance_id", ""),
		"time": world_state.world_time_minutes,
	}

	if not game_director.save_game(SAVE_PATH):
		return _fail("Saving failed: " + world_state.get_last_persistence_error())
	if not _disk_file_has_current_version():
		return false
	expected["entity_count"] = world_state.entity_records.size()
	expected["hex_count"] = world_state.hex_records.size()
	return true

func _verify_restored_state(game_director: GameDirector) -> bool:
	var macro_map: MacroGameManager = game_director.macro_map
	var player_core: HumanoidCore = macro_map.player_token.get_humanoid_core()
	var save_coords: Vector2i = expected["coords"]

	if world_state.world_seed != "DEMO_WASTELAND_01":
		return _fail("Reload did not restore the world seed.")
	if world_state.world_time_minutes != int(expected["time"]):
		return _fail("Reload did not restore authoritative world time.")
	if macro_map.player_token.current_hex_coords != save_coords:
		return _fail("Reload did not restore the player coordinates.")

	var restored_arm_hp: float = player_core.body.limb_hp[
		GameEnums.LimbRegion.LEFT_ARM
	]
	if not is_equal_approx(restored_arm_hp, float(expected["arm_hp"])):
		return _fail("Reload did not restore the player injury.")
	if (
		player_core.inventory.find_item_by_instance_id(
			expected["carried_id"]
		) == null
	):
		return _fail("Reload did not restore carried runtime item identity.")

	var firearm: ItemData = player_core.inventory.find_item_by_instance_id(
		expected["firearm_id"]
	)
	if firearm == null or firearm.current_magazine != 1:
		return _fail("Reload did not restore firearm runtime state.")

	var hex_data: MacroHexData = macro_map.world_generator.get_hex_at(save_coords)
	if (
		hex_data.search_count != 2
		or hex_data.camp_rest_count != 1
		or hex_data.camp_item_states.size() != 1
	):
		return _fail("Reload did not restore SEARCH and CAMP hex state.")
	if world_state.is_entity_alive(expected["dead_enemy_id"]):
		return _fail("Reload resurrected a dead persistent enemy.")
	if not _ground_has(save_coords, expected["ground_item_id"]):
		return _fail("Reload did not restore persistent ground loot.")
	if world_state.entity_records.size() != int(expected["entity_count"]):
		return _fail("Reload duplicated or deleted persistent entity records.")
	if world_state.hex_records.size() != int(expected["hex_count"]):
		return _fail("Reload duplicated or deleted generated hex records.")
	if _has_duplicate_entity_ids():
		return _fail("Reload produced duplicate entity identities.")
	return true

func _spawn_game() -> GameDirector:
	var main_scene := load(
		"res://SystemCore/game_director.tscn"
	) as PackedScene
	if main_scene == null:
		_fail("Could not load the configured game director scene.")
		return null
	var game_director := main_scene.instantiate() as GameDirector
	root.add_child(game_director)
	await process_frame
	await process_frame
	return game_director

func _runtime_item_state(item_id: String) -> Dictionary:
	var definition := load(
		"res://ItemCore/Items/%s.tres" % item_id
	) as ItemData
	if definition == null:
		return {}
	return definition.create_runtime_instance().to_runtime_state()

func _disk_file_has_current_version() -> bool:
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return _fail("The save file was not written to disk.")
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		return _fail("The save file is not valid JSON.")
	var data: Dictionary = json.data
	if int(data.get("version", -1)) != RuntimeStateStore.SAVE_VERSION:
		return _fail("The save file does not expose the current format version.")
	return true

func _ground_has(coords: Vector2i, instance_id: String) -> bool:
	for item_state in world_state.get_ground_items(coords):
		if item_state.get("instance_id", "") == instance_id:
			return true
	return false

func _has_duplicate_entity_ids() -> bool:
	var seen: Dictionary = {}
	for record in world_state.get_all_entity_records():
		var entity_id: String = record.get("entity_id", "")
		if seen.has(entity_id):
			return true
		seen[entity_id] = true
	return false

func _fail(message: String) -> bool:
	if world_state:
		world_state.delete_save_file(SAVE_PATH)
	push_error("[TEST FAIL] " + message)
	quit(1)
	return false
