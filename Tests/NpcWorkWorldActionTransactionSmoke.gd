extends SceneTree

const SAVE_PATH := "res://.godot/test-logs/npc_work_world_action_transaction.json"
const ACTOR_ID := "npc-work-transaction-worker"
const TARGET_ID := "npc-work-transaction-target"
const COORDS := Vector2i.ZERO


func _initialize() -> void:
	call_deferred("_run")


func _run() -> bool:
	var store := _fixture_store()
	var service := WorldActionApplicationService.new()
	service.configure(store)
	var starting_time := store.world_time_minutes
	var first := _work_receipt(store, "npc-repair-session", 0, false)
	var first_snapshot := store.capture_reconciliation_snapshot()
	var first_application := service.apply(first)
	if not first_application.applied or first_application.idempotent:
		return _fail("First NPC work cycle failed: " + first_application.error)
	var after_first := store.get_entity_snapshot(ACTOR_ID)
	var first_runtime: Dictionary = after_first.get("runtime", {})
	if str(first_runtime.get("world_work", {}).get("action_id", "")) != first.action_id:
		return _fail("Incomplete NPC work did not persist semantic progress.")
	if int(first_runtime.get("world_work", {}).get("completed_units", -1)) != 1:
		return _fail("Incomplete NPC work persisted the wrong completed-unit count.")
	if int(after_first.get("revision", -1)) != int(first_snapshot["entities"][ACTOR_ID]["revision"]) + 1:
		return _fail("First NPC work cycle did not advance actor revision once.")
	if not _has_item(first_runtime, "npc-material", 1):
		return _fail("First NPC repair did not consume exactly one material unit.")
	if not is_equal_approx(_condition(first_runtime, "npc-tool"), 9.75):
		return _fail("First NPC repair did not apply tool wear exactly once.")
	if store.world_time_minutes != starting_time + 15:
		return _fail("First NPC work cycle did not advance world time once.")
	if store.get_world_action_reservation(first.action_id) == null:
		return _fail("Incomplete NPC work released its continuation reservation.")
	var after_first_snapshot := store.capture_reconciliation_snapshot()
	var replay := service.apply(first)
	if not replay.applied or not replay.idempotent:
		return _fail("NPC work receipt replay was not idempotent: " + replay.error)
	if store.capture_reconciliation_snapshot() != after_first_snapshot:
		return _fail("NPC work replay repeated a mutation.")

	var second := _work_receipt(store, first.action_id, 1, true)
	var second_application := service.apply(second)
	if not second_application.applied or second_application.idempotent:
		return _fail("Final NPC work cycle failed: " + second_application.error)
	var after_second := store.get_entity_snapshot(ACTOR_ID)
	var second_runtime: Dictionary = after_second.get("runtime", {})
	if second_runtime.has("world_work"):
		return _fail("Completed NPC work left stale progress in canonical runtime.")
	if _has_item(second_runtime, "npc-material"):
		return _fail("Final NPC repair did not consume the final material unit.")
	if not is_equal_approx(_condition(second_runtime, "npc-tool"), 9.5):
		return _fail("Final NPC repair did not apply its tool wear once.")
	if int(after_second.get("revision", -1)) != int(after_first.get("revision", -1)) + 1:
		return _fail("Final NPC work cycle did not advance actor revision once.")
	if store.world_time_minutes != starting_time + 30:
		return _fail("Two NPC work cycles did not advance time exactly twice.")
	if store.get_world_action_reservation(first.action_id) != null:
		return _fail("Completed NPC work retained its reservation.")
	if not store.validate_integrity().is_empty():
		return _fail("NPC work consumption broke canonical item ownership.")

	if not _verify_save_load(store, second):
		return false
	if not _verify_rejections(store, service):
		return false
	if not _verify_atomic_search_rejections():
		return false
	print("NPC_WORK_WORLD_ACTION_TRANSACTION_SMOKE: PASS")
	quit(0)
	return true


func _fixture_store() -> RuntimeStateStore:
	var store := RuntimeStateStore.new()
	store.begin_new_world("NPC_WORK_WORLD_ACTION_TRANSACTION")
	store.set_campaign_state({"seed": store.world_seed}, "node-a", 0)
	var actor := EntityRecord.new()
	actor.entity_id = ACTOR_ID
	actor.coords = COORDS
	actor.definition = {"finesse": 9}
	actor.runtime = {
		"inventory_items": [
			_item("npc-tool", "multitool", [], 1, 10.0),
			_item("npc-material", "scrap", ["repair_material"], 2, 10.0),
		],
	}
	store.register_entity(actor)
	var target := WorldObjectRecord.new()
	target.object_id = TARGET_ID
	target.node_id = "node-a"
	target.coords = COORDS
	target.components["repairable"] = {"condition": 0.25}
	var hex := HexRecord.new()
	hex.world_objects = [target.to_dict()]
	store.set_hex_record(COORDS, hex)
	return store


func _work_receipt(
	store: RuntimeStateStore,
	action_id: String,
	completed_units: int,
	complete: bool
) -> WorldActionReceipt:
	var target := _target(store)
	var request := WorldActionRequest.new()
	request.actor_id = ACTOR_ID
	request.target_id = TARGET_ID
	request.target_coords = COORDS
	request.verb_id = WorldActionResolver.VERB_REPAIR
	request.method_id = "multitool"
	request.expected_actor_revision = int(store.get_entity_snapshot(ACTOR_ID).get("revision", -1))
	request.expected_target_revision = target.revision
	request.payload = {
		"action_id": action_id,
		"node_id": store.active_node_id,
		"expected_hex_revision": store.get_hex_record(COORDS).revision,
	}
	var reservation := store.get_world_action_reservation(action_id)
	if reservation == null:
		reservation = store.begin_world_action(request)
	var profile := WorldWorkTaskProfile.new()
	profile.profile_id = "npc-repair-transaction"
	profile.work_units = 2
	profile.base_noise = 0.0
	profile.base_tool_wear = 0.25
	var work_state := {
		"action_id": reservation.action_id,
		"receipt_id": reservation.next_receipt_id(),
		"attempt_index": reservation.attempt_index,
		"completed_units": completed_units,
		"misses": 0,
		"elapsed_minutes": 15,
		"world_time_minutes": store.world_time_minutes,
	}
	var receipt := WorldActionResolver.resolve_work_attempt(
		request, profile, work_state, true
	)
	var next_completed := int(receipt.work_progress * profile.normalized_units())
	var next_work_state := work_state.duplicate(true)
	next_work_state["completed_units"] = next_completed
	receipt.target_state = target.to_dict()
	receipt.mutations.append({
		"type": "consume_material",
		"instance_id": "npc-material",
		"item_id": "scrap",
	})
	receipt.mutations.append({
		"type": WorldActionNpcWorkTransactionService.MUTATION_TYPE,
		"clear_world_work": complete,
		"world_work_state": {} if complete else next_work_state,
	})
	return receipt


func _verify_save_load(store: RuntimeStateStore, final_receipt: WorldActionReceipt) -> bool:
	var directory := ProjectSettings.globalize_path(SAVE_PATH).get_base_dir()
	if not DirAccess.dir_exists_absolute(directory):
		DirAccess.make_dir_recursive_absolute(directory)
	if not store.save_to_disk(SAVE_PATH):
		return _fail("Could not save canonical NPC work state.")
	var loaded := RuntimeStateStore.new()
	if not loaded.load_from_disk(SAVE_PATH):
		return _fail("Could not reload canonical NPC work state.")
	var runtime: Dictionary = loaded.get_entity_snapshot(ACTOR_ID).get("runtime", {})
	if runtime.has("world_work") or _has_item(runtime, "npc-material"):
		return _fail("Save/load restored consumed NPC work state or material.")
	if not is_equal_approx(_condition(runtime, "npc-tool"), 9.5):
		return _fail("Save/load lost canonical NPC tool wear.")
	var loaded_service := WorldActionApplicationService.new()
	loaded_service.configure(loaded)
	var replay := loaded_service.apply(final_receipt)
	if not replay.applied or not replay.idempotent:
		return _fail("NPC work receipt lost idempotence across save/load.")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	return true


func _verify_rejections(
	store: RuntimeStateStore,
	service: WorldActionApplicationService
) -> bool:
	var stale := _rejection_receipt(store, "npc-stale")
	var stale_runtime: Dictionary = store.get_entity_snapshot(ACTOR_ID).get("runtime", {})
	stale_runtime["stale_revision_probe"] = true
	store.update_entity_runtime(ACTOR_ID, stale_runtime)
	if not _expect_rejected_unchanged(store, service, stale, "stale actor revision"):
		return false

	var cases := [
		{"name": "actor snapshot", "change": func(r): r.mutations.append({"type": "replace_actor_runtime"})},
		{"name": "duplicate semantic mutation", "change": func(r): r.mutations.append(r.mutations[-1].duplicate(true))},
		{"name": "player actor", "change": func(r): r.actor_id = "player"},
		{"name": "completion mismatch", "change": func(r): r.mutations[-1]["clear_world_work"] = true},
		{"name": "wrong action identity", "change": func(r): r.mutations[-1]["world_work_state"]["action_id"] = "wrong"},
		{"name": "missing material mutation", "change": func(r): r.mutations.remove_at(1)},
		{"name": "missing target state", "change": func(r): r.target_state = {}},
	]
	for test_case in cases:
		var receipt := _rejection_receipt(store, "npc-reject-" + str(test_case["name"]).replace(" ", "-"))
		(test_case["change"] as Callable).call(receipt)
		if not _expect_rejected_unchanged(store, service, receipt, str(test_case["name"])):
			return false
	var non_repair := _rejection_receipt(store, "npc-non-repair-material")
	non_repair.verb_id = WorldActionResolver.VERB_SEARCH
	if not _expect_rejected_unchanged(store, service, non_repair, "non-repair material"):
		return false
	return true


func _verify_atomic_search_rejections() -> bool:
	var cases := [
		{
			"name": "stale resource count",
			"remaining": 2,
			"depleted": false,
			"expected_remaining": 3,
			"duplicate_item": false,
		},
		{
			"name": "depleted resource",
			"remaining": 1,
			"depleted": true,
			"expected_remaining": 1,
			"duplicate_item": false,
		},
		{
			"name": "duplicate salvage identity",
			"remaining": 2,
			"depleted": false,
			"expected_remaining": 2,
			"duplicate_item": true,
		},
	]
	for test_case in cases:
		var store := _search_fixture_store(
			int(test_case["remaining"]),
			bool(test_case["depleted"]),
			bool(test_case["duplicate_item"])
		)
		var service := WorldActionApplicationService.new()
		service.configure(store)
		var receipt := _search_completion_receipt(
			store,
			int(test_case["expected_remaining"])
		)
		if not _expect_rejected_unchanged(
			store,
			service,
			receipt,
			"atomic SEARCH " + str(test_case["name"])
		):
			return false
	return true


func _search_fixture_store(
	remaining: int,
	depleted: bool,
	duplicate_item: bool
) -> RuntimeStateStore:
	var store := RuntimeStateStore.new()
	store.begin_new_world("NPC_SEARCH_ATOMIC_REJECTION")
	store.set_campaign_state({"seed": store.world_seed}, "node-a", 0)
	var actor := EntityRecord.new()
	actor.entity_id = ACTOR_ID
	actor.coords = COORDS
	actor.definition = {"finesse": 9}
	actor.runtime = {"inventory_items": []}
	if duplicate_item:
		actor.runtime["inventory_items"].append(
			_item("npc-search-duplicate", "scrap", [], 1, 10.0)
		)
	store.register_entity(actor)
	var target := WorldObjectRecord.new()
	target.object_id = TARGET_ID
	target.definition_id = "rubble"
	target.node_id = "node-a"
	target.coords = COORDS
	target.components = {
		"rubble": {"material_units": remaining, "depleted": depleted},
		"container": {
			"finite": true,
			"remaining_searches": remaining,
			"depleted": depleted,
		},
	}
	var hex := HexRecord.new()
	hex.search_site_id = "route1_rubble_open"
	hex.world_objects = [target.to_dict()]
	store.set_hex_record(COORDS, hex)
	return store


func _search_completion_receipt(
	store: RuntimeStateStore,
	expected_remaining: int
) -> WorldActionReceipt:
	var target := _target(store)
	var request := WorldActionRequest.new()
	request.actor_id = ACTOR_ID
	request.target_id = TARGET_ID
	request.target_coords = COORDS
	request.verb_id = WorldActionResolver.VERB_SEARCH
	request.expected_actor_revision = int(
		store.get_entity_snapshot(ACTOR_ID).get("revision", -1)
	)
	request.expected_target_revision = target.revision
	request.payload = {
		"action_id": "npc-search-rejection",
		"node_id": store.active_node_id,
		"expected_hex_revision": store.get_hex_record(COORDS).revision,
	}
	var reservation := store.begin_world_action(request)
	var item_state := _item("npc-search-duplicate", "scrap", [], 1, 10.0)
	var receipt := WorldActionReceipt.new()
	receipt.committed = true
	receipt.action_id = reservation.action_id
	receipt.receipt_id = reservation.next_receipt_id()
	receipt.actor_id = ACTOR_ID
	receipt.target_id = TARGET_ID
	receipt.target_coords = COORDS
	receipt.node_id = store.active_node_id
	receipt.verb_id = WorldActionResolver.VERB_SEARCH
	receipt.expected_actor_revision = request.expected_actor_revision
	receipt.expected_target_revision = target.revision
	receipt.expected_hex_revision = int(request.payload["expected_hex_revision"])
	receipt.target_state = target.to_dict()
	receipt.elapsed_minutes = 15
	receipt.work_progress = 1.0
	receipt.work_completed = true
	receipt.mutations = [
		{"type": "work_progress", "progress": 1.0},
		{
			"type": WorldActionNpcWorkTransactionService.MUTATION_TYPE,
			"clear_world_work": true,
			"world_work_state": {},
			"search_completion": {
				"resource_component": "rubble",
				"expected_remaining": expected_remaining,
				"item_state": item_state,
			},
		},
	]
	return receipt


func _rejection_receipt(store: RuntimeStateStore, action_id: String) -> WorldActionReceipt:
	var receipt := _work_receipt(store, action_id, 0, false)
	return receipt


func _expect_rejected_unchanged(
	store: RuntimeStateStore,
	service: WorldActionApplicationService,
	receipt: WorldActionReceipt,
	label: String
) -> bool:
	var before := store.capture_reconciliation_snapshot()
	var result := service.apply(receipt)
	if result.applied or result.error.is_empty():
		return _fail("Malformed NPC work receipt was accepted: " + label)
	if store.capture_reconciliation_snapshot() != before:
		return _fail("Rejected NPC work receipt mutated state: " + label)
	store.cancel_world_action(receipt.action_id)
	return true


func _target(store: RuntimeStateStore) -> WorldObjectRecord:
	return WorldObjectRecord.from_dict(store.get_hex_record(COORDS).world_objects[0])


func _item(
	instance_id: String,
	item_id: String,
	roles: Array,
	stack_count: int,
	condition: float
) -> Dictionary:
	return {
		"instance_id": instance_id,
		"item_id": item_id,
		"definition": {
			"id": item_id,
			"functional_roles": roles.duplicate(),
			"tags": [],
		},
		"owner_id": ACTOR_ID,
		"physical_location": "inventory",
		"equipped_slot": GameEnums.EquipmentSlot.NONE,
		"stack_count": stack_count,
		"current_condition": condition,
	}


func _has_item(runtime: Dictionary, instance_id: String, count: int = -1) -> bool:
	for value in runtime.get("inventory_items", []):
		if value is Dictionary and str(value.get("instance_id", "")) == instance_id:
			return count < 0 or int(value.get("stack_count", 1)) == count
	return false


func _condition(runtime: Dictionary, instance_id: String) -> float:
	for value in runtime.get("inventory_items", []):
		if value is Dictionary and str(value.get("instance_id", "")) == instance_id:
			return float(value.get("current_condition", -1.0))
	return -1.0


func _fail(message: String) -> bool:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	push_error("[NPC_WORK_WORLD_ACTION_TRANSACTION] " + message)
	quit(1)
	return false
