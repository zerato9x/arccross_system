extends Node

## Thin persistence facade for menus and bootstrap flows.
## Disk I/O and slot metadata only; gameplay sync remains in GameDirector.

func begin_new_world(seed: String) -> void:
	var store := _store()
	if store:
		store.begin_new_world(seed)


func begin_new_world_from_setup(setup: NewRunSetup, allowed_start_node_ids: PackedStringArray) -> PackedStringArray:
	if setup == null:
		return PackedStringArray(["New run setup is missing."])
	var failures := setup.validate(allowed_start_node_ids)
	if not failures.is_empty():
		return failures
	var setup_state := setup.to_state()
	if Dictionary(setup_state.get("definition", {})).is_empty():
		return PackedStringArray(["Could not build the player definition."])
	var store := _store()
	if store == null:
		return PackedStringArray(["World state service is unavailable."])
	store.begin_new_world(setup.world_seed, setup_state)
	return PackedStringArray()


func load_from_slot(slot: int) -> bool:
	var store := _store()
	if store == null:
		return false
	var metadata := store.get_save_metadata(slot)
	if not metadata.is_empty() and not bool(metadata.get("compatible", false)):
		push_warning(
			"[SaveLoadService] Legacy run save is incompatible. "
			+ "Call begin_fresh_run_from_incompatible_slot() after explicit UI confirm."
		)
		return false
	return store.load_from_slot(slot)


## Explicit wipe path for incompatible legacy slots. Meta progression is preserved
## because it lives in a separate profile file.
func begin_fresh_run_from_incompatible_slot(slot: int, seed: String = "DEMO_WASTELAND_01") -> bool:
	var store := _store()
	if store == null:
		return false
	var metadata := store.get_save_metadata(slot)
	if metadata.is_empty() or bool(metadata.get("compatible", false)):
		return false
	push_warning(
		(
			"[SaveLoadService] Starting a fresh character from incompatible slot %d; "
			% slot
		)
		+ "Meta Progress profile is preserved."
	)
	store.begin_new_world(seed)
	return true


func is_slot_compatible(slot: int) -> bool:
	var metadata := get_save_metadata(slot)
	if metadata.is_empty():
		return false
	return bool(metadata.get("compatible", false))


func has_save_file(path: String = RuntimeStateStore.DEFAULT_SAVE_PATH) -> bool:
	var store := _store()
	if store == null:
		return false
	return store.has_save_file(path)


func get_save_metadata(slot: int) -> Dictionary:
	var store := _store()
	if store == null:
		return {}
	return store.get_save_metadata(slot)


func _store() -> RuntimeStateStore:
	return get_node_or_null("/root/WorldState") as RuntimeStateStore
