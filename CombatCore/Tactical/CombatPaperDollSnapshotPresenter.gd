extends RefCounted
class_name CombatPaperDollSnapshotPresenter

## Combat-owned projection seam for the paper-doll surface. The HUD consumes
## neutral equipment/limb records; it never imports a gameplay inventory or
## humanoid domain object to populate presentation.

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


static func key_gear_tiles(equipment: Array) -> Array:
	var by_slot := {}
	for raw_item in equipment:
		if not raw_item is Dictionary:
			continue
		var item: Dictionary = raw_item
		by_slot[int(item.get("equipment_slot", GameEnums.EquipmentSlot.NONE))] = item
	var tiles: Array = []
	var used_instance_ids := {}
	for config in KEY_GEAR_PRIORITY:
		var slot: int = int(config["slot"])
		var item: Dictionary = by_slot.get(slot, {})
		if slot == GameEnums.EquipmentSlot.OUTER_TORSO and item.is_empty():
			item = by_slot.get(GameEnums.EquipmentSlot.INNER_TORSO, {})
		if item.is_empty():
			continue
		var instance_id := str(item.get("instance_id", ""))
		if not instance_id.is_empty() and used_instance_ids.has(instance_id):
			continue
		if not instance_id.is_empty():
			used_instance_ids[instance_id] = true
		tiles.append({"label": str(config["label"]), "slot": slot, "item": item})
	return tiles
