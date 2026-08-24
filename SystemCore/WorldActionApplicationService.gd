extends RefCounted
class_name WorldActionApplicationService

## Atomic application boundary for neutral world-action receipts. Rules decide
## the receipt; this service validates and commits canonical runtime state once.

const ALLOWED_MUTATION_TYPES := [
	"work_progress",
	"elapsed_time",
	"authored_effect",
	"target_damaged",
	"target_became_debris",
	"forced_entry",
	"dismantled",
	"consume_material",
	"transfer_ground_item",
	"drop_ground_item",
	"replace_actor_runtime",
	"move_actor",
	"movement_trace",
	"set_hex_explored",
	"trap_armed",
	"medical_application",
	"inventory_action",
	"poi_selection_application",
	"camp_cycle_application",
	"search_application",
	"npc_work_application",
	"add_ground_item",
	"biological_hit",
	"append_trace",
	"door_open",
	"set_run_flag",
]

var store: RuntimeStateStore
var diagnostic_callback: Callable
var _inventory_transaction := WorldActionInventoryTransactionService.new()
var _poi_selection_transaction := WorldActionPoiSelectionTransactionService.new()
var _camp_transaction := WorldActionCampTransactionService.new()
var _movement_transaction := WorldActionMovementTransactionService.new()
var _search_transaction := WorldActionSearchTransactionService.new()
var _npc_work_transaction := WorldActionNpcWorkTransactionService.new()


func configure(
	state: RuntimeStateStore,
	diagnostics: Callable = Callable()
) -> void:
	store = state
	diagnostic_callback = diagnostics
	_inventory_transaction.configure(state)
	_poi_selection_transaction.configure(state)
	_camp_transaction.configure(state)
	_movement_transaction.configure(state)
	_search_transaction.configure(state)


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
		var repeated_error := _payload_integrity_error(receipt)
		if repeated_error.is_empty():
			result.applied = true
			result.idempotent = true
		else:
			result.error = repeated_error
		return result
	var validation_error := _validation_error(receipt)
	if not validation_error.is_empty():
		result.error = validation_error
		_debug_mark("application rejected during validation")
		return result

	var transaction := store.capture_reconciliation_snapshot()
	_debug_mark("transaction snapshot captured")
	var elapsed := maxi(0, receipt.elapsed_minutes)
	var previous_world_time := store.world_time_minutes
	var actor_staging := _stage_actor_runtime(receipt, elapsed)
	var actor_runtime: Dictionary = actor_staging.get("runtime", {})
	if actor_runtime.is_empty():
		_debug_mark("actor runtime staging failed")
		return _rollback(
			result,
			transaction,
			str(actor_staging.get(
				"error",
				"Could not stage world-action actor runtime."
			))
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
	if not receipt.target_state.is_empty():
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
		reservation.expected_actor_revision = _actor_revision(receipt.actor_id)
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


func _debug_mark(label: String) -> void:
	if diagnostic_callback.is_valid():
		diagnostic_callback.call("receipt // " + label)


func _validation_error(receipt: WorldActionReceipt) -> String:
	if store == null:
		return "RuntimeStateStore is unavailable."
	if receipt == null or not receipt.committed:
		return "World-action receipt is missing or uncommitted."
	var payload_error := _payload_integrity_error(receipt)
	if not payload_error.is_empty():
		return payload_error
	if receipt.node_id != store.active_node_id:
		return "World-action receipt targets a different active node."
	var reservation := store.get_world_action_reservation(receipt.action_id)
	if reservation == null:
		return "World-action reservation is missing."
	if (
		reservation.actor_id != receipt.actor_id
		or reservation.target_id != receipt.target_id
		or reservation.node_id != receipt.node_id
		or reservation.target_coords != receipt.target_coords
	):
		return "World-action receipt does not match its reservation."
	if reservation.next_receipt_id() != receipt.receipt_id:
		return "World-action receipt attempt identity does not match its reservation."
	if receipt.expected_actor_revision != _actor_revision(receipt.actor_id):
		return "World-action actor revision drifted before application."
	var hex := store.get_hex_record(receipt.target_coords)
	if hex == null or receipt.expected_hex_revision != hex.revision:
		return "World-action hex revision drifted before application."
	if not receipt.target_state.is_empty():
		var target := _world_object(hex, receipt.target_id)
		if target == null or target.revision != receipt.expected_target_revision:
			return "World-action target revision drifted before application."
	return ""


func _payload_integrity_error(receipt: WorldActionReceipt) -> String:
	if receipt == null:
		return "World-action receipt is missing."
	if (
		receipt.receipt_id.is_empty()
		or receipt.action_id.is_empty()
		or receipt.actor_id.is_empty()
		or receipt.target_id.is_empty()
	):
		return "World-action receipt contains an empty identity."
	if receipt.elapsed_minutes < 0 or receipt.expected_actor_revision < 0:
		return "World-action receipt contains invalid timing or actor revision."
	if receipt.expected_hex_revision < 0:
		return "World-action receipt contains no expected hex revision."
	var consumed_ids: Dictionary = {}
	var transferred_ids: Dictionary = {}
	var medical_application_count := 0
	var has_replace_actor_runtime := false
	for mutation_value in receipt.mutations:
		if not mutation_value is Dictionary:
			return "World-action receipt contains a malformed mutation."
		var mutation: Dictionary = mutation_value
		var mutation_type := str(mutation.get("type", ""))
		if mutation_type not in ALLOWED_MUTATION_TYPES:
			return "World-action receipt contains an unsupported mutation: %s" % mutation_type
		if mutation_type == "consume_material":
			var instance_id := str(mutation.get("instance_id", ""))
			if instance_id.is_empty() or consumed_ids.has(instance_id):
				return "World-action receipt contains a duplicate or empty consumed item."
			consumed_ids[instance_id] = true
		elif mutation_type == "replace_actor_runtime":
			has_replace_actor_runtime = true
		elif mutation_type == "medical_application":
			medical_application_count += 1
			var instance_id := str(mutation.get("instance_id", ""))
			var limb_region := int(mutation.get("limb_region", -1))
			if (
				instance_id.is_empty()
				or receipt.target_id != instance_id
				or limb_region not in GameEnums.LimbRegion.values()
			):
				return "World-action medical mutation is malformed."
		elif mutation_type in ["transfer_ground_item", "drop_ground_item"]:
			var instance_id := str(mutation.get("instance_id", ""))
			if instance_id.is_empty() or transferred_ids.has(instance_id):
				return "World-action receipt contains a duplicate or empty transferred item."
			if mutation_type == "drop_ground_item":
				var item_state: Variant = mutation.get("item_state", {})
				if not item_state is Dictionary or str(item_state.get("instance_id", "")) != instance_id:
					return "World-action drop mutation has malformed item state."
			transferred_ids[instance_id] = true
		elif mutation_type == "move_actor":
			if mutation.get("to", receipt.target_coords) != receipt.target_coords:
				return "World-action movement destination does not match the receipt."
		elif mutation_type == "movement_trace":
			var trace: Variant = mutation.get("trace", {})
			if not trace is Dictionary or trace.is_empty():
				return "World-action movement trace is malformed."
		elif mutation_type == "append_trace":
			var trace: Variant = mutation.get("trace", {})
			if not trace is Dictionary or trace.is_empty():
				return "World-action trace is malformed."
		elif mutation_type == "add_ground_item":
			var item_state: Variant = mutation.get("item_state", {})
			var instance_id := str(item_state.get("instance_id", "")) if item_state is Dictionary else ""
			if instance_id.is_empty() or transferred_ids.has(instance_id):
				return "World-action ground insertion has a duplicate or empty item identity."
			transferred_ids[instance_id] = true
		elif mutation_type == "biological_hit":
			if float(mutation.get("damage", 0.0)) < 0.0:
				return "World-action biological hit has invalid damage."
	if medical_application_count > 0:
		if medical_application_count != 1:
			return "World-action receipt contains duplicate medical applications."
		if receipt.actor_id != "player":
			return "World-action medical treatment only supports the player actor."
		if receipt.verb_id != "treat" or receipt.method_id != "medical_item":
			return "World-action medical treatment has the wrong verb or method."
		if (
			not receipt.actor_state.is_empty()
			or has_replace_actor_runtime
			or not consumed_ids.is_empty()
		):
			return "World-action medical treatment contains conflicting actor mutations."
	var inventory_error := _inventory_transaction.validation_error(receipt)
	if not inventory_error.is_empty():
		return inventory_error
	var poi_selection_error := _poi_selection_transaction.validation_error(receipt)
	if not poi_selection_error.is_empty():
		return poi_selection_error
	var camp_error := _camp_transaction.validation_error(receipt)
	if not camp_error.is_empty():
		return camp_error
	var movement_error := _movement_transaction.validation_error(receipt)
	if not movement_error.is_empty():
		return movement_error
	var search_error := _search_transaction.validation_error(receipt)
	if not search_error.is_empty():
		return search_error
	var npc_work_error := _npc_work_transaction.validation_error(receipt)
	if not npc_work_error.is_empty():
		return npc_work_error
	var signal_ids: Dictionary = {}
	for signal_value in receipt.signals:
		if not signal_value is Dictionary:
			return "World-action receipt contains a malformed signal."
		var signal_id := str(signal_value.get("signal_id", ""))
		if signal_id.is_empty() or signal_ids.has(signal_id):
			return "World-action receipt contains a duplicate or empty signal identity."
		signal_ids[signal_id] = true
	if not receipt.target_state.is_empty():
		if str(receipt.target_state.get("object_id", "")) != receipt.target_id:
			return "World-action receipt target state has the wrong identity."
		if int(receipt.target_state.get("revision", -1)) != receipt.expected_target_revision:
			return "World-action receipt target state has the wrong source revision."
	return ""


func _stage_actor_runtime(
	receipt: WorldActionReceipt,
	elapsed_minutes: int
) -> Dictionary:
	var actor_data: Dictionary = (
		store.player_record.to_dict()
		if receipt.actor_id == "player" and store.player_record != null
		else store.get_entity_snapshot(receipt.actor_id)
	)
	if actor_data.is_empty():
		return {"runtime": {}, "error": "World-action actor is unavailable."}
	var movement_error := _movement_transaction.staging_error(receipt)
	if not movement_error.is_empty():
		return {"runtime": {}, "error": movement_error}
	if not receipt.actor_state.is_empty():
		actor_data["runtime"] = receipt.actor_state.duplicate(true)
	if receipt.actor_id == "player":
		var core := EntityFactory.record_to_humanoid_core(
			actor_data, null, "WorldActionApplicationActor"
		)
		if core == null:
			return {"runtime": {}, "error": "Could not construct the world-action actor."}
		for mutation in receipt.mutations:
			if str(mutation.get("type", "")) == "biological_hit":
				core.body.apply_targeted_hit(
					int(mutation.get("limb_region", GameEnums.LimbRegion.LEFT_ARM)),
					float(mutation.get("damage", 0.0)),
					float(mutation.get("armor", 0.0))
				)
		for mutation in receipt.mutations:
			if str(mutation.get("type", "")) != "medical_application":
				continue
			var item := core.inventory.find_item_by_instance_id(
				str(mutation.get("instance_id", ""))
			)
			if (
				item == null
				or not core.apply_consumable_to_limb(
					item,
					int(mutation.get("limb_region", -1))
				)
			):
				core.free()
				return {
					"runtime": {},
					"error": "Medical treatment is no longer valid.",
				}
		var inventory_result := _inventory_transaction.stage(core, receipt)
		if not bool(inventory_result.get("success", false)):
			core.free()
			return {
				"runtime": {},
				"error": str(inventory_result.get(
					"error",
					"Inventory action is no longer valid."
				)),
			}
		var poi_selection_result := _poi_selection_transaction.stage(core, receipt)
		if not bool(poi_selection_result.get("success", false)):
			core.free()
			return {
				"runtime": {},
				"error": str(poi_selection_result.get(
					"error",
					"POI gear selection is no longer valid."
				)),
			}
		var camp_result := _camp_transaction.stage(core, receipt)
		if not bool(camp_result.get("success", false)):
			core.free()
			return {
				"runtime": {},
				"error": str(camp_result.get(
					"error",
					"Camp recovery is no longer valid."
				)),
			}
		var search_result := _search_transaction.stage(receipt)
		if not bool(search_result.get("success", false)):
			core.free()
			return {
				"runtime": {},
				"error": str(search_result.get(
					"error",
					"Search outcome is no longer valid."
				)),
			}
		var staged_hex_state: Dictionary = {}
		for semantic_result in [
			poi_selection_result,
			camp_result,
			search_result,
		]:
			var candidate: Dictionary = semantic_result.get(
				"hex_state", {}
			).duplicate(true)
			if candidate.is_empty():
				continue
			if not staged_hex_state.is_empty():
				core.free()
				return {
					"runtime": {},
					"error": "World action staged conflicting semantic hex mutations.",
				}
			staged_hex_state = candidate
		core.process_survival_time(
			elapsed_minutes,
			15.0,
			maxf(0.1, receipt.exertion),
			float(receipt.presentation.get("insulation_bonus", 0.0))
		)
		# Detached staging has no scene-tree signal wiring. Reconcile terminal
		# biology explicitly before capturing the canonical runtime.
		core.reconcile_terminal_state()
		for mutation in receipt.mutations:
			if str(mutation.get("type", "")) != "consume_material":
				continue
			var item := core.inventory.find_item_by_instance_id(
				str(mutation.get("instance_id", ""))
			)
			if item == null or not core.inventory.consume_item_units(item):
				core.free()
				return {
					"runtime": {},
					"error": "World-action material is no longer available.",
				}
		if receipt.tool_wear > 0.0 and not receipt.method_id.is_empty():
			core.inventory.condition_service.apply_tool_wear(
				core.inventory,
				receipt.method_id,
				receipt.tool_wear
			)
		var runtime := core.capture_runtime_state().to_dict()
		core.free()
		return {
			"runtime": runtime,
			"error": "",
			"ground_remove_ids": inventory_result.get(
				"ground_remove_ids", []
			).duplicate(true),
			"ground_additions": inventory_result.get(
				"ground_additions", []
			).duplicate(true) + poi_selection_result.get(
				"ground_additions", []
			).duplicate(true),
			"hex_state": staged_hex_state,
		}
	var runtime: Dictionary = (
		receipt.actor_state.duplicate(true)
		if not receipt.actor_state.is_empty()
		else actor_data.get("runtime", {}).duplicate(true)
	)
	var npc_work_result := _npc_work_transaction.stage(runtime, receipt)
	if not bool(npc_work_result.get("success", false)):
		return {
			"runtime": {},
			"error": str(npc_work_result.get(
				"error",
				"NPC work progress is no longer valid."
			)),
		}
	runtime = npc_work_result.get("runtime", {}).duplicate(true)
	for mutation in receipt.mutations:
		if str(mutation.get("type", "")) == "consume_material":
			if not _consume_neutral_item(runtime, str(mutation.get("instance_id", ""))):
				return {
					"runtime": {},
					"error": "World-action material is no longer available.",
				}
	_apply_neutral_tool_wear(runtime, receipt.method_id, receipt.tool_wear)
	return {"runtime": runtime, "error": ""}


func _commit_actor_and_item_runtime(
	receipt: WorldActionReceipt,
	actor_runtime: Dictionary,
	actor_staging: Dictionary
) -> bool:
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
		return store.update_player_runtime(
			actor_runtime,
			store.player_record.coords,
			false
		)
	return store.update_entity_runtime(receipt.actor_id, actor_runtime, false)


func _consume_neutral_item(runtime: Dictionary, instance_id: String) -> bool:
	for list_path in ["inventory_items", "backpack"]:
		var items: Array = (
			runtime.get(list_path, []).duplicate(true)
			if list_path == "inventory_items"
			else runtime.get("inventory", {}).get("backpack", []).duplicate(true)
		)
		for index in range(items.size()):
			var state: Variant = items[index]
			if not state is Dictionary or str(state.get("instance_id", "")) != instance_id:
				continue
			var count := int(state.get("stack_count", 1))
			if count > 1:
				state = state.duplicate(true)
				state["stack_count"] = count - 1
				items[index] = state
			else:
				items.remove_at(index)
			if list_path == "inventory_items":
				runtime["inventory_items"] = items
			else:
				var inventory: Dictionary = runtime.get("inventory", {}).duplicate(true)
				inventory["backpack"] = items
				runtime["inventory"] = inventory
			return true
	var inventory: Dictionary = runtime.get("inventory", {}).duplicate(true)
	var equipment: Dictionary = inventory.get("equipment", {}).duplicate(true)
	for slot in equipment.keys():
		var state: Variant = equipment[slot]
		if state is Dictionary and str(state.get("instance_id", "")) == instance_id:
			equipment.erase(slot)
			inventory["equipment"] = equipment
			runtime["inventory"] = inventory
			return true
	return false


func _apply_neutral_tool_wear(runtime: Dictionary, method_id: String, wear: float) -> void:
	if wear <= 0.0 or method_id.is_empty():
		return
	var items: Array = runtime.get("inventory_items", []).duplicate(true)
	for index in range(items.size()):
		var state: Variant = items[index]
		if not state is Dictionary:
			continue
		var definition: Dictionary = state.get("definition", {})
		var item_id := str(definition.get("id", state.get("item_id", "")))
		if (
			(method_id == "crowbar" and item_id not in ["crowbar", "bent_pry_bar"])
			or (method_id == "multitool" and item_id not in ["multitool", "lockpick"])
		):
			continue
		state = state.duplicate(true)
		state["current_condition"] = maxf(
			0.0,
			float(state.get("current_condition", GameEnums.SCALE_MAX)) - wear
		)
		items[index] = state
		runtime["inventory_items"] = items
		return


func _actor_revision(actor_id: String) -> int:
	if actor_id == "player":
		return store.player_record.revision if store.player_record != null else -1
	return int(store.get_entity_snapshot(actor_id).get("revision", -1))


func _world_object(hex: HexRecord, object_id: String) -> WorldObjectRecord:
	if hex == null:
		return null
	for value in hex.world_objects:
		if value is Dictionary and str(value.get("object_id", "")) == object_id:
			return WorldObjectRecord.from_dict(value)
	return null


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
