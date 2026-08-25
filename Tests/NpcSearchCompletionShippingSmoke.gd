extends SceneTree

const SAVE_PATH := "res://.godot/test-logs/npc_search_completion_shipping.json"
const ACTOR_ID := "npc-search-shipping-worker"
const TARGET_ID := "npc-search-shipping-rubble"
const COORDS := Vector2i.ZERO
const _LootCatalog := preload("res://SystemCore/LootCatalog.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> bool:
	var store := _fixture_store()
	var generator := HexWorldGenerator.new()
	generator.configure_services(store)
	generator.refresh_hex_projection(COORDS)
	var loot_catalog := _LootCatalog.new()
	loot_catalog.reload_catalog()
	var coordinator := MacroWorldActionCoordinator.new()
	coordinator.configure(WorldActionKernel.new())
	var work_service := MacroNpcWorkService.new()
	work_service.configure(store, generator, coordinator, loot_catalog)
	var adapter := MacroReceiptApplicationService.new()
	adapter.configure(store, generator, null)
	var starting_time := store.world_time_minutes
	var final_receipt: WorldActionReceipt = null
	for turn_index in range(24):
		var record := EntityRecord.from_dict(store.get_entity_snapshot(ACTOR_ID))
		var before := store.capture_reconciliation_snapshot()
		var result := work_service.try_work(record, turn_index, {
			"commit_receipt": Callable(adapter, "commit"),
		})
		if result.is_empty():
			continue
		var receipt := result.get("receipt") as WorldActionReceipt
		if receipt == null:
			return _fail("Shipping work path returned no typed receipt.")
		if not receipt.work_completed:
			var target_during_work := _target(store)
			if int(target_during_work.component("rubble").get("material_units", -1)) != 2:
				return _fail("Incomplete NPC SEARCH depleted canonical rubble early.")
			if _salvage_ids(store).size() != 0:
				return _fail("Incomplete NPC SEARCH created salvage early.")
			if store.capture_reconciliation_snapshot() == before:
				return _fail("Incomplete NPC SEARCH did not commit progress/time.")
			continue
		final_receipt = receipt
		break
	if final_receipt == null:
		return _fail("Seeded shipping path did not complete NPC SEARCH.")
	var target := _target(store)
	if int(target.component("rubble").get("material_units", -1)) != 1:
		return _fail("Completed NPC SEARCH did not deplete rubble exactly once.")
	if target.revision != final_receipt.expected_target_revision + 1:
		return _fail("Completed NPC SEARCH advanced target revision incorrectly.")
	var hex := store.get_hex_record(COORDS)
	if hex.trace_records.size() != 1:
		return _fail("Completed NPC SEARCH did not append exactly one disturbance trace.")
	var actor := store.get_entity_snapshot(ACTOR_ID)
	var runtime: Dictionary = actor.get("runtime", {})
	if runtime.has("world_work"):
		return _fail("Completed NPC SEARCH retained continuation state.")
	if str(runtime.get("macro_purpose_label", "")) != "Carrying salvage":
		return _fail("Completed NPC SEARCH did not update canonical purpose.")
	if str(actor.get("knowledge", {}).get("northward_evidence", {}).get(
		"evidence", ""
	)) != "disturbed_rubble":
		return _fail("Completed NPC SEARCH did not commit canonical evidence.")
	var salvage_ids := _salvage_ids(store)
	if salvage_ids.size() != 1:
		return _fail("Completed NPC SEARCH did not create exactly one salvage item.")
	var salvage_id := str(salvage_ids[0])
	if not salvage_id.begins_with("item_npc_search_"):
		return _fail("NPC SEARCH salvage identity is not receipt-deterministic.")
	var ownership := store.find_item_ownership(salvage_id)
	if (
		str(ownership.get("location", "")) != "inventory"
		or str(ownership.get("owner_id", "")) != ACTOR_ID
	):
		return _fail("NPC SEARCH salvage has the wrong canonical owner.")
	if store.get_world_action_reservation(final_receipt.action_id) != null:
		return _fail("Completed NPC SEARCH retained its reservation.")
	if store.world_time_minutes <= starting_time:
		return _fail("NPC SEARCH did not advance world time.")
	var committed_snapshot := store.capture_reconciliation_snapshot()
	var replay := adapter.commit(final_receipt, COORDS, target, ACTOR_ID)
	if not replay.applied or not replay.idempotent:
		return _fail("Completed NPC SEARCH receipt replay was not idempotent.")
	if store.capture_reconciliation_snapshot() != committed_snapshot:
		return _fail("Completed NPC SEARCH replay duplicated state.")
	if not _verify_save_load(store, salvage_id):
		return false
	if not store.validate_integrity().is_empty():
		return _fail("Completed NPC SEARCH broke runtime integrity.")
	loot_catalog.free()
	print("NPC_SEARCH_COMPLETION_SHIPPING_SMOKE: PASS")
	quit(0)
	return true


func _fixture_store() -> RuntimeStateStore:
	var store := RuntimeStateStore.new()
	store.begin_new_world("NPC_SEARCH_COMPLETION_SHIPPING")
	store.set_campaign_state({"seed": store.world_seed}, "node-a", 0)
	var actor := EntityRecord.new()
	actor.entity_id = ACTOR_ID
	actor.coords = COORDS
	actor.definition = {"finesse": 12}
	actor.runtime = {"inventory_items": []}
	store.register_entity(actor)
	var target := WorldObjectRecord.new()
	target.object_id = TARGET_ID
	target.definition_id = "rubble"
	target.node_id = "node-a"
	target.coords = COORDS
	target.components = {
		"rubble": {"material_units": 2, "depleted": false},
		"container": {"finite": true, "remaining_searches": 2, "depleted": false},
	}
	var hex := HexRecord.new()
	hex.search_site_id = "route1_rubble_open"
	hex.world_objects = [target.to_dict()]
	store.set_hex_record(COORDS, hex)
	return store


func _target(store: RuntimeStateStore) -> WorldObjectRecord:
	for value in store.get_hex_record(COORDS).world_objects:
		if value is Dictionary and str(value.get("object_id", "")) == TARGET_ID:
			return WorldObjectRecord.from_dict(value)
	return null


func _salvage_ids(store: RuntimeStateStore) -> Array[String]:
	var ids: Array[String] = []
	var runtime: Dictionary = store.get_entity_snapshot(ACTOR_ID).get("runtime", {})
	for value in runtime.get("inventory_items", []):
		if not value is Dictionary:
			continue
		var instance_id := str(value.get("instance_id", ""))
		if instance_id.begins_with("item_npc_search_"):
			ids.append(instance_id)
	return ids


func _verify_save_load(store: RuntimeStateStore, salvage_id: String) -> bool:
	var directory := ProjectSettings.globalize_path(SAVE_PATH).get_base_dir()
	if not DirAccess.dir_exists_absolute(directory):
		DirAccess.make_dir_recursive_absolute(directory)
	if not store.save_to_disk(SAVE_PATH):
		return _fail("Could not save completed NPC SEARCH state.")
	var loaded := RuntimeStateStore.new()
	if not loaded.load_from_disk(SAVE_PATH):
		return _fail("Could not reload completed NPC SEARCH state.")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	var target := _target(loaded)
	if target == null or int(target.component("rubble").get("material_units", -1)) != 1:
		return _fail("Save/load lost NPC SEARCH resource depletion.")
	var ownership := loaded.find_item_ownership(salvage_id)
	if str(ownership.get("owner_id", "")) != ACTOR_ID:
		return _fail("Save/load lost NPC SEARCH salvage ownership.")
	if str(loaded.get_entity_snapshot(ACTOR_ID).get("knowledge", {}).get(
		"northward_evidence", {}
	).get("evidence", "")) != "disturbed_rubble":
		return _fail("Save/load lost NPC SEARCH evidence.")
	return true


func _fail(message: String) -> bool:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	push_error("[NPC_SEARCH_COMPLETION_SHIPPING] " + message)
	quit(1)
	return false
