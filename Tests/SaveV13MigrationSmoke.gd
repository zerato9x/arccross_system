extends SceneTree

const SAVE_PATH := "res://.godot/test-logs/save_v13_migration.json"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> bool:
	var source := RuntimeStateStore.new()
	source.begin_new_world("SAVE_V13_MIGRATION")
	source.set_player_record({
		"entity_id": "player",
		"kind": GameEnums.RuntimeEntityKind.PLAYER,
		"coords": Vector2i.ZERO,
		"runtime": {"inventory_items": []},
	}, Vector2i.ZERO)
	source.set_campaign_state({"seed": source.world_seed}, "node-a", 0)
	var hex := HexRecord.new()
	source.set_hex_record(Vector2i.ZERO, hex)
	var request := WorldActionRequest.new()
	request.actor_id = "player"
	request.target_id = "camp-a"
	request.target_coords = Vector2i.ZERO
	request.verb_id = "camp"
	request.expected_actor_revision = source.player_record.revision
	request.payload = {
		"action_id": "legacy-camp",
		"node_id": "node-a",
		"expected_hex_revision": 0,
	}
	if source.begin_world_action(request) == null:
		return _fail("Could not create the typed source reservation.")
	if not source.save_to_disk(SAVE_PATH):
		return _fail("Could not write the current source fixture.")
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	var json := JSON.new()
	if file == null or json.parse(file.get_as_text()) != OK:
		return _fail("Could not parse the source fixture.")
	file.close()
	var fixture: Dictionary = json.data
	fixture["version"] = 13
	fixture.erase("applied_world_receipts")
	for hex_entry in fixture.get("hexes", []):
		if hex_entry is Dictionary:
			var record: Dictionary = hex_entry.get("record", {})
			record.erase("revision")
			hex_entry["record"] = record
	fixture["active_world_actions"] = {
		"legacy-camp": {
			"actor_id": "player",
			"target_id": "camp-a",
			"target_coords": {
				"__arccross_type": "Vector2i",
				"x": 0,
				"y": 0,
			},
			"verb_id": "camp",
			"method_id": "",
			"progress": 1,
		}
	}
	file = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		return _fail("Could not rewrite the v13 fixture.")
	file.store_string(JSON.stringify(fixture, "\t"))
	file.close()

	var loaded := RuntimeStateStore.new()
	if not loaded.load_from_disk(SAVE_PATH):
		return _fail("v13 migration failed: " + loaded.get_last_persistence_error())
	var migrated_hex := loaded.get_hex_record(Vector2i.ZERO)
	if migrated_hex == null or migrated_hex.revision != 0:
		return _fail("v13 hex revision did not migrate to zero.")
	var reservation := loaded.get_world_action_reservation("legacy-camp")
	if reservation == null or reservation.node_id != "node-a":
		return _fail("v13 action state did not migrate to a typed reservation.")
	if not loaded.applied_world_receipts.is_empty():
		return _fail("v13 migration invented applied world-receipt history.")
	if not loaded.validate_integrity().is_empty():
		return _fail("Migrated v13 state failed integrity validation.")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	print("SAVE_V13_MIGRATION_SMOKE: PASS")
	quit(0)
	return true


func _fail(message: String) -> bool:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	push_error("[SAVE_V13_MIGRATION] " + message)
	quit(1)
	return false
