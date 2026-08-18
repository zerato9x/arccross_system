extends RefCounted
class_name MacroInventoryResolver

## WorldCore-owned macro inventory command resolver.
## Delegates biology/inventory rules to HumanoidCore while returning neutral
## mutations for RuntimeStateStore application.


static func resolve_action(
	action_id: String,
	instance_id: String,
	equipment_slot: int,
	player_core: HumanoidCore,
	coords: Vector2i,
	ground_query_callback: Callable,
	can_offer_equip_callback: Callable,
	inventory_error_callback: Callable,
	action_payload: Dictionary = {}
) -> Dictionary:
	var inventory := player_core.inventory
	var message := ""
	var ground_mutations: Array = []
	var ground_restore: Array = []
	var elapsed_minutes := 0
	var neutral_action := {}
	var ground_transfer_instance_id := ""
	var committed := false

	match action_id:
		GameEnums.MACRO_INV_TAKE:
			var item_state: Dictionary = {}
			for value in ground_query_callback.call(coords):
				if value is Dictionary and str(value.get("instance_id", "")) == instance_id:
					item_state = (value as Dictionary).duplicate(true)
					break
			if item_state.is_empty():
				message = "That ground item is no longer available."
			else:
				var ground_item := ItemData.from_runtime_state(item_state)
				if ground_item == null or not inventory.can_add_to_backpack(ground_item):
					message = inventory_error_callback.call(
						"That item does not fit in the backpack."
					)
				else:
					if inventory.add_to_backpack(
						ground_item,
						equipment_slot as GameEnums.EquipmentSlot
					):
						message = "Took %s." % ground_item.display_name
						ground_transfer_instance_id = instance_id
						committed = true
					else:
						message = inventory_error_callback.call(
							"The preflighted pickup could not be committed."
						)
		GameEnums.MACRO_INV_DROP:
			var dropped := inventory.remove_item_by_instance_id(instance_id)
			if dropped:
				ground_mutations.append(dropped.to_runtime_state())
				message = "Dropped %s." % dropped.display_name
				committed = true
			else:
				message = "That carried item is no longer available."
		GameEnums.MACRO_INV_EQUIP:
			var equippable := inventory.find_item_by_instance_id(instance_id)
			if equippable == null or not inventory.backpack_array.has(equippable):
				message = "Only stowed items can be equipped."
			elif (
				not inventory.can_equip_in_slot(
					equippable,
					equipment_slot as GameEnums.EquipmentSlot
				)
				or not can_offer_equip_callback.call(equippable)
			):
				message = "That item cannot be equipped in the requested slot."
			elif inventory.equip_item(
				equippable,
				equipment_slot as GameEnums.EquipmentSlot
			):
				message = "Equipped %s." % equippable.display_name
				committed = true
			else:
				message = inventory_error_callback.call(
					"The equipment change failed."
				)
		GameEnums.MACRO_INV_UNEQUIP:
			if not inventory.paper_doll.has(equipment_slot):
				message = "That equipment slot does not exist."
			else:
				var equipped: ItemData = inventory.paper_doll[equipment_slot]
				if equipped == null or equipped.instance_id != instance_id:
					message = "That equipped item is no longer available."
				else:
					inventory.unequip_item(equipment_slot)
					message = "Unequipped %s." % equipped.display_name
					committed = true
		GameEnums.MACRO_INV_CONSUME:
			var consumable := inventory.find_item_by_instance_id(instance_id)
			if consumable == null or not inventory.backpack_array.has(consumable):
				message = "Only backpack consumables can be used."
			elif player_core.use_consumable_item(consumable):
				message = "Used %s." % consumable.display_name
				committed = true
				return {
					"message": message,
					"player_runtime": player_core.capture_runtime_state().to_dict(),
					"ground_mutations": ground_mutations,
					"ground_restore": ground_restore,
					"item_used_category": consumable.catalog_category,
					"committed": committed,
				}
			else:
				message = inventory_error_callback.call(
					"The item could not be used."
				)
		GameEnums.MACRO_INV_MOVE:
			var movable := inventory.find_item_by_instance_id(instance_id)
			if movable == null or not inventory.backpack_array.has(movable):
				message = "That stowed item is no longer available."
			elif inventory.move_to_container(
				movable,
				equipment_slot as GameEnums.EquipmentSlot
			):
				message = "Moved %s." % movable.display_name
				committed = true
			else:
				message = inventory_error_callback.call(
					"That item does not fit there."
				)
		GameEnums.MACRO_INV_LOAD_MAGAZINE:
			var magazine := inventory.find_item_by_instance_id(instance_id)
			var loaded_rounds := inventory.load_magazine(magazine)
			if loaded_rounds > 0:
				message = "Fitted %d rounds into %s." % [
					loaded_rounds,
					magazine.display_name,
				]
				committed = true
			else:
				message = inventory_error_callback.call(
					"The magazine could not be loaded."
				)
		GameEnums.MACRO_INV_INTERACT:
			message = "That object is too large to carry. It remains on the ground."
		GameEnums.MACRO_INV_REPAIR:
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
			message = str(repair.get("message", "The repair could not be completed."))
			if bool(repair.get("attempted", false)):
				elapsed_minutes = 30
				committed = true
			neutral_action = {
				"action_id": GameEnums.MACRO_INV_REPAIR,
				"target_instance_id": target_id,
				"tool_instance_id": tool_id,
				"material_instance_id": material_id,
				"repair_context": context,
				"result": repair,
			}
		GameEnums.MACRO_INV_INSPECT:
			var inspected := inventory.find_item_by_instance_id(instance_id)
			if inspected == null:
				message = "That carried item is no longer available."
			elif not inspected.can_inspect_knowledge():
				message = "%s contains no decodable evidence." % inspected.display_name
			else:
				message = "Inspecting %s." % inspected.display_name
				committed = true
				neutral_action = {
					"action_id": GameEnums.MACRO_INV_INSPECT,
					"instance_id": inspected.instance_id,
					"item_id": inspected.id,
					"knowledge_entry_id": inspected.knowledge_entry_id,
				}
		_:
			message = "Unknown inventory command."

	return {
		"message": message,
		"player_runtime": player_core.capture_runtime_state().to_dict(),
		"ground_mutations": ground_mutations,
		"ground_restore": ground_restore,
		"ground_transfer_instance_id": ground_transfer_instance_id,
		"elapsed_minutes": elapsed_minutes,
		"neutral_action": neutral_action,
		"committed": committed,
	}
