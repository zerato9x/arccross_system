extends RefCounted
class_name HumanoidInventoryActionService

## Applies one inventory command to a supplied HumanoidCore. The caller owns
## the core and decides whether the resulting runtime is committed. This class
## deliberately knows nothing about RuntimeStateStore, world receipts, or UI.

var _last_error: String = ""
var _spilled_states: Array[Dictionary] = []


func apply(
	core: HumanoidCore,
	action_id: String,
	instance_id: String,
	equipment_slot: int,
	action_payload: Dictionary,
	ground_items: Array
) -> Dictionary:
	var result := _base_result()
	if core == null or core.inventory == null or core.body == null:
		result.message = "The actor inventory is unavailable."
		return result
	var inventory := core.inventory
	_last_error = ""
	_spilled_states.clear()
	if not inventory.inventory_error.is_connected(_capture_error):
		inventory.inventory_error.connect(_capture_error)
	if not inventory.items_spilled.is_connected(_capture_spills):
		inventory.items_spilled.connect(_capture_spills)
	inventory.set_equipment_validator(Callable(core, "_can_equip_item"))

	match action_id:
		GameEnums.MACRO_INV_TAKE:
			_apply_take(result, inventory, instance_id, equipment_slot, ground_items)
		GameEnums.MACRO_INV_DROP:
			_apply_drop(result, inventory, instance_id)
		GameEnums.MACRO_INV_EQUIP:
			_apply_equip(result, inventory, instance_id, equipment_slot)
		GameEnums.MACRO_INV_UNEQUIP:
			_apply_unequip(result, inventory, instance_id, equipment_slot)
		GameEnums.MACRO_INV_CONSUME:
			_apply_consume(result, core, instance_id)
		GameEnums.MACRO_INV_MOVE:
			_apply_move(result, inventory, instance_id, equipment_slot)
		GameEnums.MACRO_INV_LOAD_MAGAZINE:
			_apply_load_magazine(result, inventory, instance_id)
		GameEnums.MACRO_INV_REPAIR:
			_apply_repair(result, inventory, instance_id, action_payload)
		GameEnums.MACRO_INV_INSPECT:
			_apply_inspect(result, inventory, instance_id)
		GameEnums.MACRO_INV_INTERACT:
			result.message = "That object is too large to carry. It remains on the ground."
		_:
			result.message = "Unknown inventory command."

	result.ground_additions = _spilled_states.duplicate(true)
	return result


func _base_result() -> Dictionary:
	return {
		"committed": false,
		"message": "The inventory action could not be completed.",
		"ground_remove_ids": [],
		"ground_additions": [],
		"neutral_action": {},
	}


func _apply_take(
	result: Dictionary,
	inventory: InventorySystem,
	instance_id: String,
	equipment_slot: int,
	ground_items: Array
) -> void:
	var item_state := _ground_item_state(ground_items, instance_id)
	if item_state.is_empty():
		result.message = "That ground item is no longer available."
		return
	var item := ItemData.from_runtime_state(item_state)
	var preferred := equipment_slot as GameEnums.EquipmentSlot
	if item == null or not inventory.can_add_to_backpack(item, preferred):
		result.message = _error_or("That item does not fit in carried storage.")
		return
	if not inventory.add_to_backpack(item, preferred):
		result.message = _error_or("The preflighted pickup could not be committed.")
		return
	result.committed = true
	result.message = "Took %s." % item.display_name
	result.ground_remove_ids = [instance_id]


func _apply_drop(
	result: Dictionary,
	inventory: InventorySystem,
	instance_id: String
) -> void:
	var dropped := inventory.remove_item_by_instance_id(instance_id)
	if dropped == null:
		result.message = "That carried item is no longer available."
		return
	result.committed = true
	result.message = "Dropped %s." % dropped.display_name
	_spilled_states.append(dropped.to_runtime_state())


func _apply_equip(
	result: Dictionary,
	inventory: InventorySystem,
	instance_id: String,
	equipment_slot: int
) -> void:
	var item := inventory.find_item_by_instance_id(instance_id)
	var slot := equipment_slot as GameEnums.EquipmentSlot
	if item == null or not inventory.backpack_array.has(item):
		result.message = "Only stowed items can be equipped."
		return
	if not inventory.can_equip_in_slot(item, slot):
		result.message = "That item cannot be equipped in the requested slot."
		return
	if not inventory.equip_item(item, slot):
		result.message = _error_or("The equipment change failed.")
		return
	result.committed = true
	result.message = "Equipped %s." % item.display_name


func _apply_unequip(
	result: Dictionary,
	inventory: InventorySystem,
	instance_id: String,
	equipment_slot: int
) -> void:
	if equipment_slot not in GameEnums.EquipmentSlot.values():
		result.message = "That equipment slot does not exist."
		return
	var item: ItemData = inventory.paper_doll.get(equipment_slot)
	if item == null or item.instance_id != instance_id:
		result.message = "That equipped item is no longer available."
		return
	inventory.unequip_item(equipment_slot as GameEnums.EquipmentSlot)
	result.committed = true
	result.message = "Unequipped %s." % item.display_name


func _apply_consume(
	result: Dictionary,
	core: HumanoidCore,
	instance_id: String
) -> void:
	var item := core.inventory.find_item_by_instance_id(instance_id)
	if item == null or not core.inventory.backpack_array.has(item):
		result.message = "Only backpack consumables can be used."
		return
	if not core.use_consumable_item(item):
		result.message = _error_or("The item could not be used.")
		return
	result.committed = true
	result.message = "Used %s." % item.display_name
	result.item_used_category = item.catalog_category


func _apply_move(
	result: Dictionary,
	inventory: InventorySystem,
	instance_id: String,
	equipment_slot: int
) -> void:
	var item := inventory.find_item_by_instance_id(instance_id)
	if item == null or not inventory.backpack_array.has(item):
		result.message = "That stowed item is no longer available."
		return
	if not inventory.move_to_container(
		item,
		equipment_slot as GameEnums.EquipmentSlot
	):
		result.message = _error_or("That item does not fit there.")
		return
	result.committed = true
	result.message = "Moved %s." % item.display_name


func _apply_load_magazine(
	result: Dictionary,
	inventory: InventorySystem,
	instance_id: String
) -> void:
	var magazine := inventory.find_item_by_instance_id(instance_id)
	var loaded_rounds := inventory.load_magazine(magazine)
	if loaded_rounds <= 0:
		result.message = _error_or("The magazine could not be loaded.")
		return
	result.committed = true
	result.message = "Fitted %d rounds into %s." % [
		loaded_rounds,
		magazine.display_name,
	]


func _apply_repair(
	result: Dictionary,
	inventory: InventorySystem,
	instance_id: String,
	action_payload: Dictionary
) -> void:
	var target_id := str(action_payload.get("target_instance_id", instance_id))
	var tool_id := str(action_payload.get("tool_instance_id", ""))
	var material_id := str(action_payload.get("material_instance_id", ""))
	var context := str(action_payload.get("repair_context", "field"))
	var repair := inventory.repair_item(
		inventory.find_item_by_instance_id(target_id),
		inventory.find_item_by_instance_id(tool_id),
		inventory.find_item_by_instance_id(material_id),
		context,
		float(action_payload.get("roll_override", -1.0))
	)
	result.message = str(repair.get("message", "The repair could not be completed."))
	result.neutral_action = {
		"action_id": GameEnums.MACRO_INV_REPAIR,
		"target_instance_id": target_id,
		"tool_instance_id": tool_id,
		"material_instance_id": material_id,
		"repair_context": context,
		"result": repair,
	}
	result.committed = bool(repair.get("attempted", false))


func _apply_inspect(
	result: Dictionary,
	inventory: InventorySystem,
	instance_id: String
) -> void:
	var item := inventory.find_item_by_instance_id(instance_id)
	if item == null:
		result.message = "That carried item is no longer available."
		return
	if not item.can_inspect_knowledge():
		result.message = "%s contains no decodable evidence." % item.display_name
		return
	result.committed = true
	result.message = "Inspecting %s." % item.display_name
	result.neutral_action = {
		"action_id": GameEnums.MACRO_INV_INSPECT,
		"instance_id": item.instance_id,
		"item_id": item.id,
		"knowledge_entry_id": item.knowledge_entry_id,
	}


func _ground_item_state(ground_items: Array, instance_id: String) -> Dictionary:
	for value in ground_items:
		if value is Dictionary and str(value.get("instance_id", "")) == instance_id:
			return (value as Dictionary).duplicate(true)
	return {}


func _capture_error(message: String) -> void:
	_last_error = message


func _capture_spills(items: Array[ItemData]) -> void:
	for item in items:
		if item != null:
			_spilled_states.append(item.to_runtime_state())


func _error_or(fallback: String) -> String:
	return _last_error if not _last_error.is_empty() else fallback
