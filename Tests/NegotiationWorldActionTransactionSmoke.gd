extends SceneTree

const SAVE_PATH := "res://.godot/test-logs/negotiation_world_action_transaction.json"
const ENEMY_ID := "negotiation-transaction-enemy"
const COORDS := Vector2i(2, -1)
const ELAPSED_MINUTES := 15


func _initialize() -> void:
	call_deferred("_run")


func _run() -> bool:
	if not _verify_atomic_intimidation():
		return false
	if not _verify_ceasefire_and_combat_outcomes():
		return false
	if not _verify_rejections():
		return false
	if not _verify_deterministic_surrender_identity():
		return false
	print("NEGOTIATION_WORLD_ACTION_TRANSACTION_SMOKE: PASS")
	quit(0)
	return true


func _verify_atomic_intimidation() -> bool:
	var store := _fixture_store()
	if store == null:
		return false
	var service := WorldActionApplicationService.new()
	service.configure(store)
	var starting_time := store.world_time_minutes
	var starting_player_revision := store.player_record.revision
	var starting_enemy := store.get_entity_snapshot(ENEMY_ID)
	var receipt := _receipt(
		store,
		"negotiation-intimidated",
		GameEnums.NegotiationOutcome.INTIMIDATED,
		GameEnums.EntityWorldStatus.WITHDRAWN,
		CombatRelationshipLedger.Relation.NEUTRAL,
		"player_intimidated",
		-3.0,
		8.0,
		{"main_hand": "", "starting_items": []},
		[_ground_item("negotiation-drop-a"), _ground_item("negotiation-drop-b")]
	)
	var application := service.apply(receipt)
	if not application.applied or application.idempotent:
		return _fail("Atomic intimidation failed: " + application.error)
	var enemy := store.get_entity_snapshot(ENEMY_ID)
	if store.player_record.revision != starting_player_revision + 1:
		return _fail("Negotiation did not advance the player revision once.")
	if int(enemy.get("revision", -1)) != int(starting_enemy.get("revision", -1)) + 1:
		return _fail("Negotiation did not advance the enemy revision once.")
	if int(enemy.get("negotiation_attempts", -1)) != 1:
		return _fail("Negotiation did not advance the target attempt once.")
	if int(enemy.get("world_status", -1)) != GameEnums.EntityWorldStatus.WITHDRAWN:
		return _fail("Intimidated target did not become withdrawn.")
	if store.get_entity_id_at(COORDS) == ENEMY_ID:
		return _fail("Withdrawn target retained an active coordinate index.")
	if store.relationship_between("player", ENEMY_ID) != CombatRelationshipLedger.Relation.NEUTRAL:
		return _fail("Intimidation did not neutralize the canonical relationship.")
	if enemy.get("definition", {}).get("loadout", {}).get("main_hand", "missing") != "":
		return _fail("Intimidation did not commit the surrendered loadout.")
	var memory: Dictionary = enemy.get("runtime", {}).get("macro_ai", {}).get("memory", {})
	if (
		not is_equal_approx(float(memory.get("player_trust", 0.0)), -3.0)
		or not is_equal_approx(float(memory.get("player_threat", 0.0)), 8.0)
		or str(memory.get("events", [])[-1].get("id", "")) != "player_intimidated"
	):
		return _fail("Intimidation did not commit its semantic memory event.")
	if store.world_time_minutes != starting_time + ELAPSED_MINUTES:
		return _fail("Negotiation did not advance world time exactly once.")
	for instance_id in ["negotiation-drop-a", "negotiation-drop-b"]:
		var ownership := store.find_item_ownership(instance_id)
		if str(ownership.get("location", "")) != "ground":
			return _fail("Surrender gear did not gain one ground owner: " + instance_id)
	if store.get_world_action_reservation(receipt.action_id) != null:
		return _fail("Completed negotiation retained its reservation.")
	if not store.validate_integrity().is_empty():
		return _fail("Negotiation broke canonical runtime integrity.")
	var committed_snapshot := store.capture_reconciliation_snapshot()
	var replay := service.apply(receipt)
	if not replay.applied or not replay.idempotent:
		return _fail("Negotiation replay was not idempotent: " + replay.error)
	if store.capture_reconciliation_snapshot() != committed_snapshot:
		return _fail("Negotiation replay repeated canonical mutations.")
	if not _verify_save_load(store, receipt, committed_snapshot):
		return false
	return true


func _verify_save_load(
	store: RuntimeStateStore,
	receipt: WorldActionReceipt,
	expected_snapshot: Dictionary
) -> bool:
	var absolute_path := ProjectSettings.globalize_path(SAVE_PATH)
	var directory := absolute_path.get_base_dir()
	if not DirAccess.dir_exists_absolute(directory):
		DirAccess.make_dir_recursive_absolute(directory)
	if not store.save_to_disk(SAVE_PATH):
		return _fail("Could not save canonical negotiation state.")
	var loaded := RuntimeStateStore.new()
	if not loaded.load_from_disk(SAVE_PATH):
		return _fail("Could not reload canonical negotiation state.")
	var enemy := loaded.get_entity_snapshot(ENEMY_ID)
	if (
		int(enemy.get("world_status", -1)) != GameEnums.EntityWorldStatus.WITHDRAWN
		or int(enemy.get("negotiation_attempts", -1)) != 1
		or loaded.find_item_ownership("negotiation-drop-a").is_empty()
	):
		return _fail("Save/load lost committed negotiation state.")
	var service := WorldActionApplicationService.new()
	service.configure(loaded)
	var loaded_snapshot := loaded.capture_reconciliation_snapshot()
	var replay := service.apply(receipt)
	if not replay.applied or not replay.idempotent:
		return _fail("Negotiation lost replay identity across save/load.")
	if loaded.capture_reconciliation_snapshot() != loaded_snapshot:
		return _fail("Loaded negotiation replay mutated canonical state.")
	if expected_snapshot.get("applied_world_receipts", {}) != loaded_snapshot.get(
		"applied_world_receipts", {}
	):
		return _fail("Save/load changed applied negotiation receipt history.")
	DirAccess.remove_absolute(absolute_path)
	return true


func _verify_ceasefire_and_combat_outcomes() -> bool:
	var cases := [
		{
			"name": "ceasefire",
			"outcome": GameEnums.NegotiationOutcome.CEASEFIRE,
			"status": GameEnums.EntityWorldStatus.CEASEFIRE,
			"relationship": CombatRelationshipLedger.Relation.NEUTRAL,
			"event": "ceasefire_reached",
			"trust": 3.0,
			"threat": 0.0,
		},
		{
			"name": "combat",
			"outcome": GameEnums.NegotiationOutcome.COMBAT,
			"status": WorldActionNegotiationTransactionService.NO_CHANGE,
			"relationship": WorldActionNegotiationTransactionService.NO_CHANGE,
			"event": "talk_broke_down",
			"trust": -2.0,
			"threat": 5.0,
		},
	]
	for test_case in cases:
		var store := _fixture_store()
		var service := WorldActionApplicationService.new()
		service.configure(store)
		var receipt := _receipt(
			store,
			"negotiation-" + str(test_case["name"]),
			int(test_case["outcome"]),
			int(test_case["status"]),
			int(test_case["relationship"]),
			str(test_case["event"]),
			float(test_case["trust"]),
			float(test_case["threat"])
		)
		var result := service.apply(receipt)
		if not result.applied:
			return _fail(str(test_case["name"]) + " negotiation failed: " + result.error)
		var enemy := store.get_entity_snapshot(ENEMY_ID)
		var expected_status := (
			GameEnums.EntityWorldStatus.HOSTILE
			if int(test_case["status"]) == WorldActionNegotiationTransactionService.NO_CHANGE
			else int(test_case["status"])
		)
		if int(enemy.get("world_status", -1)) != expected_status:
			return _fail(str(test_case["name"]) + " committed the wrong world status.")
		var expected_relationship := (
			CombatRelationshipLedger.Relation.HOSTILE
			if int(test_case["relationship"]) == WorldActionNegotiationTransactionService.NO_CHANGE
			else int(test_case["relationship"])
		)
		if store.relationship_between("player", ENEMY_ID) != expected_relationship:
			return _fail(str(test_case["name"]) + " committed the wrong relationship.")
	return true


func _verify_rejections() -> bool:
	var remote_coords := COORDS + Vector2i(1, 0)
	var store := _fixture_store()
	var service := WorldActionApplicationService.new()
	service.configure(store)
	var stale := _receipt(
		store, "negotiation-stale", GameEnums.NegotiationOutcome.CEASEFIRE,
		GameEnums.EntityWorldStatus.CEASEFIRE,
		CombatRelationshipLedger.Relation.NEUTRAL,
		"ceasefire_reached", 3.0, 0.0
	)
	if not store.patch_entity_record(ENEMY_ID, {"knowledge": {"revision_probe": true}}):
		return _fail("Could not create stale negotiation fixture.")
	if not _expect_rejected_unchanged(store, service, stale, "stale enemy revision"):
		return false
	store = _fixture_store()
	store.set_hex_record(remote_coords, HexRecord.new())
	service = WorldActionApplicationService.new()
	service.configure(store)
	var remote_target := _receipt(
		store, "negotiation-remote-target", GameEnums.NegotiationOutcome.CEASEFIRE,
		GameEnums.EntityWorldStatus.CEASEFIRE,
		CombatRelationshipLedger.Relation.NEUTRAL,
		"ceasefire_reached", 3.0, 0.0, {}, [], remote_coords, COORDS
	)
	if not _expect_rejected_unchanged(
		store, service, remote_target, "remote target coordinate"
	):
		return false
	store = _fixture_store()
	service = WorldActionApplicationService.new()
	service.configure(store)
	var forged_player_coords := _receipt(
		store, "negotiation-forged-player-coords",
		GameEnums.NegotiationOutcome.CEASEFIRE,
		GameEnums.EntityWorldStatus.CEASEFIRE,
		CombatRelationshipLedger.Relation.NEUTRAL,
		"ceasefire_reached", 3.0, 0.0, {}, [], COORDS, remote_coords
	)
	if not _expect_rejected_unchanged(
		store, service, forged_player_coords, "forged player coordinate"
	):
		return false
	var cases := [
		{
			"name": "duplicate application",
			"change": func(r): r.mutations.append(r.mutations[-1].duplicate(true)),
		},
		{
			"name": "skipped attempt",
			"change": func(r): r.mutations[-1]["next_negotiation_attempt"] = 3,
		},
		{
			"name": "wrong intimidated status",
			"change": func(r): r.mutations[-1]["next_world_status"] = GameEnums.EntityWorldStatus.CEASEFIRE,
		},
		{
			"name": "outcome memory mismatch",
			"change": func(r): r.mutations[-1]["memory_event"]["trust_delta"] = 12.0,
		},
		{
			"name": "duplicate surrender identity",
			"change": func(r): r.mutations[-1]["created_ground_items"].append(r.mutations[-1]["created_ground_items"][0].duplicate(true)),
		},
		{
			"name": "independent ground mutation",
			"change": func(r): r.mutations.append({"type": "add_ground_item", "item_state": _ground_item("extra-ground")}),
		},
	]
	for test_case in cases:
		store = _fixture_store()
		service = WorldActionApplicationService.new()
		service.configure(store)
		var receipt := _receipt(
			store,
			"negotiation-reject-" + str(test_case["name"]).replace(" ", "-"),
			GameEnums.NegotiationOutcome.INTIMIDATED,
			GameEnums.EntityWorldStatus.WITHDRAWN,
			CombatRelationshipLedger.Relation.NEUTRAL,
			"player_intimidated",
			-3.0,
			8.0,
			{},
			[_ground_item("duplicate-surrender")]
		)
		(test_case["change"] as Callable).call(receipt)
		if not _expect_rejected_unchanged(store, service, receipt, str(test_case["name"])):
			return false
	return true


func _verify_deterministic_surrender_identity() -> bool:
	var definition := {
		"loadout": {
			"main_hand": "res://ItemCore/Items/crowbar.tres",
			"starting_items": ["res://ItemCore/Items/water_bottle.tres"],
		},
	}
	var catalog := root.get_node_or_null("/root/LootCatalog")
	if catalog == null:
		return _fail("LootCatalog autoload is unavailable for determinism proof.")
	var first := MacroInteractionResolver.resolve_threat_surrender(
		"NEGOTIATION_DETERMINISM", ENEMY_ID, 4, definition, catalog
	)
	var second := MacroInteractionResolver.resolve_threat_surrender(
		"NEGOTIATION_DETERMINISM", ENEMY_ID, 4, definition, catalog
	)
	var first_ids := _item_ids(first.get("ground_items", []))
	var second_ids := _item_ids(second.get("ground_items", []))
	if first_ids.is_empty() or first_ids != second_ids:
		return _fail("Surrender re-resolution changed deterministic item identity.")
	return true


func _fixture_store() -> RuntimeStateStore:
	var store := RuntimeStateStore.new()
	store.begin_new_world("NEGOTIATION_WORLD_ACTION_TRANSACTION")
	var definition := preload("res://BiologicalCore/player_def.tres") as EntityDefinition
	var core := EntityFactory.record_to_humanoid_core({
		"entity_id": "player",
		"definition": definition.to_state(),
		"runtime": {},
	}, null, "NegotiationTransactionFixture")
	if core == null:
		_fail("Could not construct negotiation transaction actor.")
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
		_fail("Could not seed canonical negotiation actor.")
		return null
	store.set_campaign_state({"seed": store.world_seed}, "negotiation-node", 0)
	var enemy := EntityRecord.new()
	enemy.entity_id = ENEMY_ID
	enemy.coords = COORDS
	enemy.world_status = GameEnums.EntityWorldStatus.HOSTILE
	enemy.definition = {
		"faction": GameEnums.Faction.SCAVENGER_CELL,
		"loadout": {"main_hand": "crowbar", "starting_items": ["water"]},
	}
	enemy.runtime = {"npc_role_id": "raider"}
	if store.register_entity(enemy).is_empty():
		_fail("Could not seed canonical negotiation target.")
		return null
	store.set_relationship("player", ENEMY_ID, CombatRelationshipLedger.Relation.HOSTILE)
	store.set_hex_record(COORDS, HexRecord.new())
	return store


func _receipt(
	store: RuntimeStateStore,
	action_id: String,
	outcome: int,
	next_status: int,
	next_relationship: int,
	event_id: String,
	trust_delta: float,
	threat_delta: float,
	kept_loadout: Dictionary = {},
	created_items: Array = [],
	target_coords: Vector2i = COORDS,
	player_memory_coords: Vector2i = COORDS
) -> WorldActionReceipt:
	var enemy := store.get_entity_snapshot(ENEMY_ID)
	var request := WorldActionRequest.new()
	request.actor_id = "player"
	request.target_id = ENEMY_ID
	request.target_coords = target_coords
	request.verb_id = WorldActionNegotiationTransactionService.VERB_ID
	request.expected_actor_revision = store.player_record.revision
	request.payload = {
		"action_id": action_id,
		"node_id": store.active_node_id,
		"world_time_minutes": store.world_time_minutes,
		"expected_hex_revision": store.get_hex_record(target_coords).revision,
	}
	var reservation := store.begin_world_action(request)
	var receipt := WorldActionResolver.resolve_direct_action(
		request, ELAPSED_MINUTES, 0.1, 0.0, "Negotiation fixture."
	)
	receipt.node_id = store.active_node_id
	receipt.action_id = reservation.action_id
	receipt.receipt_id = reservation.next_receipt_id()
	receipt.expected_hex_revision = store.get_hex_record(target_coords).revision
	receipt.mutations.append({
		"type": WorldActionNegotiationTransactionService.MUTATION_TYPE,
		"expected_enemy_revision": int(enemy.get("revision", -1)),
		"expected_negotiation_attempt": int(enemy.get("negotiation_attempts", -1)),
		"next_negotiation_attempt": int(enemy.get("negotiation_attempts", -1)) + 1,
		"outcome": outcome,
		"npc_role_id": "raider",
		"memory_event": {
			"id": event_id,
			"turn": 7,
			"coords": player_memory_coords,
			"trust_delta": trust_delta,
			"threat_delta": threat_delta,
		},
		"next_world_status": next_status,
		"next_relationship": next_relationship,
		"ground_coords": player_memory_coords,
		"kept_loadout": kept_loadout.duplicate(true),
		"created_ground_items": created_items.duplicate(true),
	})
	return receipt


func _ground_item(instance_id: String) -> Dictionary:
	var definition := load("res://ItemCore/Items/water_bottle.tres") as ItemData
	var state := definition.create_runtime_instance().to_runtime_state()
	state["instance_id"] = instance_id
	state["owner_id"] = ""
	state["physical_location"] = "ground"
	state["equipped_slot"] = GameEnums.EquipmentSlot.NONE
	return state


func _item_ids(values: Array) -> Array[String]:
	var ids: Array[String] = []
	for value in values:
		if value is Dictionary:
			ids.append(str(value.get("instance_id", "")))
	return ids


func _expect_rejected_unchanged(
	store: RuntimeStateStore,
	service: WorldActionApplicationService,
	receipt: WorldActionReceipt,
	label: String
) -> bool:
	var before := store.capture_reconciliation_snapshot()
	var application := service.apply(receipt)
	if application.applied or application.error.is_empty():
		return _fail("Malformed negotiation was accepted: " + label)
	if store.capture_reconciliation_snapshot() != before:
		return _fail("Rejected negotiation partially mutated state: " + label)
	store.cancel_world_action(receipt.action_id)
	return true


func _fail(message: String) -> bool:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	push_error("[NEGOTIATION WORLD ACTION TRANSACTION] " + message)
	quit(1)
	return false
