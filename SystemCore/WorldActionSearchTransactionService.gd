extends RefCounted
class_name WorldActionSearchTransactionService

## Canonical search-state staging. Search rules resolve deterministic outcomes
## elsewhere; this service applies only the authored search-count/target delta
## to the current canonical hex inside the world-action rollback boundary.

const MUTATION_TYPE := "search_application"
const VERB_ID := "search"

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
	var searches: Array[Dictionary] = []
	var trace_count := 0
	var injury_count := 0
	var run_flag_keys: Dictionary = {}
	for mutation_value in receipt.mutations:
		var mutation: Dictionary = mutation_value
		match str(mutation.get("type", "")):
			MUTATION_TYPE:
				searches.append(mutation)
			"append_trace":
				trace_count += 1
			"biological_hit":
				injury_count += 1
			"set_run_flag":
				var key := str(mutation.get("key", ""))
				if key.is_empty() or run_flag_keys.has(key):
					return "World-action search contains duplicate or empty run flags."
				run_flag_keys[key] = true
			"elapsed_time", "add_ground_item":
				pass
			_:
				return "World-action search contains conflicting mutations."
	if searches.size() != 1:
		return "World-action receipt contains duplicate search applications."
	if receipt.actor_id != "player":
		return "World-action search only supports the player actor."
	if receipt.verb_id != VERB_ID:
		return "World-action search has the wrong verb."
	if not receipt.actor_state.is_empty():
		return "World-action search contains a replacement actor runtime."
	if trace_count > 1 or injury_count > 1:
		return "World-action search contains duplicate trace or injury effects."
	if not receipt.target_state.is_empty():
		if trace_count != 1:
			return "Physical search depletion requires exactly one disturbance trace."
	elif receipt.target_id != "search:" + str(receipt.target_coords):
		return "World-action search targets the wrong location identity."
	var mutation := searches[0]
	if int(mutation.get("expected_search_count", -1)) < 0:
		return "World-action search contains an invalid expected search count."
	var searched_target_value: Variant = mutation.get("searched_target_id", "")
	if not searched_target_value is String:
		return "World-action search contains a malformed searched-target identity."
	return ""


func stage(receipt: WorldActionReceipt) -> Dictionary:
	if not has_action(receipt):
		return {
			"handled": false,
			"success": true,
			"hex_state": {},
		}
	if store == null:
		return _failure("Search transaction services are unavailable.")
	var current_hex := store.get_hex_record(receipt.target_coords)
	if current_hex == null:
		return _failure("Canonical search location is unavailable.")
	var mutation := _mutation(receipt)
	var expected_count := int(mutation.get("expected_search_count", -1))
	var searched_target_id := str(mutation.get("searched_target_id", ""))
	if current_hex.search_count != expected_count:
		return _failure("Search outcome is no longer valid.")
	if (
		not searched_target_id.is_empty()
		and current_hex.searched_targets.has(searched_target_id)
	):
		return _failure("Search target has already been resolved.")
	var next_hex := HexRecord.from_dict(current_hex.to_dict())
	next_hex.search_count += 1
	if not searched_target_id.is_empty():
		next_hex.searched_targets.append(searched_target_id)
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
