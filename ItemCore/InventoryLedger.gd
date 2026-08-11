extends RefCounted
class_name InventoryLedger

## Collection queries for inventory state. Mutations that require spill and
## signal policy remain in InventorySystem, while ownership lookup is neutral.

func all_items(
	backpack_array: Array[ItemData],
	paper_doll: Dictionary
) -> Array[ItemData]:
	var items: Array[ItemData] = []
	items.append_array(backpack_array)
	for item in paper_doll.values():
		if item != null and item not in items:
			items.append(item as ItemData)
	return items


func find_item_by_instance_id(
	backpack_array: Array[ItemData],
	paper_doll: Dictionary,
	instance_id: String
) -> ItemData:
	for item in all_items(backpack_array, paper_doll):
		if item.instance_id == instance_id:
			return item
	return null


func remove_from_backpack(
	backpack_array: Array[ItemData],
	item_container_slots: Dictionary,
	instance_id: String
) -> ItemData:
	for item in backpack_array:
		if item.instance_id != instance_id:
			continue
		backpack_array.erase(item)
		item_container_slots.erase(instance_id)
		return item
	return null
