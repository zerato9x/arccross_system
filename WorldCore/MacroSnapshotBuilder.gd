extends RefCounted

## Neutral macro presentation snapshots for inventory UI and world HUD.
## Domain rules stay in MacroGameManager callbacks passed at build time.

static func build_limb_snapshot(body: HumanoidBody) -> Array:
	return BiologicalSnapshotService.capture_limbs(body)


static func build_medical_item_snapshot(inventory: InventorySystem) -> Array:
	return InventorySnapshotService.capture_medical_items(inventory)


static func build_emergencies(body: HumanoidBody, player_core: HumanoidCore) -> Array:
	return BiologicalSnapshotService.capture_emergencies(body)


static func build_inventory_snapshot(
	player_core: HumanoidCore,
	player_coords: Vector2i,
	world_state: RuntimeStateStore,
	can_offer_equip_callback: Callable,
	allowed_equipment_slots_callback: Callable
) -> Dictionary:
	return build_inventory_snapshot_from_neutral(
		BiologicalSnapshotService.capture(player_core),
		InventorySnapshotService.capture(
			player_core,
			world_state.get_ground_items(player_coords),
			can_offer_equip_callback,
			allowed_equipment_slots_callback
		),
		player_coords,
		world_state.get_world_time_snapshot()
	)


static func build_inventory_snapshot_from_neutral(
	biological_snapshot: Dictionary,
	inventory_snapshot: Dictionary,
	player_coords: Vector2i,
	world_time: Dictionary
) -> Dictionary:
	if biological_snapshot.is_empty() or inventory_snapshot.is_empty():
		return {}
	var result := inventory_snapshot.duplicate(true)
	result["coords"] = player_coords
	result["world_time"] = world_time.duplicate(true)
	result["character"] = biological_snapshot.get("character", {}).duplicate(true)
	result["limbs"] = biological_snapshot.get("limbs", []).duplicate(true)
	var loadout: Dictionary = result.get("loadout_stats", {}).duplicate(true)
	loadout["threat"] = float(biological_snapshot.get("threat", 0.0))
	loadout["burden"] = float(biological_snapshot.get("burden", 0.0))
	loadout["kinetic_tier"] = str(biological_snapshot.get("kinetic_tier", ""))
	result["loadout_stats"] = loadout
	return result


static func _legacy_build_inventory_snapshot(
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
		"character": build_character_snapshot(player_core),
		"loadout_stats": {
			"weight": inventory.get_total_weight(),
			"bulk": inventory.get_total_bulk(),
			"threat": player_core.get_effective_threat(),
			"insulation": inventory.get_total_insulation(),
			"protection_blunt": inventory.get_protection_for(GameEnums.DamageType.BLUNT),
			"protection_sharp": inventory.get_protection_for(GameEnums.DamageType.SHARP),
			"protection_ballistic": inventory.get_protection_for(GameEnums.DamageType.BALLISTIC),
			"burden": player_core.total_burden,
			"kinetic_tier": GameEnums.KineticTier.keys()[player_core.kinetic_tier],
		},
		"medical_items": build_medical_item_snapshot(inventory),
		"containers": containers,
		"equipment": equipment,
		"limbs": build_limb_snapshot(player_core.body),
		"backpack": backpack,
		"ground": ground,
	}


static func build_character_snapshot(player_core: HumanoidCore) -> Dictionary:
	return BiologicalSnapshotService.capture_character(player_core)


static func item_inventory_descriptor(
	item: ItemData,
	can_offer_equip_callback: Callable,
	allowed_equipment_slots_callback: Callable,
	inventory: InventorySystem,
	equipment_slot: int = GameEnums.EquipmentSlot.NONE,
	container_slot: int = GameEnums.EquipmentSlot.NONE
) -> Dictionary:
	return InventorySnapshotService.descriptor(
		item,
		can_offer_equip_callback,
		allowed_equipment_slots_callback,
		inventory,
		equipment_slot,
		container_slot
	)


static func _legacy_item_inventory_descriptor(
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
		"item_grade": item.item_grade,
		"condition_enabled": item.condition_enabled,
		"repair_domain": item.repair_domain,
		"maintenance_constraint": item.maintenance_constraint,
		"current_condition": item.current_condition,
		"condition_band": ItemConditionRules.condition_band(item.current_condition),
		"fault_chance": ItemConditionRules.fault_chance(item.current_condition),
		"is_jammed": item.is_jammed,
		"readiness": ItemConditionRules.readiness_descriptor(item),
		"tags": item.tags.duplicate(),
		"functional_roles": Array(item.get_functional_roles()),
		"knowledge_entry_id": item.knowledge_entry_id,
		"can_inspect_knowledge": item.can_inspect_knowledge(),
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
		"balance_impact": item.balance_impact,
		"armor_penetration": item.armor_penetration,
		"accuracy_rating": item.accuracy_rating,
		"maximum_range_cells": item.maximum_range_cells,
		"optimal_range_cells": item.optimal_range_cells,
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
	return InventorySnapshotService.ground_descriptor(
		item_state,
		can_offer_equip_callback,
		allowed_equipment_slots_callback,
		inventory
	)


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
	hex_distance_callback: Callable,
	movement_active: bool = false,
	travel_known: bool = false
) -> Dictionary:
	var is_current := coords == player_coords
	var is_known := hex_data.is_explored or is_current
	var is_travel_known := is_known or travel_known
	var entity_name := ""
	var entity_status := ""
	var entity_purpose := ""
	var hostile := false
	if is_known and entity_record != null and is_entity_alive_callback.call(
		entity_record.entity_id
	):
		entity_name = str(
			entity_record.definition.get("archetype_name", "Unknown")
		)
		entity_status = enum_key(
			GameEnums.EntityWorldStatus.keys(),
			int(entity_record.world_status)
		)
		# Purpose resolution is presentation-only here. The simulator helper
		# normalizes missing purpose fields, so never hand it the live store record.
		var purpose_record := EntityRecord.from_dict(entity_record.to_dict())
		entity_purpose = ensure_npc_purpose_callback.call(purpose_record).capitalize()
		hostile = is_entity_hostile_callback.call(entity_record.entity_id)

	var entity_inspect := {}
	if is_known and entity_record != null and not entity_name.is_empty():
		entity_inspect = MacroEntityCollisionResolver.build_opponent_summary(
			entity_record
		)

	var distance: int = hex_distance_callback.call(player_coords, coords)
	var travel_minutes := GameTimeRules.move_minutes_for_hex(hex_data) if distance == 1 else 0
	var travel_km := GameTimeRules.travel_distance_km(1) if distance == 1 else 0.0
	var search_site: Dictionary = {}
	if not hex_data.search_site_id.is_empty():
		var search_catalog := SearchSiteCatalog.data()
		search_site = (
			search_catalog.descriptor(hex_data.search_site_id)
			if search_catalog != null
			else {}
		)
	var search_requirements: Dictionary = search_site.get("requirements", {})
	var descriptor := {
		"coords": coords,
		"label": hex_label if is_known else "HEX %d,%d // UNKNOWN" % [coords.x, coords.y],
		"region": (
			enum_key(GameEnums.MacroRegion.keys(), int(hex_data.region))
			if is_known else "UNKNOWN"
		),
		"arm_direction": enum_key(
			GameEnums.MacroArmDirection.keys(),
			int(hex_data.arm_direction)
		) if is_known else "UNKNOWN",
		"terrain": enum_key(
			GameEnums.MacroTerrainTile.keys(),
			int(hex_data.terrain_tile)
		) if is_known else "UNKNOWN",
		"flora": enum_key(
			GameEnums.MacroFloraLayer.keys(),
			int(hex_data.flora_layer)
		) if is_known else "UNKNOWN",
		"rock": (
			enum_key(GameEnums.MacroRockLayer.keys(), int(hex_data.rock_layer))
			if is_known else "UNKNOWN"
		),
		"water": enum_key(
			GameEnums.MacroWaterLayer.keys(),
			int(hex_data.water_layer)
		) if is_known else "UNKNOWN",
		"structure": (
			enum_key(
				GameEnums.MacroStructureLayer.keys(),
				int(hex_data.structure_layer)
			)
			if is_known else "UNKNOWN"
		),
		"passable": hex_data.is_passable(),
		"explored": hex_data.is_explored or is_current,
		"hazard": hex_data.hazard_level if is_known else 0.0,
		"distance": distance,
		"travel_minutes": travel_minutes,
		"travel_km": travel_km,
		"travel_exertion": hex_data.travel_exertion(),
		"is_current": is_current,
		"travel_known": is_travel_known,
		"can_travel": (
			distance > 0
			and is_travel_known
			and hex_data.is_passable()
		),
		"can_interact": is_current,
		"is_poi": hex_data.is_poi if is_known else false,
		"poi_name": hex_data.poi_name if is_known else "",
		"search_count": hex_data.search_count if is_known else 0,
		"search_site_id": hex_data.search_site_id if is_known else "",
		"search_site_name": str(search_site.get("display_name", "")) if is_known else "",
		"search_site_description": str(search_site.get("description", "")) if is_known else "",
		"search_marker_kind": str(search_site.get("marker_kind", "")) if is_known else "",
		"search_requires_access": is_known and not search_requirements.is_empty(),
		"search_depleted": is_known and not search_site.is_empty() and hex_data.search_count > 0,
		"camp_rest_count": hex_data.camp_rest_count if is_known else 0,
		"ground_item_count": ground_items.size() if is_known else 0,
		"entity_name": entity_name,
		"entity_status": entity_status,
		"entity_purpose": entity_purpose,
		"hostile": hostile,
		"entity_inspect": entity_inspect,
		"feature_title": feature_title(hex_data) if is_known else "Unknown Hex",
		"environment_summary": (
			environment_summary(hex_data)
			if is_known else "No survey data is available for this hex."
		),
		"movement_note": movement_note(hex_data) if is_known else "UNKNOWN // travel here to survey",
		"visibility": _hex_visibility(hex_data) if is_known else "UNKNOWN",
		"cover": _hex_cover(hex_data) if is_known else "UNKNOWN",
		"resource_hint": resource_hint(hex_data) if is_known else "Possible finds: unknown",
	}
	descriptor["exploration"] = {
		"available": is_current and not movement_active,
		"lock_reason": (
			"Movement in progress"
			if is_current and movement_active
			else ("Travel here first" if not is_current else "")
		),
	}
	descriptor["intel_signals"] = _build_intel_signals(
		hex_data,
		search_site,
		search_requirements,
		ground_items,
		is_known,
		hostile,
	)
	return descriptor


static func _build_intel_signals(
	hex_data: MacroHexData,
	search_site: Dictionary,
	search_requirements: Dictionary,
	ground_items: Array,
	is_known: bool,
	hostile: bool
) -> Array:
	if not is_known:
		return [
			_intel_signal("loot", "unknown", "UNKNOWN", "inventory", "muted"),
			_intel_signal("structure", "unknown", "UNKNOWN", "location", "muted"),
			_intel_signal("risk", "unknown", "UNKNOWN", "warning", "muted"),
		]

	var loot_state := "none"
	var loot_label := "NONE"
	var loot_role := "muted"
	var marker_kind := str(search_site.get("marker_kind", "")).to_lower()
	var loot_profile_id := str(search_site.get("loot_profile_id", "")).to_lower()
	if not ground_items.is_empty():
		loot_state = "known"
		loot_label = "GROUND ITEMS"
		loot_role = "discovery"
	elif not search_site.is_empty() and hex_data.search_count > 0:
		loot_state = "none"
		loot_label = "NONE"
	elif not search_site.is_empty() and (
		marker_kind.contains("locked") or not search_requirements.is_empty()
	):
		loot_state = "known"
		loot_label = "LOCKED SALVAGE"
		loot_role = "caution"
	elif not search_site.is_empty() or not hex_data.loot_tier_id.is_empty():
		loot_state = "known"
		loot_label = (
			"SUPPLIES"
			if marker_kind.contains("supply")
			or loot_profile_id.contains("supply")
			or loot_profile_id.contains("food")
			or loot_profile_id.contains("medical")
			else "SALVAGE"
		)
		loot_role = "discovery"

	var structure_state := "none"
	var structure_label := "OPEN GROUND"
	var composition := hex_data.composition_role.to_lower()
	if composition.contains("camp") or composition.contains("tent"):
		structure_state = "known"
		structure_label = "CAMP"
	elif hex_data.structure_layer == GameEnums.MacroStructureLayer.STRUCTURES or hex_data.is_poi:
		structure_state = "known"
		structure_label = "BUILDING"
	elif hex_data.structure_layer == GameEnums.MacroStructureLayer.REMNANTS or composition.contains("rubble"):
		structure_state = "known"
		structure_label = "REMAINS"

	var risk_state := "known"
	var risk_label := "LOW"
	var risk_role := "info"
	if hostile:
		risk_label = "HOSTILE"
		risk_role = "critical"
	else:
		var risk_score := clampf(hex_data.hazard_level / float(GameEnums.SCALE_MAX), 0.0, 1.0)
		var modifiers: Dictionary = search_site.get("metric_modifiers", {})
		if not modifiers.is_empty():
			risk_score = clampf(
				risk_score - float(modifiers.get("safety", 0.0)) / float(GameEnums.SCALE_MAX),
			0.0,
			1.0
		)
		if risk_score >= 0.7:
			risk_label = "HIGH"
			risk_role = "critical"
		elif risk_score >= 0.3:
			risk_label = "ELEVATED"
			risk_role = "caution"
	return [
		_intel_signal("loot", loot_state, loot_label, "inventory", loot_role),
		_intel_signal("structure", structure_state, structure_label, "location", "info" if structure_state == "known" else "muted"),
		_intel_signal("risk", risk_state, risk_label, "warning", risk_role),
	]


static func _intel_signal(
	kind: String,
	state: String,
	label: String,
	icon_id: String,
	role: String
) -> Dictionary:
	return {
		"kind": kind,
		"state": state,
		"label": label,
		"icon_id": icon_id,
		"role": role,
	}


static func _hex_feature_title(hex_data: MacroHexData) -> String:
	return feature_title(hex_data)


static func feature_title(hex_data: MacroHexData) -> String:
	if hex_data.is_poi and not hex_data.poi_name.is_empty():
		return hex_data.poi_name
	if not hex_data.search_site_id.is_empty():
		var catalog := SearchSiteCatalog.data()
		var site := catalog.get_site(hex_data.search_site_id) if catalog != null else null
		if site != null:
			return site.display_name
	if hex_data.water_layer == GameEnums.MacroWaterLayer.SHALLOW_RIVER:
		return "Shallow River Bend"
	if hex_data.water_layer == GameEnums.MacroWaterLayer.DEEP_WATER:
		return "Deep Water Parcel"
	if hex_data.rock_layer == GameEnums.MacroRockLayer.ROCKS:
		return "Blocked Boulder Lot"
	if hex_data.rock_layer == GameEnums.MacroRockLayer.HILLS:
		return "Rocky Rise Parcel"
	if hex_data.flora_layer == GameEnums.MacroFloraLayer.TREES:
		return "Grove Parcel"
	if hex_data.structure_layer == GameEnums.MacroStructureLayer.REMNANTS:
		return "Remnant Lot"
	if hex_data.structure_layer == GameEnums.MacroStructureLayer.STRUCTURES:
		return "Isolated Structure"
	if hex_data.terrain_tile == GameEnums.MacroTerrainTile.MUD_YELLOW:
		return "Waterlogged Parcel"
	if hex_data.flora_layer == GameEnums.MacroFloraLayer.SHRUBS:
		return "Scrub Parcel"
	return "Open Parcel"


static func _hex_environment_summary(hex_data: MacroHexData) -> String:
	return environment_summary(hex_data)


static func environment_summary(hex_data: MacroHexData) -> String:
	if hex_data.water_layer == GameEnums.MacroWaterLayer.SHALLOW_RIVER:
		return "Cold shallow water and stony banks across this ~450 m parcel."
	if hex_data.water_layer == GameEnums.MacroWaterLayer.DEEP_WATER:
		return "Dark water with no safe footing on this parcel's bank."
	if hex_data.rock_layer == GameEnums.MacroRockLayer.ROCKS:
		return "Weathered stone closes off direct passage through the parcel."
	if hex_data.rock_layer == GameEnums.MacroRockLayer.HILLS:
		return "Uneven stone shelves break up this neighborhood rise."
	if hex_data.flora_layer == GameEnums.MacroFloraLayer.TREES:
		return "A tight grove and understory cut sightlines across the parcel."
	if hex_data.structure_layer != GameEnums.MacroStructureLayer.NONE:
		return "Human-made remains interrupt this neighborhood parcel."
	if hex_data.terrain_tile == GameEnums.MacroTerrainTile.MUD_YELLOW:
		return "Soft saturated ground on this parcel records tracks and slows steps."
	if hex_data.flora_layer == GameEnums.MacroFloraLayer.SHRUBS:
		return "Waist-high scrub clusters across this ~450 m parcel."
	return "Open grassland parcel with short sightlines and little shelter."


static func _hex_movement_note(hex_data: MacroHexData) -> String:
	return movement_note(hex_data)


static func movement_note(hex_data: MacroHexData) -> String:
	if not hex_data.is_passable():
		if hex_data.water_layer == GameEnums.MacroWaterLayer.DEEP_WATER:
			return "IMPASSABLE // deep water"
		return "IMPASSABLE // massive stone obstruction"
	if hex_data.water_layer == GameEnums.MacroWaterLayer.SHALLOW_RIVER:
		return "FORDABLE // current and slick stones slow movement"
	if hex_data.rock_layer == GameEnums.MacroRockLayer.HILLS:
		return "DIFFICULT // uneven climbing"
	if hex_data.terrain_tile == GameEnums.MacroTerrainTile.MUD_YELLOW:
		return "SLOW // unstable wet ground"
	if hex_data.flora_layer == GameEnums.MacroFloraLayer.TREES:
		return "SLOW // dense understory"
	return "CLEAR // normal travel"


static func _hex_visibility(hex_data: MacroHexData) -> String:
	if hex_data.flora_layer == GameEnums.MacroFloraLayer.TREES:
		return "OBSTRUCTED"
	if hex_data.structure_layer != GameEnums.MacroStructureLayer.NONE:
		return "BROKEN"
	if hex_data.rock_layer != GameEnums.MacroRockLayer.NONE:
		return "LIMITED"
	return "OPEN"


static func _hex_cover(hex_data: MacroHexData) -> String:
	if (
		hex_data.rock_layer != GameEnums.MacroRockLayer.NONE
		or hex_data.structure_layer != GameEnums.MacroStructureLayer.NONE
	):
		return "HIGH"
	if hex_data.flora_layer == GameEnums.MacroFloraLayer.TREES:
		return "MEDIUM"
	if hex_data.flora_layer == GameEnums.MacroFloraLayer.SHRUBS:
		return "LOW"
	return "NONE"


static func _hex_resource_hint(hex_data: MacroHexData) -> String:
	return resource_hint(hex_data)


static func resource_hint(hex_data: MacroHexData) -> String:
	if hex_data.water_layer != GameEnums.MacroWaterLayer.NONE:
		return "Possible finds: water, reeds, smooth stone"
	if hex_data.flora_layer == GameEnums.MacroFloraLayer.TREES:
		return "Possible finds: wood, forage, concealment"
	if hex_data.rock_layer != GameEnums.MacroRockLayer.NONE:
		return "Possible finds: stone, sheltered crevices"
	if hex_data.structure_layer != GameEnums.MacroStructureLayer.NONE:
		return "Possible finds: salvage, containers, traces of habitation"
	if hex_data.flora_layer == GameEnums.MacroFloraLayer.SHRUBS:
		return "Possible finds: fibers, berries, small game signs"
	return "Possible finds: grasses, exposed tracks"


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
			# HUD activity must not become an implicit NPC simulation tick.
			var purpose_record := EntityRecord.from_dict(record.to_dict())
			var purpose: String = ensure_npc_purpose_callback.call(purpose_record)
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
	is_entity_hostile_callback: Callable,
	movement_active: bool = false,
	travel_known_callback: Callable = Callable()
) -> Dictionary:
	return build_world_hud_snapshot_from_neutral(
		BiologicalSnapshotService.capture(player_core),
		InventorySnapshotService.capture(
			player_core,
			world_state.get_ground_items(player_coords),
			Callable(),
			Callable()
		),
		player_coords,
		selected_hex_coords,
		world_time,
		last_macro_event,
		macro_turn_index,
		active_token_count,
		world_state,
		world_generator,
		ensure_npc_purpose_callback,
		hex_distance_callback,
		hex_label_callback,
		is_entity_alive_callback,
		is_entity_hostile_callback,
		movement_active,
		travel_known_callback
	)


static func build_world_hud_snapshot_from_neutral(
	biological_snapshot: Dictionary,
	inventory_snapshot: Dictionary,
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
	is_entity_hostile_callback: Callable,
	movement_active: bool = false,
	travel_known_callback: Callable = Callable()
) -> Dictionary:
	if biological_snapshot.is_empty() or inventory_snapshot.is_empty():
		return {}
	var current_hex := world_generator.get_hex_at(player_coords)
	var selected_hex := world_generator.get_hex_at(selected_hex_coords)
	var result := {
		"coords": player_coords,
		"current_hex": build_hex_descriptor(
			player_coords, player_coords, current_hex,
			_entity_record_at(world_state, player_coords),
			world_state.get_ground_items(player_coords),
			hex_label_callback.call(player_coords, current_hex),
			is_entity_alive_callback, is_entity_hostile_callback,
			ensure_npc_purpose_callback, hex_distance_callback,
			movement_active,
			travel_known_callback.is_valid()
			and bool(travel_known_callback.call(player_coords))
		),
		"selected_hex": build_hex_descriptor(
			selected_hex_coords, player_coords, selected_hex,
			_entity_record_at(world_state, selected_hex_coords),
			world_state.get_ground_items(selected_hex_coords),
			hex_label_callback.call(selected_hex_coords, selected_hex),
			is_entity_alive_callback, is_entity_hostile_callback,
			ensure_npc_purpose_callback, hex_distance_callback,
			movement_active,
			travel_known_callback.is_valid()
			and bool(travel_known_callback.call(selected_hex_coords))
		),
		"macro_activity": build_macro_activity_snapshot(
			player_coords, macro_turn_index, active_token_count,
			_detached_entity_records(world_state),
			ensure_npc_purpose_callback, hex_distance_callback
		),
		"last_macro_event": last_macro_event,
		"world_time": world_time,
		"current_capacity": inventory_snapshot.get("current_capacity", 0),
		"maximum_capacity": inventory_snapshot.get("maximum_capacity", 0),
		"medical_items": inventory_snapshot.get("medical_items", []).duplicate(true),
		"limbs": biological_snapshot.get("limbs", []).duplicate(true),
		"emergencies": biological_snapshot.get("emergencies", []).duplicate(true),
		"calendar": GameTimeRules.calendar_snapshot(int(world_time.get("total_minutes", 0))),
	}
	for key in [
		"blood", "pain", "shock", "consciousness", "bleeding_rate",
		"wound_count", "infection_risk", "hunger", "thirst", "fatigue",
		"core_temperature", "morale", "arc_energy", "red_mist",
	]:
		result[key] = biological_snapshot.get(key)
	return result


static func _entity_record_at(
	world_state: RuntimeStateStore,
	coords: Vector2i
) -> EntityRecord:
	var snapshot := world_state.get_entity_snapshot_at(coords)
	return EntityRecord.from_dict(snapshot) if not snapshot.is_empty() else null


static func _detached_entity_records(
	world_state: RuntimeStateStore
) -> Array[EntityRecord]:
	var records: Array[EntityRecord] = []
	for snapshot in world_state.get_all_entity_snapshots():
		if snapshot is Dictionary:
			records.append(EntityRecord.from_dict(snapshot))
	return records


static func _legacy_build_world_hud_snapshot(
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
			_entity_record_at(world_state, player_coords),
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
			_entity_record_at(world_state, selected_hex_coords),
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
			_detached_entity_records(world_state),
			ensure_npc_purpose_callback,
			hex_distance_callback
		),
		"last_macro_event": last_macro_event,
		"world_time": world_time,
		"blood": body.blood_level,
		"pain": body.get_total_pain(),
		"shock": body.shock,
		"consciousness": body.consciousness,
		"bleeding_rate": body.get_total_bleeding_rate(),
		"wound_count": body.get_total_wound_count(),
		"infection_risk": body.get_infection_risk(),
		"hunger": body.hunger,
		"thirst": body.thirst,
		"fatigue": body.fatigue,
		"core_temperature": body.core_temperature,
		"morale": player_core.current_morale,
		"arc_energy": player_core.current_arc_energy,
		"red_mist": player_core.red_mist_corruption,
		"current_capacity": inventory.current_size,
		"maximum_capacity": inventory.current_max_capacity,
		"medical_items": build_medical_item_snapshot(inventory),
		"limbs": build_limb_snapshot(body),
		"emergencies": build_emergencies(body, player_core),
		"calendar": GameTimeRules.calendar_snapshot(int(world_time.get("total_minutes", 0))),
	}
