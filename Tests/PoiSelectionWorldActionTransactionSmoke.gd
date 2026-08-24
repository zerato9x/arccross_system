extends SceneTree

const COORDS := Vector2i.ZERO
const BLANKET_ID := "poi_transaction_blanket"
const TRAP_ID := "poi_transaction_trap"
const ACTION_MINUTES := 15


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if not _test_sleep_trap_replay_and_persistence():
		return
	if not _test_stale_and_disappeared_item_rollback():
		return
	if not _test_malformed_receipts():
		return
	print("POI_SELECTION_WORLD_ACTION_TRANSACTION_SMOKE: PASS")
	quit(0)


func _test_sleep_trap_replay_and_persistence() -> bool:
	var store := _build_store()
	if store == null:
		return false
	var service := WorldActionApplicationService.new()
	service.configure(store)
	var actor_revision := store.player_record.revision
	var hex_revision := store.get_hex_record(COORDS).revision
	var time_before := store.world_time_minutes
	var sleep_receipt := _selection_receipt(
		store,
		WorldActionPoiSelectionTransactionService.MODE_SLEEP_SETUP,
		[BLANKET_ID],
		0,
		"poi-sleep"
	)
	var sleep_application := service.apply(sleep_receipt)
	if not sleep_application.applied or sleep_application.idempotent:
		return _fail("Valid canonical sleep-gear deployment was rejected: " + sleep_application.error)
	if store.player_record.revision != actor_revision + 1:
		return _fail("Sleep-gear deployment did not advance actor revision exactly once.")
	if store.get_hex_record(COORDS).revision != hex_revision + 1:
		return _fail("Sleep-gear deployment did not advance hex revision exactly once.")
	if store.world_time_minutes != time_before:
		return _fail("Zero-time camp configuration advanced world time.")
	if _inventory_has(store, BLANKET_ID):
		return _fail("Deployed sleep gear remained in canonical inventory.")
	var sleep_hex := store.get_hex_record(COORDS)
	if sleep_hex.sleep_gear_instance_id != BLANKET_ID or not _state_list_has(
		sleep_hex.camp_item_states, BLANKET_ID
	):
		return _fail("Canonical hex did not retain the deployed sleep gear.")
	var blanket_owner := store.find_item_ownership(BLANKET_ID)
	if blanket_owner.get("location", "") != "deployed_camp":
		return _fail("Deployed sleep gear has no singular camp ownership.")

	var after_sleep := store.capture_reconciliation_snapshot()
	var sleep_replay := service.apply(sleep_receipt)
	if not sleep_replay.applied or not sleep_replay.idempotent:
		return _fail("Sleep-gear receipt replay was not idempotent.")
	if store.capture_reconciliation_snapshot() != after_sleep:
		return _fail("Sleep-gear receipt replay repeated deployment effects.")

	actor_revision = store.player_record.revision
	hex_revision = store.get_hex_record(COORDS).revision
	var trap_receipt := _selection_receipt(
		store,
		WorldActionPoiSelectionTransactionService.MODE_TRAP_INSTALL,
		[TRAP_ID],
		ACTION_MINUTES,
		"poi-trap"
	)
	var trap_application := service.apply(trap_receipt)
	if not trap_application.applied:
		return _fail("Valid canonical trap installation was rejected: " + trap_application.error)
	if store.player_record.revision != actor_revision + 1:
		return _fail("Trap installation did not advance actor revision exactly once.")
	if store.get_hex_record(COORDS).revision != hex_revision + 1:
		return _fail("Trap installation did not advance hex revision exactly once.")
	if store.world_time_minutes != time_before + ACTION_MINUTES:
		return _fail("Trap installation did not advance world time exactly once.")
	if _inventory_has(store, TRAP_ID):
		return _fail("Installed trap remained in canonical inventory.")
	var trap_hex := store.get_hex_record(COORDS)
	if not _state_list_has(trap_hex.camp_traps, TRAP_ID):
		return _fail("Canonical hex did not retain the installed trap.")
	if not _state_list_has(trap_hex.camp_item_states, BLANKET_ID):
		return _fail("Installing a trap dismantled unrelated camp gear.")
	var trap_owner := store.find_item_ownership(TRAP_ID)
	if trap_owner.get("location", "") != "deployed_trap":
		return _fail("Installed trap has no singular deployed ownership.")
	var integrity_errors := store.validate_world_action_integrity(
		COORDS, "player", trap_receipt.action_id, true
	)
	if not integrity_errors.is_empty():
		return _fail("POI selection left runtime integrity errors: " + "; ".join(integrity_errors))

	var save_path := "res://.godot/test-logs/poi_selection_transaction.json"
	if not store.save_to_disk(save_path):
		return _fail("Could not save committed POI selections.")
	var loaded := RuntimeStateStore.new()
	if not loaded.load_from_disk(save_path):
		return _fail("Could not reload committed POI selections.")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	if loaded.find_item_ownership(BLANKET_ID).get("location", "") != "deployed_camp":
		return _fail("Save/load lost deployed camp-gear ownership.")
	if loaded.find_item_ownership(TRAP_ID).get("location", "") != "deployed_trap":
		return _fail("Save/load lost deployed trap ownership.")
	return true


func _test_stale_and_disappeared_item_rollback() -> bool:
	var stale_store := _build_store()
	var stale_receipt := _selection_receipt(
		stale_store,
		WorldActionPoiSelectionTransactionService.MODE_TRAP_INSTALL,
		[TRAP_ID],
		ACTION_MINUTES,
		"poi-stale"
	)
	stale_store.update_player_runtime(
		stale_store.player_record.runtime.duplicate(true), COORDS
	)
	if not _assert_rejected_without_mutation(
		stale_store, stale_receipt, "Stale POI actor revision"
	):
		return false

	var missing_store := _build_store()
	var missing_receipt := _selection_receipt(
		missing_store,
		WorldActionPoiSelectionTransactionService.MODE_TRAP_INSTALL,
		[TRAP_ID],
		ACTION_MINUTES,
		"poi-missing"
	)
	var missing_core := _core_from_store(missing_store, "PoiMissingFixture")
	missing_core.inventory.remove_item_by_instance_id(TRAP_ID)
	missing_store.update_player_runtime(
		missing_core.capture_runtime_state().to_dict(), COORDS
	)
	missing_core.free()
	return _assert_rejected_without_mutation(
		missing_store,
		missing_receipt,
		"POI item disappearing after selection validation"
	)


func _test_malformed_receipts() -> bool:
	for kind in ["wrong_target", "duplicate", "replacement", "wrong_method", "bad_mode", "duplicate_id"]:
		var store := _build_store()
		var receipt := _selection_receipt(
			store,
			WorldActionPoiSelectionTransactionService.MODE_TRAP_INSTALL,
			[TRAP_ID],
			ACTION_MINUTES,
			"poi-malformed-" + kind
		)
		match kind:
			"wrong_target":
				receipt.target_id = "trap:somewhere-else"
			"duplicate":
				receipt.mutations.append(receipt.mutations[1].duplicate(true))
			"replacement":
				receipt.actor_state = store.player_record.runtime.duplicate(true)
				receipt.mutations.append({"type": "replace_actor_runtime"})
			"wrong_method":
				receipt.method_id = "live_inventory_callback"
			"bad_mode":
				receipt.mutations[1]["mode"] = "summon_campsite_from_aether"
			"duplicate_id":
				receipt.mutations[1]["selected_instance_ids"] = [TRAP_ID, TRAP_ID]
		if not _assert_rejected_without_mutation(store, receipt, kind):
			return false
	return true


func _build_store() -> RuntimeStateStore:
	var store := RuntimeStateStore.new()
	store.begin_new_world("POI_SELECTION_TRANSACTION")
	var definition := preload("res://BiologicalCore/player_def.tres") as EntityDefinition
	var core := EntityFactory.record_to_humanoid_core({
		"entity_id": "player",
		"definition": definition.to_state(),
		"runtime": {},
	}, null, "PoiSelectionFixture")
	if core == null:
		_fail("Could not construct the POI transaction actor.")
		return null
	var blanket := (load("res://ItemCore/Items/blanket.tres") as ItemData).create_runtime_instance()
	blanket.instance_id = BLANKET_ID
	var trap := (load("res://ItemCore/Items/trap_makeshift.tres") as ItemData).create_runtime_instance()
	trap.instance_id = TRAP_ID
	if not core.inventory.add_to_backpack(blanket) or not core.inventory.add_to_backpack(trap):
		core.free()
		_fail("Could not seed canonical camp and trap gear.")
		return null
	var runtime := core.capture_runtime_state().to_dict()
	core.free()
	if not store.set_player_record({
		"entity_id": "player",
		"kind": GameEnums.RuntimeEntityKind.PLAYER,
		"coords": COORDS,
		"definition": definition.to_state(),
		"runtime": runtime,
	}, COORDS):
		_fail("Could not seed the canonical POI player record.")
		return null
	store.set_campaign_state({"seed": store.world_seed}, "poi-node", 0)
	store.set_hex_record(COORDS, HexRecord.new())
	return store


func _selection_receipt(
	store: RuntimeStateStore,
	mode: String,
	selected_ids: Array,
	elapsed_minutes: int,
	requested_action_id: String
) -> WorldActionReceipt:
	var request := WorldActionRequest.new()
	request.actor_id = "player"
	request.target_id = ("trap:" if mode == WorldActionPoiSelectionTransactionService.MODE_TRAP_INSTALL else "poi:") + str(COORDS)
	request.target_coords = COORDS
	request.verb_id = "trap" if mode == WorldActionPoiSelectionTransactionService.MODE_TRAP_INSTALL else "configure_camp"
	request.method_id = "trap_gear" if mode == WorldActionPoiSelectionTransactionService.MODE_TRAP_INSTALL else "poi_selection"
	request.expected_actor_revision = store.player_record.revision
	request.payload = {
		"action_id": requested_action_id,
		"world_time_minutes": store.world_time_minutes,
		"expected_hex_revision": store.get_hex_record(COORDS).revision,
	}
	var reservation := store.begin_world_action(request)
	var receipt := WorldActionResolver.resolve_direct_action(
		request,
		elapsed_minutes,
		0.25 if elapsed_minutes > 0 else 0.0,
		0.55 if elapsed_minutes > 0 else 0.0,
		"POI selection transaction fixture."
	)
	receipt.node_id = store.active_node_id
	receipt.expected_hex_revision = store.get_hex_record(COORDS).revision
	receipt.action_id = reservation.action_id
	receipt.receipt_id = reservation.next_receipt_id()
	receipt.mutations.append({
		"type": WorldActionPoiSelectionTransactionService.MUTATION_TYPE,
		"mode": mode,
		"selected_instance_ids": selected_ids.duplicate(),
	})
	return receipt


func _core_from_store(store: RuntimeStateStore, actor_name: String) -> HumanoidCore:
	return EntityFactory.record_to_humanoid_core(
		store.player_record.to_dict(), null, actor_name
	)


func _inventory_has(store: RuntimeStateStore, instance_id: String) -> bool:
	var core := _core_from_store(store, "PoiInventoryProbe")
	var found := core.inventory.find_item_by_instance_id(instance_id) != null
	core.free()
	return found


func _state_list_has(states: Array, instance_id: String) -> bool:
	for state in states:
		if state is Dictionary and str(state.get("instance_id", "")) == instance_id:
			return true
	return false


func _assert_rejected_without_mutation(
	store: RuntimeStateStore,
	receipt: WorldActionReceipt,
	label: String
) -> bool:
	var before := store.capture_reconciliation_snapshot()
	var service := WorldActionApplicationService.new()
	service.configure(store)
	var application := service.apply(receipt)
	if application.applied or application.error.is_empty():
		return _fail(label + " was not rejected with an error.")
	if store.capture_reconciliation_snapshot() != before:
		return _fail(label + " partially mutated canonical state.")
	return true


func _fail(message: String) -> bool:
	push_error("[TEST FAIL] " + message)
	quit(1)
	return false
