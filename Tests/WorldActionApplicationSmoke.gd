extends SceneTree

const SAVE_PATH := "res://.godot/test-logs/world_action_application.json"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> bool:
	var store := RuntimeStateStore.new()
	store.begin_new_world("WORLD_ACTION_APPLICATION")
	var player_definition := preload("res://BiologicalCore/player_def.tres") as EntityDefinition
	var player_runtime := _runtime_for_definition(player_definition, "player")
	store.set_player_record({
		"entity_id": "player",
		"kind": GameEnums.RuntimeEntityKind.PLAYER,
		"coords": Vector2i.ZERO,
		"definition": player_definition.to_state(),
		"runtime": player_runtime,
	}, Vector2i.ZERO)
	store.set_campaign_state({"seed": store.world_seed}, "node-a", 0)
	var target := WorldObjectRecord.new()
	target.object_id = "door-a"
	target.node_id = "node-a"
	target.coords = Vector2i.ZERO
	target.components["door"] = {"open": false, "locked": false}
	var hex := HexRecord.new()
	hex.world_objects = [target.to_dict()]
	store.set_hex_record(Vector2i.ZERO, hex)

	var request := WorldActionRequest.new()
	request.actor_id = "player"
	request.target_id = target.object_id
	request.target_coords = Vector2i.ZERO
	request.verb_id = WorldActionResolver.VERB_OPEN
	request.expected_actor_revision = store.player_record.revision
	request.expected_target_revision = target.revision
	request.payload = {
		"action_id": "open-door-a",
		"node_id": "node-a",
		"expected_hex_revision": store.get_hex_record(Vector2i.ZERO).revision,
	}
	var reservation := store.begin_world_action(request)
	if reservation == null:
		return _fail("Could not reserve the controlled world action.")
	request.payload["receipt_id"] = reservation.next_receipt_id()
	var receipt := WorldActionResolver.resolve_direct_action(request, 5, 0.2)
	var door := target.component("door")
	door["open"] = true
	target.components["door"] = door
	receipt.target_state = target.to_dict()
	var service := WorldActionApplicationService.new()
	service.configure(store)
	var applied := service.apply(receipt)
	if not applied.applied or applied.idempotent:
		return _fail("Valid world receipt was not applied: " + applied.error)
	if store.world_time_minutes != GameTimeRules.STARTING_WORLD_MINUTES + 5:
		return _fail("World time was not applied exactly once.")
	var committed_target := WorldObjectRecord.from_dict(
		store.get_hex_record(Vector2i.ZERO).world_objects[0]
	)
	if not bool(committed_target.component("door").get("open", false)):
		return _fail("Target object mutation was not committed.")
	if committed_target.revision != 1 or store.get_hex_record(Vector2i.ZERO).revision != 1:
		return _fail("Object and hex revisions were not advanced once.")
	var time_after_first := store.world_time_minutes
	var repeated := service.apply(receipt)
	if not repeated.applied or not repeated.idempotent or store.world_time_minutes != time_after_first:
		return _fail("Repeated world receipt was not idempotent.")

	var stale_request := WorldActionRequest.from_dict(request.to_dict())
	stale_request.payload["action_id"] = "stale-open"
	stale_request.expected_actor_revision = store.player_record.revision
	stale_request.expected_target_revision = committed_target.revision
	stale_request.payload["expected_hex_revision"] = 0
	var stale_reservation := store.begin_world_action(stale_request)
	stale_request.payload["receipt_id"] = stale_reservation.next_receipt_id()
	var stale_receipt := WorldActionResolver.resolve_direct_action(stale_request, 1)
	stale_receipt.target_state = committed_target.to_dict()
	var before_stale := store.capture_reconciliation_snapshot()
	var rejected := service.apply(stale_receipt)
	if rejected.applied or rejected.error.is_empty():
		return _fail("Stale hex revision was accepted.")
	if store.capture_reconciliation_snapshot() != before_stale:
		return _fail("Rejected stale receipt partially mutated state.")
	store.cancel_world_action(stale_receipt.action_id)

	var ground_item := _item("transaction-ground-item")
	if not store.add_ground_items(Vector2i.ZERO, [ground_item]):
		return _fail("Could not seed the atomic ground-transfer fixture.")
	var transfer_request := WorldActionRequest.new()
	transfer_request.actor_id = "player"
	transfer_request.target_id = "transaction-ground-item"
	transfer_request.target_coords = Vector2i.ZERO
	transfer_request.verb_id = WorldActionResolver.VERB_PICK_UP
	transfer_request.expected_actor_revision = store.player_record.revision
	transfer_request.payload = {
		"action_id": "take-transaction-ground-item",
		"node_id": "node-a",
		"expected_hex_revision": store.get_hex_record(Vector2i.ZERO).revision,
	}
	var transfer_reservation := store.begin_world_action(transfer_request)
	transfer_request.payload["receipt_id"] = transfer_reservation.next_receipt_id()
	var transfer_receipt := WorldActionResolver.resolve_direct_action(transfer_request, 1)
	var transfer_core := EntityFactory.record_to_humanoid_core(
		store.player_record.to_dict(), null, "WorldActionTransferFixture"
	)
	if not transfer_core.inventory.add_to_backpack(ItemData.from_runtime_state(ground_item)):
		transfer_core.free()
		return _fail("Could not stage the destination inventory runtime.")
	transfer_receipt.actor_state = transfer_core.capture_runtime_state().to_dict()
	transfer_core.free()
	transfer_receipt.mutations.append({"type": "replace_actor_runtime"})
	transfer_receipt.mutations.append({
		"type": "transfer_ground_item",
		"instance_id": "transaction-ground-item",
	})
	var transfer_applied := service.apply(transfer_receipt)
	if not transfer_applied.applied:
		return _fail("Atomic ground transfer failed: " + transfer_applied.error)
	var ownership := store.find_item_ownership("transaction-ground-item")
	if ownership.get("location", "") != "inventory" or ownership.get("owner_id", "") != "player":
		return _fail("Ground transfer did not produce one canonical inventory owner.")

	var save_directory := ProjectSettings.globalize_path(SAVE_PATH).get_base_dir()
	if not DirAccess.dir_exists_absolute(save_directory):
		DirAccess.make_dir_recursive_absolute(save_directory)
	if not store.save_to_disk(SAVE_PATH):
		return _fail("Could not save applied-receipt history.")
	var loaded := RuntimeStateStore.new()
	if not loaded.load_from_disk(SAVE_PATH):
		return _fail("Could not reload applied-receipt history.")
	var loaded_service := WorldActionApplicationService.new()
	loaded_service.configure(loaded)
	var repeated_after_load := loaded_service.apply(transfer_receipt)
	if not repeated_after_load.applied or not repeated_after_load.idempotent:
		return _fail("Duplicate receipt was not idempotent after save/load.")
	for index in range(300):
		loaded.mark_world_receipt_applied("bounded-receipt-%03d" % index)
	if loaded.applied_world_receipts.size() != 256:
		return _fail("Applied world-receipt history exceeded its 256-entry bound.")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	print("WORLD_ACTION_APPLICATION_SMOKE: PASS")
	quit(0)
	return true


func _runtime_for_definition(definition: EntityDefinition, actor_id: String) -> Dictionary:
	var core := EntityFactory.record_to_humanoid_core({
		"entity_id": actor_id,
		"definition": definition.to_state(),
		"runtime": {},
	}, null, actor_id)
	var runtime := core.capture_runtime_state().to_dict()
	core.free()
	return runtime


func _item(instance_id: String) -> Dictionary:
	var definition := load("res://ItemCore/Items/water_bottle.tres") as ItemData
	var state := definition.create_runtime_instance().to_runtime_state()
	state["instance_id"] = instance_id
	state["owner_id"] = ""
	state["physical_location"] = "ground"
	state["equipped_slot"] = GameEnums.EquipmentSlot.NONE
	return state


func _fail(message: String) -> bool:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	push_error("[WORLD_ACTION_APPLICATION] " + message)
	quit(1)
	return false
