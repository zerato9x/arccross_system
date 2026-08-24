extends SceneTree

const SAVE_PATH := "res://.godot/test-logs/medical_world_action_transaction.json"
const BANDAGE_INSTANCE_ID := "medical_transaction_bandage"
const LIMB := GameEnums.LimbRegion.LEFT_ARM
const ACTION_MINUTES := 5


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if not _test_success_replay_and_persistence():
		return
	if not _test_final_unit_consumption():
		return
	if not _test_stale_revision_rollback():
		return
	if not _test_canonical_treatment_rejection():
		return
	if not _test_malformed_receipts():
		return
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	print("MEDICAL_WORLD_ACTION_TRANSACTION_SMOKE: PASS")
	quit(0)


func _test_success_replay_and_persistence() -> bool:
	var store := _build_store(2, true)
	if store == null:
		return false
	var before_core := _core_from_store(store, "MedicalBefore")
	var bleeding_before := before_core.body.get_limb_bleeding_rate(LIMB)
	before_core.free()
	if bleeding_before <= 0.0:
		return _fail("Controlled medical fixture did not produce bleeding.")
	var revision_before := store.player_record.revision
	var time_before := store.world_time_minutes
	var receipt := _medical_receipt(store, BANDAGE_INSTANCE_ID, LIMB, "medical-success")
	if receipt == null:
		return false
	var service := WorldActionApplicationService.new()
	service.configure(store)
	var application := service.apply(receipt)
	if not application.applied or application.idempotent:
		return _fail("Valid medical receipt was not applied: " + application.error)
	var after_core := _core_from_store(store, "MedicalAfter")
	var bleeding_after := after_core.body.get_limb_bleeding_rate(LIMB)
	var remaining_bandage := after_core.inventory.find_item_by_instance_id(
		BANDAGE_INSTANCE_ID
	)
	if bleeding_after >= bleeding_before:
		after_core.free()
		return _fail("Canonical medical treatment did not reduce bleeding.")
	if remaining_bandage == null or remaining_bandage.stack_count != 1:
		after_core.free()
		return _fail("Medical treatment did not consume exactly one stack unit.")
	after_core.free()
	if store.player_record.revision != revision_before + 1:
		return _fail("Medical treatment did not advance the actor revision exactly once.")
	if store.world_time_minutes != time_before + ACTION_MINUTES:
		return _fail("Medical treatment did not advance world time exactly once.")
	var ownership := store.find_item_ownership(BANDAGE_INSTANCE_ID)
	if ownership.get("owner_id", "") != "player":
		return _fail("Remaining medical stack lost canonical player ownership.")

	var after_first := store.capture_reconciliation_snapshot()
	var replay := service.apply(receipt)
	if not replay.applied or not replay.idempotent:
		return _fail("Repeated medical receipt was not idempotent.")
	if store.capture_reconciliation_snapshot() != after_first:
		return _fail("Repeated medical receipt mutated canonical state twice.")

	if not store.save_to_disk(SAVE_PATH):
		return _fail("Could not save the committed medical transaction.")
	var loaded := RuntimeStateStore.new()
	if not loaded.load_from_disk(SAVE_PATH):
		return _fail("Could not reload the committed medical transaction.")
	var loaded_core := _core_from_store(loaded, "MedicalLoaded")
	var loaded_bandage := loaded_core.inventory.find_item_by_instance_id(
		BANDAGE_INSTANCE_ID
	)
	if not is_equal_approx(
		loaded_core.body.get_limb_bleeding_rate(LIMB),
		bleeding_after
	):
		loaded_core.free()
		return _fail("Treated wound changed after save/load.")
	if loaded_bandage == null or loaded_bandage.stack_count != 1:
		loaded_core.free()
		return _fail("Consumed medical stack changed after save/load.")
	loaded_core.free()
	return true


func _test_final_unit_consumption() -> bool:
	var store := _build_store(1, true)
	if store == null:
		return false
	var receipt := _medical_receipt(store, BANDAGE_INSTANCE_ID, LIMB, "medical-final-unit")
	if receipt == null:
		return false
	var service := WorldActionApplicationService.new()
	service.configure(store)
	var application := service.apply(receipt)
	if not application.applied:
		return _fail("Final-unit medical receipt was rejected: " + application.error)
	var core := _core_from_store(store, "MedicalFinalUnit")
	var item := core.inventory.find_item_by_instance_id(BANDAGE_INSTANCE_ID)
	core.free()
	if item != null:
		return _fail("Final medical unit remained in inventory after consumption.")
	if not store.find_item_ownership(BANDAGE_INSTANCE_ID).is_empty():
		return _fail("Consumed final medical unit remained in the ownership ledger.")
	return true


func _test_stale_revision_rollback() -> bool:
	var store := _build_store(2, true)
	if store == null:
		return false
	var receipt := _medical_receipt(store, BANDAGE_INSTANCE_ID, LIMB, "medical-stale")
	if receipt == null:
		return false
	if not store.update_player_runtime(
		store.player_record.runtime.duplicate(true),
		Vector2i.ZERO
	):
		return _fail("Could not create controlled medical actor revision drift.")
	return _assert_rejected_without_mutation(
		store,
		receipt,
		"Stale medical actor revision"
	)


func _test_canonical_treatment_rejection() -> bool:
	var store := _build_store(1, false)
	if store == null:
		return false
	var ui_projection := _core_from_store(store, "MedicalStaleUiProjection")
	root.add_child(ui_projection)
	ui_projection.body.apply_targeted_hit(
		LIMB,
		4.0,
		8.0,
		GameEnums.DamageType.SHARP
	)
	var ui_validation := MacroMedicalResolver.validate_apply_to_limb(
		ui_projection,
		BANDAGE_INSTANCE_ID,
		LIMB
	)
	ui_projection.free()
	if not bool(ui_validation.get("valid", false)):
		return _fail("Controlled stale UI projection was not medically valid.")
	var receipt := _medical_receipt(
		store,
		BANDAGE_INSTANCE_ID,
		LIMB,
		"medical-no-longer-valid"
	)
	if receipt == null:
		return false
	return _assert_rejected_without_mutation(
		store,
		receipt,
		"Canonical no-longer-valid treatment"
	)


func _test_malformed_receipts() -> bool:
	var cases := [
		{"label": "missing item", "kind": "missing_item"},
		{"label": "wrong target identity", "kind": "wrong_target"},
		{"label": "invalid limb", "kind": "invalid_limb"},
		{"label": "duplicate application", "kind": "duplicate"},
		{"label": "double consumption", "kind": "consume_material"},
	]
	for case in cases:
		var store := _build_store(2, true)
		if store == null:
			return false
		var receipt := _medical_receipt(
			store,
			BANDAGE_INSTANCE_ID,
			LIMB,
			"medical-malformed-" + str(case["kind"])
		)
		if receipt == null:
			return false
		match str(case["kind"]):
			"missing_item":
				receipt.target_id = "missing-medical-item"
				receipt.mutations[1]["instance_id"] = "missing-medical-item"
			"wrong_target":
				receipt.target_id = "different-medical-item"
			"invalid_limb":
				receipt.mutations[1]["limb_region"] = 999
			"duplicate":
				receipt.mutations.append(receipt.mutations[1].duplicate(true))
			"consume_material":
				receipt.mutations.append({
					"type": "consume_material",
					"instance_id": BANDAGE_INSTANCE_ID,
				})
		if not _assert_rejected_without_mutation(store, receipt, str(case["label"])):
			return false
	return true


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


func _build_store(stack_count: int, with_bleed: bool) -> RuntimeStateStore:
	var store := RuntimeStateStore.new()
	store.begin_new_world("MEDICAL_WORLD_ACTION_TRANSACTION")
	var definition := preload("res://BiologicalCore/player_def.tres") as EntityDefinition
	var core := EntityFactory.record_to_humanoid_core({
		"entity_id": "player",
		"definition": definition.to_state(),
		"runtime": {},
	}, null, "MedicalTransactionFixture")
	if core == null:
		_fail("Could not construct the medical transaction fixture actor.")
		return null
	root.add_child(core)
	if with_bleed:
		core.body.apply_targeted_hit(
			LIMB,
			4.0,
			8.0,
			GameEnums.DamageType.SHARP
		)
	var definition_item := load("res://ItemCore/Items/bandage.tres") as ItemData
	var bandage := definition_item.create_runtime_instance()
	bandage.instance_id = BANDAGE_INSTANCE_ID
	bandage.stack_count = stack_count
	if not core.inventory.add_to_backpack(bandage):
		core.free()
		_fail("Could not add the controlled medical stack to the fixture actor.")
		return null
	var runtime := core.capture_runtime_state().to_dict()
	core.free()
	if not store.set_player_record({
		"entity_id": "player",
		"kind": GameEnums.RuntimeEntityKind.PLAYER,
		"coords": Vector2i.ZERO,
		"definition": definition.to_state(),
		"runtime": runtime,
	}, Vector2i.ZERO):
		_fail("Could not seed the canonical medical player record.")
		return null
	store.set_campaign_state({"seed": store.world_seed}, "medical-node", 0)
	store.set_hex_record(Vector2i.ZERO, HexRecord.new())
	if store.get_hex_record(Vector2i.ZERO) == null:
		_fail("Could not seed the canonical medical hex record.")
		return null
	return store


func _medical_receipt(
	store: RuntimeStateStore,
	instance_id: String,
	limb_region: int,
	action_id: String
) -> WorldActionReceipt:
	var request := WorldActionRequest.new()
	request.actor_id = "player"
	request.target_id = instance_id
	request.target_coords = Vector2i.ZERO
	request.verb_id = "treat"
	request.method_id = "medical_item"
	request.expected_actor_revision = store.player_record.revision
	request.payload = {
		"action_id": action_id,
		"node_id": store.active_node_id,
		"expected_hex_revision": store.get_hex_record(Vector2i.ZERO).revision,
		"world_time_minutes": store.world_time_minutes,
	}
	var reservation := store.begin_world_action(request)
	if reservation == null:
		_fail("Could not reserve controlled medical action " + action_id + ".")
		return null
	request.payload["receipt_id"] = reservation.next_receipt_id()
	var receipt := WorldActionResolver.resolve_direct_action(
		request,
		ACTION_MINUTES,
		0.35,
		0.15,
		"Treatment applied."
	)
	receipt.mutations.append({
		"type": "medical_application",
		"instance_id": instance_id,
		"limb_region": limb_region,
	})
	return receipt


func _core_from_store(store: RuntimeStateStore, node_name: String) -> HumanoidCore:
	return EntityFactory.record_to_humanoid_core(
		store.player_record.to_dict(),
		null,
		node_name
	)


func _fail(message: String) -> bool:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	push_error("[MEDICAL_WORLD_ACTION_TRANSACTION] " + message)
	quit(1)
	return false
