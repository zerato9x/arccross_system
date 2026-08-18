extends RefCounted
class_name InventorySnapshotService

## ItemCore-owned neutral capture boundary. This is the only snapshot layer
## allowed to query live InventorySystem and ItemData rule helpers.


static func capture(
	core: HumanoidCore,
	ground_item_states: Array,
	can_offer_equip_callback: Callable,
	allowed_equipment_slots_callback: Callable
) -> Dictionary:
	if core == null or core.inventory == null:
		return {}
	var inventory := core.inventory
	var equipment: Array = []
	var seen_slots: Dictionary = {}
	for slot in GameEnums.EquipmentSlot.values():
		if slot == GameEnums.EquipmentSlot.NONE or seen_slots.has(slot):
			continue
		seen_slots[slot] = true
		var equipped: ItemData = inventory.paper_doll.get(slot)
		if equipped != null:
			equipment.append(descriptor(
				equipped, can_offer_equip_callback,
				allowed_equipment_slots_callback, inventory, slot
			))
	var backpack: Array = []
	for item in inventory.backpack_array:
		backpack.append(descriptor(
			item, can_offer_equip_callback, allowed_equipment_slots_callback,
			inventory, GameEnums.EquipmentSlot.NONE,
			inventory.get_item_container_slot(item)
		))
	var ground: Array = []
	for item_state in ground_item_states:
		if item_state is Dictionary:
			ground.append(ground_descriptor(
				item_state, can_offer_equip_callback,
				allowed_equipment_slots_callback, inventory
			))
	var capacity_breakdown: Array = []
	var containers: Array = []
	for slot in inventory.get_storage_slots():
		var equipped: ItemData = inventory.paper_doll.get(slot)
		var container_items: Array = []
		for item in inventory.get_container_items(slot):
			container_items.append(descriptor(
				item, can_offer_equip_callback,
				allowed_equipment_slots_callback, inventory,
				GameEnums.EquipmentSlot.NONE, slot
			))
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
		"current_capacity": inventory.current_size,
		"maximum_capacity": inventory.current_max_capacity,
		"capacity_breakdown": capacity_breakdown,
		"loadout_stats": {
			"weight": inventory.get_total_weight(),
			"bulk": inventory.get_total_bulk(),
			"insulation": inventory.get_total_insulation(),
			"protection_blunt": inventory.get_protection_for(GameEnums.DamageType.BLUNT),
			"protection_sharp": inventory.get_protection_for(GameEnums.DamageType.SHARP),
			"protection_ballistic": inventory.get_protection_for(GameEnums.DamageType.BALLISTIC),
		},
		"medical_items": capture_medical_items(inventory),
		"containers": containers,
		"equipment": equipment,
		"backpack": backpack,
		"ground": ground,
	}


static func capture_medical_items(inventory: InventorySystem) -> Array:
	var medical_items: Array = []
	if inventory == null:
		return medical_items
	for item in inventory.get_all_items():
		if item == null or item.item_type != GameEnums.ItemType.CONSUMABLE:
			continue
		medical_items.append({
			"instance_id": item.instance_id,
			"item_id": item.id,
			"name": item.display_name,
			"sprite_path": item.get_inventory_sprite_path(),
			"effect": int(item.consumable_effect),
			"potency": item.consumable_potency,
			"stack_count": item.stack_count,
		})
	return medical_items


static func descriptor(
	item: ItemData,
	can_offer_equip_callback: Callable,
	allowed_equipment_slots_callback: Callable,
	inventory: InventorySystem,
	equipment_slot: int = GameEnums.EquipmentSlot.NONE,
	container_slot: int = GameEnums.EquipmentSlot.NONE
) -> Dictionary:
	var allowed_slots: Array = (
		allowed_equipment_slots_callback.call(item)
		if allowed_equipment_slots_callback.is_valid()
		else []
	)
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
		"can_equip": can_offer_equip_callback.is_valid() and can_offer_equip_callback.call(item),
		"can_consume": item.item_type == GameEnums.ItemType.CONSUMABLE,
		"can_load_magazine": item.is_magazine() and item.loaded_rounds < item.magazine_capacity,
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


static func ground_descriptor(
	item_state: Dictionary,
	can_offer_equip_callback: Callable,
	allowed_equipment_slots_callback: Callable,
	inventory: InventorySystem
) -> Dictionary:
	var item := ItemData.from_runtime_state(item_state)
	var result := descriptor(
		item, can_offer_equip_callback, allowed_equipment_slots_callback, inventory
	)
	result["can_equip"] = false
	result["can_consume"] = false
	result["can_load_magazine"] = false
	return result
