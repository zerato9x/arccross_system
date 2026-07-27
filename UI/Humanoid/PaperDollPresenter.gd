extends RefCounted
class_name PaperDollPresenter

## Presentation-only helpers for Innawoods PaperDollModel and key-gear tiles.
## Does not own gameplay state.

const KEY_GEAR_PRIORITY := [
	{"slot": GameEnums.EquipmentSlot.HAND, "label": "HAND"},
	{"slot": GameEnums.EquipmentSlot.OFFHAND, "label": "OFF"},
	{"slot": GameEnums.EquipmentSlot.OUTER_TORSO, "label": "ARMOR"},
	{"slot": GameEnums.EquipmentSlot.HEAD, "label": "HEAD"},
	{"slot": GameEnums.EquipmentSlot.EYES, "label": "EYES"},
	{"slot": GameEnums.EquipmentSlot.BACKPACK, "label": "PACK"},
	{"slot": GameEnums.EquipmentSlot.BELT, "label": "BELT"},
	{"slot": GameEnums.EquipmentSlot.SLING, "label": "SLING"},
]


static func apply_to_doll(
	doll: PaperDollModel,
	equipment: Array,
	limbs: Array = []
) -> void:
	if doll == null:
		return
	doll.update_model(equipment)
	doll.set_backdrop_visible(false)
	if not limbs.is_empty():
		doll.update_wounds(limbs)


static func equipment_from_inventory_snapshot(snapshot: Dictionary) -> Array:
	return snapshot.get("equipment", []) if snapshot is Dictionary else []


static func limbs_from_inventory_snapshot(snapshot: Dictionary) -> Array:
	return snapshot.get("limbs", []) if snapshot is Dictionary else []


static func equipment_from_entity_record(record) -> Array:
	var record_dict := _record_as_dict(record)
	if record_dict.is_empty():
		return []
	var equipment: Array = []
	var runtime: Dictionary = record_dict.get("runtime", {})
	var inventory_state: Dictionary = runtime.get("inventory", {})
	var equipment_state: Dictionary = inventory_state.get("equipment", {})
	if not equipment_state.is_empty():
		for raw_slot_key in equipment_state.keys():
			var item_state: Dictionary = equipment_state[raw_slot_key]
			var descriptor := _descriptor_from_runtime_item(
				item_state,
				int(raw_slot_key)
			)
			if not descriptor.is_empty():
				equipment.append(descriptor)
		return equipment

	var definition_state: Dictionary = record_dict.get("definition", {})
	var loadout_state: Dictionary = definition_state.get("loadout", {})
	for loadout_key in HumanoidVisualCatalog.LOADOUT_SLOT_KEYS.keys():
		var slot: int = HumanoidVisualCatalog.LOADOUT_SLOT_KEYS[loadout_key]
		var path := str(loadout_state.get(loadout_key, ""))
		var descriptor := _descriptor_from_resource_path(path, slot)
		if not descriptor.is_empty():
			equipment.append(descriptor)
	return equipment


static func appearance_from_entity_record(record) -> Dictionary:
	return HumanoidVisualCatalog.appearance_from_record(_record_as_dict(record))


static func appearance_from_equipment(equipment: Array) -> Dictionary:
	return HumanoidVisualCatalog.appearance_from_equipment_snapshot(equipment)


static func key_gear_tiles(
	equipment: Array,
	backpack: Array = []
) -> Array:
	var by_slot := equipment_by_slot(equipment)
	var tiles: Array = []
	var used_instance_ids: Dictionary = {}
	for config in KEY_GEAR_PRIORITY:
		var slot: int = int(config["slot"])
		var item: Dictionary = {}
		if slot == GameEnums.EquipmentSlot.OUTER_TORSO:
			item = by_slot.get(slot, {})
			if item.is_empty():
				item = by_slot.get(GameEnums.EquipmentSlot.INNER_TORSO, {})
		else:
			item = by_slot.get(slot, {})
		if item.is_empty():
			continue
		var instance_id := str(item.get("instance_id", ""))
		if not instance_id.is_empty() and used_instance_ids.has(instance_id):
			continue
		if not instance_id.is_empty():
			used_instance_ids[instance_id] = true
		tiles.append({
			"label": str(config["label"]),
			"slot": slot,
			"item": item,
		})

	var light := _find_light_source(equipment, backpack, used_instance_ids)
	if not light.is_empty():
		tiles.append({
			"label": "LIGHT",
			"slot": int(light.get("equipment_slot", GameEnums.EquipmentSlot.NONE)),
			"item": light,
		})
	return tiles


static func equipment_by_slot(equipment: Array) -> Dictionary:
	var mapped := {}
	for raw_item in equipment:
		if not raw_item is Dictionary:
			continue
		var item: Dictionary = raw_item
		mapped[int(item.get("equipment_slot", GameEnums.EquipmentSlot.NONE))] = item
	return mapped


static func condition_role(item: Dictionary) -> String:
	if item.is_empty() or not bool(item.get("condition_enabled", true)):
		return "muted"
	var band := str(item.get("condition_band", ""))
	if band.is_empty():
		band = ItemConditionRules.condition_band(
			float(item.get("current_condition", GameEnums.SCALE_MAX))
		)
	match band:
		ItemConditionRules.CONDITION_FINE:
			return "success"
		ItemConditionRules.CONDITION_WORN:
			return "info"
		ItemConditionRules.CONDITION_DAMAGED:
			return "caution"
		ItemConditionRules.CONDITION_CRITICAL:
			return "critical"
		ItemConditionRules.CONDITION_BROKEN:
			return "critical"
	return "muted"


static func condition_label(item: Dictionary) -> String:
	if item.is_empty():
		return ""
	if not bool(item.get("condition_enabled", true)):
		return "OK"
	var band := str(item.get("condition_band", ""))
	if band.is_empty():
		band = ItemConditionRules.condition_band(
			float(item.get("current_condition", GameEnums.SCALE_MAX))
		)
	return "%s %.1f" % [band.to_upper(), float(item.get("current_condition", 0.0))]


static func _find_light_source(
	equipment: Array,
	backpack: Array,
	used_instance_ids: Dictionary
) -> Dictionary:
	for pool in [equipment, backpack]:
		for raw_item in pool:
			if not raw_item is Dictionary:
				continue
			var item: Dictionary = raw_item
			var instance_id := str(item.get("instance_id", ""))
			if not instance_id.is_empty() and used_instance_ids.has(instance_id):
				continue
			if _item_has_light_role(item):
				return item
	return {}


static func _item_has_light_role(item: Dictionary) -> bool:
	var roles: Array = item.get("interaction_roles", item.get("roles", []))
	for role in roles:
		if int(role) == GameEnums.InteractionItemRole.LIGHT_SOURCE:
			return true
	var tags: Array = item.get("tags", [])
	for tag in tags:
		var token := str(tag).to_lower()
		if "light" in token or "flash" in token:
			return true
	var item_id := str(item.get("item_id", item.get("id", ""))).to_lower()
	return "flashlight" in item_id or item_id.ends_with("_light")


static func _descriptor_from_runtime_item(
	item_state: Dictionary,
	equipment_slot: int
) -> Dictionary:
	if item_state.is_empty():
		return {}
	var item := ItemData.from_runtime_state(item_state)
	if item == null:
		return {}
	return _descriptor_from_item_data(item, equipment_slot)


static func _descriptor_from_resource_path(
	path: String,
	equipment_slot: int
) -> Dictionary:
	if path.is_empty() or not ResourceLoader.exists(path):
		return {}
	var definition := load(path) as ItemData
	if definition == null:
		return {}
	var item := definition.create_runtime_instance()
	return _descriptor_from_item_data(item, equipment_slot)


static func _descriptor_from_item_data(
	item: ItemData,
	equipment_slot: int
) -> Dictionary:
	if item == null:
		return {}
	return {
		"instance_id": item.instance_id,
		"id": item.id,
		"item_id": item.id,
		"name": item.display_name,
		"item_type": item.item_type,
		"weapon_type": item.weapon_type,
		"condition_enabled": item.condition_enabled,
		"current_condition": item.current_condition,
		"condition_band": ItemConditionRules.condition_band(item.current_condition),
		"tags": item.tags.duplicate(),
		"interaction_roles": item.interaction_roles.duplicate(),
		"roles": item.interaction_roles.duplicate(),
		"equipment_slot": equipment_slot,
		"target_slot": item.target_slot,
		"sprite_path": item.get_inventory_sprite_path(),
		"equipped_sprite_paths": item.get_equipped_sprite_paths(),
		"requires_two_hands": item.requires_two_hands,
	}


static func _record_as_dict(record) -> Dictionary:
	if record is EntityRecord:
		return {
			"entity_id": record.entity_id,
			"definition": record.definition.duplicate(true),
			"runtime": record.runtime.duplicate(true),
			"world_status": record.world_status,
		}
	if record is Dictionary:
		return record
	return {}
