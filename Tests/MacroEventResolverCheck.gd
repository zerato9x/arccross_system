extends SceneTree

const COORDS := Vector2i(3, -2)
const SOURCE_ID := "event_locked_treatment_room"


func _initialize() -> void:
	var base_context := {
		"item_ids": [],
		"item_tags": [],
		"item_roles": [],
		"item_names": {},
		"occupations": [],
		"traits": [],
		"flaws": [],
		"stats": {"brawn": 1, "finesse": 1, "fortitude": 1, "will": 1},
	}
	var session: Dictionary = MacroEventResolver.build_event_session(
		MacroEventResolver.EVENT_LOCKED_TREATMENT_ROOM,
		base_context
	)
	if session.is_empty() or session.get("choices", []).size() != 5:
		_fail("Locked treatment room session did not expose all choices.")
		return
	if not _choice_enabled(session, "listen_first"):
		_fail("Always-available observation choice was locked.")
		return
	if _choice_enabled(session, "cut_alarm"):
		_fail("Contextual alarm choice was enabled without its requirement.")
		return

	var blocked: Dictionary = MacroEventResolver.resolve_choice(
		MacroEventResolver.EVENT_LOCKED_TREATMENT_ROOM,
		"cut_alarm",
		base_context
	)
	if not blocked.get("effects", {}).is_empty() or blocked.has("choice_id"):
		_fail("Blocked choices produced a successful event result.")
		return

	var equipped_context: Dictionary = base_context.duplicate(true)
	equipped_context["item_ids"] = ["wire_cutter"]
	equipped_context["item_names"] = {"wire_cutter": "Wire Cutter"}
	var equipped_session: Dictionary = MacroEventResolver.build_event_session(
		MacroEventResolver.EVENT_LOCKED_TREATMENT_ROOM,
		equipped_context
	)
	if not _choice_enabled(equipped_session, "cut_alarm"):
		_fail("Wire cutter did not unlock the alarm choice.")
		return

	var resolved: Dictionary = MacroEventResolver.resolve_choice(
		MacroEventResolver.EVENT_LOCKED_TREATMENT_ROOM,
		"listen_first",
		base_context
	)
	if (
		resolved.get("choice_id", "") != "listen_first"
		or int(resolved.get("effects", {}).get("elapsed_minutes", 0)) != 5
	):
		_fail("Valid choice did not return its expected result and effects.")
		return
	if not _transaction_checks():
		return

	print("[TEST PASS] Macro event resolver and atomic source transaction.")
	quit(0)


func _transaction_checks() -> bool:
	var store := _transaction_store(false)
	if store == null:
		return false
	var service := WorldActionApplicationService.new()
	service.configure(store)
	var starting_time := store.world_time_minutes
	var starting_player_revision := store.player_record.revision
	var starting_hex_revision := store.get_hex_record(COORDS).revision
	var receipt := _event_receipt(store, "macro-event-success")
	var application := service.apply(receipt)
	if not application.applied or application.idempotent:
		_fail("Macro-event transaction failed: " + application.error)
		return false
	if store.world_time_minutes != starting_time + 5:
		_fail("Macro-event transaction did not apply elapsed time exactly once.")
		return false
	if store.player_record.revision != starting_player_revision + 1:
		_fail("Macro-event transaction did not advance player revision once.")
		return false
	var committed_hex := store.get_hex_record(COORDS)
	if (
		committed_hex.revision != starting_hex_revision + 1
		or not committed_hex.searched_targets.has(SOURCE_ID)
	):
		_fail("Macro-event transaction did not complete its canonical source.")
		return false
	var committed_snapshot := store.capture_reconciliation_snapshot()
	var replay := service.apply(receipt)
	if not replay.applied or not replay.idempotent:
		_fail("Macro-event transaction replay was not idempotent.")
		return false
	if store.capture_reconciliation_snapshot() != committed_snapshot:
		_fail("Macro-event transaction replay repeated canonical mutations.")
		return false

	store = _transaction_store(true)
	service = WorldActionApplicationService.new()
	service.configure(store)
	var already_resolved := _event_receipt(store, "macro-event-already-resolved")
	if not _expect_rejected_unchanged(
		store, service, already_resolved, "already-resolved event source"
	):
		return false

	store = _transaction_store(false)
	service = WorldActionApplicationService.new()
	service.configure(store)
	var duplicate := _event_receipt(store, "macro-event-duplicate")
	duplicate.mutations.append(duplicate.mutations[-1].duplicate(true))
	if not _expect_rejected_unchanged(
		store, service, duplicate, "duplicate macro-event application"
	):
		return false

	store = _transaction_store(false)
	service = WorldActionApplicationService.new()
	service.configure(store)
	var stale := _event_receipt(store, "macro-event-stale-hex")
	var changed_hex := HexRecord.from_dict(store.get_hex_record(COORDS).to_dict())
	changed_hex.is_explored = true
	if not store.replace_hex_record(COORDS, changed_hex, changed_hex.revision):
		_fail("Could not construct stale macro-event Hex fixture.")
		return false
	if not _expect_rejected_unchanged(store, service, stale, "stale event Hex"):
		return false
	return true


func _transaction_store(already_resolved: bool) -> RuntimeStateStore:
	var store := RuntimeStateStore.new()
	store.begin_new_world("MACRO_EVENT_TRANSACTION")
	var definition := preload("res://BiologicalCore/player_def.tres") as EntityDefinition
	var core := EntityFactory.record_to_humanoid_core({
		"entity_id": "player",
		"definition": definition.to_state(),
		"runtime": {},
	}, null, "MacroEventTransactionFixture")
	if core == null:
		_fail("Could not construct macro-event transaction actor.")
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
		_fail("Could not seed macro-event transaction actor.")
		return null
	store.set_campaign_state({"seed": store.world_seed}, "macro-event-node", 0)
	var hex := HexRecord.new()
	if already_resolved:
		hex.searched_targets.append(SOURCE_ID)
	store.set_hex_record(COORDS, hex)
	return store


func _event_receipt(
	store: RuntimeStateStore,
	action_id: String
) -> WorldActionReceipt:
	var request := WorldActionRequest.new()
	request.actor_id = "player"
	request.target_id = MacroEventResolver.EVENT_LOCKED_TREATMENT_ROOM
	request.target_coords = COORDS
	request.verb_id = WorldActionMacroEventTransactionService.VERB_ID
	request.expected_actor_revision = store.player_record.revision
	request.payload = {
		"action_id": action_id,
		"node_id": store.active_node_id,
		"world_time_minutes": store.world_time_minutes,
		"expected_hex_revision": store.get_hex_record(COORDS).revision,
	}
	var reservation := store.begin_world_action(request)
	var receipt := WorldActionResolver.resolve_direct_action(
		request, 5, 0.25, 0.0, "Macro-event transaction fixture."
	)
	receipt.node_id = store.active_node_id
	receipt.action_id = reservation.action_id
	receipt.receipt_id = reservation.next_receipt_id()
	receipt.expected_hex_revision = store.get_hex_record(COORDS).revision
	receipt.mutations.append({
		"type": WorldActionMacroEventTransactionService.MUTATION_TYPE,
		"event_id": MacroEventResolver.EVENT_LOCKED_TREATMENT_ROOM,
		"choice_id": "listen_first",
		"source_search_option_id": SOURCE_ID,
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
		_fail("Malformed macro-event transaction was accepted: " + label)
		return false
	if store.capture_reconciliation_snapshot() != before:
		_fail("Rejected macro-event transaction mutated state: " + label)
		return false
	store.cancel_world_action(receipt.action_id)
	return true


func _choice_enabled(session: Dictionary, choice_id: String) -> bool:
	for choice in session.get("choices", []):
		if str(choice.get("id", "")) == choice_id:
			return bool(choice.get("enabled", false))
	return false


func _fail(message: String) -> void:
	push_error("[TEST FAIL] " + message)
	quit(1)
