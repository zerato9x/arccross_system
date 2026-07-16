extends Node

## Thin persistence facade for menus and bootstrap flows.
## Disk I/O and slot metadata only; gameplay sync remains in GameDirector.

func begin_new_world(seed: String) -> void:
	var store := _store()
	if store:
		store.begin_new_world(seed)


func load_from_slot(slot: int) -> bool:
	var store := _store()
	if store == null:
		return false
	var metadata := store.get_save_metadata(slot)
	if not metadata.is_empty() and not bool(metadata.get("compatible", false)):
		push_warning(
			"[SaveLoadService] Legacy run save is incompatible with the "
			+ "directional node-web overhaul. Starting a fresh character; "
			+ "the separate Meta Progress profile is preserved."
		)
		store.begin_new_world("DEMO_WASTELAND_01")
		return true
	return store.load_from_slot(slot)


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
