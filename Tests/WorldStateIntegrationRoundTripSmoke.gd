extends SceneTree

const SAVE_PATH := "res://.godot/test-logs/world_state_integration_round_trip.json"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> bool:
	var store := RuntimeStateStore.new()
	store.begin_new_world("WORLD_STATE_INTEGRATION")
	var player_definition := preload("res://BiologicalCore/player_def.tres") as EntityDefinition
	var player_core := EntityFactory.record_to_humanoid_core({
		"entity_id": "player",
		"definition": player_definition.to_state(),
		"runtime": {},
	}, null, "WorldStateIntegrationPlayer")
	var firearm := player_core.inventory.get_active_weapon(false)
	if firearm != null:
		firearm.current_magazine = 1
	var firearm_id := firearm.instance_id if firearm != null else ""
	store.set_player_record({
		"entity_id": "player",
		"kind": GameEnums.RuntimeEntityKind.PLAYER,
		"coords": Vector2i.ZERO,
		"definition": player_definition.to_state(),
		"runtime": player_core.capture_runtime_state().to_dict(),
	}, Vector2i.ZERO)
	player_core.free()

	var work_target := WorldObjectRecord.new()
	work_target.object_id = "integration-shelter"
	work_target.node_id = "node-a"
	work_target.coords = Vector2i(1, 0)
	work_target.components["repairable"] = {"condition": 0.25}
	var destination_hex := HexRecord.new()
	destination_hex.world_objects = [work_target.to_dict()]
	var baseline_a := {
		Vector2i.ZERO: HexRecord.new(),
		Vector2i(1, 0): destination_hex,
	}
	var graph := {"seed": store.world_seed, "nodes": {"node-a": {}, "node-b": {}}}
	if not store.transition_active_node("node-a", 0, baseline_a, graph, Vector2i.ZERO):
		return _fail("Could not materialize node A.")
	var application := WorldActionApplicationService.new()
	application.configure(store)

	var moved := _apply(
		store, application, "move-a", "player", "hex:1,0", Vector2i(1, 0),
		"travel", 5, [
			{"type": "move_actor", "from": Vector2i.ZERO, "to": Vector2i(1, 0)},
			{"type": "set_hex_explored"},
			{"type": "movement_trace", "trace": {
				"kind": "tracks", "source_id": "player", "coords": Vector2i(1, 0),
				"created_minute": store.world_time_minutes,
				"expires_minute": store.world_time_minutes + 180,
			}},
		]
	)
	if not moved.applied or store.player_record.coords != Vector2i(1, 0):
		return _fail("Move transaction did not commit canonical position.")

	var loot := _item("integration-search-loot")
	var searched := _apply(
		store, application, "search-a", "player", "search:" + str(Vector2i(1, 0)), Vector2i(1, 0),
		WorldActionResolver.VERB_SEARCH, 15, [
			{
				"type": WorldActionSearchTransactionService.MUTATION_TYPE,
				"expected_search_count": 0,
				"searched_target_id": "integration-shelter",
			},
			{"type": "add_ground_item", "item_state": loot},
			{"type": "set_run_flag", "key": "integration_search_complete", "value": true},
		]
	)
	if not searched.applied or store.get_hex_record(Vector2i(1, 0)).search_count != 1:
		return _fail("Search transaction did not commit depletion.")
	if store.get_ground_items(Vector2i(1, 0)).size() != 1:
		return _fail("Search transaction did not commit ground loot once.")

	var camped := _apply(
		store, application, "camp-a", "player", "camp:" + str(Vector2i(1, 0)), Vector2i(1, 0),
		WorldActionResolver.VERB_SLEEP, 30,
		[{
			"type": WorldActionCampTransactionService.MUTATION_TYPE,
			"fatigue_recovery": 0.0,
			"healing_amount": 0.0,
			"camp_rest_count_delta": 1,
		}]
	)
	if not camped.applied or store.get_hex_record(Vector2i(1, 0)).camp_rest_count != 1:
		return _fail("Camp transaction did not commit camp state.")

	var npc := EntityRecord.new()
	npc.entity_id = "integration-worker"
	npc.coords = Vector2i.ZERO
	npc.runtime = {"inventory_items": [], "macro_work_cycles": 0}
	if store.register_entity(npc).is_empty():
		return _fail("Could not register the NPC work fixture.")
	var current_target := WorldObjectRecord.from_dict(
		store.get_hex_record(Vector2i(1, 0)).world_objects[0]
	)
	var repairable := current_target.component("repairable")
	repairable["condition"] = 0.75
	current_target.components["repairable"] = repairable
	var npc_receipt := _apply(
		store, application, "npc-work-a", npc.entity_id, current_target.object_id,
		Vector2i(1, 0), WorldActionResolver.VERB_REPAIR, 15,
		[{"type": "work_progress", "target_id": current_target.object_id,
			"completed_units": 1, "work_units": 1}], current_target
	)
	if not npc_receipt.applied:
		return _fail("NPC work transaction failed: " + npc_receipt.error)

	var baseline_b := {Vector2i.ZERO: HexRecord.new()}
	if not store.transition_active_node("node-b", 1, baseline_b, graph, Vector2i.ZERO):
		return _fail("Node A to B transition failed.")
	if not store.transition_active_node("node-a", 0, baseline_a, graph, Vector2i(1, 0)):
		return _fail("Node A restoration failed.")
	if store.get_hex_record(Vector2i(1, 0)).camp_rest_count != 1:
		return _fail("Node travel lost camp/search runtime state.")

	var directory := ProjectSettings.globalize_path(SAVE_PATH).get_base_dir()
	if not DirAccess.dir_exists_absolute(directory):
		DirAccess.make_dir_recursive_absolute(directory)
	if not store.save_to_disk(SAVE_PATH):
		return _fail("World integration save failed: " + store.get_last_persistence_error())
	var loaded := RuntimeStateStore.new()
	if not loaded.load_from_disk(SAVE_PATH):
		return _fail("World integration load failed: " + loaded.get_last_persistence_error())
	if loaded.active_node_id != "node-a" or loaded.player_record.coords != Vector2i(1, 0):
		return _fail("Load lost active node or canonical player coordinates.")
	if not bool(loaded.run_flags.get("integration_search_complete", false)):
		return _fail("Load lost the search run flag.")
	if loaded.get_ground_items(Vector2i(1, 0)).size() != 1:
		return _fail("Load lost or duplicated search loot.")
	if loaded.get_hex_record(Vector2i(1, 0)).revision < 4:
		return _fail("World revisions did not survive the round trip.")
	if loaded.world_signal_records.is_empty() or loaded.applied_world_receipts.size() < 4:
		return _fail("Signals or applied-receipt idempotence history was lost.")
	if not firearm_id.is_empty():
		var loaded_core := EntityFactory.record_to_humanoid_core(
			loaded.player_record.to_dict(), null, "WorldStateIntegrationVerifier"
		)
		var loaded_firearm := loaded_core.inventory.find_item_by_instance_id(firearm_id)
		if loaded_firearm == null or loaded_firearm.current_magazine != 1:
			loaded_core.free()
			return _fail("Firearm identity/state was lost.")
		loaded_core.free()
	if not loaded.validate_integrity().is_empty():
		return _fail("Loaded world integration state failed integrity validation.")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	print("WORLD_STATE_INTEGRATION_ROUND_TRIP_SMOKE: PASS")
	quit(0)
	return true


func _apply(
	store: RuntimeStateStore,
	service: WorldActionApplicationService,
	action_id: String,
	actor_id: String,
	target_id: String,
	coords: Vector2i,
	verb_id: String,
	elapsed: int,
	mutations: Array,
	target: WorldObjectRecord = null
) -> WorldActionApplicationReceipt:
	var request := WorldActionRequest.new()
	request.actor_id = actor_id
	request.target_id = target_id
	request.target_coords = coords
	request.verb_id = verb_id
	if verb_id == WorldActionResolver.VERB_SLEEP:
		request.method_id = WorldActionCampTransactionService.METHOD_ID
	request.expected_actor_revision = (
		store.player_record.revision
		if actor_id == "player"
		else store.get_entity(actor_id).revision
	)
	request.expected_target_revision = target.revision if target != null else -1
	request.payload = {
		"action_id": action_id,
		"node_id": store.active_node_id,
		"expected_hex_revision": store.get_hex_record(coords).revision,
		"world_time_minutes": store.world_time_minutes,
	}
	var reservation := store.begin_world_action(request)
	if reservation == null:
		var rejected := WorldActionApplicationReceipt.new()
		rejected.error = "Reservation failed: " + action_id
		return rejected
	request.payload["receipt_id"] = reservation.next_receipt_id()
	var receipt := WorldActionResolver.resolve_direct_action(request, elapsed)
	receipt.mutations.append_array(mutations)
	if verb_id == "travel":
		var signal_record := WorldSignalRecord.new()
		signal_record.signal_id = action_id + ":tracks"
		signal_record.signal_type = "tracks"
		signal_record.source_id = actor_id
		signal_record.node_id = store.active_node_id
		signal_record.coords = coords
		signal_record.created_minute = store.world_time_minutes
		signal_record.expires_minute = store.world_time_minutes + 180
		receipt.add_signal(signal_record)
	if target != null:
		receipt.target_state = target.to_dict()
	return service.apply(receipt)


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
	push_error("[WORLD_STATE_INTEGRATION] " + message)
	quit(1)
	return false
