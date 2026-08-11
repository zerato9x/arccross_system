extends RefCounted
class_name EquipmentRules

## Equipment legality is intentionally independent of InventorySystem signals
## and storage mutation. The facade still owns the compatibility wrappers.

func can_equip_in_slot(
	item: ItemData,
	slot: GameEnums.EquipmentSlot
) -> bool:
	if item == null:
		return false
	if item.item_type == GameEnums.ItemType.WEAPON:
		if item.requires_two_hands:
			return slot == GameEnums.EquipmentSlot.HAND
		return slot in [
			GameEnums.EquipmentSlot.HAND,
			GameEnums.EquipmentSlot.OFFHAND,
		]
	if (
		item.item_type == GameEnums.ItemType.ARMOR
		and item.target_slot == GameEnums.EquipmentSlot.HAND
	):
		return slot == GameEnums.EquipmentSlot.OFFHAND
	return item.target_slot == slot


func preferred_equipment_slot(
	item: ItemData,
	paper_doll: Dictionary
) -> GameEnums.EquipmentSlot:
	if item == null:
		return GameEnums.EquipmentSlot.NONE
	if item.item_type == GameEnums.ItemType.WEAPON:
		if paper_doll.get(GameEnums.EquipmentSlot.HAND) == null:
			return GameEnums.EquipmentSlot.HAND
		if not item.requires_two_hands:
			return GameEnums.EquipmentSlot.OFFHAND
		return GameEnums.EquipmentSlot.HAND
	if (
		item.item_type == GameEnums.ItemType.ARMOR
		and item.target_slot == GameEnums.EquipmentSlot.HAND
	):
		return GameEnums.EquipmentSlot.OFFHAND
	return item.target_slot


func weapon_equip_error(
	item: ItemData,
	slot: GameEnums.EquipmentSlot,
	paper_doll: Dictionary
) -> String:
	if item == null or item.item_type != GameEnums.ItemType.WEAPON:
		return ""
	if item.requires_two_hands:
		var offhand: ItemData = paper_doll.get(GameEnums.EquipmentSlot.OFFHAND)
		if offhand != null and offhand != item:
			return "The offhand must be empty for a two-handed weapon."
	elif slot == GameEnums.EquipmentSlot.OFFHAND:
		var main_hand: ItemData = paper_doll.get(GameEnums.EquipmentSlot.HAND)
		if main_hand != null and main_hand.requires_two_hands:
			return "The main-hand weapon already requires both hands."

	var is_equipping_melee := item.is_melee()
	for existing_slot in [
		GameEnums.EquipmentSlot.HAND,
		GameEnums.EquipmentSlot.OFFHAND,
	]:
		if existing_slot == slot:
			continue
		var existing: ItemData = paper_doll.get(existing_slot)
		if existing == null or existing.item_type != GameEnums.ItemType.WEAPON:
			continue
		if is_equipping_melee and existing.is_melee():
			return "You can only ready one melee weapon."
		if not is_equipping_melee and existing.is_ranged():
			return "You can only ready one firearm."
	return ""
