extends RefCounted
class_name MacroInventoryBridge

## Pure, stateless inventory/equipment query helpers extracted from
## MacroGameManager. WorldCore may lean on ItemCore/SystemCore here, but must
## never reach into CombatCore or UI. Query helpers accept either a live
## InventorySystem or a plain Array[ItemData] so callers can reuse them against
## snapshots and projections without a player token.


static func can_offer_equip(item: ItemData) -> bool:
	return (
		not allowed_equipment_slots(item).is_empty()
		and (
			item.item_type == GameEnums.ItemType.WEAPON
			or item.item_type == GameEnums.ItemType.ARMOR
		)
	)


static func allowed_equipment_slots(item: ItemData) -> Array[int]:
	if item.item_type == GameEnums.ItemType.WEAPON:
		if item.requires_two_hands:
			return [GameEnums.EquipmentSlot.HAND]
		return [
			GameEnums.EquipmentSlot.HAND,
			GameEnums.EquipmentSlot.OFFHAND,
		]
	if (
		item.item_type == GameEnums.ItemType.ARMOR
		and item.target_slot == GameEnums.EquipmentSlot.HAND
	):
		return [GameEnums.EquipmentSlot.OFFHAND]
	if item.target_slot != GameEnums.EquipmentSlot.NONE:
		return [item.target_slot]
	return []


static func has_any_item_id(inventory_or_core_items, item_ids: Array) -> bool:
	for item in _items_from(inventory_or_core_items):
		if item_ids.has(item.id):
			return true
	return false


static func has_any_tag(inventory_or_core_items, tags: Array) -> bool:
	for item in _items_from(inventory_or_core_items):
		for tag in tags:
			if item.tags.has(str(tag)):
				return true
	return false


static func has_any_role(inventory_or_core_items, roles: Array) -> bool:
	for item in _items_from(inventory_or_core_items):
		for role in roles:
			if item.has_interaction_role(int(role)):
				return true
	return false


static func find_item_by_instance_id(
	inventory_or_core_items,
	instance_id: String
) -> ItemData:
	if inventory_or_core_items is InventorySystem:
		return inventory_or_core_items.find_item_by_instance_id(instance_id)
	for item in _items_from(inventory_or_core_items):
		if item != null and item.instance_id == instance_id:
			return item
	return null


static func _items_from(inventory_or_core_items) -> Array:
	if inventory_or_core_items is InventorySystem:
		return inventory_or_core_items.get_all_items()
	if inventory_or_core_items is Array:
		return inventory_or_core_items
	return []
