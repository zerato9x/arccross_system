extends SceneTree

const COORDS := Vector2i.ZERO
const ELAPSED_MINUTES := 15
const SEARCH_TARGET := "fixture-a"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if not _test_canonical_search_and_replay():
		return
	if not _test_physical_target_depletion():
		return
	if not _test_stale_and_malformed_rollback():
		return
	print("SEARCH_WORLD_ACTION_TRANSACTION_SMOKE: PASS")
	quit(0)


func _test_canonical_search_and_replay() -> bool:
	var store := _build_store(false)
	if store == null:
		return false
	var expected_core := EntityFactory.record_to_humanoid_core(
		store.player_record.to_dict(), null, "SearchExpectedActor"
	)
	expected_core.body.apply_targeted_hit(
		GameEnums.LimbRegion.LEFT_ARM,
		3.0,
		0.0
	)
	expected_core.process_survival_time(ELAPSED_MINUTES, 15.0, 1.0, 0.0)
	expected_core.reconcile_terminal_state()
	var expected_fatigue := expected_core.body.fatigue
	var expected_blood := expected_core.body.blood_level
	var expected_limb_hp: float = expected_core.body.limb_hp[
		GameEnums.LimbRegion.LEFT_ARM
	]
	var expected_wound_count: int = expected_core.body.get_wounds_for_limb(
		GameEnums.LimbRegion.LEFT_ARM
	).size()
	expected_core.free()

	var actor_revision := store.player_record.revision
	var hex_before := store.get_hex_record(COORDS)
	var hex_revision := hex_before.revision
	var time_before := store.world_time_minutes
	var camp_items_before := hex_before.camp_item_states.duplicate(true)
	var receipt := _search_receipt(
		store,
		"search-success",
		0,
		SEARCH_TARGET,
		{},
		[
			{"type": "add_ground_item", "item_state": _item("search-loot")},
			{"type": "set_run_flag", "key": "search_fixture_complete", "value": true},
			{
				"type": "biological_hit",
				"limb_region": GameEnums.LimbRegion.LEFT_ARM,
				"damage": 3.0,
				"armor": 0.0,
			},
		]
	)
	var service := WorldActionApplicationService.new()
	service.configure(store)
	var application := service.apply(receipt)
	if not application.applied or application.idempotent:
		return _fail("Valid canonical search was rejected: " + application.error)
	var committed_hex := store.get_hex_record(COORDS)
	if committed_hex.search_count != 1:
		return _fail("Search did not increment canonical search count exactly once.")
	if committed_hex.searched_targets != [SEARCH_TARGET]:
		return _fail("Search did not commit its semantic searched-target identity.")
	if committed_hex.camp_item_states != camp_items_before:
		return _fail("Search overwrote unrelated canonical camp state.")
	if committed_hex.revision != hex_revision + 1:
		return _fail("Search did not advance hex revision exactly once.")
	if store.player_record.revision != actor_revision + 1:
		return _fail("Search did not advance actor revision exactly once.")
	var committed_core := EntityFactory.record_to_humanoid_core(
		store.player_record.to_dict(), null, "SearchCommittedActor"
	)
	if (
		not is_equal_approx(committed_core.body.fatigue, expected_fatigue)
		or not is_equal_approx(committed_core.body.blood_level, expected_blood)
		or not is_equal_approx(
			committed_core.body.limb_hp[GameEnums.LimbRegion.LEFT_ARM],
			expected_limb_hp
		)
		or committed_core.body.get_wounds_for_limb(
			GameEnums.LimbRegion.LEFT_ARM
		).size() != expected_wound_count
	):
		committed_core.free()
		return _fail("Search injury and elapsed survival were not staged canonically.")
	committed_core.free()
	if store.world_time_minutes != time_before + ELAPSED_MINUTES:
		return _fail("Search did not advance world time exactly once.")
	if store.get_ground_items(COORDS).size() != 1:
		return _fail("Search loot was not inserted exactly once.")
	if not bool(store.get_run_flags_snapshot().get("search_fixture_complete", false)):
		return _fail("Search run-flag patch was not committed.")
	if not store.validate_integrity().is_empty():
		return _fail("Committed search failed runtime/item ownership integrity.")

	var after_commit := store.capture_reconciliation_snapshot()
	var replay := service.apply(receipt)
	if not replay.applied or not replay.idempotent:
		return _fail("Search receipt replay was not idempotent.")
	if store.capture_reconciliation_snapshot() != after_commit:
		return _fail("Search replay repeated loot, injury, time, or depletion.")

	var save_path := "res://.godot/test-logs/search_world_action_transaction.json"
	if not store.save_to_disk(save_path):
		return _fail("Could not save committed search state.")
	var loaded := RuntimeStateStore.new()
	if not loaded.load_from_disk(save_path):
		return _fail("Could not reload committed search state.")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	if loaded.get_hex_record(COORDS).searched_targets != [SEARCH_TARGET]:
		return _fail("Save/load lost semantic search depletion.")
	if loaded.get_ground_items(COORDS).size() != 1:
		return _fail("Save/load lost or duplicated committed search loot.")
	return true


func _test_physical_target_depletion() -> bool:
	var store := _build_store(true)
	var target := WorldObjectRecord.from_dict(
		store.get_hex_record(COORDS).world_objects[0]
	)
	var target_state := target.to_dict()
	var container: Dictionary = target_state.get("components", {}).get(
		"container", {}
	).duplicate(true)
	container["remaining_searches"] = 0
	container["depleted"] = true
	target_state["components"]["container"] = container
	var receipt := _search_receipt(
		store,
		"search-physical-target",
		0,
		target.object_id,
		target_state,
		[{
			"type": "append_trace",
			"trace": {
				"kind": "disturbed_rubble",
				"source_id": "player",
				"coords": COORDS,
				"created_minute": store.world_time_minutes,
				"expires_minute": store.world_time_minutes + 120,
			},
		}]
	)
	var service := WorldActionApplicationService.new()
	service.configure(store)
	var application := service.apply(receipt)
	if not application.applied:
		return _fail("Physical search transaction was rejected: " + application.error)
	var committed_hex := store.get_hex_record(COORDS)
	var committed_target := WorldObjectRecord.from_dict(committed_hex.world_objects[0])
	if committed_target.revision != target.revision + 1:
		return _fail("Physical search did not advance target revision exactly once.")
	if not bool(committed_target.component("container").get("depleted", false)):
		return _fail("Physical search did not commit canonical target depletion.")
	if committed_hex.search_count != 1 or not committed_hex.searched_targets.has(target.object_id):
		return _fail("Physical search did not commit semantic hex depletion.")
	if committed_hex.trace_records.size() != 1:
		return _fail("Physical search did not append exactly one disturbance trace.")
	return true


func _test_stale_and_malformed_rollback() -> bool:
	var stale_store := _build_store(false)
	var stale_receipt := _search_receipt(
		stale_store, "search-stale", 0, SEARCH_TARGET
	)
	stale_store.update_player_runtime(
		stale_store.player_record.runtime.duplicate(true), COORDS
	)
	if not _assert_rejected_without_mutation(
		stale_store, stale_receipt, "Stale search actor revision"
	):
		return false

	for kind in [
		"wrong_count",
		"duplicate",
		"wrong_target",
		"wrong_verb",
		"actor_state",
		"replace_hex",
		"duplicate_flag",
		"physical_without_trace",
	]:
		var physical: bool = str(kind) == "physical_without_trace"
		var store := _build_store(physical)
		var target_state: Dictionary = {}
		var searched_target := SEARCH_TARGET
		if physical:
			var target := WorldObjectRecord.from_dict(
				store.get_hex_record(COORDS).world_objects[0]
			)
			target_state = target.to_dict()
			searched_target = target.object_id
		var receipt := _search_receipt(
			store,
			"search-malformed-" + kind,
			0,
			searched_target,
			target_state
		)
		match kind:
			"wrong_count":
				receipt.mutations[1]["expected_search_count"] = 1
			"duplicate":
				receipt.mutations.append(receipt.mutations[1].duplicate(true))
			"wrong_target":
				receipt.target_id = "forged-search-target"
			"wrong_verb":
				receipt.verb_id = "inspect"
			"actor_state":
				receipt.actor_state = store.player_record.runtime.duplicate(true)
			"replace_hex":
				receipt.mutations.append({
					"type": "replace_hex_state",
					"hex_state": store.get_hex_record(COORDS).to_dict(),
				})
			"duplicate_flag":
				receipt.mutations.append({"type": "set_run_flag", "key": "same", "value": true})
				receipt.mutations.append({"type": "set_run_flag", "key": "same", "value": false})
		if not _assert_rejected_without_mutation(store, receipt, kind):
			return false

	var repeated_store := _build_store(false)
	var first := _search_receipt(
		repeated_store, "search-first", 0, SEARCH_TARGET
	)
	var service := WorldActionApplicationService.new()
	service.configure(repeated_store)
	if not service.apply(first).applied:
		return _fail("Could not establish already-searched fixture.")
	var repeated := _search_receipt(
		repeated_store, "search-repeat-target", 1, SEARCH_TARGET
	)
	if not _assert_rejected_without_mutation(
		repeated_store, repeated, "Already-searched target"
	):
		return false
	return true


func _build_store(with_target: bool) -> RuntimeStateStore:
	var store := RuntimeStateStore.new()
	store.begin_new_world("SEARCH_WORLD_ACTION_TRANSACTION")
	var definition := preload("res://BiologicalCore/player_def.tres") as EntityDefinition
	var core := EntityFactory.record_to_humanoid_core({
		"entity_id": "player",
		"definition": definition.to_state(),
		"runtime": {},
	}, null, "SearchTransactionFixture")
	if core == null:
		_fail("Could not construct search transaction actor.")
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
		_fail("Could not seed canonical search actor.")
		return null
	store.set_campaign_state({"seed": store.world_seed}, "search-node", 0)
	var hex := HexRecord.new()
	hex.camp_item_states = [{
		"instance_id": "unrelated-camp-gear",
		"definition": {"id": "camp_fixture"},
		"owner_id": "",
		"physical_location": "camp",
	}]
	if with_target:
		var target := WorldObjectRecord.new()
		target.object_id = "physical-search-target"
		target.node_id = store.active_node_id
		target.coords = COORDS
		target.components["container"] = {
			"finite": true,
			"remaining_searches": 1,
			"depleted": false,
		}
		hex.world_objects.append(target.to_dict())
	store.set_hex_record(COORDS, hex)
	return store


func _search_receipt(
	store: RuntimeStateStore,
	requested_action_id: String,
	expected_search_count: int,
	searched_target_id: String,
	target_state: Dictionary = {},
	extra_mutations: Array = []
) -> WorldActionReceipt:
	var request := WorldActionRequest.new()
	request.actor_id = "player"
	request.target_id = (
		str(target_state.get("object_id", ""))
		if not target_state.is_empty()
		else "search:" + str(COORDS)
	)
	request.target_coords = COORDS
	request.verb_id = WorldActionSearchTransactionService.VERB_ID
	request.expected_actor_revision = store.player_record.revision
	request.expected_target_revision = int(target_state.get("revision", -1))
	request.payload = {
		"action_id": requested_action_id,
		"world_time_minutes": store.world_time_minutes,
		"expected_hex_revision": store.get_hex_record(COORDS).revision,
	}
	var reservation := store.begin_world_action(request)
	var receipt := WorldActionResolver.resolve_direct_action(
		request, ELAPSED_MINUTES, 1.0, 0.0, "Search transaction fixture."
	)
	receipt.node_id = store.active_node_id
	receipt.expected_hex_revision = store.get_hex_record(COORDS).revision
	receipt.action_id = reservation.action_id
	receipt.receipt_id = reservation.next_receipt_id()
	receipt.target_state = target_state.duplicate(true)
	receipt.mutations.append({
		"type": WorldActionSearchTransactionService.MUTATION_TYPE,
		"expected_search_count": expected_search_count,
		"searched_target_id": searched_target_id,
	})
	receipt.mutations.append_array(extra_mutations)
	return receipt


func _item(instance_id: String) -> Dictionary:
	var definition := load("res://ItemCore/Items/water_bottle.tres") as ItemData
	var state := definition.create_runtime_instance().to_runtime_state()
	state["instance_id"] = instance_id
	state["owner_id"] = ""
	state["physical_location"] = "ground"
	state["equipped_slot"] = GameEnums.EquipmentSlot.NONE
	return state


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
