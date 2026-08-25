extends SceneTree

const COORDS := Vector2i.ZERO
const ELAPSED_MINUTES := 480
const FATIGUE_RECOVERY := 4.0
const HEALING_AMOUNT := 2.0
const INSULATION_BONUS := 1.5


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if not _test_canonical_camp_cycle_and_replay():
		return
	if not _test_stale_and_malformed_rollback():
		return
	print("CAMP_WORLD_ACTION_TRANSACTION_SMOKE: PASS")
	quit(0)


func _test_canonical_camp_cycle_and_replay() -> bool:
	var store := _build_store()
	if store == null:
		return false
	var expected_core := _core_from_store(store, "CampExpectedActor")
	_apply_recovery(expected_core, FATIGUE_RECOVERY, HEALING_AMOUNT)
	expected_core.process_survival_time(
		ELAPSED_MINUTES, 15.0, 0.25, INSULATION_BONUS
	)
	expected_core.reconcile_terminal_state()
	var expected_runtime := expected_core.capture_runtime_state().to_dict()
	expected_core.free()

	var actor_revision := store.player_record.revision
	var hex_revision := store.get_hex_record(COORDS).revision
	var time_before := store.world_time_minutes
	var receipt := _camp_receipt(store, "camp-success")
	var service := WorldActionApplicationService.new()
	service.configure(store)
	var application := service.apply(receipt)
	if not application.applied or application.idempotent:
		return _fail("Valid canonical camp cycle was rejected: " + application.error)
	if store.player_record.runtime != expected_runtime:
		return _fail("Camp recovery was not applied to detached canonical biology before elapsed time.")
	if store.player_record.revision != actor_revision + 1:
		return _fail("Camp cycle did not advance actor revision exactly once.")
	if store.get_hex_record(COORDS).revision != hex_revision + 1:
		return _fail("Camp cycle did not advance hex revision exactly once.")
	if store.get_hex_record(COORDS).camp_rest_count != 2:
		return _fail("First camp cycle did not preserve the session-plus-cycle rest count.")
	if store.world_time_minutes != time_before + ELAPSED_MINUTES:
		return _fail("Camp cycle did not advance world time exactly once.")
	var committed_core := _core_from_store(store, "CampCommittedProbe")
	if committed_core.body.limb_hp[GameEnums.LimbRegion.LEFT_LEG] > 0.0:
		committed_core.free()
		return _fail("Camp recovery resurrected a destroyed limb.")
	committed_core.free()

	var after_commit := store.capture_reconciliation_snapshot()
	var replay := service.apply(receipt)
	if not replay.applied or not replay.idempotent:
		return _fail("Camp receipt replay was not idempotent.")
	if store.capture_reconciliation_snapshot() != after_commit:
		return _fail("Camp receipt replay repeated recovery, time, or rest count.")

	var save_path := "res://.godot/test-logs/camp_world_action_transaction.json"
	if not store.save_to_disk(save_path):
		return _fail("Could not save the committed camp transaction.")
	var loaded := RuntimeStateStore.new()
	if not loaded.load_from_disk(save_path):
		return _fail("Could not reload the committed camp transaction.")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	var committed_reload_probe := _core_from_store(store, "CampSaveSourceProbe")
	var loaded_reload_probe := _core_from_store(loaded, "CampSaveLoadedProbe")
	var committed_normalized := committed_reload_probe.capture_runtime_state().to_dict()
	var loaded_normalized := loaded_reload_probe.capture_runtime_state().to_dict()
	committed_reload_probe.free()
	loaded_reload_probe.free()
	if not _body_states_equivalent(
		committed_normalized.get("body", {}),
		loaded_normalized.get("body", {})
	):
		return _fail("Save/load changed normalized canonical camp biology.")
	if loaded.get_hex_record(COORDS).camp_rest_count != 2:
		return _fail("Save/load lost the canonical camp rest count.")
	return true


func _test_stale_and_malformed_rollback() -> bool:
	var stale_store := _build_store()
	var stale_receipt := _camp_receipt(stale_store, "camp-stale")
	stale_store.update_player_runtime(
		stale_store.player_record.runtime.duplicate(true), COORDS
	)
	if not _assert_rejected_without_mutation(
		stale_store, stale_receipt, "Stale camp actor revision"
	):
		return false

	for kind in ["wrong_target", "duplicate", "replacement", "wrong_method", "bad_recovery", "bad_delta"]:
		var store := _build_store()
		var receipt := _camp_receipt(store, "camp-malformed-" + kind)
		match kind:
			"wrong_target":
				receipt.target_id = "camp:wrong"
			"duplicate":
				receipt.mutations.append(receipt.mutations[1].duplicate(true))
			"replacement":
				receipt.mutations.append({"type": "replace_actor_runtime"})
			"wrong_method":
				receipt.method_id = "live_body_edit"
			"bad_recovery":
				receipt.mutations[1]["fatigue_recovery"] = -1.0
			"bad_delta":
				receipt.mutations[1]["camp_rest_count_delta"] = 99
		if not _assert_rejected_without_mutation(store, receipt, kind):
			return false
	return true


func _build_store() -> RuntimeStateStore:
	var store := RuntimeStateStore.new()
	store.begin_new_world("CAMP_WORLD_ACTION_TRANSACTION")
	var definition := preload("res://BiologicalCore/player_def.tres") as EntityDefinition
	var core := EntityFactory.record_to_humanoid_core({
		"entity_id": "player",
		"definition": definition.to_state(),
		"runtime": {},
	}, null, "CampTransactionFixture")
	if core == null:
		_fail("Could not construct the camp transaction actor.")
		return null
	core.body.fatigue = 8.0
	core.body.apply_targeted_hit(
		GameEnums.LimbRegion.LEFT_ARM,
		5.0,
		0.0,
		GameEnums.DamageType.BLUNT
	)
	core.body.limb_hp[GameEnums.LimbRegion.LEFT_LEG] = 0.0
	var runtime := core.capture_runtime_state().to_dict()
	core.free()
	if not store.set_player_record({
		"entity_id": "player",
		"kind": GameEnums.RuntimeEntityKind.PLAYER,
		"coords": COORDS,
		"definition": definition.to_state(),
		"runtime": runtime,
	}, COORDS):
		_fail("Could not seed canonical camp biology.")
		return null
	store.set_campaign_state({"seed": store.world_seed}, "camp-node", 0)
	store.set_hex_record(COORDS, HexRecord.new())
	return store


func _camp_receipt(store: RuntimeStateStore, requested_action_id: String) -> WorldActionReceipt:
	var request := WorldActionRequest.new()
	request.actor_id = "player"
	request.target_id = "camp:" + str(COORDS)
	request.target_coords = COORDS
	request.verb_id = WorldActionCampTransactionService.VERB_ID
	request.method_id = WorldActionCampTransactionService.METHOD_ID
	request.expected_actor_revision = store.player_record.revision
	request.payload = {
		"action_id": requested_action_id,
		"world_time_minutes": store.world_time_minutes,
		"expected_hex_revision": store.get_hex_record(COORDS).revision,
	}
	var reservation := store.begin_world_action(request)
	var receipt := WorldActionResolver.resolve_direct_action(
		request, ELAPSED_MINUTES, 0.25, 0.0, "Camp transaction fixture."
	)
	receipt.node_id = store.active_node_id
	receipt.expected_hex_revision = store.get_hex_record(COORDS).revision
	receipt.action_id = reservation.action_id
	receipt.receipt_id = reservation.next_receipt_id()
	receipt.presentation["insulation_bonus"] = INSULATION_BONUS
	receipt.mutations.append({
		"type": WorldActionCampTransactionService.MUTATION_TYPE,
		"fatigue_recovery": FATIGUE_RECOVERY,
		"healing_amount": HEALING_AMOUNT,
		"camp_rest_count_delta": 2,
	})
	return receipt


func _apply_recovery(core: HumanoidCore, fatigue_recovery: float, healing_amount: float) -> void:
	core.body.fatigue = maxf(0.0, core.body.fatigue - fatigue_recovery)
	for limb in core.body.limb_hp.keys():
		if core.body.limb_hp[limb] <= 0.0:
			continue
		core.body.limb_hp[limb] += minf(
			core.body.get_limb_max(limb) - core.body.limb_hp[limb],
			healing_amount
		)


func _body_states_equivalent(before: Dictionary, after: Dictionary) -> bool:
	for key in [
		"core_temperature",
		"blood_level",
		"shock",
		"consciousness",
		"wet_exposure",
		"hunger",
		"thirst",
		"fatigue",
	]:
		if not is_equal_approx(float(before.get(key, 0.0)), float(after.get(key, 0.0))):
			return false
	if before.get("destroyed_limbs", []) != after.get("destroyed_limbs", []):
		return false
	var before_wounds: Dictionary = before.get("wounds_by_limb", {})
	var after_wounds: Dictionary = after.get("wounds_by_limb", {})
	if before_wounds.keys() != after_wounds.keys():
		return false
	for limb_key in before_wounds.keys():
		var source: Array = before_wounds[limb_key]
		var loaded: Array = after_wounds[limb_key]
		if source.size() != loaded.size():
			return false
		for index in range(source.size()):
			if str(source[index].get("wound_id", "")) != str(loaded[index].get("wound_id", "")):
				return false
			if not is_equal_approx(
				float(source[index].get("severity", 0.0)),
				float(loaded[index].get("severity", 0.0))
			):
				return false
	return true


func _core_from_store(store: RuntimeStateStore, actor_name: String) -> HumanoidCore:
	return EntityFactory.record_to_humanoid_core(
		store.player_record.to_dict(), null, actor_name
	)


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
