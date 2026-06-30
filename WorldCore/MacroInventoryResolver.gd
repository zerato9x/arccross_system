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
	ground_take_callback: Callable,
	ground_add_callback: Callable,
	can_offer_equip_callback: Callable,
	inventory_error_callback: Callable
) -> Dictionary:
	var inventory := player_core.inventory
	var message := ""
	var ground_mutations: Array = []
	var ground_restore: Array = []

	match action_id:
		GameEnums.MACRO_INV_TAKE:
			var item_state: Dictionary = ground_take_callback.call(
				coords,
				instance_id
			)
			if item_state.is_empty():
				message = "That ground item is no longer available."
			else:
				var ground_item := ItemData.from_runtime_state(item_state)
				if inventory.add_to_backpack(
					ground_item,
					equipment_slot as GameEnums.EquipmentSlot
				):
					message = "Took %s." % ground_item.display_name
				else:
					ground_restore.append(item_state)
					message = inventory_error_callback.call(
						"That item does not fit in the backpack."
					)
		GameEnums.MACRO_INV_DROP:
			var dropped := inventory.remove_item_by_instance_id(instance_id)
			if dropped:
				ground_mutations.append(dropped.to_runtime_state())
				message = "Dropped %s." % dropped.display_name
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
		GameEnums.MACRO_INV_CONSUME:
			var consumable := inventory.find_item_by_instance_id(instance_id)
			if consumable == null or not inventory.backpack_array.has(consumable):
				message = "Only backpack consumables can be used."
			elif player_core.use_consumable_item(consumable):
				message = "Used %s." % consumable.display_name
				return {
					"message": message,
					"player_runtime": player_core.capture_runtime_state().to_dict(),
					"ground_mutations": ground_mutations,
					"ground_restore": ground_restore,
					"item_used_category": consumable.catalog_category,
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
			else:
				message = inventory_error_callback.call(
					"The magazine could not be loaded."
				)
		GameEnums.MACRO_INV_INTERACT:
			message = "That object is too large to carry. It remains on the ground."
		_:
			message = "Unknown inventory command."

	return {
		"message": message,
		"player_runtime": player_core.capture_runtime_state().to_dict(),
		"ground_mutations": ground_mutations,
		"ground_restore": ground_restore,
	}
