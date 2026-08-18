extends SceneTree

const SAVE_PATH := "res://.godot/test-logs/save_last_valid_protection.json"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> bool:
	var store := RuntimeStateStore.new()
	store.begin_new_world("SAVE_LAST_VALID_PROTECTION")
	store.set_player_record({
		"entity_id": "player",
		"kind": GameEnums.RuntimeEntityKind.PLAYER,
		"coords": Vector2i.ZERO,
		"runtime": {"inventory_items": []},
	}, Vector2i.ZERO)
	var directory := ProjectSettings.globalize_path(SAVE_PATH).get_base_dir()
	if not DirAccess.dir_exists_absolute(directory):
		DirAccess.make_dir_recursive_absolute(directory)
	if not store.save_to_disk(SAVE_PATH):
		return _fail("Could not write the valid baseline save.")
	var valid_contents := FileAccess.get_file_as_string(SAVE_PATH)
	store.applied_world_receipts[""] = 0
	if store.save_to_disk(SAVE_PATH):
		return _fail("Invalid runtime state overwrote the save.")
	if FileAccess.get_file_as_string(SAVE_PATH) != valid_contents:
		return _fail("Rejected save changed the previous valid file.")
	var loaded := RuntimeStateStore.new()
	if not loaded.load_from_disk(SAVE_PATH):
		return _fail("Previous valid save no longer loads.")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	print("SAVE_LAST_VALID_PROTECTION_SMOKE: PASS")
	quit(0)
	return true


func _fail(message: String) -> bool:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	push_error("[SAVE_LAST_VALID_PROTECTION] " + message)
	quit(1)
	return false
