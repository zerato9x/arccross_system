extends RefCounted
class_name WorldActionNegotiationTransactionService

## Canonical negotiation staging. Receipts carry an outcome and one bounded
## memory event; they never carry a caller-owned EntityRecord replacement.

const MUTATION_TYPE := "negotiation_application"
const VERB_ID := "talk"
const AI_SCHEMA_VERSION := 1
const NO_CHANGE := -1

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
	var ground_insertions := 0
	for mutation_value in receipt.mutations:
		var mutation: Dictionary = mutation_value
		match str(mutation.get("type", "")):
			MUTATION_TYPE:
				actions.append(mutation)
			"add_ground_item":
				ground_insertions += 1
	if actions.size() != 1:
		return "World-action receipt contains duplicate negotiation applications."
	if receipt.actor_id != "player" or receipt.verb_id != VERB_ID:
		return "Negotiation application requires a player talk action."
	if receipt.target_id.is_empty() or receipt.target_id == receipt.actor_id:
		return "Negotiation application has an invalid target identity."
	if ground_insertions > 0:
		return "Negotiation application cannot mix independent ground insertions."
	var action := actions[0]
	var expected_revision := int(action.get("expected_enemy_revision", -1))
	var expected_attempt := int(action.get("expected_negotiation_attempt", -1))
	if expected_revision < 0 or expected_attempt < 0:
		return "Negotiation application has invalid concurrency expectations."
	if int(action.get("next_negotiation_attempt", -1)) != expected_attempt + 1:
		return "Negotiation application must advance its attempt exactly once."
	var outcome := int(action.get("outcome", -1))
	if outcome not in GameEnums.NegotiationOutcome.values():
		return "Negotiation application has an invalid outcome."
	var event_value: Variant = action.get("memory_event", {})
	if not event_value is Dictionary:
		return "Negotiation application has malformed memory data."
	var event: Dictionary = event_value
	if (
		str(event.get("id", "")).is_empty()
		or int(event.get("turn", -1)) < 0
		or not event.get("coords", null) is Vector2i
		or typeof(event.get("trust_delta", 0.0)) not in [TYPE_INT, TYPE_FLOAT]
		or typeof(event.get("threat_delta", 0.0)) not in [TYPE_INT, TYPE_FLOAT]
	):
		return "Negotiation application has malformed memory data."
	if str(action.get("npc_role_id", "")).is_empty():
		return "Negotiation application has no canonical NPC role identity."
	var event_id := str(event.get("id", ""))
	var trust_delta := float(event.get("trust_delta", 0.0))
	var threat_delta := float(event.get("threat_delta", 0.0))
	var expected_memory_by_outcome := {
		GameEnums.NegotiationOutcome.COMBAT: ["talk_broke_down", -2.0, 5.0],
		GameEnums.NegotiationOutcome.INTIMIDATED: ["player_intimidated", -3.0, 8.0],
		GameEnums.NegotiationOutcome.CEASEFIRE: ["ceasefire_reached", 3.0, 0.0],
	}
	var expected_memory: Array = expected_memory_by_outcome.get(outcome, [])
	if (
		expected_memory.is_empty()
		or event_id != str(expected_memory[0])
		or not is_equal_approx(trust_delta, float(expected_memory[1]))
		or not is_equal_approx(threat_delta, float(expected_memory[2]))
	):
		return "Negotiation application memory does not match its outcome."
	var next_status := int(action.get("next_world_status", NO_CHANGE))
	var next_relationship := int(action.get("next_relationship", NO_CHANGE))
	var kept_loadout_value: Variant = action.get("kept_loadout", {})
	var created_items_value: Variant = action.get("created_ground_items", [])
	if (
		not kept_loadout_value is Dictionary
		or not created_items_value is Array
		or not action.get("ground_coords", receipt.target_coords) is Vector2i
	):
		return "Negotiation application has malformed surrender data."
	if action.get("ground_coords", receipt.target_coords) != event.get("coords"):
		return "Negotiation surrender location does not match the player memory event."
	match outcome:
		GameEnums.NegotiationOutcome.COMBAT:
			if next_status != NO_CHANGE or next_relationship != NO_CHANGE:
				return "Combat negotiation cannot rewrite status or relationship."
			if not kept_loadout_value.is_empty() or not created_items_value.is_empty():
				return "Combat negotiation cannot create surrender state."
		GameEnums.NegotiationOutcome.INTIMIDATED:
			if (
				next_status != GameEnums.EntityWorldStatus.WITHDRAWN
				or next_relationship != CombatRelationshipLedger.Relation.NEUTRAL
			):
				return "Intimidated negotiation has the wrong terminal state."
		GameEnums.NegotiationOutcome.CEASEFIRE:
			if (
				next_status != GameEnums.EntityWorldStatus.CEASEFIRE
				or next_relationship != CombatRelationshipLedger.Relation.NEUTRAL
			):
				return "Ceasefire negotiation has the wrong terminal state."
			if not kept_loadout_value.is_empty() or not created_items_value.is_empty():
				return "Ceasefire negotiation cannot create surrender state."
	var created_ids: Dictionary = {}
	for item_value in created_items_value:
		if not item_value is Dictionary:
			return "Negotiation surrender contains malformed ground gear."
		var item_state: Dictionary = item_value
		var instance_id := str(item_state.get("instance_id", ""))
		if instance_id.is_empty() or created_ids.has(instance_id):
			return "Negotiation surrender contains duplicate or empty gear identity."
		created_ids[instance_id] = true
	return ""


func stage(receipt: WorldActionReceipt) -> Dictionary:
	if not has_action(receipt):
		return {"handled": false, "success": true}
	if store == null:
		return _failure("Negotiation transaction services are unavailable.")
	var action := _mutation(receipt)
	var snapshot := store.get_entity_snapshot(receipt.target_id)
	if snapshot.is_empty():
		return _failure("Canonical negotiation target is unavailable.")
	var record := EntityRecord.from_dict(snapshot)
	if (
		record.revision != int(action.get("expected_enemy_revision", -1))
		or record.negotiation_attempts
		!= int(action.get("expected_negotiation_attempt", -1))
	):
		return _failure("Negotiation target revision or attempt drifted.")
	if record.coords != receipt.target_coords:
		return _failure("Negotiation target moved away from the receipt location.")
	if (
		record.life_state != GameEnums.EntityLifeState.ALIVE
		or record.world_status != GameEnums.EntityWorldStatus.HOSTILE
	):
		return _failure("Negotiation target is no longer a living hostile actor.")
	var event: Dictionary = action.get("memory_event", {})
	if (
		store.player_record == null
		or event.get("coords", null) != store.player_record.coords
	):
		return _failure("Negotiation player location drifted before application.")
	var next_runtime := record.runtime.duplicate(true)
	var ai_value: Variant = next_runtime.get("macro_ai", {})
	var ai: Dictionary = ai_value.duplicate(true) if ai_value is Dictionary else {}
	ai["schema_version"] = AI_SCHEMA_VERSION
	var role_id := str(action.get("npc_role_id", ""))
	if role_id.is_empty():
		role_id = str(next_runtime.get("npc_role_id", record.definition.get(
			"npc_role_id", "salvager"
		)))
	ai["role_id"] = role_id
	var memory_value: Variant = ai.get("memory", {})
	var memory: Dictionary = (
		memory_value.duplicate(true) if memory_value is Dictionary else {}
	)
	memory["player_trust"] = clampf(
		float(memory.get("player_trust", 0.0)) + float(event.get("trust_delta", 0.0)),
		-12.0,
		12.0
	)
	memory["player_threat"] = clampf(
		float(memory.get("player_threat", 0.0)) + float(event.get("threat_delta", 0.0)),
		0.0,
		12.0
	)
	memory["last_player_coords"] = event.get("coords", receipt.target_coords)
	memory["last_player_turn"] = int(event.get("turn", -1))
	var events_value: Variant = memory.get("events", [])
	var events: Array = events_value.duplicate(true) if events_value is Array else []
	events.append({
		"id": str(event.get("id", "")),
		"turn": int(event.get("turn", -1)),
		"coords": event.get("coords", receipt.target_coords),
	})
	while events.size() > 8:
		events.pop_front()
	memory["events"] = events
	ai["memory"] = memory
	next_runtime["macro_ai"] = ai
	var next_definition := record.definition.duplicate(true)
	var kept_loadout: Dictionary = action.get("kept_loadout", {})
	if not kept_loadout.is_empty():
		next_definition["loadout"] = kept_loadout.duplicate(true)
	var created_items: Array = action.get("created_ground_items", []).duplicate(true)
	var seen_ids: Dictionary = {}
	for item_value in created_items:
		var item_state: Dictionary = item_value
		for instance_id in store.runtime_item_ids({"inventory_items": [item_state]}):
			if (
				instance_id.is_empty()
				or seen_ids.has(instance_id)
				or not store.find_item_ownership(instance_id).is_empty()
			):
				return _failure("Negotiation surrender gear identity already exists.")
			seen_ids[instance_id] = true
	return {
		"handled": true,
		"success": true,
		"error": "",
		"enemy_id": receipt.target_id,
		"expected_enemy_revision": record.revision,
		"expected_negotiation_attempt": record.negotiation_attempts,
		"next_negotiation_attempt": int(action.get("next_negotiation_attempt", -1)),
		"next_runtime": next_runtime,
		"next_definition": next_definition,
		"next_world_status": int(action.get("next_world_status", NO_CHANGE)),
		"next_relationship": int(action.get("next_relationship", NO_CHANGE)),
		"coords": action.get("ground_coords", receipt.target_coords),
		"created_ground_items": created_items,
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
	}
