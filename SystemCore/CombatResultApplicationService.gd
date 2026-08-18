extends RefCounted
class_name CombatResultApplicationService

var store: RuntimeStateStore


func configure(state: RuntimeStateStore) -> void:
	store = state


func apply(
	result: CombatResultRecord,
	handoff: CombatHandoffRecord
) -> CombatApplicationReceipt:
	var receipt := CombatApplicationReceipt.new()
	if result != null:
		receipt.encounter_id = result.encounter_id
		receipt.source_coords = result.source_coords
	if result != null and store != null and store.has_applied_combat_result(result.encounter_id):
		var repeated_payload_error := _payload_integrity_error(result)
		if not repeated_payload_error.is_empty():
			receipt.error = repeated_payload_error
			return receipt
		receipt.applied = true
		receipt.idempotent = true
		return receipt
	var validation_error := _validation_error(result, handoff)
	if not validation_error.is_empty():
		receipt.error = validation_error
		return receipt
	var transaction := store.capture_reconciliation_snapshot()
	# Consume the macro copies before staged actor runtimes are written. This
	# keeps the temporary authoritative state valid even when a combat result
	# hands one of those instances into an actor inventory.
	for instance_id in handoff.initial_ground_item_ids:
		if store.remove_ground_item(result.source_coords, instance_id).is_empty():
			return _rollback(
				receipt,
				transaction,
				"Combat handoff ground item could not be consumed: %s" % instance_id
			)
	var runtime_by_actor := _runtime_updates(result)
	var status_by_actor := _participant_statuses(result)
	var ground_by_id := _ground_items_by_id(result.ground_items)
	var player_runtime: Dictionary = runtime_by_actor.get("player", {}).duplicate(true)
	player_runtime = _apply_player_elapsed_survival(player_runtime, result.elapsed_minutes)
	if player_runtime.is_empty():
		return _rollback(receipt, transaction, "Could not hydrate the player result runtime.")

	if not store.update_player_runtime(
		player_runtime,
		store.player_record.coords,
		false
	):
		return _rollback(receipt, transaction, "Could not commit the player result runtime.")
	receipt.player_runtime = player_runtime.duplicate(true)

	for actor_id in handoff.actor_ids:
		if actor_id == "player":
			continue
		var record := store.get_entity(actor_id)
		var runtime: Dictionary = runtime_by_actor.get(actor_id, {}).duplicate(true)
		if record == null or runtime.is_empty():
			return _rollback(
				receipt,
				transaction,
				"Combat result actor is missing from RuntimeStateStore: %s" % actor_id
			)
		var old_coords := record.coords
		var status := str(status_by_actor.get(actor_id, _status_from_runtime(runtime)))
		var context: Dictionary = handoff.participant_contexts.get(actor_id, {}).duplicate(true)
		runtime["last_combat_outcome"] = result.outcome
		runtime["last_combat_reason"] = result.reason
		if status == "escaped":
			runtime["macro_escape_direction"] = int(context.get(
				"escape_direction",
				context.get("entry_direction", GameEnums.MacroTravelDirection.NONE)
			))
			runtime["return_policy"] = str(context.get("return_policy", "origin"))
			var escape_goal := str(context.get("macro_goal", "EXIT"))
			if escape_goal.is_empty():
				escape_goal = "EXIT"
			runtime["macro_goal"] = escape_goal
			runtime["macro_purpose"] = escape_goal
		var dead := status == "dead" or bool(runtime.get("is_dead", false))
		var withdrawn := status in ["escaped", "withdrawn", "surrendered", "incapacitated"]
		if dead:
			for item_state in _carried_item_states(runtime):
				var instance_id := str(item_state.get("instance_id", ""))
				if not instance_id.is_empty() and not ground_by_id.has(instance_id):
					ground_by_id[instance_id] = _ground_item_state(item_state)
			runtime = _without_carried_items(runtime)
		if not store.update_entity_runtime(actor_id, runtime, false):
			return _rollback(receipt, transaction, "Could not commit runtime for %s." % actor_id)
		if dead:
			if not store.set_entity_life_state(actor_id, GameEnums.EntityLifeState.DEAD):
				return _rollback(receipt, transaction, "Could not commit death for %s." % actor_id)
			receipt.hostile_roster_changed = true
		elif withdrawn:
			if not store.set_entity_world_status(
				actor_id, GameEnums.EntityWorldStatus.WITHDRAWN
			):
				return _rollback(receipt, transaction, "Could not withdraw %s." % actor_id)
			receipt.hostile_roster_changed = true
		receipt.participant_actions.append({
			"actor_id": actor_id,
			"status": status,
			"old_coords": old_coords,
			"participant_context": context,
		})

	if not result.relationship_state.is_empty():
		store.set_relationship_state(result.relationship_state)
	# Remaining ground instances are reinserted from the final tactical
	# snapshot; picked-up instances remain in their actor runtime and therefore
	# cannot fork across both scenes.
	if not _apply_combat_site_state(result, ground_by_id.values()):
		return _rollback(receipt, transaction, "Could not commit the combat-site state.")
	var ground_items: Array = ground_by_id.values()
	if not ground_items.is_empty() and not store.add_ground_items(result.source_coords, ground_items):
		return _rollback(receipt, transaction, "Combat ground-item transfer failed integrity validation.")
	receipt.ground_items.clear()
	for ground_item in ground_items:
		if ground_item is Dictionary:
			receipt.ground_items.append((ground_item as Dictionary).duplicate(true))
	receipt.should_retreat_player = result.outcome in [
		GameEnums.CombatOutcome.PLAYER_DEFEAT,
		GameEnums.CombatOutcome.PLAYER_ESCAPED,
		GameEnums.CombatOutcome.PLAYER_SURRENDERED,
	] and result.reason != "death"

	var integrity_errors := store.validate_integrity()
	if not integrity_errors.is_empty():
		return _rollback(receipt, transaction, "; ".join(integrity_errors))
	if not store.complete_combat_handoff(result.encounter_id):
		return _rollback(receipt, transaction, "Could not close the combat handoff.")
	store.advance_world_time(result.elapsed_minutes)
	store.mark_combat_result_applied(result.encounter_id)
	receipt.applied = true
	return receipt


func _validation_error(
	result: CombatResultRecord,
	handoff: CombatHandoffRecord
) -> String:
	if store == null:
		return "RuntimeStateStore is unavailable."
	if result == null or handoff == null:
		return "Combat result or active handoff is missing."
	if store.get_active_combat_handoff() != handoff:
		return "Combat result does not target RuntimeStateStore's active handoff."
	if handoff.status != CombatHandoffRecord.Status.ACTIVE:
		return "Combat handoff is not active."
	if result.encounter_id.is_empty() or result.encounter_id != handoff.encounter_id:
		return "Combat result encounter identity does not match the active handoff."
	if result.source_coords != handoff.source_coords:
		return "Combat result source coordinates do not match the active handoff."
	if result.elapsed_minutes < 0:
		return "Combat result elapsed time cannot be negative."
	var runtime_by_actor := _runtime_updates(result)
	if runtime_by_actor.size() != result.actor_runtime_updates.size():
		return "Combat result contains duplicate or empty actor runtime updates."
	var payload_error := _payload_integrity_error(result)
	if not payload_error.is_empty():
		return payload_error
	if runtime_by_actor.size() != handoff.actor_ids.size():
		return "Combat result actor set does not match the active handoff."
	var participant_error := _participant_result_error(result, handoff.actor_ids)
	if not participant_error.is_empty():
		return participant_error
	var location_error := _location_result_error(result, handoff.actor_ids)
	if not location_error.is_empty():
		return location_error
	var ground_ids: Dictionary = {}
	for value in result.ground_items:
		if not value is Dictionary:
			return "Combat result contains a malformed ground item."
		var instance_id := str(value.get("instance_id", ""))
		if instance_id.is_empty() or ground_ids.has(instance_id):
			return "Combat result contains a duplicate or empty ground-item identity."
		ground_ids[instance_id] = true
	for actor_id in handoff.actor_ids:
		if not runtime_by_actor.has(actor_id):
			return "Combat result is missing actor runtime: %s" % actor_id
		var expected_revision := int(handoff.participant_revisions.get(actor_id, -1))
		var current_revision := (
			store.player_record.revision
			if actor_id == "player" and store.player_record != null
			else int(store.get_entity(actor_id).revision) if store.get_entity(actor_id) != null else -1
		)
		if expected_revision < 0 or current_revision != expected_revision:
			return "Combat participant revision drifted during handoff: %s" % actor_id
	for actor_id in runtime_by_actor.keys():
		if actor_id not in handoff.actor_ids:
			return "Combat result contains an actor outside the handoff: %s" % actor_id
	return ""


func _payload_integrity_error(result: CombatResultRecord) -> String:
	if result == null:
		return "Combat result is missing."
	if (
		result.outcome < GameEnums.CombatOutcome.PLAYER_VICTORY
		or result.outcome > GameEnums.CombatOutcome.ENEMY_SURRENDERED
	):
		return "Combat result contains an invalid outcome."
	var seen_actor_ids: Dictionary = {}
	for update in result.actor_runtime_updates:
		if not update is Dictionary:
			return "Combat result contains a malformed actor runtime."
		var actor_id := str(update.get("actor_id", ""))
		if actor_id.is_empty() or seen_actor_ids.has(actor_id):
			return "Combat result contains a duplicate or empty actor runtime identity."
		var runtime_value: Variant = update.get("runtime", {})
		if not runtime_value is Dictionary:
			return "Combat result contains a malformed actor runtime."
		seen_actor_ids[actor_id] = true
	var runtime_by_actor := _runtime_updates(result)
	var seen_runtime_items: Dictionary = {}
	for actor_id in runtime_by_actor.keys():
		for instance_id in store.runtime_item_ids(runtime_by_actor[actor_id]):
			if instance_id.is_empty():
				return "Combat result contains an item without an instance_id."
			if seen_runtime_items.has(instance_id):
				return "Combat result duplicates item identity: %s." % instance_id
			seen_runtime_items[instance_id] = actor_id
	for ground_value in result.ground_items:
		if not ground_value is Dictionary:
			return "Combat result contains a malformed ground item."
		var ground_item: Dictionary = ground_value
		if str(ground_item.get("instance_id", "")).is_empty():
			return "Combat result contains a ground item without an instance_id."
		for instance_id in store.runtime_item_ids({"inventory_items": [ground_item]}):
			if instance_id.is_empty() or seen_runtime_items.has(instance_id):
				return "Combat result duplicates item identity: %s." % instance_id
			seen_runtime_items[instance_id] = "ground"
	var relationship_error := CombatRelationshipLedger.validation_error(
		result.relationship_state
	)
	if not result.relationship_state.is_empty() and not relationship_error.is_empty():
		return relationship_error
	return ""


func _participant_result_error(result: CombatResultRecord, actor_ids: Array[String]) -> String:
	var seen: Dictionary = {}
	for participant in result.participant_results:
		if not participant is Dictionary:
			return "Combat result contains a malformed participant result."
		var actor_id := str(participant.get("actor_id", ""))
		if actor_id.is_empty() or seen.has(actor_id):
			return "Combat result contains duplicate or empty participant results."
		if actor_id not in actor_ids:
			return "Combat participant result is outside the handoff: %s" % actor_id
		var status := str(participant.get("status", "active"))
		if status not in ["active", "dead", "escaped", "withdrawn", "surrendered", "incapacitated"]:
			return "Combat participant result has an invalid status: %s" % status
		seen[actor_id] = true
	if seen.size() != actor_ids.size():
		return "Combat result is missing a participant result."
	return ""


func _location_result_error(result: CombatResultRecord, actor_ids: Array[String]) -> String:
	var groups: Array = [
		result.body_locations,
		result.incapacitated_locations,
		result.surrendered_locations,
	]
	for locations in groups:
		var seen: Dictionary = {}
		for location in locations:
			if not location is Dictionary:
				return "Combat result contains a malformed actor location."
			var actor_id := str(location.get("actor_id", ""))
			if actor_id.is_empty() or actor_id not in actor_ids or seen.has(actor_id):
				return "Combat result contains an invalid or duplicate actor location."
			seen[actor_id] = true
	return ""


func _runtime_updates(result: CombatResultRecord) -> Dictionary:
	var updates: Dictionary = {}
	for update in result.actor_runtime_updates:
		if not update is Dictionary or not update.get("runtime", {}) is Dictionary:
			continue
		var actor_id := str(update.get("actor_id", ""))
		if actor_id.is_empty() or updates.has(actor_id):
			continue
		updates[actor_id] = update.get("runtime", {}).duplicate(true)
	return updates


func _participant_statuses(result: CombatResultRecord) -> Dictionary:
	var statuses: Dictionary = {}
	for participant in result.participant_results:
		var actor_id := str(participant.get("actor_id", ""))
		if not actor_id.is_empty():
			statuses[actor_id] = str(participant.get("status", "active"))
	return statuses


func _status_from_runtime(runtime: Dictionary) -> String:
	if bool(runtime.get("is_dead", false)):
		return "dead"
	if bool(runtime.get("is_comatose", false)):
		return "incapacitated"
	return "active"


func _apply_player_elapsed_survival(runtime: Dictionary, elapsed_minutes: int) -> Dictionary:
	if store.player_record == null:
		return {}
	var player_state := store.player_record.to_dict()
	player_state["runtime"] = runtime.duplicate(true)
	var core := EntityFactory.record_to_humanoid_core(player_state, null, "CombatResultPlayer")
	if core == null:
		return {}
	core.process_survival_time(elapsed_minutes, 15.0, 1.5)
	var final_runtime := core.capture_runtime_state().to_dict()
	core.free()
	return final_runtime


func _ground_items_by_id(items: Array) -> Dictionary:
	var by_id: Dictionary = {}
	for value in items:
		if not value is Dictionary:
			continue
		var item_state: Dictionary = value
		var instance_id := str(item_state.get("instance_id", ""))
		if not instance_id.is_empty():
			by_id[instance_id] = _ground_item_state(item_state)
	return by_id


func _carried_item_states(runtime: Dictionary) -> Array[Dictionary]:
	var carried: Array[Dictionary] = []
	var inventory: Dictionary = runtime.get("inventory", {})
	for value in inventory.get("equipment", {}).values():
		if value is Dictionary:
			carried.append((value as Dictionary).duplicate(true))
	for value in inventory.get("backpack", []):
		if value is Dictionary:
			carried.append((value as Dictionary).duplicate(true))
	for value in runtime.get("inventory_items", []):
		if value is Dictionary:
			carried.append((value as Dictionary).duplicate(true))
	return carried


func _without_carried_items(runtime: Dictionary) -> Dictionary:
	var cleared := runtime.duplicate(true)
	var inventory: Dictionary = cleared.get("inventory", {}).duplicate(true)
	if not inventory.is_empty():
		inventory["equipment"] = {}
		inventory["backpack"] = []
		cleared["inventory"] = inventory
	if cleared.has("inventory_items"):
		cleared["inventory_items"] = []
	return cleared


func _ground_item_state(item_state: Dictionary) -> Dictionary:
	var ground := item_state.duplicate(true)
	ground["owner_id"] = ""
	ground["physical_location"] = "ground"
	ground.erase("container_instance_id")
	ground["equipped_slot"] = GameEnums.EquipmentSlot.NONE
	return ground


func _apply_combat_site_state(result: CombatResultRecord, ground_items: Array) -> bool:
	var record := store.get_hex_record(result.source_coords)
	if record == null:
		return true
	var next_record := HexRecord.from_dict(record.to_dict())
	var state := result.environment_patch.duplicate(true)
	state["bodies"] = result.body_locations.duplicate(true)
	state["incapacitated"] = result.incapacitated_locations.duplicate(true)
	state["surrendered_actor_ids"] = result.surrendered_actor_ids.duplicate()
	state["surrendered"] = result.surrendered_locations.duplicate(true)
	state["ground_items"] = ground_items.duplicate(true)
	next_record.combat_site_state = state
	return store.replace_hex_record(result.source_coords, next_record, record.revision)


func _rollback(
	receipt: CombatApplicationReceipt,
	snapshot: Dictionary,
	message: String
) -> CombatApplicationReceipt:
	store.restore_reconciliation_snapshot(snapshot)
	receipt.applied = false
	receipt.error = message
	return receipt
