extends SceneTree

const SAVE_PATH := "res://.godot/test-logs/save_v14_migration.json"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> bool:
	var source := RuntimeStateStore.new()
	source.begin_new_world("SAVE_V14_MIGRATION")
	source.set_player_record({
		"entity_id": "player",
		"kind": GameEnums.RuntimeEntityKind.PLAYER,
		"coords": Vector2i.ZERO,
		"runtime": {"inventory_items": []},
	}, Vector2i.ZERO)
	source.set_campaign_state({"seed": source.world_seed}, "node-a", 0)
	var target := WorldObjectRecord.new()
	target.object_id = "legacy-target"
	target.node_id = "node-a"
	target.coords = Vector2i.ZERO
	target.runtime["last_receipt"] = _legacy_receipt("target-history")
	var hex := HexRecord.new()
	hex.world_objects = [target.to_dict()]
	source.set_hex_record(Vector2i.ZERO, hex)
	var request := WorldActionRequest.new()
	request.actor_id = "player"
	request.target_id = target.object_id
	request.target_coords = Vector2i.ZERO
	request.verb_id = "search"
	request.expected_actor_revision = source.player_record.revision
	request.expected_target_revision = target.revision
	request.payload = {
		"action_id": "v14-active-action",
		"node_id": "node-a",
		"expected_hex_revision": source.get_hex_record(Vector2i.ZERO).revision,
	}
	var reservation := source.begin_world_action(request)
	if reservation == null:
		return _fail("Could not create the v14 source reservation.")
	reservation.progress = 0.5
	reservation.state = {
		"completed_units": 1,
		"last_receipt": _legacy_receipt("reservation-history"),
	}
	if not source.update_world_action_reservation(reservation):
		return _fail("Could not seed the v14 reservation state.")
	if not source.save_to_disk(SAVE_PATH):
		return _fail("Could not write the current source fixture.")
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	var json := JSON.new()
	if file == null or json.parse(file.get_as_text()) != OK:
		return _fail("Could not parse the source fixture.")
	file.close()
	var fixture: Dictionary = json.data
	fixture["version"] = 14
	file = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		return _fail("Could not rewrite the v14 fixture.")
	file.store_string(JSON.stringify(fixture, "\t"))
	file.close()
	var loaded := RuntimeStateStore.new()
	if not loaded.load_from_disk(SAVE_PATH):
		return _fail("v14 migration failed: " + loaded.get_last_persistence_error())
	var migrated_reservation := loaded.get_world_action_reservation(
		"v14-active-action"
	)
	if migrated_reservation == null or not is_equal_approx(
		migrated_reservation.progress, 0.5
	):
		return _fail("v14 migration lost reservation progress.")
	if int(migrated_reservation.state.get("completed_units", -1)) != 1:
		return _fail("v14 migration lost reservation semantic progress.")
	if not _receipt_is_retired(migrated_reservation.state.get(
		"last_receipt", {}
	)):
		return _fail("v14 migration retained a legacy reservation receipt.")
	var migrated_target := WorldObjectRecord.from_dict(
		loaded.get_hex_record(Vector2i.ZERO).world_objects[0]
	)
	if not _receipt_is_retired(migrated_target.runtime.get("last_receipt", {})):
		return _fail("v14 migration retained a legacy target receipt.")
	if not loaded.validate_integrity().is_empty():
		return _fail("Migrated v14 state failed integrity validation.")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	print("SAVE_V14_MIGRATION_SMOKE: PASS")
	quit(0)
	return true


func _legacy_receipt(receipt_id: String) -> Dictionary:
	return {
		"action_id": "legacy-action",
		"receipt_id": receipt_id,
		"actor_state": {"forged": true},
		"mutations": [
			{"type": "replace_actor_runtime"},
			{"type": "work_progress", "completed_units": 1},
		],
	}


func _receipt_is_retired(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	var receipt: Dictionary = value
	if receipt.has("actor_state"):
		return false
	for mutation in receipt.get("mutations", []):
		if mutation is Dictionary and str(mutation.get("type", "")) == "replace_actor_runtime":
			return false
	return receipt.get("mutations", []).size() == 1


func _fail(message: String) -> bool:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	push_error("[SAVE_V14_MIGRATION] " + message)
	quit(1)
	return false
