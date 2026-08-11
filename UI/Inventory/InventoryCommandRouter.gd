extends RefCounted
class_name InventoryCommandRouter

## Normalizes UI gestures into one neutral inventory intent. The router does
## not resolve or mutate inventory state; the application layer owns that.


func intent(
	action_id: String,
	instance_id: String,
	equipment_slot: int = GameEnums.EquipmentSlot.NONE,
	payload: Dictionary = {}
) -> Dictionary:
	return {
		"action_id": action_id,
		"instance_id": instance_id,
		"equipment_slot": equipment_slot,
		"payload": payload.duplicate(true),
	}


func requires_confirmation(action_id: String) -> bool:
	return action_id in [
		GameEnums.MACRO_INV_CONSUME,
		GameEnums.MACRO_INV_DROP,
	]
