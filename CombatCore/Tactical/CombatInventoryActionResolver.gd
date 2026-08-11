extends RefCounted
class_name CombatInventoryActionResolver

## Inventory-facing combat predicates. Item mutation remains owned by
## InventorySystem and CombatResolutionEngine.

func has_reload_source(actor: HumanoidCore, weapon: ItemData) -> bool:
	if actor == null or actor.inventory == null or weapon == null:
		return false
	if not weapon.magazine_id.is_empty():
		return actor.inventory.find_filled_magazine(weapon.magazine_id) != null
	if not weapon.reload_aid_id.is_empty():
		return actor.inventory.find_filled_magazine(weapon.reload_aid_id) != null
	if weapon.cycle_loads_one_round:
		return false
	return actor.inventory.has_combat_item(weapon.ammunition_id)


func item_for_request(actor: HumanoidCore, instance_id: String) -> ItemData:
	return actor.inventory.find_item_by_instance_id(instance_id) if actor != null and actor.inventory != null else null
