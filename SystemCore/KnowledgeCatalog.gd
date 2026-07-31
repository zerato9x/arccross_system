extends Node

## Loads mod-friendly knowledge Resources and evaluates their neutral decode
## requirements. World and UI consumers receive dictionaries only.

const ENTRY_DIRECTORY := "res://ItemCore/Knowledge/"

var _entries_by_id: Dictionary = {}


func _ready() -> void:
	reload_catalog()


func reload_catalog() -> void:
	_entries_by_id.clear()
	_load_directory(ENTRY_DIRECTORY)


func has_entry(entry_id: String) -> bool:
	return _entries_by_id.has(entry_id)


func get_entry_descriptor(entry_id: String) -> Dictionary:
	var entry := _entries_by_id.get(entry_id) as KnowledgeEntryDefinition
	return entry.to_descriptor() if entry != null else {}


func get_all_entry_descriptors() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for entry_id in _entries_by_id.keys():
		rows.append(get_entry_descriptor(str(entry_id)))
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("title", "")).naturalnocasecmp_to(
			str(b.get("title", ""))
		) < 0
	)
	return rows


func evaluate_decode(entry_id: String, context: Dictionary = {}) -> Dictionary:
	var descriptor := get_entry_descriptor(entry_id)
	if descriptor.is_empty():
		return {"decoded": false, "reason": "Unknown knowledge entry."}
	var requirements: Dictionary = descriptor.get("decode_requirements", {})
	var missing: Array[String] = []
	if not _matches_any(
		context.get("capability_ids", []),
		requirements.get("any_capabilities", [])
	):
		missing.append("capability")
	if not _matches_any(
		context.get("item_tags", []),
		requirements.get("any_item_tags", [])
	):
		missing.append("tool")
	var known: Array = context.get("known_knowledge_ids", [])
	for required_id in requirements.get("all_knowledge_ids", []):
		if not known.has(str(required_id)):
			missing.append("knowledge:%s" % str(required_id))
	return {
		"decoded": missing.is_empty(),
		"reason": "" if missing.is_empty() else "Missing " + ", ".join(missing) + ".",
		"entry": descriptor,
		"trigger_ids": descriptor.get("discovery_trigger_ids", []).duplicate(),
	}


func _matches_any(owned_value: Variant, required_value: Variant) -> bool:
	var required: Array = required_value if required_value is Array else []
	if required.is_empty():
		return true
	var owned: Array = owned_value if owned_value is Array else []
	for value in required:
		if owned.has(value) or owned.has(str(value)):
			return true
	return false


func _load_directory(directory_path: String) -> void:
	var directory := DirAccess.open(directory_path)
	if directory == null:
		push_error("[KNOWLEDGE CATALOG] Cannot open " + directory_path)
		return
	directory.list_dir_begin()
	var file_name := directory.get_next()
	while not file_name.is_empty():
		var resource_path := directory_path.path_join(file_name)
		if directory.current_is_dir():
			if not file_name.begins_with("."):
				_load_directory(resource_path)
		elif file_name.ends_with(".tres"):
			var entry := load(resource_path) as KnowledgeEntryDefinition
			if entry != null and not entry.id.is_empty():
				if _entries_by_id.has(entry.id):
					push_error("[KNOWLEDGE CATALOG] Duplicate ID: " + entry.id)
				else:
					_entries_by_id[entry.id] = entry
		file_name = directory.get_next()
	directory.list_dir_end()
