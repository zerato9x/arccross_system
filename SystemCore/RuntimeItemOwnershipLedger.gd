extends RefCounted
class_name RuntimeItemOwnershipLedger

## Single run-scoped ownership index. RuntimeStateStore remains the public
## authority; this service centralizes the transfer and de-duplication rules.

var store: RuntimeStateStore


func _init(state: RuntimeStateStore) -> void:
	store = state


func find_item_ownership(instance_id: String) -> Dictionary:
	if store == null or instance_id.is_empty():
		return {}
	for coords in store.ground_item_records.keys():
		for item_value in store.ground_item_records[coords]:
			if item_value is Dictionary and str(item_value.get("instance_id", "")) == instance_id:
				return {"location": "ground", "coords": coords, "owner_id": ""}
	if store.player_record != null:
		var player_location := _runtime_item_location(store.player_record.runtime, instance_id)
		if not player_location.is_empty():
			player_location["location"] = "inventory"
			player_location["owner_id"] = "player"
			return player_location
	for record_value in store.entity_records.values():
		var record := record_value as EntityRecord
		if record == null:
			continue
		var location := _runtime_item_location(record.runtime, instance_id)
		if not location.is_empty():
			location["location"] = "inventory"
			location["owner_id"] = record.entity_id
			return location
	var object_location := _world_object_item_location(instance_id)
	if not object_location.is_empty():
		return object_location
	return {}


func transfer_item_to_entity(entity_id: String, item_state: Dictionary) -> bool:
	var record := store.get_entity(entity_id) if store != null else null
	if record == null or item_state.is_empty():
		return false
	var normalized := item_state.duplicate(true)
	var instance_id := str(normalized.get("instance_id", ""))
	if instance_id.is_empty():
		return false
	remove_item_instance(instance_id)
	normalized["owner_id"] = entity_id
	normalized["physical_location"] = "inventory"
	var carried: Array = record.runtime.get("inventory_items", [])
	carried.append(normalized)
	record.runtime["inventory_items"] = carried
	record.revision += 1
	store.patch_entity_record(entity_id, {
		"runtime": record.runtime,
		"revision": record.revision,
	})
	return true


func remove_item_instance(instance_id: String) -> void:
	if store == null or instance_id.is_empty():
		return
	for coords in store.ground_item_records.keys().duplicate():
		var items: Array = store.ground_item_records[coords]
		for index in range(items.size() - 1, -1, -1):
			var item_value = items[index]
			if item_value is Dictionary and str(item_value.get("instance_id", "")) == instance_id:
				items.remove_at(index)
		if items.is_empty():
			store.ground_item_records.erase(coords)
	if store.player_record != null:
		_remove_from_runtime(store.player_record.runtime, instance_id)
	for record_value in store.entity_records.values():
		var record := record_value as EntityRecord
		if record != null:
			_remove_from_runtime(record.runtime, instance_id)
	_remove_item_from_world_objects(instance_id)


func _world_object_item_location(instance_id: String) -> Dictionary:
	for coords in store.hex_records.keys():
		var hex := store.hex_records[coords] as HexRecord
		if hex == null:
			continue
		for object_value in hex.world_objects:
			if not object_value is Dictionary:
				continue
			if _contains_item_instance(object_value, instance_id):
				return {
					"location": "world_object",
					"coords": coords,
					"object_id": str(object_value.get("object_id", "")),
					"owner_id": str(object_value.get("owner_id", "")),
				}
	return {}


func _remove_item_from_world_objects(instance_id: String) -> void:
	for coords in store.hex_records.keys():
		var hex := store.hex_records[coords] as HexRecord
		if hex == null:
			continue
		var changed := false
		for index in range(hex.world_objects.size()):
			var object_value = hex.world_objects[index]
			if not object_value is Dictionary:
				continue
			var object_copy: Dictionary = object_value.duplicate(true)
			if _strip_item_instances(object_copy, instance_id):
				hex.world_objects[index] = object_copy
				changed = true
		if changed:
			hex.last_simulated_minute = store.world_time_minutes
			store.hex_records[coords] = hex


func _contains_item_instance(value: Variant, instance_id: String) -> bool:
	if value is Dictionary:
		var dictionary: Dictionary = value
		if str(dictionary.get("instance_id", "")) == instance_id:
			return true
		for child in dictionary.values():
			if _contains_item_instance(child, instance_id):
				return true
	elif value is Array:
		for child in value:
			if _contains_item_instance(child, instance_id):
				return true
	return false


func _strip_item_instances(value: Variant, instance_id: String) -> bool:
	var changed := false
	if value is Dictionary:
		var dictionary: Dictionary = value
		for key in dictionary.keys().duplicate():
			var child = dictionary[key]
			if child is Dictionary and str(child.get("instance_id", "")) == instance_id:
				dictionary.erase(key)
				changed = true
				continue
			if child is Array:
				for index in range(child.size() - 1, -1, -1):
					var item = child[index]
					if item is Dictionary and str(item.get("instance_id", "")) == instance_id:
						child.remove_at(index)
						changed = true
					elif _strip_item_instances(item, instance_id):
						changed = true
				dictionary[key] = child
			elif child is Dictionary and _strip_item_instances(child, instance_id):
				changed = true
	elif value is Array:
		var array_value: Array = value
		for index in range(array_value.size() - 1, -1, -1):
			var child = array_value[index]
			if child is Dictionary and str(child.get("instance_id", "")) == instance_id:
				array_value.remove_at(index)
				changed = true
			elif _strip_item_instances(child, instance_id):
				changed = true
	return changed


func _runtime_item_location(runtime: Dictionary, instance_id: String) -> Dictionary:
	for key in ["inventory_items"]:
		for item_value in runtime.get(key, []):
			if item_value is Dictionary and str(item_value.get("instance_id", "")) == instance_id:
				return {"container": key}
	var inventory: Dictionary = runtime.get("inventory", {})
	for slot in inventory.get("equipment", {}).keys():
		var equipped = inventory["equipment"][slot]
		if equipped is Dictionary and str(equipped.get("instance_id", "")) == instance_id:
			return {"container": "equipment", "slot": str(slot)}
	for item_value in inventory.get("backpack", []):
		if item_value is Dictionary and str(item_value.get("instance_id", "")) == instance_id:
			return {"container": "backpack"}
	return {}


func _remove_from_runtime(runtime: Dictionary, instance_id: String) -> void:
	var macro_items: Array = runtime.get("inventory_items", [])
	for index in range(macro_items.size() - 1, -1, -1):
		var item_value = macro_items[index]
		if item_value is Dictionary and str(item_value.get("instance_id", "")) == instance_id:
			macro_items.remove_at(index)
	runtime["inventory_items"] = macro_items
	var inventory: Dictionary = runtime.get("inventory", {})
	var equipment: Dictionary = inventory.get("equipment", {})
	for slot in equipment.keys().duplicate():
		var equipped = equipment[slot]
		if equipped is Dictionary and str(equipped.get("instance_id", "")) == instance_id:
			equipment.erase(slot)
	var backpack: Array = inventory.get("backpack", [])
	for index in range(backpack.size() - 1, -1, -1):
		var item_value = backpack[index]
		if item_value is Dictionary and str(item_value.get("instance_id", "")) == instance_id:
			backpack.remove_at(index)
	inventory["equipment"] = equipment
	inventory["backpack"] = backpack
	runtime["inventory"] = inventory
