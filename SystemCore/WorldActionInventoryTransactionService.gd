extends RefCounted
class_name WorldActionInventoryTransactionService

## Inventory-specific receipt validation, detached application, and canonical
## player/ground commit. The general world-action boundary delegates here so it
## does not become yet another universal object with a method for every noun.

const MUTATION_TYPE := "inventory_action"
const METHOD_ID := "inventory"
const SUPPORTED_ACTIONS := [
	GameEnums.MACRO_INV_TAKE,
	GameEnums.MACRO_INV_DROP,
	GameEnums.MACRO_INV_EQUIP,
	GameEnums.MACRO_INV_UNEQUIP,
	GameEnums.MACRO_INV_CONSUME,
	GameEnums.MACRO_INV_MOVE,
	GameEnums.MACRO_INV_LOAD_MAGAZINE,
	GameEnums.MACRO_INV_REPAIR,
]

var store: RuntimeStateStore


func configure(state: RuntimeStateStore) -> void:
	store = state


func has_action(receipt: WorldActionReceipt) -> bool:
	if receipt == null:
		return false
	for mutation in receipt.mutations:
		if mutation is Dictionary and str(mutation.get("type", "")) == MUTATION_TYPE:
			return true
	return false


func validation_error(receipt: WorldActionReceipt) -> String:
	if not has_action(receipt):
		return ""
	var inventory_mutations: Array[Dictionary] = []
	for mutation_value in receipt.mutations:
		var mutation: Dictionary = mutation_value
		var mutation_type := str(mutation.get("type", ""))
		if mutation_type == MUTATION_TYPE:
			inventory_mutations.append(mutation)
		elif mutation_type != "elapsed_time":
			return "World-action inventory action contains conflicting mutations."
	if inventory_mutations.size() != 1:
		return "World-action receipt contains duplicate inventory actions."
	if receipt.actor_id != "player":
		return "World-action inventory actions only support the player actor."
	if receipt.method_id != METHOD_ID:
		return "World-action inventory action has the wrong method."
	if not receipt.actor_state.is_empty():
		return "World-action inventory action contains a replacement actor runtime."
	var mutation := inventory_mutations[0]
	var instance_id := str(mutation.get("instance_id", ""))
	var action_id := str(mutation.get("action_id", ""))
	var equipment_slot := int(mutation.get("equipment_slot", -1))
	var action_payload: Variant = mutation.get("action_payload", {})
	if (
		instance_id.is_empty()
		or receipt.target_id != instance_id
		or action_id not in SUPPORTED_ACTIONS
		or equipment_slot not in GameEnums.EquipmentSlot.values()
		or not action_payload is Dictionary
	):
		return "World-action inventory mutation is malformed."
	var expected_verb := "pick_up" if action_id == GameEnums.MACRO_INV_TAKE else action_id
	if receipt.verb_id != expected_verb:
		return "World-action inventory action has the wrong verb."
	return ""


func stage(core: HumanoidCore, receipt: WorldActionReceipt) -> Dictionary:
	if not has_action(receipt):
		return {
			"handled": false,
			"success": true,
			"ground_remove_ids": [],
			"ground_additions": [],
		}
	if core == null or store == null:
		return {
			"handled": true,
			"success": false,
			"error": "Inventory transaction services are unavailable.",
		}
	var mutation := _mutation(receipt)
	var payload: Dictionary = mutation.get("action_payload", {}).duplicate(true)
	var result := HumanoidInventoryActionService.new().apply(
		core,
		str(mutation.get("action_id", "")),
		str(mutation.get("instance_id", "")),
		int(mutation.get("equipment_slot", GameEnums.EquipmentSlot.NONE)),
		payload,
		store.get_ground_items(receipt.target_coords)
	)
	return {
		"handled": true,
		"success": bool(result.get("committed", false)),
		"error": str(result.get("message", "Inventory action is no longer valid.")),
		"ground_remove_ids": result.get("ground_remove_ids", []).duplicate(true),
		"ground_additions": result.get("ground_additions", []).duplicate(true),
	}


func commit(
	receipt: WorldActionReceipt,
	actor_runtime: Dictionary,
	staging: Dictionary
) -> bool:
	if store == null or not has_action(receipt):
		return false
	return store.commit_entity_runtime_with_ground_delta(
		receipt.actor_id,
		actor_runtime,
		receipt.target_coords,
		staging.get("ground_remove_ids", []),
		staging.get("ground_additions", [])
	)


func _mutation(receipt: WorldActionReceipt) -> Dictionary:
	for mutation in receipt.mutations:
		if str(mutation.get("type", "")) == MUTATION_TYPE:
			return mutation
	return {}
