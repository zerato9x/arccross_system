extends RefCounted
class_name WorldActionTradeTransactionService

## Canonical trade staging. The receipt identifies the selected instances and
## bounded social outcome; this service derives both actor runtimes from the
## canonical store and mutates only a detached player core.

const MUTATION_TYPE := "trade_application"
const VERB_ID := "talk"
const ELAPSED_MINUTES := 5
const EXERTION := 0.15
const AI_SCHEMA_VERSION := 1

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
		if not mutation_value is Dictionary:
			continue
		var mutation: Dictionary = mutation_value
		var mutation_type := str(mutation.get("type", ""))
		if mutation_type == MUTATION_TYPE:
			actions.append(mutation)
		elif mutation_type in [
			"consume_material",
			"transfer_ground_item",
			"drop_ground_item",
			"inventory_action",
			"poi_selection_application",
			"camp_cycle_application",
			"search_application",
			"npc_work_application",
			"negotiation_application",
			"macro_event_application",
			"add_ground_item",
		]:
			return "Trade application contains a conflicting semantic mutation."
	if actions.size() != 1:
		return "World-action receipt contains duplicate trade applications."
	if receipt.actor_id != "player" or receipt.verb_id != VERB_ID:
		return "Trade application requires a player talk action."
	if receipt.target_id.is_empty() or receipt.target_id == receipt.actor_id:
		return "Trade application has an invalid counterparty identity."
	if (
		receipt.elapsed_minutes != ELAPSED_MINUTES
		or not is_equal_approx(receipt.exertion, EXERTION)
	):
		return "Trade application has an invalid survival cost."
	var action := actions[0]
	var offered_id := str(action.get("offered_instance_id", ""))
	var received_value: Variant = action.get("received_item_state", {})
	if not received_value is Dictionary:
		return "Trade application has malformed received item state."
	var received: Dictionary = received_value
	var received_id := str(received.get("instance_id", ""))
	if offered_id.is_empty() or received_id.is_empty() or offered_id == received_id:
		return "Trade application has invalid item identities."
	if (
		str(received.get("owner_id", "")) != "player"
		or str(received.get("physical_location", "")) != "inventory"
	):
		return "Trade application received item has the wrong proposed owner."
	if str(action.get("received_source", "")) not in ["inventory", "authored_loadout"]:
		return "Trade application has an unsupported received-item source."
	if int(action.get("expected_enemy_revision", -1)) < 0:
		return "Trade application has no counterparty revision expectation."
	var memory_value: Variant = action.get("memory_event", {})
	if not memory_value is Dictionary:
		return "Trade application has malformed memory data."
	var memory: Dictionary = memory_value
	var trust_delta := float(memory.get("trust_delta", 0.0))
	if (
		int(memory.get("turn", -1)) < 0
		or not memory.get("coords", null) is Vector2i
		or memory.get("coords") != receipt.target_coords
		or not (
			is_equal_approx(trust_delta, 0.25)
			or is_equal_approx(trust_delta, 1.0)
		)
	):
		return "Trade application memory does not match a legal barter outcome."
	return ""


func stage(core: HumanoidCore, receipt: WorldActionReceipt) -> Dictionary:
	if not has_action(receipt):
		return {"handled": false, "success": true}
	if store == null or core == null or store.player_record == null:
		return _failure("Trade transaction services are unavailable.")
	var action := _mutation(receipt)
	var enemy_snapshot := store.get_entity_snapshot(receipt.target_id)
	if enemy_snapshot.is_empty():
		return _failure("Canonical trade counterparty is unavailable.")
	var enemy := EntityRecord.from_dict(enemy_snapshot)
	if (
		enemy.revision != int(action.get("expected_enemy_revision", -1))
		or enemy.life_state != GameEnums.EntityLifeState.ALIVE
		or enemy.world_status != GameEnums.EntityWorldStatus.CEASEFIRE
	):
		return _failure("Trade counterparty revision or disposition drifted.")
	if (
		enemy.coords != receipt.target_coords
		or store.player_record.coords != receipt.target_coords
	):
		return _failure("Trade participants are no longer at the receipt location.")
	if not bool(enemy.definition.get("allows_trade", true)):
		return _failure("Trade counterparty no longer permits barter.")

	var offered_id := str(action.get("offered_instance_id", ""))
	var offer_location := store.find_item_ownership(offered_id)
	if (
		str(offer_location.get("location", "")) != "inventory"
		or str(offer_location.get("owner_id", "")) != "player"
	):
		return _failure("Trade offer no longer has one canonical player owner.")
	var offered := core.inventory.find_item_by_instance_id(offered_id)
	if offered == null or not core.inventory.backpack_array.has(offered):
		return _failure("Trade offer is no longer in the player's backpack.")
	var offered_state := offered.to_runtime_state()
	offered_state["owner_id"] = enemy.entity_id
	offered_state["physical_location"] = "inventory"

	var received: Dictionary = action.get("received_item_state", {}).duplicate(true)
	var received_id := str(received.get("instance_id", ""))
	var received_source := str(action.get("received_source", ""))
	var enemy_inventory: Array = enemy.runtime.get("inventory_items", []).duplicate(true)
	var next_loadout: Dictionary = enemy.definition.get("loadout", {}).duplicate(true)
	if received_source == "inventory":
		var received_index := _item_index(enemy_inventory, received_id)
		if received_index < 0 or _item_index(enemy_inventory, received_id, received_index + 1) >= 0:
			return _failure("Trade receipt item is no longer uniquely carried by the counterparty.")
		var canonical_received: Dictionary = enemy_inventory[received_index].duplicate(true)
		canonical_received["owner_id"] = "player"
		canonical_received["physical_location"] = "inventory"
		if canonical_received != received:
			return _failure("Trade receipt rewrites the canonical received item.")
		enemy_inventory.remove_at(received_index)
	elif received_source == "authored_loadout":
		if not enemy_inventory.is_empty():
			return _failure("Authored trade fallback cannot bypass runtime inventory.")
		if not store.find_item_ownership(received_id).is_empty():
			return _failure("Authored trade item identity already has an owner.")
		var template_path := str(received.get("template_path", ""))
		if not _authored_received_matches(received, template_path):
			return _failure("Authored trade item does not match its canonical template.")
		if not _remove_starting_template(next_loadout, template_path):
			return _failure("Authored trade template is no longer in the counterparty loadout.")
		if not offered.template_path.is_empty():
			var starting_items: Array = next_loadout.get("starting_items", []).duplicate()
			starting_items.append(offered.template_path)
			next_loadout["starting_items"] = starting_items
	else:
		return _failure("Trade receipt has an unsupported item source.")
	enemy_inventory.append(offered_state)

	var removed := core.inventory.remove_item_by_instance_id(offered_id)
	var received_item := ItemData.from_runtime_state(received)
	if removed == null or received_item == null:
		return _failure("Trade items could not be staged in detached player state.")
	if not core.inventory.add_to_backpack(received_item):
		return _failure("Player backpack cannot receive the traded item.")

	var next_runtime := enemy.runtime.duplicate(true)
	next_runtime["inventory_items"] = enemy_inventory
	_apply_memory_event(next_runtime, enemy, action.get("memory_event", {}))
	var next_definition := enemy.definition.duplicate(true)
	next_definition["loadout"] = next_loadout
	return {
		"handled": true,
		"success": true,
		"error": "",
		"enemy_id": enemy.entity_id,
		"expected_enemy_revision": enemy.revision,
		"enemy_runtime": next_runtime,
		"enemy_definition": next_definition,
		"offered_instance_id": offered_id,
		"received_instance_id": received_id,
		"received_source": received_source,
		"trust_delta": float(action.get("memory_event", {}).get("trust_delta", 0.0)),
	}


func _apply_memory_event(
	runtime: Dictionary,
	enemy: EntityRecord,
	event_value: Variant
) -> void:
	var event: Dictionary = event_value if event_value is Dictionary else {}
	var ai_value: Variant = runtime.get("macro_ai", {})
	var ai: Dictionary = ai_value.duplicate(true) if ai_value is Dictionary else {}
	ai["schema_version"] = AI_SCHEMA_VERSION
	ai["role_id"] = str(runtime.get(
		"npc_role_id", enemy.definition.get("npc_role_id", "salvager")
	))
	var memory_value: Variant = ai.get("memory", {})
	var memory: Dictionary = (
		memory_value.duplicate(true) if memory_value is Dictionary else {}
	)
	memory["player_trust"] = clampf(
		float(memory.get("player_trust", 0.0))
		+ float(event.get("trust_delta", 0.0)),
		-12.0,
		12.0
	)
	memory["player_threat"] = clampf(
		float(memory.get("player_threat", 0.0)), 0.0, 12.0
	)
	memory["last_player_coords"] = event.get("coords", enemy.coords)
	memory["last_player_turn"] = int(event.get("turn", -1))
	var events_value: Variant = memory.get("events", [])
	var events: Array = events_value.duplicate(true) if events_value is Array else []
	events.append({
		"id": "trade_completed",
		"turn": int(event.get("turn", -1)),
		"coords": event.get("coords", enemy.coords),
	})
	while events.size() > 8:
		events.pop_front()
	memory["events"] = events
	ai["memory"] = memory
	runtime["macro_ai"] = ai


func _authored_received_matches(state: Dictionary, template_path: String) -> bool:
	if template_path.is_empty():
		return false
	var template := load(template_path) as ItemData
	var received := ItemData.from_runtime_state(state)
	return (
		template != null
		and received != null
		and received.id == template.id
		and received.template_path == template_path
	)


func _remove_starting_template(loadout: Dictionary, template_path: String) -> bool:
	var starting_items: Array = loadout.get("starting_items", []).duplicate()
	for index in range(starting_items.size()):
		if str(starting_items[index]) != template_path:
			continue
		starting_items.remove_at(index)
		loadout["starting_items"] = starting_items
		return true
	return false


func _item_index(items: Array, instance_id: String, from_index: int = 0) -> int:
	for index in range(from_index, items.size()):
		var value: Variant = items[index]
		if value is Dictionary and str(value.get("instance_id", "")) == instance_id:
			return index
	return -1


func _mutation(receipt: WorldActionReceipt) -> Dictionary:
	for mutation in receipt.mutations:
		if mutation is Dictionary and str(mutation.get("type", "")) == MUTATION_TYPE:
			return mutation
	return {}


func _failure(message: String) -> Dictionary:
	return {
		"handled": true,
		"success": false,
		"error": message,
	}
