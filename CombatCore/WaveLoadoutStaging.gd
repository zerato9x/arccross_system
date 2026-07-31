extends RefCounted
class_name WaveLoadoutStaging

const AUTO_STORAGE_PATH := "res://ItemCore/Items/backpack_service_big.tres"

const SLOT_ORDER: Array[int] = [
	GameEnums.EquipmentSlot.HEAD,
	GameEnums.EquipmentSlot.EYES,
	GameEnums.EquipmentSlot.FACE,
	GameEnums.EquipmentSlot.NECK,
	GameEnums.EquipmentSlot.ARMS,
	GameEnums.EquipmentSlot.INNER_TORSO,
	GameEnums.EquipmentSlot.OUTER_TORSO,
	GameEnums.EquipmentSlot.VEST,
	GameEnums.EquipmentSlot.BELT,
	GameEnums.EquipmentSlot.SLING,
	GameEnums.EquipmentSlot.BACKPACK,
	GameEnums.EquipmentSlot.LEGS,
	GameEnums.EquipmentSlot.FEET,
	GameEnums.EquipmentSlot.HAND,
	GameEnums.EquipmentSlot.OFFHAND,
]

const STORAGE_SLOTS: Array[int] = [
	GameEnums.EquipmentSlot.VEST,
	GameEnums.EquipmentSlot.OUTER_TORSO,
	GameEnums.EquipmentSlot.LEGS,
	GameEnums.EquipmentSlot.BELT,
	GameEnums.EquipmentSlot.SLING,
	GameEnums.EquipmentSlot.BACKPACK,
]

const SLOT_TO_STATE_KEY := {
	GameEnums.EquipmentSlot.HAND: "weapon",
	GameEnums.EquipmentSlot.OFFHAND: "offhand",
	GameEnums.EquipmentSlot.INNER_TORSO: "inner_torso",
	GameEnums.EquipmentSlot.OUTER_TORSO: "outer_torso",
	GameEnums.EquipmentSlot.LEGS: "legs",
	GameEnums.EquipmentSlot.FEET: "feet",
	GameEnums.EquipmentSlot.VEST: "vest",
	GameEnums.EquipmentSlot.BACKPACK: "backpack_gear",
	GameEnums.EquipmentSlot.HEAD: "head",
	GameEnums.EquipmentSlot.EYES: "eyes",
	GameEnums.EquipmentSlot.FACE: "face",
	GameEnums.EquipmentSlot.NECK: "neck",
	GameEnums.EquipmentSlot.ARMS: "arms",
	GameEnums.EquipmentSlot.BELT: "belt",
	GameEnums.EquipmentSlot.SLING: "sling",
}

var target_name: String = "COMBATANT"
var definition_state: Dictionary = {}
var equipment: Dictionary = {}
var starting_items: Array[String] = []
var auto_storage_provisioned: bool = false

func configure(
	new_target_name: String,
	new_definition_state: Dictionary,
	loadout_state: Dictionary
) -> void:
	target_name = new_target_name
	definition_state = new_definition_state.duplicate(true)
	equipment.clear()
	starting_items.clear()
	auto_storage_provisioned = false
	for slot_value in SLOT_ORDER:
		var slot := int(slot_value)
		var key := str(SLOT_TO_STATE_KEY.get(slot, ""))
		if key.is_empty():
			continue
		var item_path := str(loadout_state.get(key, ""))
		if not item_path.is_empty():
			equipment[slot] = item_path
	for path_value in loadout_state.get("starting_items", []):
		var item_path := str(path_value)
		if not item_path.is_empty():
			starting_items.append(item_path)

func to_loadout_state() -> Dictionary:
	var state := {"starting_items": starting_items.duplicate()}
	for slot_value in SLOT_ORDER:
		var slot := int(slot_value)
		var key := str(SLOT_TO_STATE_KEY.get(slot, ""))
		if not key.is_empty():
			state[key] = str(equipment.get(slot, ""))
	return state

func get_equipped_path(slot: int) -> String:
	return str(equipment.get(slot, ""))

func get_equipped_item(slot: int) -> ItemData:
	return _load_item(get_equipped_path(slot))

func equip_path(item_path: String, requested_slot: int = 0) -> Dictionary:
	var item := _load_item(item_path)
	if item == null:
		return _failure("Item resource failed to load: %s" % item_path)
	var slot := requested_slot
	if slot == GameEnums.EquipmentSlot.NONE:
		slot = _preferred_slot(item)
	if slot not in SLOT_ORDER:
		return _failure("%s is not a supported equipment slot." % _slot_name(slot))
	if not _can_equip_in_slot(item, slot):
		return _failure(
			"%s targets %s and cannot be equipped in %s."
			% [item.display_name, _slot_name(_preferred_slot(item)), _slot_name(slot)]
		)
	var weapon_error := _weapon_equip_error(item, slot)
	if not weapon_error.is_empty():
		return _failure(weapon_error)

	var replaced_path := get_equipped_path(slot)
	equipment[slot] = item_path
	# Equipment changes may temporarily create semantic warnings (for example,
	# pistol ammunition while a melee weapon is selected). Keep that staged and
	# let the workstation disable START with the visible reason. Only reject a
	# change here when it breaks the real storage contract.
	var storage_validation := _simulate_storage()
	if not bool(storage_validation.get("valid", false)):
		if replaced_path.is_empty():
			equipment.erase(slot)
		else:
			equipment[slot] = replaced_path
		var storage_errors: Array = storage_validation.get("errors", [])
		return _failure(
			str(storage_errors[0]) if not storage_errors.is_empty() else "Invalid staged storage."
		)

	var replaced := _load_item(replaced_path)
	var replacement_note := ""
	if replaced != null:
		replacement_note = " Replaced %s; the old item was removed from staging." % replaced.display_name
	return {
		"ok": true,
		"message": "%s equipped %s in %s.%s" % [
			target_name,
			item.display_name,
			_slot_name(slot),
			replacement_note,
		],
		"slot": slot,
		"item_path": item_path,
		"replaced_path": replaced_path,
	}

func add_loose_path(item_path: String, quantity: int = 1) -> Dictionary:
	var item := _load_item(item_path)
	if item == null:
		return _failure("Item resource failed to load: %s" % item_path)
	if item.get_effective_item_size() == GameEnums.ItemSize.BIG:
		return _failure(
			"%s is BIG and InventorySystem does not allow BIG loose items in worn storage."
			% item.display_name
		)
	var requested := maxi(1, quantity)
	var added := 0
	var provisioned_now := false
	for _index in range(requested):
		starting_items.append(item_path)
		var storage := _simulate_storage()
		if not bool(storage.get("valid", false)):
			if _try_auto_provision_storage():
				provisioned_now = true
				storage = _simulate_storage()
		if not bool(storage.get("valid", false)):
			starting_items.pop_back()
			break
		added += 1
	if added == 0:
		return _failure(
			"No legal worn storage can accept %s. Equip storage or remove other loose items."
			% item.display_name
		)
	var suffix := ""
	if provisioned_now:
		suffix = " Lab storage was auto-provisioned and is shown in BACKPACK."
	elif added < requested:
		suffix = " Storage filled after %d of %d." % [added, requested]
	return {
		"ok": true,
		"message": "%s added %d x %s to loose inventory.%s" % [
			target_name,
			added,
			item.display_name,
			suffix,
		],
		"added": added,
		"requested": requested,
		"auto_storage": provisioned_now,
	}

func equip_loose_index(index: int, requested_slot: int = 0) -> Dictionary:
	if index < 0 or index >= starting_items.size():
		return _failure("Select a loose inventory item first.")
	var item_path := starting_items[index]
	var result := equip_path(item_path, requested_slot)
	if bool(result.get("ok", false)):
		starting_items.remove_at(index)
	return result

func unequip_slot(slot: int) -> Dictionary:
	var item_path := get_equipped_path(slot)
	var item := _load_item(item_path)
	if item == null:
		return _failure("%s is already empty." % _slot_name(slot))
	if item.get_effective_item_size() == GameEnums.ItemSize.BIG:
		return _failure(
			"%s is BIG and cannot become a loose stored item. Remove it instead."
			% item.display_name
		)
	equipment.erase(slot)
	starting_items.append(item_path)
	var storage := _simulate_storage()
	if not bool(storage.get("valid", false)) and slot != GameEnums.EquipmentSlot.BACKPACK:
		_try_auto_provision_storage()
		storage = _simulate_storage()
	if not bool(storage.get("valid", false)):
		starting_items.pop_back()
		equipment[slot] = item_path
		return _failure(
			"%s cannot be unequipped: no legal storage can hold it and the existing loose inventory."
			% item.display_name
		)
	return {
		"ok": true,
		"message": "%s moved %s from %s to loose inventory." % [
			target_name,
			item.display_name,
			_slot_name(slot),
		],
	}

func remove_equipped(slot: int) -> Dictionary:
	var item_path := get_equipped_path(slot)
	var item := _load_item(item_path)
	if item == null:
		return _failure("%s is already empty." % _slot_name(slot))
	equipment.erase(slot)
	var storage := _simulate_storage()
	if not bool(storage.get("valid", false)):
		equipment[slot] = item_path
		return _failure(
			"Removing %s would leave loose items without legal storage." % item.display_name
		)
	return {
		"ok": true,
		"message": "%s removed %s from the staged loadout." % [target_name, item.display_name],
	}

func remove_loose_index(index: int, quantity: int = 1) -> Dictionary:
	if index < 0 or index >= starting_items.size():
		return _failure("Select a loose inventory item first.")
	var item_path := starting_items[index]
	var item := _load_item(item_path)
	var removed := 0
	var wanted := maxi(1, quantity)
	for _index in range(wanted):
		var found := starting_items.find(item_path)
		if found < 0:
			break
		starting_items.remove_at(found)
		removed += 1
	return {
		"ok": removed > 0,
		"message": "%s removed %d x %s from loose inventory." % [
			target_name,
			removed,
			item.display_name if item != null else item_path.get_file(),
		],
	}

func validate() -> Dictionary:
	var storage := _simulate_storage()
	var errors: Array[String] = []
	for raw_error in storage.get("errors", []):
		errors.append(str(raw_error))
	var hand := get_equipped_item(GameEnums.EquipmentSlot.HAND)
	var offhand := get_equipped_item(GameEnums.EquipmentSlot.OFFHAND)
	if hand != null and hand.requires_two_hands and offhand != null:
		errors.append("The main-hand weapon requires both hands; OFFHAND must be empty.")
	var ammunition_ids: Dictionary = {}
	for path_value in starting_items:
		var item := _load_item(path_value)
		if item != null and item.item_type == GameEnums.ItemType.AMMUNITION:
			if item.accepted_ammunition_id.is_empty():
				ammunition_ids[item.id] = true
			else:
				ammunition_ids[item.accepted_ammunition_id] = true
	var compatible_ammunition: Dictionary = {}
	for slot in [GameEnums.EquipmentSlot.HAND, GameEnums.EquipmentSlot.OFFHAND]:
		var weapon := get_equipped_item(slot)
		if weapon != null and weapon.is_ranged():
			if not weapon.ammunition_id.is_empty():
				compatible_ammunition[weapon.ammunition_id] = true
	if not ammunition_ids.is_empty() and compatible_ammunition.is_empty():
		errors.append("Ammunition is staged without a compatible ranged weapon.")
	elif not ammunition_ids.is_empty():
		var has_match := false
		for ammo_id in ammunition_ids:
			if compatible_ammunition.has(ammo_id):
				has_match = true
				break
		if not has_match:
			errors.append("Staged ammunition does not match the equipped ranged weapon.")
	return {
		"valid": errors.is_empty(),
		"errors": errors,
		"reason": "" if errors.is_empty() else errors[0],
		"used": int(storage.get("used", 0)),
		"capacity": int(storage.get("capacity", 0)),
		"auto_storage": auto_storage_provisioned,
	}

func get_summary() -> String:
	var validation := validate()
	return "%s // EQUIPPED %d // LOOSE %d // CAPACITY %d/%d" % [
		target_name,
		equipment.size(),
		starting_items.size(),
		int(validation.get("used", 0)),
		int(validation.get("capacity", 0)),
	]

func get_derived_stats() -> Dictionary:
	var stats := {
		"weight": 0.0,
		"bulk": 0.0,
		"threat": 0.0,
		"insulation": 0.0,
		"blunt": 0.0,
		"sharp": 0.0,
		"ballistic": 0.0,
	}
	for path_value in equipment.values():
		var item := _load_item(str(path_value))
		if item == null:
			continue
		stats.weight += item.weight
		stats.bulk += item.bulk
		stats.threat += item.threat
		stats.insulation += item.insulation
		stats.blunt += item.protection_blunt
		stats.sharp += item.protection_sharp
		stats.ballistic += item.protection_ballistic
	var validation := validate()
	var capacity := maxi(1, int(validation.get("capacity", 0)))
	var used := int(validation.get("used", 0))
	var burden := int(floor(float(used) / float(capacity) * 6.0)) + int(floor(stats.weight))
	var kinetic_tier := GameEnums.KineticTier.FLUID
	if burden >= 9:
		kinetic_tier = GameEnums.KineticTier.AGONIZING
	elif burden >= 4:
		kinetic_tier = GameEnums.KineticTier.LABORED
	var movement_cost := 2
	if kinetic_tier == GameEnums.KineticTier.LABORED:
		movement_cost = 3
	elif kinetic_tier == GameEnums.KineticTier.AGONIZING:
		movement_cost = 4
	var active_weapon := get_equipped_item(GameEnums.EquipmentSlot.HAND)
	if active_weapon == null:
		active_weapon = get_equipped_item(GameEnums.EquipmentSlot.OFFHAND)
	var optimal_range_cells := Vector2i(1, 1)
	var maximum_range_cells := 1
	if active_weapon != null:
		optimal_range_cells = active_weapon.optimal_range_cells
		maximum_range_cells = active_weapon.maximum_range_cells
	var is_mindless := (
		int(definition_state.get("faction", GameEnums.Faction.UNALIGNED))
			== GameEnums.Faction.CRAVEN_HIVE
		or int(definition_state.get("agenda", GameEnums.Agenda.SURVIVALIST))
			== GameEnums.Agenda.MINDLESS
	)
	stats["burden"] = burden
	stats["kinetic_tier"] = kinetic_tier
	stats["movement_cost"] = movement_cost
	stats["optimal_range_cells"] = optimal_range_cells
	stats["maximum_range_cells"] = maximum_range_cells
	stats["ap"] = 8 if is_mindless else 12
	stats["blood"] = 12
	return stats

func _simulate_storage() -> Dictionary:
	var capacities: Dictionary = {}
	var used_by_slot: Dictionary = {}
	var errors: Array[String] = []
	var grouped_items: Dictionary = {}
	var total_capacity := 0
	for slot_value in STORAGE_SLOTS:
		var slot := int(slot_value)
		var storage := get_equipped_item(slot)
		var capacity := storage.capacity_bonus if storage != null else 0
		capacities[slot] = capacity
		used_by_slot[slot] = 0
		total_capacity += capacity
	for path_value in starting_items:
		var item := _load_item(path_value)
		if item == null:
			errors.append("Missing staged item resource: %s" % path_value)
			continue
		if item.get_effective_item_size() == GameEnums.ItemSize.BIG:
			errors.append("%s is BIG and cannot be stored loose." % item.display_name)
			continue
		var group_key := "%s|%d|%d|%d" % [
			item.id,
			item.starting_magazine,
			item.max_magazine,
			item.starting_loaded_rounds,
		]
		if not grouped_items.has(group_key):
			grouped_items[group_key] = {"item": item, "count": 0}
		grouped_items[group_key]["count"] = int(grouped_items[group_key]["count"]) + 1
	for group_value in grouped_items.values():
		var item: ItemData = group_value["item"]
		var unit_count := int(group_value["count"])
		var footprint_count := int(ceil(float(unit_count) / float(item.get_stack_limit())))
		for _footprint in range(footprint_count):
			var placed := false
			for slot_value in _storage_priority(item):
				var slot := int(slot_value)
				var capacity := int(capacities.get(slot, 0))
				var used := int(used_by_slot.get(slot, 0))
				if capacity > 0 and used + item.get_inventory_cost() <= capacity:
					used_by_slot[slot] = used + item.get_inventory_cost()
					placed = true
					break
			if not placed:
				errors.append("No legal storage has room for %s." % item.display_name)
	var total_used := 0
	for value in used_by_slot.values():
		total_used += int(value)
	return {
		"valid": errors.is_empty(),
		"errors": errors,
		"used": total_used,
		"capacity": total_capacity,
		"used_by_slot": used_by_slot,
	}

func _storage_priority(item: ItemData) -> Array[int]:
	var result: Array[int] = []
	var candidates: Array[int]
	if item.item_type == GameEnums.ItemType.AMMUNITION:
		candidates = [
			GameEnums.EquipmentSlot.VEST,
			GameEnums.EquipmentSlot.BACKPACK,
			GameEnums.EquipmentSlot.OUTER_TORSO,
			GameEnums.EquipmentSlot.LEGS,
			GameEnums.EquipmentSlot.BELT,
			GameEnums.EquipmentSlot.SLING,
		]
	else:
		candidates = [
			GameEnums.EquipmentSlot.BACKPACK,
			GameEnums.EquipmentSlot.OUTER_TORSO,
			GameEnums.EquipmentSlot.LEGS,
			GameEnums.EquipmentSlot.VEST,
			GameEnums.EquipmentSlot.BELT,
			GameEnums.EquipmentSlot.SLING,
		]
	for slot in candidates:
		if (
			item.get_effective_item_size() != GameEnums.ItemSize.AVERAGE
			or slot in [GameEnums.EquipmentSlot.BACKPACK, GameEnums.EquipmentSlot.SLING]
		):
			result.append(slot)
	return result

func _try_auto_provision_storage() -> bool:
	if not get_equipped_path(GameEnums.EquipmentSlot.BACKPACK).is_empty():
		return false
	var storage := _load_item(AUTO_STORAGE_PATH)
	if storage == null or storage.capacity_bonus <= 0:
		return false
	equipment[GameEnums.EquipmentSlot.BACKPACK] = AUTO_STORAGE_PATH
	auto_storage_provisioned = true
	return true

func _preferred_slot(item: ItemData) -> int:
	if item.item_type == GameEnums.ItemType.WEAPON:
		if get_equipped_path(GameEnums.EquipmentSlot.HAND).is_empty():
			return GameEnums.EquipmentSlot.HAND
		if not item.requires_two_hands:
			return GameEnums.EquipmentSlot.OFFHAND
		return GameEnums.EquipmentSlot.HAND
	if item.item_type == GameEnums.ItemType.ARMOR and item.target_slot == GameEnums.EquipmentSlot.HAND:
		return GameEnums.EquipmentSlot.OFFHAND
	return item.target_slot

func _can_equip_in_slot(item: ItemData, slot: int) -> bool:
	if item.item_type == GameEnums.ItemType.WEAPON:
		if item.requires_two_hands:
			return slot == GameEnums.EquipmentSlot.HAND
		return slot in [GameEnums.EquipmentSlot.HAND, GameEnums.EquipmentSlot.OFFHAND]
	if item.item_type == GameEnums.ItemType.ARMOR and item.target_slot == GameEnums.EquipmentSlot.HAND:
		return slot == GameEnums.EquipmentSlot.OFFHAND
	return item.target_slot == slot and slot != GameEnums.EquipmentSlot.NONE

func _weapon_equip_error(item: ItemData, slot: int) -> String:
	if item.item_type != GameEnums.ItemType.WEAPON:
		return ""
	if item.requires_two_hands:
		var offhand := get_equipped_item(GameEnums.EquipmentSlot.OFFHAND)
		if offhand != null:
			return "The offhand must be empty for a two-handed weapon."
	elif slot == GameEnums.EquipmentSlot.OFFHAND:
		var main_hand := get_equipped_item(GameEnums.EquipmentSlot.HAND)
		if main_hand != null and main_hand.requires_two_hands:
			return "The main-hand weapon already requires both hands."
	for other_slot in [GameEnums.EquipmentSlot.HAND, GameEnums.EquipmentSlot.OFFHAND]:
		if other_slot == slot:
			continue
		var existing := get_equipped_item(other_slot)
		if existing == null or existing.item_type != GameEnums.ItemType.WEAPON:
			continue
		if item.is_melee() and existing.is_melee():
			return "InventorySystem permits only one readied melee weapon."
		if item.is_ranged() and existing.is_ranged():
			return "InventorySystem permits only one readied firearm."
	return ""

func _load_item(item_path: String) -> ItemData:
	if item_path.is_empty() or not ResourceLoader.exists(item_path):
		return null
	return load(item_path) as ItemData

func _slot_name(slot: int) -> String:
	if slot < 0 or slot >= GameEnums.EquipmentSlot.keys().size():
		return "UNKNOWN SLOT"
	return str(GameEnums.EquipmentSlot.keys()[slot]).replace("_", " ")

func _failure(message: String) -> Dictionary:
	return {"ok": false, "message": message}
