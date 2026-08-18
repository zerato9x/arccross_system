extends SceneTree

const SAVE_PATH := "res://.godot/test-logs/save_v12_migration.json"


func _init() -> void:
	var source := RuntimeStateStore.new()
	source.begin_new_world("SAVE_V12_MIGRATION")
	source.set_player_record({
		"entity_id": "player",
		"kind": GameEnums.RuntimeEntityKind.PLAYER,
		"coords": Vector2i(3, -2),
		"runtime": {"inventory": {"equipment": {}, "backpack": []}},
	}, Vector2i(3, -2))
	if not source.save_to_disk(SAVE_PATH):
		_fail("Could not write the current source fixture.")
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	var json := JSON.new()
	if file == null or json.parse(file.get_as_text()) != OK:
		_fail("Could not parse the source fixture.")
		return
	file.close()
	var fixture: Dictionary = json.data
	fixture["version"] = 12
	fixture.erase("relationship_state")
	fixture.erase("applied_combat_encounters")
	var player_data: Dictionary = fixture.get("player_record", {})
	player_data.erase("coords")
	fixture["player_record"] = player_data
	file = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		_fail("Could not rewrite the v12 fixture.")
		return
	file.store_string(JSON.stringify(fixture, "\t"))
	file.close()

	var loaded := RuntimeStateStore.new()
	if not loaded.load_from_disk(SAVE_PATH):
		_fail("v12 migration failed: " + loaded.get_last_persistence_error())
		return
	if loaded.player_record == null or loaded.player_record.coords != Vector2i(3, -2):
		_fail("v12 player_coords did not migrate into player_record.coords.")
		return
	if not loaded.applied_combat_encounters.is_empty():
		_fail("v12 migration invented applied encounter history.")
		return
	if not loaded.applied_world_receipts.is_empty():
		_fail("v12 migration invented applied world-receipt history.")
		return
	if not loaded.validate_integrity().is_empty():
		_fail("Migrated v12 state failed integrity validation.")
		return
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	print("SAVE_V12_MIGRATION_SMOKE: PASS")
	quit(0)


func _fail(message: String) -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	push_error("[SAVE_V12_MIGRATION] " + message)
	quit(1)
