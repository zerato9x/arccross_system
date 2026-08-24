extends SceneTree

const ORIGIN := Vector2i.ZERO
const TARGET := Vector2i(1, 0)
const ELAPSED_MINUTES := 12


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if not _test_player_movement_and_replay():
		return
	if not _test_stale_and_malformed_rollback():
		return
	if not _test_npc_movement():
		return
	print("MOVEMENT_WORLD_ACTION_TRANSACTION_SMOKE: PASS")
	quit(0)


func _test_player_movement_and_replay() -> bool:
	var store := _build_store()
	if store == null:
		return false
	var expected_core := EntityFactory.record_to_humanoid_core(
		store.player_record.to_dict(), null, "MovementExpectedActor"
	)
	expected_core.process_survival_time(ELAPSED_MINUTES, 15.0, 0.65, 0.0)
	expected_core.reconcile_terminal_state()
	var expected_runtime := expected_core.capture_runtime_state().to_dict()
	expected_core.free()

	var actor_revision := store.player_record.revision
	var hex_revision := store.get_hex_record(TARGET).revision
	var time_before := store.world_time_minutes
	var receipt := _movement_receipt(
		store, "player-move-success", "player", ORIGIN, TARGET
	)
	var service := WorldActionApplicationService.new()
	service.configure(store)
	var application := service.apply(receipt)
	if not application.applied or application.idempotent:
		return _fail("Valid canonical player movement was rejected: " + application.error)
	if store.player_record.coords != TARGET:
		return _fail("Player movement did not commit canonical coordinates.")
	if store.player_record.runtime != expected_runtime:
		return _fail("Movement did not stage elapsed survival from canonical runtime.")
	if store.player_record.revision != actor_revision + 1:
		return _fail("Player movement did not advance actor revision exactly once.")
	if store.get_hex_record(TARGET).revision != hex_revision + 1:
		return _fail("Player movement did not advance destination revision exactly once.")
	if not store.get_hex_record(TARGET).is_explored:
		return _fail("Player movement did not commit destination exploration.")
	if store.get_hex_record(TARGET).trace_records.size() != 1:
		return _fail("Player movement did not append exactly one movement trace.")
	if store.world_time_minutes != time_before + ELAPSED_MINUTES:
		return _fail("Player movement did not advance world time exactly once.")

	var after_commit := store.capture_reconciliation_snapshot()
	var replay := service.apply(receipt)
	if not replay.applied or not replay.idempotent:
		return _fail("Movement receipt replay was not idempotent.")
	if store.capture_reconciliation_snapshot() != after_commit:
		return _fail("Movement receipt replay repeated relocation or elapsed time.")

	var save_path := "res://.godot/test-logs/movement_world_action_transaction.json"
	if not store.save_to_disk(save_path):
		return _fail("Could not save committed movement state.")
	var loaded := RuntimeStateStore.new()
	if not loaded.load_from_disk(save_path):
		return _fail("Could not reload committed movement state.")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	if loaded.player_record.coords != TARGET:
		return _fail("Save/load lost committed player coordinates.")
	if loaded.world_time_minutes != store.world_time_minutes:
		return _fail("Save/load changed committed movement time.")
	return true


func _test_stale_and_malformed_rollback() -> bool:
	var stale_store := _build_store()
	var stale_receipt := _movement_receipt(
		stale_store, "player-move-stale", "player", ORIGIN, TARGET
	)
	stale_store.update_player_runtime(
		stale_store.player_record.runtime.duplicate(true), ORIGIN
	)
	if not _assert_rejected_without_mutation(
		stale_store, stale_receipt, "Stale movement actor revision"
	):
		return false

	for kind in [
		"actor_state",
		"duplicate",
		"wrong_origin",
		"wrong_destination",
		"wrong_verb",
		"missing_trace",
		"conflicting_mutation",
	]:
		var store := _build_store()
		var receipt := _movement_receipt(
			store, "player-move-malformed-" + kind, "player", ORIGIN, TARGET
		)
		match kind:
			"actor_state":
				receipt.actor_state = store.player_record.runtime.duplicate(true)
			"duplicate":
				receipt.mutations.append(receipt.mutations[1].duplicate(true))
			"wrong_origin":
				receipt.mutations[1]["from"] = Vector2i(-1, 0)
			"wrong_destination":
				receipt.mutations[1]["to"] = Vector2i(2, 0)
			"wrong_verb":
				receipt.verb_id = "teleport"
			"missing_trace":
				receipt.mutations.remove_at(3)
			"conflicting_mutation":
				receipt.mutations.append({"type": "replace_actor_runtime"})
		if not _assert_rejected_without_mutation(store, receipt, kind):
			return false
	return true


func _test_npc_movement() -> bool:
	var store := _build_store()
	var npc := EntityRecord.new()
	npc.entity_id = "movement-npc"
	npc.coords = ORIGIN
	npc.runtime = {"inventory_items": [], "marker": "canonical"}
	if store.register_entity(npc).is_empty():
		return _fail("Could not register canonical NPC movement fixture.")
	var before := store.get_entity_snapshot(npc.entity_id)
	var receipt := _movement_receipt(
		store, "npc-move-success", npc.entity_id, ORIGIN, TARGET
	)
	# NPC movement must not mutate player exploration state.
	receipt.mutations.remove_at(2)
	var service := WorldActionApplicationService.new()
	service.configure(store)
	var application := service.apply(receipt)
	if not application.applied:
		return _fail("Canonical NPC movement was rejected: " + application.error)
	var moved := store.get_entity_snapshot(npc.entity_id)
	if moved.get("coords") != TARGET:
		return _fail("NPC movement did not commit canonical coordinates.")
	if moved.get("runtime", {}) != before.get("runtime", {}):
		return _fail("NPC movement replaced canonical runtime during relocation.")
	if int(moved.get("revision", -1)) != int(before.get("revision", -1)) + 1:
		return _fail("NPC movement did not advance actor revision exactly once.")
	return true


func _build_store() -> RuntimeStateStore:
	var store := RuntimeStateStore.new()
	store.begin_new_world("MOVEMENT_WORLD_ACTION_TRANSACTION")
	var definition := preload("res://BiologicalCore/player_def.tres") as EntityDefinition
	var core := EntityFactory.record_to_humanoid_core({
		"entity_id": "player",
		"definition": definition.to_state(),
		"runtime": {},
	}, null, "MovementTransactionFixture")
	if core == null:
		_fail("Could not construct movement transaction actor.")
		return null
	core.body.fatigue = 6.25
	core.body.apply_targeted_hit(
		GameEnums.LimbRegion.LEFT_ARM,
		4.0,
		0.0,
		GameEnums.DamageType.BLUNT
	)
	var runtime := core.capture_runtime_state().to_dict()
	core.free()
	if not store.set_player_record({
		"entity_id": "player",
		"kind": GameEnums.RuntimeEntityKind.PLAYER,
		"coords": ORIGIN,
		"definition": definition.to_state(),
		"runtime": runtime,
	}, ORIGIN):
		_fail("Could not seed canonical movement actor.")
		return null
	store.set_campaign_state({"seed": store.world_seed}, "movement-node", 0)
	store.set_hex_record(ORIGIN, HexRecord.new())
	store.set_hex_record(TARGET, HexRecord.new())
	return store


func _movement_receipt(
	store: RuntimeStateStore,
	requested_action_id: String,
	actor_id: String,
	from: Vector2i,
	to: Vector2i
) -> WorldActionReceipt:
	var request := WorldActionRequest.new()
	request.actor_id = actor_id
	request.target_id = "hex:" + str(to)
	request.target_coords = to
	request.verb_id = WorldActionMovementTransactionService.VERB_TRAVEL
	request.expected_actor_revision = (
		store.player_record.revision
		if actor_id == "player"
		else int(store.get_entity_snapshot(actor_id).get("revision", -1))
	)
	request.payload = {
		"action_id": requested_action_id,
		"world_time_minutes": store.world_time_minutes,
		"expected_hex_revision": store.get_hex_record(to).revision,
	}
	var reservation := store.begin_world_action(request)
	var receipt := WorldActionResolver.resolve_direct_action(
		request, ELAPSED_MINUTES, 0.65, 0.0, "Movement transaction fixture."
	)
	receipt.node_id = store.active_node_id
	receipt.expected_hex_revision = store.get_hex_record(to).revision
	receipt.action_id = reservation.action_id
	receipt.receipt_id = reservation.next_receipt_id()
	receipt.mutations.append({"type": "move_actor", "from": from, "to": to})
	receipt.mutations.append({"type": "set_hex_explored"})
	receipt.mutations.append({
		"type": "movement_trace",
		"trace": {
			"kind": "tracks",
			"source_id": actor_id,
			"coords": to,
			"created_minute": store.world_time_minutes,
			"expires_minute": store.world_time_minutes + 180,
		},
	})
	return receipt


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
