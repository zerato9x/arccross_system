extends RefCounted

## Neutral macro presentation snapshots for inventory UI and world HUD.
## Domain rules stay in MacroGameManager callbacks passed at build time.


static func build_limb_snapshot(body: HumanoidBody) -> Array:
	var limbs: Array = []
	if body == null:
		return limbs
	for region in [
		GameEnums.LimbRegion.HEAD,
		GameEnums.LimbRegion.UPPER_TORSO,
		GameEnums.LimbRegion.LOWER_TORSO,
		GameEnums.LimbRegion.LEFT_ARM,
		GameEnums.LimbRegion.RIGHT_ARM,
		GameEnums.LimbRegion.LEFT_LEG,
		GameEnums.LimbRegion.RIGHT_LEG,
	]:
		var trauma_index := int(
			body.limb_trauma.get(region, GameEnums.TraumaType.NONE)
		)
		limbs.append({
			"region": GameEnums.LimbRegion.keys()[region],
			"current": float(body.limb_hp.get(region, 0.0)),
			"maximum": body.get_limb_max(region),
			"trauma": GameEnums.TraumaType.keys()[trauma_index],
		})
	return limbs


static func build_inventory_snapshot(
	player_core: HumanoidCore,
	player_coords: Vector2i,
	world_state: RuntimeStateStore,
	can_offer_equip_callback: Callable,
	allowed_equipment_slots_callback: Callable
) -> Dictionary:
	var inventory := player_core.inventory
	var equipment: Array = []
	var seen_slots: Dictionary = {}
	for slot in GameEnums.EquipmentSlot.values():
		if slot == GameEnums.EquipmentSlot.NONE:
			continue
		if seen_slots.has(slot):
			continue
		seen_slots[slot] = true
		var equipped: ItemData = inventory.paper_doll.get(slot)
		if equipped:
			equipment.append(
				item_inventory_descriptor(
					equipped,
					can_offer_equip_callback,
					allowed_equipment_slots_callback,
					inventory,
					slot
				)
			)

	var backpack: Array = []
	for item in inventory.backpack_array:
		backpack.append(
			item_inventory_descriptor(
				item,
				can_offer_equip_callback,
				allowed_equipment_slots_callback,
				inventory,
				GameEnums.EquipmentSlot.NONE,
				inventory.get_item_container_slot(item)
			)
		)

	var ground: Array = []
	for item_state in world_state.get_ground_items(player_coords):
		ground.append(
			ground_inventory_descriptor(
				item_state,
				can_offer_equip_callback,
				allowed_equipment_slots_callback,
				inventory
			)
		)

	var capacity_breakdown: Array = []
	var containers: Array = []
	for slot in inventory.get_storage_slots():
		var equipped: ItemData = inventory.paper_doll.get(slot)
		var container_items: Array = []
		for item in inventory.get_container_items(slot):
			container_items.append(
				item_inventory_descriptor(
					item,
					can_offer_equip_callback,
					allowed_equipment_slots_callback,
					inventory,
					GameEnums.EquipmentSlot.NONE,
					slot
				)
			)
		capacity_breakdown.append({
			"name": equipped.display_name,
			"capacity": equipped.capacity_bonus,
		})
		containers.append({
			"slot": slot,
			"name": equipped.display_name,
			"capacity": inventory.get_container_capacity(slot),
			"used": inventory.get_container_used_capacity(slot),
			"combat_accessible": slot == GameEnums.EquipmentSlot.VEST,
			"items": container_items,
		})

	return {
		"coords": player_coords,
		"world_time": world_state.get_world_time_snapshot(),
		"current_capacity": inventory.current_size,
		"maximum_capacity": inventory.current_max_capacity,
		"capacity_breakdown": capacity_breakdown,
		"containers": containers,
		"equipment": equipment,
		"limbs": build_limb_snapshot(player_core.body),
		"backpack": backpack,
		"ground": ground,
	}


static func item_inventory_descriptor(
	item: ItemData,
	can_offer_equip_callback: Callable,
	allowed_equipment_slots_callback: Callable,
	inventory: InventorySystem,
	equipment_slot: int = GameEnums.EquipmentSlot.NONE,
	container_slot: int = GameEnums.EquipmentSlot.NONE
) -> Dictionary:
	var allowed_slots: Array = allowed_equipment_slots_callback.call(item)
	return {
		"instance_id": item.instance_id,
		"item_id": item.id,
		"name": item.display_name,
		"description": item.lore_description,
		"item_type": item.item_type,
		"catalog_category": item.catalog_category,
		"tags": item.tags.duplicate(),
		"interaction_roles": item.interaction_roles.duplicate(),
		"roles": item.interaction_roles.duplicate(),
		"size_cost": item.get_inventory_cost(),
		"item_size": item.get_effective_item_size(),
		"stack_count": item.stack_count,
		"stack_limit": item.get_stack_limit(),
		"capacity_bonus": item.capacity_bonus,
		"target_slot": item.target_slot,
		"preferred_equipment_slot": inventory.get_preferred_equipment_slot(item),
		"allowed_equipment_slots": allowed_slots,
		"equipment_slot": equipment_slot,
		"container_slot": container_slot,
		"can_equip": can_offer_equip_callback.call(item),
		"can_consume": item.item_type == GameEnums.ItemType.CONSUMABLE,
		"can_load_magazine": (
			item.is_magazine()
			and item.loaded_rounds < item.magazine_capacity
		),
		"can_pick_up": item.get_effective_item_size() != GameEnums.ItemSize.BIG,
		"sprite_path": item.get_inventory_sprite_path(),
		"equipped_sprite_paths": item.get_equipped_sprite_paths(),
		"requires_two_hands": item.requires_two_hands,
		"weapon_type": item.weapon_type,
		"damage_type": item.damage_type,
		"flesh_damage": item.flesh_damage,
		"stance_damage": item.stance_damage,
		"armor_penetration": item.armor_penetration,
		"accuracy_rating": item.accuracy_rating,
		"effective_range": item.effective_range,
		"optimal_range": item.optimal_range,
		"protection_blunt": item.protection_blunt,
		"protection_sharp": item.protection_sharp,
		"protection_ballistic": item.protection_ballistic,
		"bulk": item.bulk,
		"weight": item.weight,
		"threat": item.threat,
		"insulation": item.insulation,
		"consumable_effect": item.consumable_effect,
		"consumable_potency": item.consumable_potency,
		"current_magazine": item.current_magazine,
		"max_magazine": item.max_magazine,
		"needs_cycling": item.needs_cycling,
		"accepted_ammunition_id": item.accepted_ammunition_id,
		"magazine_capacity": item.magazine_capacity,
		"loaded_rounds": item.loaded_rounds,
		"search_loot_bonus": item.search_loot_bonus,
		"search_safety_bonus": item.search_safety_bonus,
		"search_sneak_bonus": item.search_sneak_bonus,
		"camp_sleep_bonus": item.camp_sleep_bonus,
		"camp_shelter_bonus": item.camp_shelter_bonus,
		"camp_healing_bonus": item.camp_healing_bonus,
		"camp_concealment_bonus": item.camp_concealment_bonus,
		"camp_alertness_bonus": item.camp_alertness_bonus,
	}


static func ground_inventory_descriptor(
	item_state: Dictionary,
	can_offer_equip_callback: Callable,
	allowed_equipment_slots_callback: Callable,
	inventory: InventorySystem
) -> Dictionary:
	var item := ItemData.from_runtime_state(item_state)
	var descriptor := item_inventory_descriptor(
		item,
		can_offer_equip_callback,
		allowed_equipment_slots_callback,
		inventory
	)
	descriptor["can_equip"] = false
	descriptor["can_consume"] = false
	descriptor["can_load_magazine"] = false
	return descriptor


static func enum_key(keys: Array, value: int) -> String:
	if value >= 0 and value < keys.size():
		return str(keys[value])
	return str(value)


static func build_hex_descriptor(
	coords: Vector2i,
	player_coords: Vector2i,
	hex_data: MacroHexData,
	entity_record: EntityRecord,
	ground_items: Array,
	hex_label: String,
	is_entity_alive_callback: Callable,
	is_entity_hostile_callback: Callable,
	ensure_npc_purpose_callback: Callable,
	hex_distance_callback: Callable
) -> Dictionary:
	var entity_name := ""
	var entity_status := ""
	var entity_purpose := ""
	var hostile := false
	if entity_record != null and is_entity_alive_callback.call(
		entity_record.entity_id
	):
		entity_name = str(
			entity_record.definition.get("archetype_name", "Unknown")
		)
		entity_status = enum_key(
			GameEnums.EntityWorldStatus.keys(),
			int(entity_record.world_status)
		)
		entity_purpose = ensure_npc_purpose_callback.call(entity_record).capitalize()
		hostile = is_entity_hostile_callback.call(entity_record.entity_id)

	var distance: int = hex_distance_callback.call(player_coords, coords)
	return {
		"coords": coords,
		"label": hex_label,
		"region": enum_key(GameEnums.MacroRegion.keys(), int(hex_data.region)),
		"arm_direction": enum_key(
			GameEnums.MacroArmDirection.keys(),
			int(hex_data.arm_direction)
		),
		"terrain": enum_key(
			GameEnums.MacroTerrainTile.keys(),
			int(hex_data.terrain_tile)
		),
		"flora": enum_key(
			GameEnums.MacroFloraLayer.keys(),
			int(hex_data.flora_layer)
		),
		"rock": enum_key(GameEnums.MacroRockLayer.keys(), int(hex_data.rock_layer)),
		"structure": enum_key(
			GameEnums.MacroStructureLayer.keys(),
			int(hex_data.structure_layer)
		),
		"passable": hex_data.is_passable(),
		"explored": hex_data.is_explored,
		"hazard": hex_data.hazard_level,
		"distance": distance,
		"is_current": coords == player_coords,
		"can_travel": distance == 1 and hex_data.is_passable(),
		"can_interact": (
			coords == player_coords
			and (
				hex_data.has_landmark()
				or not ground_items.is_empty()
				or hostile
			)
		),
		"is_poi": hex_data.is_poi,
		"poi_name": hex_data.poi_name,
		"search_count": hex_data.search_count,
		"camp_rest_count": hex_data.camp_rest_count,
		"ground_item_count": ground_items.size(),
		"entity_name": entity_name,
		"entity_status": entity_status,
		"entity_purpose": entity_purpose,
		"hostile": hostile,
	}


static func build_macro_activity_snapshot(
	player_coords: Vector2i,
	macro_turn_index: int,
	active_token_count: int,
	entity_records: Array,
	ensure_npc_purpose_callback: Callable,
	hex_distance_callback: Callable
) -> Dictionary:
	var hostile_count := 0
	var passive_count := 0
	var purpose_counts: Dictionary = {}
	var nearest_hostile_distance := 999999
	var nearest_hostile_coords := Vector2i.ZERO
	var nearest_hostile_name := ""
	for record in entity_records:
		if not record is EntityRecord:
			continue
		if (
			record.kind != GameEnums.RuntimeEntityKind.NPC
			or record.life_state != GameEnums.EntityLifeState.ALIVE
			or record.world_status == GameEnums.EntityWorldStatus.WITHDRAWN
		):
			continue
		if record.world_status == GameEnums.EntityWorldStatus.HOSTILE:
			hostile_count += 1
			var purpose: String = ensure_npc_purpose_callback.call(record)
			purpose_counts[purpose] = int(purpose_counts.get(purpose, 0)) + 1
			var distance: int = hex_distance_callback.call(
				player_coords,
				record.coords
			)
			if distance < nearest_hostile_distance:
				nearest_hostile_distance = distance
				nearest_hostile_coords = record.coords
				nearest_hostile_name = str(
					record.definition.get("archetype_name", "Unknown")
				)
		else:
			passive_count += 1
	return {
		"turn": macro_turn_index,
		"active_tokens": active_token_count,
		"hostile_count": hostile_count,
		"passive_count": passive_count,
		"purpose_counts": purpose_counts,
		"nearest_hostile_distance": nearest_hostile_distance,
		"nearest_hostile_coords": nearest_hostile_coords,
		"nearest_hostile_name": nearest_hostile_name,
	}


static func build_world_hud_snapshot(
	player_core: HumanoidCore,
	player_coords: Vector2i,
	selected_hex_coords: Vector2i,
	world_time: Dictionary,
	last_macro_event: String,
	macro_turn_index: int,
	active_token_count: int,
	world_state: RuntimeStateStore,
	world_generator: HexWorldGenerator,
	ensure_npc_purpose_callback: Callable,
	hex_distance_callback: Callable,
	hex_label_callback: Callable,
	is_entity_alive_callback: Callable,
	is_entity_hostile_callback: Callable
) -> Dictionary:
	if player_core == null or player_core.body == null or player_core.inventory == null:
		return {}
	var body := player_core.body
	var inventory := player_core.inventory
	var current_hex := world_generator.get_hex_at(player_coords)
	var selected_hex := world_generator.get_hex_at(selected_hex_coords)
	return {
		"coords": player_coords,
		"current_hex": build_hex_descriptor(
			player_coords,
			player_coords,
			current_hex,
			world_state.get_entity_at(player_coords),
			world_state.get_ground_items(player_coords),
			hex_label_callback.call(player_coords, current_hex),
			is_entity_alive_callback,
			is_entity_hostile_callback,
			ensure_npc_purpose_callback,
			hex_distance_callback
		),
		"selected_hex": build_hex_descriptor(
			selected_hex_coords,
			player_coords,
			selected_hex,
			world_state.get_entity_at(selected_hex_coords),
			world_state.get_ground_items(selected_hex_coords),
			hex_label_callback.call(selected_hex_coords, selected_hex),
			is_entity_alive_callback,
			is_entity_hostile_callback,
			ensure_npc_purpose_callback,
			hex_distance_callback
		),
		"macro_activity": build_macro_activity_snapshot(
			player_coords,
			macro_turn_index,
			active_token_count,
			world_state.get_all_entity_records(),
			ensure_npc_purpose_callback,
			hex_distance_callback
		),
		"last_macro_event": last_macro_event,
		"world_time": world_time,
		"blood": body.blood_level,
		"hunger": body.hunger,
		"thirst": body.thirst,
		"fatigue": body.fatigue,
		"core_temperature": body.core_temperature,
		"stance": player_core.stance_points,
		"stance_state": GameEnums.StanceState.keys()[player_core.current_stance],
		"morale": player_core.current_morale,
		"arc_energy": player_core.current_arc_energy,
		"red_mist": player_core.red_mist_corruption,
		"current_capacity": inventory.current_size,
		"maximum_capacity": inventory.current_max_capacity,
		"limbs": build_limb_snapshot(body),
	}
