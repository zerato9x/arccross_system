extends RefCounted
class_name InventoryCapacityCalculator

## Pure capacity math shared by the inventory facade and neutral presenters.
## It deliberately receives collections rather than owning authoritative state.

func container_capacity(
	paper_doll: Dictionary,
	slot: GameEnums.EquipmentSlot
) -> int:
	var storage_item := paper_doll.get(slot) as ItemData
	return storage_item.capacity_bonus if storage_item != null else 0


func container_used_capacity(
	backpack_array: Array[ItemData],
	item_container_slots: Dictionary,
	slot: GameEnums.EquipmentSlot
) -> int:
	var used := 0
	for item in backpack_array:
		if int(item_container_slots.get(
			item.instance_id,
			GameEnums.EquipmentSlot.NONE
		)) == slot:
			used += item.get_inventory_cost()
	return used


func total_capacity(
	paper_doll: Dictionary,
	storage_slots: Array
) -> int:
	var total := 0
	for slot in storage_slots:
		total += container_capacity(paper_doll, slot)
	return total


func total_item_cost(backpack_array: Array[ItemData]) -> int:
	var total := 0
	for item in backpack_array:
		total += item.get_inventory_cost()
	return total
