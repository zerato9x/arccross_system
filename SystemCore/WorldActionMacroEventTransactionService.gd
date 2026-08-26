extends RefCounted
class_name WorldActionMacroEventTransactionService

## Canonical macro-event source staging. Campaign presentation/progression may
## react after commit, but a searched event source and elapsed player action
## must cross the same receipt boundary.

const MUTATION_TYPE := "macro_event_application"
const VERB_ID := "talk"

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
	for mutation_value in receipt.mutations:
		if str(mutation_value.get("type", "")) == MUTATION_TYPE:
			actions.append(mutation_value)
	if actions.size() != 1:
		return "World-action receipt contains duplicate macro-event applications."
	if receipt.actor_id != "player" or receipt.verb_id != VERB_ID:
		return "Macro-event application requires a player talk action."
	var action := actions[0]
	if (
		str(action.get("event_id", "")).is_empty()
		or str(action.get("event_id", "")) != receipt.target_id
		or str(action.get("choice_id", "")).is_empty()
	):
		return "Macro-event application has malformed event identity."
	if not action.get("source_search_option_id", "") is String:
		return "Macro-event application has malformed source identity."
	return ""


func stage(receipt: WorldActionReceipt) -> Dictionary:
	if not has_action(receipt):
		return {
			"handled": false,
			"success": true,
			"error": "",
			"hex_state": {},
		}
	if store == null:
		return _failure("Macro-event transaction services are unavailable.")
	var action := _mutation(receipt)
	var source_id := str(action.get("source_search_option_id", ""))
	if source_id.is_empty():
		return {
			"handled": true,
			"success": true,
			"error": "",
			"hex_state": {},
		}
	var current_hex := store.get_hex_record(receipt.target_coords)
	if current_hex == null:
		return _failure("Canonical macro-event source Hex is unavailable.")
	if current_hex.searched_targets.has(source_id):
		return _failure("Macro-event source has already been resolved.")
	var next_hex := HexRecord.from_dict(current_hex.to_dict())
	next_hex.searched_targets.append(source_id)
	return {
		"handled": true,
		"success": true,
		"error": "",
		"hex_state": next_hex.to_dict(),
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
		"hex_state": {},
	}
