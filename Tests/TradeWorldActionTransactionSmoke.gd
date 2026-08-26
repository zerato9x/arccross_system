extends SceneTree

const ENEMY_ID := "trade-transaction-enemy"
const OFFER_ID := "trade-transaction-offer"
const RECEIVED_ID := "trade-transaction-received"
const COORDS := Vector2i(3, -2)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> bool:
	if not _verify_atomic_trade():
		return false
	if not _verify_rejections():
		return false
	print("TRADE_WORLD_ACTION_TRANSACTION_SMOKE: PASS")
	quit(0)
	return true


func _verify_atomic_trade() -> bool:
	var store := _fixture_store()
	if store == null:
		return false
	var service := WorldActionApplicationService.new()
	service.configure(store)
	var receipt := _receipt(store, "trade-atomic")
	var starting_time := store.world_time_minutes
	var starting_player_revision := store.player_record.revision
	var starting_enemy_revision := int(
		store.get_entity_snapshot(ENEMY_ID).get("revision", -1)
	)
	var application := service.apply(receipt)
	if not application.applied or application.idempotent:
		return _fail("Atomic trade failed: " + application.error)
	if store.world_time_minutes != starting_time + WorldActionTradeTransactionService.ELAPSED_MINUTES:
		return _fail("Trade did not advance world time exactly once.")
	if store.player_record.revision != starting_player_revision + 1:
		return _fail("Trade did not advance the player revision exactly once.")
	if int(store.get_entity_snapshot(ENEMY_ID).get("revision", -1)) != starting_enemy_revision + 1:
		return _fail("Trade did not advance the counterparty revision exactly once.")
	if store.find_item_ownership(OFFER_ID).get("owner_id", "") != ENEMY_ID:
		return _fail("Trade offer did not acquire the counterparty owner.")
	if store.find_item_ownership(RECEIVED_ID).get("owner_id", "") != "player":
		return _fail("Received item did not acquire the player owner.")
	var ledger := CombatRelationshipLedger.from_dict(store.get_relationship_state())
	if not is_equal_approx(ledger.trust("player", ENEMY_ID), 0.25):
		return _fail("Trade trust did not commit inside the transaction.")
	var memory: Dictionary = store.get_entity_snapshot(ENEMY_ID).get(
		"runtime", {}
	).get("macro_ai", {}).get("memory", {})
	if (
		str(memory.get("events", [])[-1].get("id", "")) != "trade_completed"
		or not is_equal_approx(float(memory.get("player_trust", 0.0)), 0.25)
	):
		return _fail("Trade memory event did not commit with the item exchange.")
	if not store.validate_integrity().is_empty():
		return _fail("Trade left invalid canonical runtime state.")
	var committed_snapshot := store.capture_reconciliation_snapshot()
	var replay := service.apply(receipt)
	if not replay.applied or not replay.idempotent:
		return _fail("Trade receipt replay was not idempotent: " + replay.error)
	if store.capture_reconciliation_snapshot() != committed_snapshot:
		return _fail("Trade receipt replay repeated canonical mutations.")
	return true


func _verify_rejections() -> bool:
	var cases := [
		{
			"name": "duplicate application",
			"change": func(_store, receipt):
				receipt.mutations.append(receipt.mutations[-1].duplicate(true)),
		},
		{
			"name": "forged received item",
			"change": func(_store, receipt):
				receipt.mutations[-1]["received_item_state"]["current_condition"] = 999.0,
		},
		{
			"name": "forged trust",
			"change": func(_store, receipt):
				receipt.mutations[-1]["memory_event"]["trust_delta"] = 12.0,
		},
		{
			"name": "stale counterparty",
			"change": func(store, _receipt):
				store.patch_entity_record(ENEMY_ID, {"knowledge": {"stale": true}}),
		},
	]
	for test_case in cases:
		var store := _fixture_store()
		var service := WorldActionApplicationService.new()
		service.configure(store)
		var receipt := _receipt(
			store,
			"trade-reject-" + str(test_case["name"]).replace(" ", "-")
		)
		(test_case["change"] as Callable).call(store, receipt)
		if not _expect_rejected_unchanged(
			store, service, receipt, str(test_case["name"])
		):
			return false
	var remote := _fixture_store()
	var remote_coords := COORDS + Vector2i(1, 0)
	remote.set_hex_record(remote_coords, HexRecord.new())
	var remote_service := WorldActionApplicationService.new()
	remote_service.configure(remote)
	var remote_receipt := _receipt(remote, "trade-reject-remote", remote_coords)
	if not _expect_rejected_unchanged(
		remote, remote_service, remote_receipt, "remote receipt coordinate"
	):
		return false
	return true


func _fixture_store() -> RuntimeStateStore:
	var store := RuntimeStateStore.new()
	store.begin_new_world("TRADE_WORLD_ACTION_TRANSACTION")
	var definition := preload("res://BiologicalCore/player_def.tres") as EntityDefinition
	var core := EntityFactory.record_to_humanoid_core({
		"entity_id": "player",
		"definition": definition.to_state(),
		"runtime": {},
	}, null, "TradeTransactionFixture")
	if core == null:
		_fail("Could not construct trade transaction actor.")
		return null
	var offer_definition := load("res://ItemCore/Items/water_bottle.tres") as ItemData
	var offer := offer_definition.create_runtime_instance()
	offer.instance_id = OFFER_ID
	if not core.inventory.add_to_backpack(offer):
		core.free()
		_fail("Could not seed the player trade offer.")
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
		_fail("Could not seed the canonical trade actor.")
		return null
	store.set_campaign_state({"seed": store.world_seed}, "trade-node", 0)
	var received_definition := load("res://ItemCore/Items/bandage.tres") as ItemData
	var received := received_definition.create_runtime_instance().to_runtime_state()
	received["instance_id"] = RECEIVED_ID
	received["owner_id"] = ENEMY_ID
	received["physical_location"] = "inventory"
	var enemy := EntityRecord.new()
	enemy.entity_id = ENEMY_ID
	enemy.coords = COORDS
	enemy.world_status = GameEnums.EntityWorldStatus.CEASEFIRE
	enemy.definition = {
		"allows_trade": true,
		"npc_role_id": "salvager",
		"loadout": {},
	}
	enemy.runtime = {"inventory_items": [received], "npc_role_id": "salvager"}
	if store.register_entity(enemy).is_empty():
		_fail("Could not seed the canonical trade counterparty.")
		return null
	store.set_relationship(
		"player", ENEMY_ID, CombatRelationshipLedger.Relation.NEUTRAL
	)
	store.set_hex_record(COORDS, HexRecord.new())
	if not store.validate_integrity().is_empty():
		_fail("Trade fixture failed canonical integrity.")
		return null
	return store


func _receipt(
	store: RuntimeStateStore,
	action_id: String,
	target_coords: Vector2i = COORDS
) -> WorldActionReceipt:
	var enemy := store.get_entity_snapshot(ENEMY_ID)
	var received: Dictionary = enemy.get("runtime", {}).get(
		"inventory_items", []
	)[0].duplicate(true)
	received["owner_id"] = "player"
	received["physical_location"] = "inventory"
	var request := WorldActionRequest.new()
	request.actor_id = "player"
	request.target_id = ENEMY_ID
	request.target_coords = target_coords
	request.verb_id = WorldActionTradeTransactionService.VERB_ID
	request.expected_actor_revision = store.player_record.revision
	request.payload = {
		"action_id": action_id,
		"node_id": store.active_node_id,
		"world_time_minutes": store.world_time_minutes,
		"expected_hex_revision": store.get_hex_record(target_coords).revision,
	}
	var reservation := store.begin_world_action(request)
	var receipt := WorldActionResolver.resolve_direct_action(
		request,
		WorldActionTradeTransactionService.ELAPSED_MINUTES,
		WorldActionTradeTransactionService.EXERTION,
		0.0,
		"Trade transaction fixture."
	)
	receipt.node_id = store.active_node_id
	receipt.action_id = reservation.action_id
	receipt.receipt_id = reservation.next_receipt_id()
	receipt.expected_hex_revision = store.get_hex_record(target_coords).revision
	receipt.mutations.append({
		"type": WorldActionTradeTransactionService.MUTATION_TYPE,
		"expected_enemy_revision": int(enemy.get("revision", -1)),
		"offered_instance_id": OFFER_ID,
		"received_item_state": received,
		"received_source": "inventory",
		"memory_event": {
			"turn": 8,
			"coords": target_coords,
			"trust_delta": 0.25,
		},
	})
	return receipt


func _expect_rejected_unchanged(
	store: RuntimeStateStore,
	service: WorldActionApplicationService,
	receipt: WorldActionReceipt,
	label: String
) -> bool:
	var before := store.capture_reconciliation_snapshot()
	var application := service.apply(receipt)
	if application.applied or application.error.is_empty():
		return _fail("Malformed trade was accepted: " + label)
	if store.capture_reconciliation_snapshot() != before:
		return _fail("Rejected trade partially mutated state: " + label)
	store.cancel_world_action(receipt.action_id)
	return true


func _fail(message: String) -> bool:
	push_error("[TRADE WORLD ACTION TRANSACTION] " + message)
	quit(1)
	return false
