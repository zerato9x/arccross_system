extends RefCounted
class_name WorldActionApplicationService

## Sole atomic commit boundary for neutral world-action receipts. Validation and
## detached staging are delegated, but snapshot/commit/time/signal/reservation/
## idempotence/rollback ownership deliberately remains here.

var store: RuntimeStateStore
var diagnostic_callback: Callable
var _inventory_transaction := WorldActionInventoryTransactionService.new()
var _poi_selection_transaction := WorldActionPoiSelectionTransactionService.new()
var _camp_transaction := WorldActionCampTransactionService.new()
var _movement_transaction := WorldActionMovementTransactionService.new()
var _search_transaction := WorldActionSearchTransactionService.new()
var _npc_work_transaction := WorldActionNpcWorkTransactionService.new()
var _negotiation_transaction := WorldActionNegotiationTransactionService.new()
var _receipt_validation := WorldActionReceiptValidationService.new()
var _actor_staging := WorldActionActorStagingService.new()


func configure(state: RuntimeStateStore, diagnostics: Callable = Callable()) -> void:
	store = state
	diagnostic_callback = diagnostics
	_inventory_transaction.configure(state)
	_poi_selection_transaction.configure(state)
	_camp_transaction.configure(state)
	_movement_transaction.configure(state)
	_search_transaction.configure(state)
	_npc_work_transaction.configure(state)
	_negotiation_transaction.configure(state)
	_receipt_validation.configure(
		state,
		_inventory_transaction,
		_poi_selection_transaction,
		_camp_transaction,
		_movement_transaction,
		_search_transaction,
		_npc_work_transaction,
		_negotiation_transaction
	)
	_actor_staging.configure(
		state,
		_inventory_transaction,
		_poi_selection_transaction,
		_camp_transaction,
		_movement_transaction,
		_search_transaction,
		_npc_work_transaction
	)


func apply(receipt: WorldActionReceipt) -> WorldActionApplicationReceipt:
	var result := WorldActionApplicationReceipt.new()
	_debug_mark("application start")
	if receipt != null:
		result.receipt_id = receipt.receipt_id
		result.action_id = receipt.action_id
		result.node_id = receipt.node_id
		result.coords = receipt.target_coords
	if receipt != null and store != null and store.has_applied_world_receipt(
		receipt.receipt_id
	):
		var repeated_error := _receipt_validation.payload_integrity_error(receipt)
		if repeated_error.is_empty():
			result.applied = true
			result.idempotent = true
		else:
			result.error = repeated_error
		return result
	var validation_error := _receipt_validation.validation_error(receipt)
	if not validation_error.is_empty():
		result.error = validation_error
		_debug_mark("application rejected during validation")
		return result

	var transaction := store.capture_reconciliation_snapshot()
	_debug_mark("transaction snapshot captured")
	var elapsed := maxi(0, receipt.elapsed_minutes)
	var previous_world_time := store.world_time_minutes
	var negotiation_staging := _negotiation_transaction.stage(receipt)
	if not bool(negotiation_staging.get("success", false)):
		_debug_mark("negotiation staging failed")
		return _rollback(
			result,
			transaction,
			str(negotiation_staging.get(
				"error", "Could not stage negotiation outcome."
			))
		)
	var actor_staging := _actor_staging.stage(receipt, elapsed)
	var actor_runtime: Dictionary = actor_staging.get("runtime", {})
	if actor_runtime.is_empty():
		_debug_mark("actor runtime staging failed")
		return _rollback(
			result,
			transaction,
			str(actor_staging.get("error", "Could not stage world-action actor runtime."))
		)
	_debug_mark("actor runtime staged")

	if not _commit_actor_and_item_runtime(receipt, actor_runtime, actor_staging):
		_debug_mark("actor and item runtime commit failed")
		return _rollback(result, transaction, "Could not commit actor/item runtime.")
	_debug_mark("actor and item runtime committed")
	if receipt.actor_id == "player":
		result.player_runtime = actor_runtime.duplicate(true)
	else:
		result.actor_runtime = actor_runtime.duplicate(true)
	if (
		bool(negotiation_staging.get("handled", false))
		and not store.commit_negotiation_outcome(negotiation_staging)
	):
		_debug_mark("negotiation target commit failed")
		return _rollback(result, transaction, "Could not commit negotiation outcome.")
	for mutation in receipt.mutations:
		if str(mutation.get("type", "")) != "add_ground_item":
			continue
		if not store.add_ground_items(
			receipt.target_coords,
			[mutation.get("item_state", {}).duplicate(true)]
		):
			return _rollback(result, transaction, "Could not add world-action ground item.")

	store.advance_world_time(elapsed, false)
	for signal_value in receipt.signals:
		var signal_record := WorldSignalRecord.from_dict(signal_value)
		store.register_world_signal(signal_record)
	store.prune_world_signals()
	_debug_mark("world-time and signals applied")

	var current_hex := store.get_hex_record(receipt.target_coords)
	var next_hex := HexRecord.from_dict(current_hex.to_dict())
	var staged_hex_state: Dictionary = actor_staging.get("hex_state", {})
	var target_state_handled := bool(actor_staging.get("target_state_handled", false))
	if not staged_hex_state.is_empty():
		next_hex = HexRecord.from_dict(staged_hex_state)
		if next_hex.revision != receipt.expected_hex_revision:
			return _rollback(result, transaction, "Staged POI hex has a stale revision.")
	for mutation in receipt.mutations:
		match str(mutation.get("type", "")):
			"movement_trace":
				var trace: Dictionary = mutation.get("trace", {}).duplicate(true)
				if trace.is_empty():
					return _rollback(result, transaction, "Movement trace payload is empty.")
				next_hex.trace_records.append(trace)
			"append_trace":
				var trace: Dictionary = mutation.get("trace", {}).duplicate(true)
				if trace.is_empty():
					return _rollback(result, transaction, "World trace payload is empty.")
				next_hex.trace_records.append(trace)
			"set_hex_explored":
				next_hex.is_explored = true
	if target_state_handled:
		var staged_target_index := _world_object_index(next_hex, receipt.target_id)
		if staged_target_index < 0:
			return _rollback(result, transaction, "Staged world-action target disappeared.")
		var staged_target := WorldObjectRecord.from_dict(
			next_hex.world_objects[staged_target_index]
		)
		result.target_revision = staged_target.revision
	elif not receipt.target_state.is_empty():
		var target_index := _world_object_index(next_hex, receipt.target_id)
		if target_index < 0:
			return _rollback(result, transaction, "World-action target disappeared during commit.")
		var target_state := receipt.target_state.duplicate(true)
		target_state["revision"] = receipt.expected_target_revision + 1
		target_state["last_simulated_minute"] = store.world_time_minutes
		next_hex.world_objects[target_index] = target_state
		result.target_revision = int(target_state["revision"])
	next_hex.world_signals.clear()
	for signal_record in store.get_active_world_signals():
		if signal_record.coords == receipt.target_coords:
			next_hex.world_signals.append(signal_record.to_dict())
	if not store.replace_hex_record(
		receipt.target_coords,
		next_hex,
		receipt.expected_hex_revision,
		true,
		false
	):
		_debug_mark("hex projection commit failed")
		return _rollback(result, transaction, "World-action hex revision drifted during commit.")
	_debug_mark("hex projection committed")
	result.hex_revision = store.get_hex_record(receipt.target_coords).revision
	for item_state in actor_staging.get("ground_additions", []):
		if not store.add_ground_items(
			receipt.target_coords,
			[item_state.duplicate(true)]
		):
			return _rollback(
				result,
				transaction,
				"Could not return displaced POI gear to the ground."
			)

	for mutation in receipt.mutations:
		if str(mutation.get("type", "")) == "set_run_flag":
			var key := str(mutation.get("key", ""))
			var flag_patch: Dictionary = {}
			flag_patch[key] = mutation.get("value")
			if key.is_empty() or not store.patch_run_flags(flag_patch):
				return _rollback(result, transaction, "Could not apply world-action run flag.")

	var reservation := store.get_world_action_reservation(receipt.action_id)
	if _is_incomplete_work_receipt(receipt):
		reservation.attempt_index += 1
		reservation.progress = clampf(receipt.work_progress, 0.0, 1.0)
		reservation.expected_actor_revision = _receipt_validation.actor_revision(
			receipt.actor_id
		)
		reservation.expected_target_revision = result.target_revision
		reservation.expected_hex_revision = result.hex_revision
		reservation.state["last_receipt"] = receipt.to_dict()
		reservation.state["progress"] = reservation.progress
		if not store.update_world_action_reservation(reservation):
			return _rollback(result, transaction, "Could not advance world-action reservation.")
	else:
		store.cancel_world_action(receipt.action_id)

	store.mark_world_receipt_applied(receipt.receipt_id)
	_debug_mark("receipt identity committed")
	var integrity_errors := store.validate_world_action_integrity(
		receipt.target_coords,
		receipt.actor_id,
		receipt.action_id,
		_receipt_touches_item_ownership(receipt)
	)
	if not integrity_errors.is_empty():
		_debug_mark("final integrity failed")
		return _rollback(result, transaction, "; ".join(integrity_errors))
	result.applied = true
	store.emit_world_time_commit(previous_world_time, elapsed)
	_debug_mark("application end")
	return result


func _commit_actor_and_item_runtime(
	receipt: WorldActionReceipt,
	actor_runtime: Dictionary,
	actor_staging: Dictionary
) -> bool:
	var created_items: Array = actor_staging.get("created_items", [])
	if not created_items.is_empty():
		if _inventory_transaction.has_action(receipt) or _movement_transaction.has_action(receipt):
			return false
		return store.commit_entity_runtime_with_created_items(
			receipt.actor_id,
			actor_runtime,
			actor_staging.get("knowledge", {}),
			created_items
		)
	if _inventory_transaction.has_action(receipt):
		return _inventory_transaction.commit(receipt, actor_runtime, actor_staging)
	if _movement_transaction.has_action(receipt):
		return _movement_transaction.commit(receipt, actor_runtime)
	var ground_transfer_id := ""
	var ground_drops: Array = []
	for mutation in receipt.mutations:
		match str(mutation.get("type", "")):
			"transfer_ground_item":
				ground_transfer_id = str(mutation.get("instance_id", ""))
			"drop_ground_item":
				ground_drops.append(mutation.get("item_state", {}).duplicate(true))
	if not ground_transfer_id.is_empty() and not ground_drops.is_empty():
		return false
	if not ground_transfer_id.is_empty():
		return store.transfer_ground_item_to_entity_with_runtime(
			receipt.target_coords,
			ground_transfer_id,
			receipt.actor_id,
			actor_runtime
		)
	if not ground_drops.is_empty():
		return store.commit_entity_runtime_with_ground_items(
			receipt.actor_id,
			actor_runtime,
			receipt.target_coords,
			ground_drops
		)
	if receipt.actor_id == "player":
		return store.update_player_runtime(actor_runtime, store.player_record.coords, false)
	return store.update_entity_runtime(receipt.actor_id, actor_runtime, false)


func _debug_mark(label: String) -> void:
	if diagnostic_callback.is_valid():
		diagnostic_callback.call("receipt // " + label)


func _world_object_index(hex: HexRecord, object_id: String) -> int:
	if hex == null:
		return -1
	for index in range(hex.world_objects.size()):
		var value: Variant = hex.world_objects[index]
		if value is Dictionary and str(value.get("object_id", "")) == object_id:
			return index
	return -1


func _is_incomplete_work_receipt(receipt: WorldActionReceipt) -> bool:
	if receipt == null or receipt.work_completed or receipt.interrupted:
		return false
	for mutation in receipt.mutations:
		if mutation is Dictionary and str(mutation.get("type", "")) == "work_progress":
			return true
	return false


func _receipt_touches_item_ownership(receipt: WorldActionReceipt) -> bool:
	if receipt == null:
		return false
	for mutation in receipt.mutations:
		if not mutation is Dictionary:
			continue
		if str(mutation.get("type", "")) in [
			"consume_material",
			"medical_application",
			"inventory_action",
			"poi_selection_application",
			"transfer_ground_item",
			"drop_ground_item",
			"add_ground_item",
			"npc_work_application",
			"negotiation_application",
		]:
			return true
	return false


func _rollback(
	result: WorldActionApplicationReceipt,
	transaction: Dictionary,
	error: String
) -> WorldActionApplicationReceipt:
	store.restore_reconciliation_snapshot(transaction)
	result.error = error
	return result
