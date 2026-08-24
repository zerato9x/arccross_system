extends RefCounted
class_name WorldActionNpcWorkTransactionService

## Canonical NPC work-session staging. Progress belongs to the actor runtime,
## but receipts carry only the semantic set/clear operation rather than a full
## caller-owned runtime snapshot.

const MUTATION_TYPE := "npc_work_application"
const SUPPORTED_VERBS := ["search", "dismantle", "repair"]


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
	var has_runtime_replacement := false
	for mutation_value in receipt.mutations:
		var mutation: Dictionary = mutation_value
		match str(mutation.get("type", "")):
			MUTATION_TYPE:
				actions.append(mutation)
			"work_progress":
				work_progress_count += 1
			"consume_material":
				consume_count += 1
			"replace_actor_runtime":
				has_runtime_replacement = true
	if actions.size() != 1:
		return "World-action receipt contains duplicate NPC work applications."
	if receipt.actor_id == "player":
		return "NPC work application cannot target the player actor."
	if receipt.verb_id not in SUPPORTED_VERBS:
		return "NPC work application has an unsupported verb."
	if work_progress_count != 1:
		return "NPC work application requires exactly one work-progress mutation."
	if not receipt.actor_state.is_empty() or has_runtime_replacement:
		return "NPC work application contains a replacement actor runtime."
	if receipt.target_state.is_empty():
		return "NPC work application has no canonical target state."
	if receipt.verb_id == "repair" and consume_count != 1:
		return "NPC repair work must consume exactly one material unit."
	if receipt.verb_id != "repair" and consume_count > 0:
		return "Non-repair NPC work cannot consume repair material."
	var action := actions[0]
	var clear_work := bool(action.get("clear_world_work", false))
	var work_state_value: Variant = action.get("world_work_state", {})
	if not work_state_value is Dictionary:
		return "NPC work application contains malformed work state."
	var work_state: Dictionary = work_state_value
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
	return ""


func stage(runtime: Dictionary, receipt: WorldActionReceipt) -> Dictionary:
	if not has_action(receipt):
		return {
			"handled": false,
			"success": true,
			"runtime": runtime.duplicate(true),
		}
	if runtime.is_empty():
		return _failure("Canonical NPC runtime is unavailable.")
	var next_runtime := runtime.duplicate(true)
	var action := _mutation(receipt)
	if bool(action.get("clear_world_work", false)):
		next_runtime.erase("world_work")
	else:
		next_runtime["world_work"] = action.get(
			"world_work_state", {}
		).duplicate(true)
	return {
		"handled": true,
		"success": true,
		"error": "",
		"runtime": next_runtime,
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
	}
