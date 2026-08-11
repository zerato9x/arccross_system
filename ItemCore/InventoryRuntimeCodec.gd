extends RefCounted
class_name InventoryRuntimeCodec

## Converts the live inventory collections to and from the stable InventoryState
## contract. No signals or capacity mutation occur here.

func capture(
	paper_doll: Dictionary,
	backpack_array: Array[ItemData],
	item_container_slots: Dictionary
) -> InventoryState:
	var state := InventoryState.new()
	state.base_max_capacity = 0

	var equipment_state: Dictionary = {}
	for slot in paper_doll.keys():
		var item := paper_doll[slot] as ItemData
		if item != null:
			equipment_state[str(slot)] = item.to_runtime_state()
	state.equipment = equipment_state

	var backpack_state: Array = []
	for item in backpack_array:
		var item_state := item.to_runtime_state()
		item_state["container_slot"] = int(item_container_slots.get(
			item.instance_id,
			GameEnums.EquipmentSlot.NONE
		))
		backpack_state.append(item_state)
	state.backpack = backpack_state
	return state


func restore(
	state,
	paper_doll: Dictionary,
	backpack_array: Array[ItemData],
	item_container_slots: Dictionary
) -> bool:
	var inv_state: InventoryState
	if state is InventoryState:
		inv_state = state
	elif state is Dictionary:
		inv_state = InventoryState.from_dict(state)
	else:
		return false

	backpack_array.clear()
	item_container_slots.clear()
	for slot in paper_doll.keys():
		paper_doll[slot] = null

	for slot_key in inv_state.equipment.keys():
		var slot := int(slot_key)
		if not paper_doll.has(slot):
			continue
		var equipped := ItemData.from_runtime_state(
			inv_state.equipment[slot_key]
		)
		equipped.physical_location = "equipped"
		equipped.equipped_slot = slot
		paper_doll[slot] = equipped

	for item_state in inv_state.backpack:
		var item := ItemData.from_runtime_state(item_state)
		backpack_array.append(item)
		var container_slot := int(item_state.get(
			"container_slot",
			GameEnums.EquipmentSlot.NONE
		))
		if container_slot != GameEnums.EquipmentSlot.NONE:
			item_container_slots[item.instance_id] = container_slot
	return true
