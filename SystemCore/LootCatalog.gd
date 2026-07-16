extends Node

const ITEM_DIRECTORY := "res://ItemCore/Items/"
const PROFILE_DIRECTORY := "res://ItemCore/LootProfiles/"

var _items_by_id: Dictionary = {}
var _items_by_path: Dictionary = {}
var _profiles_by_id: Dictionary = {}

func _ready() -> void:
	_load_items()
	_load_profiles()

func get_profile_descriptor(profile_id: String) -> Dictionary:
	var profile := _profiles_by_id.get(profile_id) as LootProfile
	if not profile:
		push_error("[LOOT CATALOG] Unknown loot profile: " + profile_id)
		return {}
	return profile.to_descriptor()

func create_runtime_item_state(item_id: String) -> Dictionary:
	var definition := _items_by_id.get(item_id) as ItemData
	if not definition:
		push_error("[LOOT CATALOG] Unknown item ID: " + item_id)
		return {}
	return definition.create_runtime_instance().to_runtime_state()

func has_item(item_id: String) -> bool:
	return _items_by_id.has(item_id)


## Debug/tooling helper: every registered item id, sorted alphabetically.
func get_all_item_ids() -> Array:
	var ids := _items_by_id.keys()
	ids.sort()
	return ids


## Debug/tooling helper: lightweight [id, display_name, item_type] rows for
## every registered item, sorted by display name. Used by the debug overlay's
## item spawner so it never has to touch raw ItemData definitions.
func get_all_item_rows() -> Array:
	var rows: Array = []
	for item_id in _items_by_id.keys():
		var definition := _items_by_id[item_id] as ItemData
		if definition == null:
			continue
		rows.append({
			"id": definition.id,
			"display_name": definition.display_name,
			"item_type": definition.item_type,
			"category": definition.catalog_category,
		})
	rows.sort_custom(func(a, b): return str(a["display_name"]) < str(b["display_name"]))
	return rows


func get_item_descriptor(item_id: String) -> Dictionary:
	var definition := _items_by_id.get(item_id) as ItemData
	if not definition:
		return {}
	return {
		"id": definition.id,
		"display_name": definition.display_name,
		"item_type": definition.item_type,
		"target_slot": definition.target_slot,
		"requires_two_hands": definition.requires_two_hands,
		"item_size": definition.get_effective_item_size(),
		"tags": definition.tags.duplicate(),
	}


func get_all_item_descriptors() -> Array[Dictionary]:
	var descriptors: Array[Dictionary] = []
	for template_path_value in _items_by_path.keys():
		var template_path := str(template_path_value)
		var definition := _items_by_path.get(template_path) as ItemData
		if definition == null:
			continue
		descriptors.append({
			"id": definition.id,
			"display_name": definition.display_name,
			"item_type": definition.item_type,
			"target_slot": definition.target_slot,
			"requires_two_hands": definition.requires_two_hands,
			"item_size": definition.get_effective_item_size(),
			"tags": definition.tags.duplicate(),
			"template_path": template_path,
		})
	descriptors.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			var a_name := str(a.get("display_name", a.get("id", "")))
			var b_name := str(b.get("display_name", b.get("id", "")))
			return a_name.naturalnocasecmp_to(b_name) < 0
	)
	return descriptors


## SystemCore-internal factory access. External domains should use descriptors
## and runtime item dicts instead.
func get_item_definition(item_id: String) -> ItemData:
	return _items_by_id.get(item_id) as ItemData


func pick_loadout_surrender_runtime_item(loadout: Dictionary) -> Dictionary:
	var candidate_paths: Array = loadout.get("starting_items", []).duplicate()
	var weapon_path: String = str(loadout.get("weapon", ""))
	if not weapon_path.is_empty():
		candidate_paths.append(weapon_path)
	for path_value in candidate_paths:
		var runtime_state := create_runtime_item_from_template_path(str(path_value))
		if not runtime_state.is_empty():
			return runtime_state
	return {}


func create_runtime_item_from_template_path(template_path: String) -> Dictionary:
	if template_path.is_empty():
		return {}
	var item := load(template_path) as ItemData
	if not item:
		return {}
	return item.create_runtime_instance().to_runtime_state()

func _load_items() -> void:
	_items_by_id.clear()
	_items_by_path.clear()
	_load_items_from_directory(ITEM_DIRECTORY)

func _load_items_from_directory(directory_path: String) -> void:
	var directory := DirAccess.open(directory_path)
	if not directory:
		push_error("[LOOT CATALOG] Cannot open item directory: " + directory_path)
		return
	directory.list_dir_begin()
	var file_name := directory.get_next()
	while not file_name.is_empty():
		var resource_path := directory_path.path_join(file_name)
		if directory.current_is_dir():
			if not file_name.begins_with("."):
				_load_items_from_directory(resource_path)
		elif file_name.ends_with(".tres"):
			var item := load(resource_path) as ItemData
			if item and not item.id.is_empty():
				_items_by_path[resource_path] = item
				if _items_by_id.has(item.id):
					push_error("[LOOT CATALOG] Duplicate item ID: " + item.id)
				else:
					_items_by_id[item.id] = item
		file_name = directory.get_next()
	directory.list_dir_end()

func _load_profiles() -> void:
	_profiles_by_id.clear()
	var directory := DirAccess.open(PROFILE_DIRECTORY)
	if not directory:
		push_error("[LOOT CATALOG] Cannot open loot profile directory.")
		return
	directory.list_dir_begin()
	var file_name := directory.get_next()
	while not file_name.is_empty():
		if file_name.ends_with(".tres"):
			var profile := load(PROFILE_DIRECTORY + file_name) as LootProfile
			if profile and not profile.profile_id.is_empty():
				_profiles_by_id[profile.profile_id] = profile
		file_name = directory.get_next()
	directory.list_dir_end()
