extends SceneTree

const NPC_ID := "npc-pickup-transaction-actor"
const ITEM_ID := "npc-pickup-transaction-item"
const COORDS := Vector2i(-2, 3)
const ELAPSED_MINUTES := 5


func _initialize() -> void:
	call_deferred("_run")


func _run() -> bool:
	if not _verify_atomic_pickup():
		return false
	if not _verify_shipping_service():
		return false
	if not _verify_rejections():
		return false
	print("NPC_PICKUP_WORLD_ACTION_TRANSACTION_SMOKE: PASS")
	quit(0)
	return true


func _verify_atomic_pickup() -> bool:
	var store := _fixture_store()
	var service := WorldActionApplicationService.new()
	service.configure(store)
	var receipt := _receipt(store, "npc-pickup-atomic")
	var starting_time := store.world_time_minutes
	var starting_revision := int(store.get_entity_snapshot(NPC_ID).get("revision", -1))
	var application := service.apply(receipt)
	if not application.applied or application.idempotent:
		return _fail("Atomic NPC pickup failed: " + application.error)
	if store.world_time_minutes != starting_time + ELAPSED_MINUTES:
		return _fail("NPC pickup did not advance world time exactly once.")
	var actor := store.get_entity_snapshot(NPC_ID)
	if int(actor.get("revision", -1)) != starting_revision + 1:
		return _fail("NPC pickup did not advance the actor revision exactly once.")
	if str(actor.get("runtime", {}).get("macro_purpose_label", "")) != "Carrying salvage":
		return _fail("NPC pickup did not stage its purpose with ownership.")
	var ownership := store.find_item_ownership(ITEM_ID)
	if (
		str(ownership.get("location", "")) != "inventory"
		or str(ownership.get("owner_id", "")) != NPC_ID
	):
		return _fail("NPC pickup did not transfer one canonical item owner.")
	if store.has_ground_items(COORDS):
		return _fail("NPC pickup left the transferred item on the ground.")
	if not store.validate_integrity().is_empty():
		return _fail("NPC pickup left invalid canonical runtime state.")
	var committed_snapshot := store.capture_reconciliation_snapshot()
	var replay := service.apply(receipt)
	if not replay.applied or not replay.idempotent:
		return _fail("NPC pickup replay was not idempotent: " + replay.error)
	if store.capture_reconciliation_snapshot() != committed_snapshot:
		return _fail("NPC pickup replay repeated canonical mutations.")
	return true


func _verify_shipping_service() -> bool:
	var store := _fixture_store()
	var service := WorldActionApplicationService.new()
	service.configure(store)
	var runtime_service := MacroNpcRuntimeService.new()
	var build := func(record: EntityRecord, _instance_id: String):
		return _receipt(store, "npc-pickup-shipping", record.coords)
	var commit := func(
		receipt: WorldActionReceipt,
		_coords: Vector2i,
		_target: WorldObjectRecord,
		_actor_id: String
	):
		return service.apply(receipt)
	runtime_service.collect_ground_items(
		store,
		EntityRecord.from_dict(store.get_entity_snapshot(NPC_ID)),
		build,
		commit
	)
	if store.find_item_ownership(ITEM_ID).get("owner_id", "") != NPC_ID:
		return _fail("Shipping NPC pickup service did not use the receipt transfer.")
	var rejected_store := _fixture_store()
	var rejected_runtime_service := MacroNpcRuntimeService.new()
	var rejected_receipt_holder: Array = [null]
	var build_rejected := func(record: EntityRecord, _instance_id: String):
		rejected_receipt_holder[0] = _receipt(
			rejected_store, "npc-pickup-shipping-rejected", record.coords
		)
		return rejected_receipt_holder[0]
	var reject_commit := func(
		_receipt_value: WorldActionReceipt,
		_coords: Vector2i,
		_target: WorldObjectRecord,
		_actor_id: String
	):
		var rejected := WorldActionApplicationReceipt.new()
		rejected.error = "Injected receipt rejection."
		return rejected
	var before := rejected_store.capture_reconciliation_snapshot()
	rejected_runtime_service.collect_ground_items(
		rejected_store,
		EntityRecord.from_dict(rejected_store.get_entity_snapshot(NPC_ID)),
		build_rejected,
		reject_commit
	)
	var after := rejected_store.capture_reconciliation_snapshot()
	# The service is allowed to release the failed reservation; every other
	# authoritative field must remain untouched.
	before["active_world_actions"] = {}
	after["active_world_actions"] = {}
	if after != before:
		return _fail("Rejected shipping NPC pickup partially mutated world state.")
	var rejected_receipt := (
		rejected_receipt_holder[0] as WorldActionReceipt
	)
	if rejected_receipt == null or rejected_store.get_world_action_reservation(
		rejected_receipt.action_id
	) != null:
		return _fail("Rejected shipping NPC pickup retained its reservation.")
	return true


func _verify_rejections() -> bool:
	var cases := [
		{
			"name": "duplicate transfer",
			"change": func(store, receipt):
				var second := _ground_item("npc-pickup-second-item")
				store.add_ground_items(COORDS, [second])
				receipt.mutations.append({
					"type": "transfer_ground_item",
					"instance_id": "npc-pickup-second-item",
				}),
		},
		{
			"name": "stale actor",
			"change": func(store, _receipt):
				store.patch_entity_record(NPC_ID, {"knowledge": {"stale": true}}),
		},
		{
			"name": "missing ground owner",
			"change": func(store, _receipt):
				store.remove_item_instance(ITEM_ID),
		},
	]
	for test_case in cases:
		var store := _fixture_store()
		var service := WorldActionApplicationService.new()
		service.configure(store)
		var receipt := _receipt(
			store,
			"npc-pickup-reject-" + str(test_case["name"]).replace(" ", "-")
		)
		(test_case["change"] as Callable).call(store, receipt)
		if not _expect_rejected_unchanged(
			store, service, receipt, str(test_case["name"])
		):
			return false
	var remote_store := _fixture_store()
	var remote_coords := COORDS + Vector2i(1, 0)
	remote_store.set_hex_record(remote_coords, HexRecord.new())
	var remote_service := WorldActionApplicationService.new()
	remote_service.configure(remote_store)
	var remote_receipt := _receipt(
		remote_store, "npc-pickup-reject-remote", remote_coords
	)
	if not _expect_rejected_unchanged(
		remote_store, remote_service, remote_receipt, "remote actor coordinate"
	):
		return false
	return true


func _fixture_store() -> RuntimeStateStore:
	var store := RuntimeStateStore.new()
	store.begin_new_world("NPC_PICKUP_WORLD_ACTION_TRANSACTION")
	store.set_campaign_state({"seed": store.world_seed}, "npc-pickup-node", 0)
	var actor := EntityRecord.new()
	actor.entity_id = NPC_ID
	actor.kind = GameEnums.RuntimeEntityKind.NPC
	actor.coords = COORDS
	actor.runtime = {"inventory_items": [], "npc_role_id": "scavenger"}
	if store.register_entity(actor).is_empty():
		_fail("Could not seed the NPC pickup actor.")
		return null
	store.set_hex_record(COORDS, HexRecord.new())
	if not store.add_ground_items(COORDS, [_ground_item(ITEM_ID)]):
		_fail("Could not seed the NPC pickup ground item.")
		return null
	if not store.validate_integrity().is_empty():
		_fail("NPC pickup fixture failed canonical integrity.")
		return null
	return store


func _receipt(
	store: RuntimeStateStore,
	action_id: String,
	target_coords: Vector2i = COORDS
) -> WorldActionReceipt:
	var actor := store.get_entity_snapshot(NPC_ID)
	var request := WorldActionRequest.new()
	request.actor_id = NPC_ID
	request.target_id = ITEM_ID
	request.target_coords = target_coords
	request.verb_id = "pick_up"
	request.expected_actor_revision = int(actor.get("revision", -1))
	request.payload = {
		"action_id": action_id,
		"node_id": store.active_node_id,
		"world_time_minutes": store.world_time_minutes,
		"expected_hex_revision": store.get_hex_record(target_coords).revision,
	}
	var reservation := store.begin_world_action(request)
	var receipt := WorldActionResolver.resolve_direct_action(
		request, ELAPSED_MINUTES, 0.05, 0.0, "NPC pickup fixture."
	)
	receipt.node_id = store.active_node_id
	receipt.action_id = reservation.action_id
	receipt.receipt_id = reservation.next_receipt_id()
	receipt.expected_hex_revision = store.get_hex_record(target_coords).revision
	receipt.mutations.append({
		"type": "transfer_ground_item",
		"instance_id": ITEM_ID,
	})
	return receipt


func _ground_item(instance_id: String) -> Dictionary:
	var definition := load("res://ItemCore/Items/bandage.tres") as ItemData
	var state := definition.create_runtime_instance().to_runtime_state()
	state["instance_id"] = instance_id
	state["owner_id"] = ""
	state["physical_location"] = "ground"
	state["equipped_slot"] = GameEnums.EquipmentSlot.NONE
	return state


func _expect_rejected_unchanged(
	store: RuntimeStateStore,
	service: WorldActionApplicationService,
	receipt: WorldActionReceipt,
	label: String
) -> bool:
	var before := store.capture_reconciliation_snapshot()
	var application := service.apply(receipt)
	if application.applied or application.error.is_empty():
		return _fail("Malformed NPC pickup was accepted: " + label)
	if store.capture_reconciliation_snapshot() != before:
		return _fail("Rejected NPC pickup partially mutated state: " + label)
	store.cancel_world_action(receipt.action_id)
	return true


func _fail(message: String) -> bool:
	push_error("[NPC PICKUP WORLD ACTION TRANSACTION] " + message)
	quit(1)
	return false
