extends Node

const ITEM_DIRECTORY := "res://ItemCore/Items/"
const PROFILE_DIRECTORY := "res://ItemCore/LootProfiles/"

var _items_by_id: Dictionary = {}
var _items_by_path: Dictionary = {}
var _profiles_by_id: Dictionary = {}

func _ready() -> void:
	reload_catalog()


func reload_catalog() -> void:
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
		"functional_roles": Array(definition.get_functional_roles()),
		"knowledge_entry_id": definition.knowledge_entry_id,
		"can_inspect_knowledge": definition.can_inspect_knowledge(),
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
			"functional_roles": Array(definition.get_functional_roles()),
			"knowledge_entry_id": definition.knowledge_entry_id,
			"template_path": template_path,
		})
	descriptors.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			var a_name := str(a.get("display_name", a.get("id", "")))
			var b_name := str(b.get("display_name", b.get("id", "")))
			return a_name.naturalnocasecmp_to(b_name) < 0
	)
	return descriptors


## Returns neutral validation failures so CI and mod tools can reject broken
## content without starting a world. An empty array means the catalog is valid.
func validate_catalog() -> PackedStringArray:
	var failures := PackedStringArray()
	var knowledge_catalog := get_node_or_null("/root/KnowledgeCatalog")
	for item_id in _items_by_id.keys():
		var item := _items_by_id[item_id] as ItemData
		if item == null:
			continue
		if item.get_functional_roles().is_empty():
			failures.append("Item %s has no functional role." % item_id)
		var sprite_path := item.get_inventory_sprite_path()
		if not sprite_path.is_empty() and not ResourceLoader.exists(sprite_path):
			failures.append("Item %s has a missing sprite: %s" % [item_id, sprite_path])
		if (
			not item.knowledge_entry_id.is_empty()
			and (knowledge_catalog == null or not knowledge_catalog.has_entry(item.knowledge_entry_id))
		):
			failures.append("Item %s references unknown knowledge %s." % [item_id, item.knowledge_entry_id])
	for profile_id in _profiles_by_id.keys():
		var profile := _profiles_by_id[profile_id] as LootProfile
		if profile == null:
			continue
		var all_entries: Array = profile.guaranteed_entries.duplicate()
		all_entries.append_array(profile.entries)
		for entry in all_entries:
			if entry == null or entry.item_id.is_empty():
				failures.append("Loot profile %s has an empty entry." % profile_id)
			elif not _items_by_id.has(entry.item_id):
				failures.append("Loot profile %s references unknown item %s." % [profile_id, entry.item_id])
			elif entry.quantity_max < entry.quantity_min:
				failures.append("Loot profile %s has an inverted quantity range." % profile_id)
	return failures


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
	_load_profiles_from_directory(PROFILE_DIRECTORY)


func _load_profiles_from_directory(directory_path: String) -> void:
	var directory := DirAccess.open(directory_path)
	if not directory:
		push_error("[LOOT CATALOG] Cannot open loot profile directory: " + directory_path)
		return
	directory.list_dir_begin()
	var file_name := directory.get_next()
	while not file_name.is_empty():
		var resource_path := directory_path.path_join(file_name)
		if directory.current_is_dir():
			if not file_name.begins_with("."):
				_load_profiles_from_directory(resource_path)
		elif file_name.ends_with(".tres"):
			var profile := load(resource_path) as LootProfile
			if profile and not profile.profile_id.is_empty():
				if _profiles_by_id.has(profile.profile_id):
					push_error("[LOOT CATALOG] Duplicate loot profile ID: " + profile.profile_id)
				else:
					_profiles_by_id[profile.profile_id] = profile
		file_name = directory.get_next()
	directory.list_dir_end()
