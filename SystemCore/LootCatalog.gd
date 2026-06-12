extends Node

const ITEM_DIRECTORY := "res://ItemCore/Items/"
const PROFILE_DIRECTORY := "res://ItemCore/LootProfiles/"

var _items_by_id: Dictionary = {}
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

func get_item_definition(item_id: String) -> ItemData:
	return _items_by_id.get(item_id) as ItemData

func _load_items() -> void:
	_items_by_id.clear()
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
