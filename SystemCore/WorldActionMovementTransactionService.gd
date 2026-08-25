extends RefCounted
class_name WorldActionMovementTransactionService

## Canonical movement contract. A receipt describes a relocation; the actor
## runtime is reconstructed from RuntimeStateStore and committed at the new
## coordinates only after the complete receipt has passed validation.

const MUTATION_TYPE := "move_actor"
const VERB_TRAVEL := "travel"
const VERB_RETREAT := "retreat"

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
	var movements: Array[Dictionary] = []
	var trace_count := 0
	var explored_count := 0
	for mutation_value in receipt.mutations:
		var mutation: Dictionary = mutation_value
		match str(mutation.get("type", "")):
			MUTATION_TYPE:
				movements.append(mutation)
			"movement_trace":
				trace_count += 1
			"set_hex_explored":
				explored_count += 1
			"elapsed_time":
				pass
			_:
				return "World-action movement contains conflicting mutations."
	if movements.size() != 1:
		return "World-action receipt contains duplicate actor movements."
	if trace_count != 1:
		return "World-action movement must contain exactly one movement trace."
	if explored_count > 1:
		return "World-action movement contains duplicate explored-hex mutations."
	if receipt.actor_id != "player" and explored_count > 0:
		return "NPC movement cannot reveal player exploration state."
	if not receipt.target_state.is_empty():
		return "World-action movement contains unrelated target state."
	if receipt.verb_id not in [VERB_TRAVEL, VERB_RETREAT]:
		return "World-action movement has an unsupported verb."
	if receipt.verb_id == VERB_RETREAT and receipt.actor_id != "player":
		return "World-action retreat only supports the player actor."
	if receipt.verb_id == VERB_TRAVEL and not receipt.target_id.begins_with("hex:"):
		return "World-action travel targets the wrong location identity."
	if receipt.verb_id == VERB_RETREAT and not receipt.target_id.begins_with("retreat:"):
		return "World-action retreat targets the wrong location identity."
	var movement := movements[0]
	var from_value: Variant = movement.get("from")
	var to_value: Variant = movement.get("to")
	if not from_value is Vector2i or not to_value is Vector2i:
		return "World-action movement has malformed coordinates."
	if to_value != receipt.target_coords:
		return "World-action movement destination does not match the receipt."
	if from_value == to_value:
		return "World-action movement does not change actor coordinates."
	return ""


func staging_error(receipt: WorldActionReceipt) -> String:
	if not has_action(receipt):
		return ""
	if store == null:
		return "RuntimeStateStore is unavailable for movement."
	var actor_coords: Variant = _actor_coords(receipt.actor_id)
	if actor_coords == null:
		return "World-action movement actor is unavailable."
	var movement := _movement(receipt)
	if movement.is_empty() or actor_coords != movement.get("from"):
		return "World-action movement origin is no longer valid."
	return ""


func commit(receipt: WorldActionReceipt, actor_runtime: Dictionary) -> bool:
	if store == null or not has_action(receipt) or actor_runtime.is_empty():
		return false
	if receipt.actor_id == "player":
		return store.update_player_runtime(
			actor_runtime,
			receipt.target_coords,
			false
		)
	return store.update_entity_runtime_at_coords(
		receipt.actor_id,
		actor_runtime,
		receipt.target_coords,
		false
	)


func _actor_coords(actor_id: String) -> Variant:
	if actor_id == "player":
		return store.player_record.coords if store.player_record != null else null
	var actor := store.get_entity_snapshot(actor_id)
	return actor.get("coords") if not actor.is_empty() else null


func _movement(receipt: WorldActionReceipt) -> Dictionary:
	for mutation in receipt.mutations:
		if str(mutation.get("type", "")) == MUTATION_TYPE:
			return mutation
	return {}
