extends RefCounted
class_name WorldActionNpcWorkTransactionService

## Canonical NPC work-session staging. Progress belongs to the actor runtime,
## but receipts carry only the semantic set/clear operation rather than a full
## caller-owned runtime snapshot.

const MUTATION_TYPE := "npc_work_application"
const SUPPORTED_VERBS := ["search", "dismantle", "repair"]
const SEARCH_RESOURCE_COMPONENTS := ["rubble", "debris", "container"]

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
	var actions: Array[Dictionary] = []
	var work_progress_count := 0
	var consume_count := 0
	for mutation_value in receipt.mutations:
		var mutation: Dictionary = mutation_value
		match str(mutation.get("type", "")):
			MUTATION_TYPE:
				actions.append(mutation)
			"work_progress":
				work_progress_count += 1
			"consume_material":
				consume_count += 1
	if actions.size() != 1:
		return "World-action receipt contains duplicate NPC work applications."
	if receipt.actor_id == "player":
		return "NPC work application cannot target the player actor."
	if receipt.verb_id not in SUPPORTED_VERBS:
		return "NPC work application has an unsupported verb."
	if work_progress_count != 1:
		return "NPC work application requires exactly one work-progress mutation."
	if receipt.target_state.is_empty():
		return "NPC work application has no canonical target state."
	if receipt.verb_id == "repair" and consume_count != 1:
		return "NPC repair work must consume exactly one material unit."
	if receipt.verb_id != "repair" and consume_count > 0:
		return "Non-repair NPC work cannot consume repair material."
	var action := actions[0]
	var clear_work := bool(action.get("clear_world_work", false))
	var work_state_value: Variant = action.get("world_work_state", {})
	var search_completion_value: Variant = action.get("search_completion", {})
	if not work_state_value is Dictionary:
		return "NPC work application contains malformed work state."
	if not search_completion_value is Dictionary:
		return "NPC work application contains malformed SEARCH completion data."
	var work_state: Dictionary = work_state_value
	var search_completion: Dictionary = search_completion_value
	if clear_work != receipt.work_completed:
		return "NPC work application completion state does not match its receipt."
	if clear_work:
		if not work_state.is_empty():
			return "Completed NPC work application still contains progress state."
	else:
		if (
			work_state.is_empty()
			or str(work_state.get("action_id", "")) != receipt.action_id
			or str(work_state.get("receipt_id", "")) != receipt.receipt_id
			or int(work_state.get("attempt_index", -1)) < 0
			or int(work_state.get("completed_units", -1)) < 0
		):
			return "NPC work application progress state is malformed."
	var completed_search := receipt.verb_id == "search" and receipt.work_completed
	if completed_search:
		var item_state_value: Variant = search_completion.get("item_state", {})
		if (
			search_completion.is_empty()
			or str(search_completion.get("resource_component", ""))
			not in SEARCH_RESOURCE_COMPONENTS
			or int(search_completion.get("expected_remaining", 0)) <= 0
			or not item_state_value is Dictionary
		):
			return "Completed NPC SEARCH has malformed atomic completion data."
		var item_state: Dictionary = item_state_value
		if (
			str(item_state.get("instance_id", "")).is_empty()
			or str(item_state.get("owner_id", "")) != receipt.actor_id
			or str(item_state.get("physical_location", "")) != "inventory"
		):
			return "Completed NPC SEARCH has malformed salvage ownership."
	elif not search_completion.is_empty():
		return "Incomplete or non-SEARCH NPC work contains completion data."
	return ""


func stage(
	runtime: Dictionary,
	knowledge: Dictionary,
	receipt: WorldActionReceipt
) -> Dictionary:
	if not has_action(receipt):
		return {
			"handled": false,
			"success": true,
			"runtime": runtime.duplicate(true),
			"knowledge": knowledge.duplicate(true),
			"hex_state": {},
			"created_items": [],
			"target_state_handled": false,
		}
	if runtime.is_empty() or store == null:
		return _failure("Canonical NPC runtime is unavailable.")
	var next_runtime := runtime.duplicate(true)
	var next_knowledge := knowledge.duplicate(true)
	var action := _mutation(receipt)
	if bool(action.get("clear_world_work", false)):
		next_runtime.erase("world_work")
	else:
		next_runtime["world_work"] = action.get(
			"world_work_state", {}
		).duplicate(true)
	var hex_state: Dictionary = {}
	var created_items: Array = []
	var target_state_handled := false
	if receipt.verb_id == "search" and receipt.work_completed:
		var completion_result := _stage_search_completion(
			next_runtime,
			next_knowledge,
			receipt,
			action.get("search_completion", {})
		)
		if not bool(completion_result.get("success", false)):
			return _failure(str(completion_result.get(
				"error", "NPC SEARCH completion is no longer valid."
			)))
		next_runtime = completion_result.get("runtime", {}).duplicate(true)
		next_knowledge = completion_result.get("knowledge", {}).duplicate(true)
		hex_state = completion_result.get("hex_state", {}).duplicate(true)
		created_items = completion_result.get("created_items", []).duplicate(true)
		target_state_handled = true
	return {
		"handled": true,
		"success": true,
		"error": "",
		"runtime": next_runtime,
		"knowledge": next_knowledge,
		"hex_state": hex_state,
		"created_items": created_items,
		"target_state_handled": target_state_handled,
	}


func _stage_search_completion(
	runtime: Dictionary,
	knowledge: Dictionary,
	receipt: WorldActionReceipt,
	completion: Dictionary
) -> Dictionary:
	var current_hex := store.get_hex_record(receipt.target_coords)
	if current_hex == null:
		return {"success": false, "error": "Canonical NPC SEARCH Hex is unavailable."}
	var target_index := -1
	var target: WorldObjectRecord = null
	for index in range(current_hex.world_objects.size()):
		var value: Variant = current_hex.world_objects[index]
		if value is Dictionary and str(value.get("object_id", "")) == receipt.target_id:
			target_index = index
			target = WorldObjectRecord.from_dict(value)
			break
	if target == null or target.revision != receipt.expected_target_revision:
		return {"success": false, "error": "Canonical NPC SEARCH target drifted."}
	var resource_component := str(completion.get("resource_component", ""))
	if resource_component not in SEARCH_RESOURCE_COMPONENTS or not target.has_component(
		resource_component
	):
		return {"success": false, "error": "NPC SEARCH resource component disappeared."}
	var resource := target.component(resource_component).duplicate(true)
	var remaining_key := (
		"remaining_searches" if resource_component == "container" else "material_units"
	)
	var current_remaining := int(resource.get(remaining_key, 0))
	if (
		current_remaining <= 0
		or bool(resource.get("depleted", false))
		or current_remaining != int(completion.get("expected_remaining", -1))
	):
		return {"success": false, "error": "NPC SEARCH resource is stale or depleted."}
	resource[remaining_key] = current_remaining - 1
	resource["depleted"] = int(resource[remaining_key]) <= 0
	target.components[resource_component] = resource
	if (
		resource_component in ["rubble", "debris"]
		and bool(resource.get("depleted", false))
		and target.has_component("container")
	):
		var container := target.component("container").duplicate(true)
		if bool(container.get("finite", false)):
			container["remaining_searches"] = 0
			container["depleted"] = true
			target.components["container"] = container
	target.revision = receipt.expected_target_revision + 1
	var next_hex := HexRecord.from_dict(current_hex.to_dict())
	next_hex.world_objects[target_index] = target.to_dict()
	var committed_minute := store.world_time_minutes + maxi(0, receipt.elapsed_minutes)
	next_hex.trace_records.append({
		"kind": "disturbed_rubble",
		"source_id": receipt.actor_id,
		"coords": receipt.target_coords,
		"created_minute": committed_minute,
		"expires_minute": committed_minute + 120,
		"age_minutes": 0,
		"direction": str(receipt.target_coords),
	})
	var item_state: Dictionary = completion.get("item_state", {}).duplicate(true)
	var instance_id := str(item_state.get("instance_id", ""))
	if (
		instance_id.is_empty()
		or not store.find_item_ownership(instance_id).is_empty()
		or store.runtime_item_ids(runtime).has(instance_id)
	):
		return {"success": false, "error": "NPC SEARCH salvage identity already exists."}
	var next_runtime := runtime.duplicate(true)
	var carried: Array = next_runtime.get("inventory_items", []).duplicate(true)
	carried.append(item_state)
	next_runtime["inventory_items"] = carried
	next_runtime["macro_purpose_label"] = "Carrying salvage"
	var next_knowledge := knowledge.duplicate(true)
	next_knowledge["northward_evidence"] = {
		"source": receipt.actor_id,
		"coords": receipt.target_coords,
		"age_minutes": 0,
		"confidence": 0.5,
		"evidence": "disturbed_rubble",
	}
	return {
		"success": true,
		"runtime": next_runtime,
		"knowledge": next_knowledge,
		"hex_state": next_hex.to_dict(),
		"created_items": [item_state],
	}


func _mutation(receipt: WorldActionReceipt) -> Dictionary:
	for mutation in receipt.mutations:
		if str(mutation.get("type", "")) == MUTATION_TYPE:
			return mutation
	return {}


func _failure(message: String) -> Dictionary:
	return {
		"handled": true,
		"success": false,
		"error": message,
		"runtime": {},
		"knowledge": {},
		"hex_state": {},
		"created_items": [],
		"target_state_handled": false,
	}
