extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var main_scene := load(
		"res://SystemCore/game_director.tscn"
	) as PackedScene
	if not main_scene:
		_fail("Could not load the game director scene.")
		return

	var game_director := main_scene.instantiate()
	root.add_child(game_director)
	await process_frame
	await process_frame

	var macro_map := game_director.get_node("MainWorld") as MacroGameManager
	var world_state := root.get_node("WorldState") as RuntimeStateStore
	if not macro_map or not world_state or not macro_map.inventory_panel:
		_fail("Inventory presentation or world systems did not initialize.")
		return

	var player_core := macro_map.player_token.get_humanoid_core()
	var coords := macro_map.player_token.current_hex_coords
	var water_state := _runtime_item_state("water_bottle")
	var shirt_state := _runtime_item_state("shirt_thermo")
	if water_state.is_empty() or shirt_state.is_empty():
		_fail("Could not create test item runtime states.")
		return

	world_state.add_ground_items(coords, [water_state, shirt_state])
	macro_map.open_inventory()
	await process_frame
	if not macro_map.inventory_panel.is_open():
		_fail("The inventory panel did not open.")
		return

	var snapshot := macro_map._build_inventory_snapshot()
	if snapshot.get("ground", []).size() != 2:
		_fail("The inventory snapshot did not expose persistent ground items.")
		return
	if snapshot.get("backpack", []).is_empty():
		_fail("The inventory snapshot did not expose backpack contents.")
		return

	macro_map.resolve_inventory_action(
		InventoryPanel.ACTION_TAKE,
		water_state.get("instance_id", ""),
		GameEnums.EquipmentSlot.NONE
	)
	await process_frame
	if _ground_has(world_state, coords, water_state.get("instance_id", "")):
		_fail("Taking an item did not remove its ground record.")
		return
	var water := player_core.inventory.find_item_by_instance_id(
		water_state.get("instance_id", "")
	)
	if water == null:
		_fail("Taking an item did not add it to the backpack.")
		return

	player_core.body.thirst = 2.0
	macro_map.resolve_inventory_action(
		InventoryPanel.ACTION_CONSUME,
		water.instance_id,
		GameEnums.EquipmentSlot.NONE
	)
	await process_frame
	if player_core.inventory.find_item_by_instance_id(water.instance_id) != null:
		_fail("Using a consumable did not remove its runtime item.")
		return
	if player_core.body.thirst <= 2.0:
		_fail("Using clean water did not route its biological effect.")
		return

	macro_map.resolve_inventory_action(
		InventoryPanel.ACTION_TAKE,
		shirt_state.get("instance_id", ""),
		GameEnums.EquipmentSlot.NONE
	)
	await process_frame
	var shirt := player_core.inventory.find_item_by_instance_id(
		shirt_state.get("instance_id", "")
	)
	if shirt == null:
		_fail("Could not take the equippable test item.")
		return

	macro_map.resolve_inventory_action(
		InventoryPanel.ACTION_EQUIP,
		shirt.instance_id,
		GameEnums.EquipmentSlot.INNER_TORSO
	)
	await process_frame
	var equipped: ItemData = player_core.inventory.paper_doll.get(
		GameEnums.EquipmentSlot.INNER_TORSO
	)
	if equipped == null or equipped.instance_id != shirt.instance_id:
		_fail("The authoritative inventory did not equip the requested item.")
		return

	macro_map.resolve_inventory_action(
		InventoryPanel.ACTION_UNEQUIP,
		shirt.instance_id,
		GameEnums.EquipmentSlot.INNER_TORSO
	)
	await process_frame
	if (
		player_core.inventory.paper_doll.get(
			GameEnums.EquipmentSlot.INNER_TORSO
		) != null
	):
		_fail("The authoritative inventory did not unequip the item.")
		return
	if player_core.inventory.find_item_by_instance_id(shirt.instance_id) == null:
		_fail("Unequipping did not return the item to the backpack.")
		return

	macro_map.resolve_inventory_action(
		InventoryPanel.ACTION_DROP,
		shirt.instance_id,
		GameEnums.EquipmentSlot.NONE
	)
	await process_frame
	if player_core.inventory.find_item_by_instance_id(shirt.instance_id) != null:
		_fail("Dropping did not remove the carried item.")
		return
	if not _ground_has(world_state, coords, shirt.instance_id):
		_fail("Dropping did not create a persistent ground record.")
		return

	var coat: ItemData = player_core.inventory.paper_doll.get(
		GameEnums.EquipmentSlot.OUTER_TORSO
	)
	if coat == null:
		_fail("The test loadout is missing its capacity-granting coat.")
		return
	var filler := load("res://ItemCore/Items/water_bottle_empty.tres") as ItemData
	while (
		filler
		and player_core.inventory.current_size
			< player_core.inventory.current_max_capacity
	):
		if not player_core.inventory.add_to_backpack(filler):
			break
	var ground_count_before_spill := world_state.get_ground_items(coords).size()
	macro_map.resolve_inventory_action(
		InventoryPanel.ACTION_UNEQUIP,
		coat.instance_id,
		GameEnums.EquipmentSlot.OUTER_TORSO
	)
	await process_frame
	if (
		player_core.inventory.current_size
		> player_core.inventory.current_max_capacity
	):
		_fail("Capacity reduction left the backpack overfilled.")
		return
	if world_state.get_ground_items(coords).size() <= ground_count_before_spill:
		_fail("Capacity overflow did not create persistent ground remnants.")
		return

	var poi_coords := Vector2i(1, 0)
	var poi_hex := macro_map.world_generator.get_hex_at(poi_coords)
	var camp_access := macro_map._get_camp_access(poi_coords, poi_hex)
	if not camp_access.get("allowed", false):
		_fail("The demo POI did not satisfy the CAMP safety rule.")
		return
	poi_hex.hazard_level = WorldRules.CAMP_HAZARD_LIMIT + 1.0
	if macro_map._get_camp_access(poi_coords, poi_hex).get("allowed", true):
		_fail("A hazardous location incorrectly allowed CAMP.")
		return

	var stored_runtime: Dictionary = (
		world_state.player_record.runtime
		if world_state.player_record
		else {}
	)
	if stored_runtime.get("inventory", {}).is_empty():
		_fail("Inventory commands did not update the persistent player record.")
		return

	print(
		"[TEST PASS] Inventory snapshots and intents preserve authoritative "
		+ "take, use, equip, unequip, drop, and CAMP safety behavior."
	)
	quit(0)

func _runtime_item_state(item_id: String) -> Dictionary:
	var definition := load(
		"res://ItemCore/Items/%s.tres" % item_id
	) as ItemData
	if not definition:
		return {}
	return definition.create_runtime_instance().to_runtime_state()

func _ground_has(
	world_state: RuntimeStateStore,
	coords: Vector2i,
	instance_id: String
) -> bool:
	for item_state in world_state.get_ground_items(coords):
		if item_state.get("instance_id", "") == instance_id:
			return true
	return false

func _fail(message: String) -> void:
	push_error("[TEST FAIL] " + message)
	quit(1)
