extends SceneTree

const ITEM_ID := "crowbar"
const ITEM_INSTANCE_ID := "inventory_transaction_crowbar"
const ACTION_MINUTES := 15
const COORDS := Vector2i.ZERO


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if not _test_take_drop_replay_and_persistence():
		return
	if not _test_stale_and_disappeared_item_rollback():
		return
	if not _test_malformed_receipts():
		return
	print("INVENTORY_WORLD_ACTION_TRANSACTION_SMOKE: PASS")
	quit(0)


func _test_take_drop_replay_and_persistence() -> bool:
	var store := _build_store()
	if store == null:
		return false
	var service := WorldActionApplicationService.new()
	service.configure(store)
	var revision_before := store.player_record.revision
	var time_before := store.world_time_minutes
	var take := _inventory_receipt(
		store,
		GameEnums.MACRO_INV_TAKE,
		ITEM_INSTANCE_ID,
		GameEnums.EquipmentSlot.NONE,
		"inventory-take"
	)
	var take_application := service.apply(take)
	if not take_application.applied or take_application.idempotent:
		return _fail("Valid canonical pickup was rejected: " + take_application.error)
	if store.player_record.revision != revision_before + 1:
		return _fail("Pickup did not advance actor revision exactly once.")
	if store.world_time_minutes != time_before + ACTION_MINUTES:
		return _fail("Pickup did not advance world time exactly once.")
	if _ground_has(store, ITEM_INSTANCE_ID):
		return _fail("Pickup left the same item on canonical ground.")
	var taken_core := _core_from_store(store, "InventoryTaken")
	if taken_core.inventory.find_item_by_instance_id(ITEM_INSTANCE_ID) == null:
		taken_core.free()
		return _fail("Pickup did not place the item in canonical inventory.")
	taken_core.free()
	var ownership := store.find_item_ownership(ITEM_INSTANCE_ID)
	if ownership.get("owner_id", "") != "player":
		return _fail("Pickup did not establish singular player ownership.")

	var after_take := store.capture_reconciliation_snapshot()
	var replay := service.apply(take)
	if not replay.applied or not replay.idempotent:
		return _fail("Pickup receipt replay was not idempotent.")
	if store.capture_reconciliation_snapshot() != after_take:
		return _fail("Pickup receipt replay repeated inventory or time effects.")

	var drop := _inventory_receipt(
		store,
		GameEnums.MACRO_INV_DROP,
		ITEM_INSTANCE_ID,
		GameEnums.EquipmentSlot.NONE,
		"inventory-drop"
	)
	var drop_application := service.apply(drop)
	if not drop_application.applied:
		return _fail("Valid canonical drop was rejected: " + drop_application.error)
	var dropped_core := _core_from_store(store, "InventoryDropped")
	var still_carried := dropped_core.inventory.find_item_by_instance_id(
		ITEM_INSTANCE_ID
	)
	dropped_core.free()
	if still_carried != null or not _ground_has(store, ITEM_INSTANCE_ID):
		return _fail("Drop did not atomically transfer inventory ownership to ground.")
	if store.find_item_ownership(ITEM_INSTANCE_ID).get("location", "") != "ground":
		return _fail("Drop left an invalid ownership-ledger location.")

	var save_path := "res://.godot/test-logs/inventory_world_action_transaction.json"
	if not store.save_to_disk(save_path):
		return _fail("Could not save the committed inventory transaction.")
	var loaded := RuntimeStateStore.new()
	if not loaded.load_from_disk(save_path):
		return _fail("Could not reload the committed inventory transaction.")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	if not _ground_has(loaded, ITEM_INSTANCE_ID):
		return _fail("Save/load lost the atomically dropped ground item.")
	if loaded.find_item_ownership(ITEM_INSTANCE_ID).get("location", "") != "ground":
		return _fail("Save/load corrupted dropped-item ownership.")
	return true


func _test_stale_and_disappeared_item_rollback() -> bool:
	var stale_store := _build_store()
	var stale_receipt := _inventory_receipt(
		stale_store,
		GameEnums.MACRO_INV_TAKE,
		ITEM_INSTANCE_ID,
		GameEnums.EquipmentSlot.NONE,
		"inventory-stale"
	)
	stale_store.update_player_runtime(
		stale_store.player_record.runtime.duplicate(true),
		COORDS
	)
	if not _assert_rejected_without_mutation(
		stale_store,
		stale_receipt,
		"Stale inventory actor revision"
	):
		return false

	var missing_store := _build_store()
	var missing_receipt := _inventory_receipt(
		missing_store,
		GameEnums.MACRO_INV_TAKE,
		ITEM_INSTANCE_ID,
		GameEnums.EquipmentSlot.NONE,
		"inventory-disappeared"
	)
	if missing_store.remove_ground_item(COORDS, ITEM_INSTANCE_ID).is_empty():
		return _fail("Could not create the disappeared-ground-item fixture.")
	return _assert_rejected_without_mutation(
		missing_store,
		missing_receipt,
		"Inventory item disappearing after UI validation"
	)


func _test_malformed_receipts() -> bool:
	for kind in ["wrong_target", "duplicate", "replacement", "wrong_method", "bad_action"]:
		var store := _build_store()
		var receipt := _inventory_receipt(
			store,
			GameEnums.MACRO_INV_TAKE,
			ITEM_INSTANCE_ID,
			GameEnums.EquipmentSlot.NONE,
			"inventory-malformed-" + kind
		)
		match kind:
			"wrong_target":
				receipt.target_id = "wrong-item"
			"duplicate":
				receipt.mutations.append(receipt.mutations[1].duplicate(true))
			"replacement":
				receipt.mutations.append({"type": "replace_actor_runtime"})
			"wrong_method":
				receipt.method_id = "live-first-nonsense"
			"bad_action":
				receipt.mutations[1]["action_id"] = "invent_item_from_aether"
		if not _assert_rejected_without_mutation(store, receipt, kind):
			return false
	return true


func _build_store() -> RuntimeStateStore:
	var store := RuntimeStateStore.new()
	store.begin_new_world("INVENTORY_WORLD_ACTION_TRANSACTION")
	var definition := preload("res://BiologicalCore/player_def.tres") as EntityDefinition
	var core := EntityFactory.record_to_humanoid_core({
		"entity_id": "player",
		"definition": definition.to_state(),
		"runtime": {},
	}, null, "InventoryTransactionFixture")
	if core == null:
		_fail("Could not construct the inventory transaction actor.")
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
		_fail("Could not seed the canonical inventory player record.")
		return null
	store.set_campaign_state({"seed": store.world_seed}, "inventory-node", 0)
	store.set_hex_record(COORDS, HexRecord.new())
	var item_definition := load(
		"res://ItemCore/Items/%s.tres" % ITEM_ID
	) as ItemData
	var item := item_definition.create_runtime_instance()
	item.instance_id = ITEM_INSTANCE_ID
	if not store.add_ground_items(COORDS, [item.to_runtime_state()]):
		_fail("Could not seed the canonical inventory ground item.")
		return null
	return store


func _inventory_receipt(
	store: RuntimeStateStore,
	action_id: String,
	instance_id: String,
	equipment_slot: int,
	requested_action_id: String
) -> WorldActionReceipt:
	var request := WorldActionRequest.new()
	request.actor_id = "player"
	request.target_id = instance_id
	request.target_coords = COORDS
	request.verb_id = "pick_up" if action_id == GameEnums.MACRO_INV_TAKE else action_id
	request.method_id = "inventory"
	request.expected_actor_revision = store.player_record.revision
	request.payload = {
		"action_id": requested_action_id,
		"world_time_minutes": store.world_time_minutes,
		"expected_hex_revision": store.get_hex_record(COORDS).revision,
	}
	var reservation := store.begin_world_action(request)
	var receipt := WorldActionResolver.resolve_direct_action(
		request,
		ACTION_MINUTES,
		0.0,
		0.0,
		"Inventory transaction fixture."
	)
	receipt.node_id = store.active_node_id
	receipt.expected_hex_revision = store.get_hex_record(COORDS).revision
	receipt.action_id = reservation.action_id
	receipt.receipt_id = reservation.next_receipt_id()
	receipt.mutations.append({
		"type": "inventory_action",
		"action_id": action_id,
		"instance_id": instance_id,
		"equipment_slot": equipment_slot,
		"action_payload": {},
	})
	return receipt


func _core_from_store(store: RuntimeStateStore, actor_name: String) -> HumanoidCore:
	return EntityFactory.record_to_humanoid_core(
		store.player_record.to_dict(),
		null,
		actor_name
	)


func _ground_has(store: RuntimeStateStore, instance_id: String) -> bool:
	for item_state in store.get_ground_items(COORDS):
		if str(item_state.get("instance_id", "")) == instance_id:
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
