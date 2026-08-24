extends RefCounted
class_name RuntimeItemOwnershipLedger

## Single run-scoped ownership index. RuntimeStateStore remains the public
## authority; this service centralizes the transfer and de-duplication rules.

var store: RuntimeStateStore


func _init(state: RuntimeStateStore) -> void:
	store = state


func _record_for_entity(entity_id: String) -> EntityRecord:
	if store == null:
		return null
	var snapshot := store.get_entity_snapshot(entity_id)
	return EntityRecord.from_dict(snapshot) if not snapshot.is_empty() else null


func find_item_ownership(instance_id: String) -> Dictionary:
	var locations := find_all_item_ownership(instance_id)
	if locations.size() == 1:
		return locations[0]
	if locations.size() > 1:
		return {"location": "invalid_duplicate", "duplicates": locations}
	return {}


func find_all_item_ownership(instance_id: String) -> Array[Dictionary]:
	var locations: Array[Dictionary] = []
	if store == null or instance_id.is_empty():
		return locations
	for coords in store.ground_item_records.keys():
		for index in range(store.ground_item_records[coords].size()):
			_collect_ground_item_locations(
				store.ground_item_records[coords][index],
				instance_id,
				coords,
				"ground:%s:%d" % [str(coords), index],
				locations
			)
	if store.player_record != null:
		for player_location in _runtime_item_locations(
			store.player_record.runtime, instance_id
		):
			player_location["location"] = "inventory"
			player_location["owner_id"] = "player"
			locations.append(player_location)
	for record_value in store.get_all_entity_snapshots():
		if not record_value is Dictionary:
			continue
		var record: Dictionary = record_value
		for location in _runtime_item_locations(
			record.get("runtime", {}),
			instance_id
		):
			location["location"] = "inventory"
			location["owner_id"] = str(record.get("entity_id", ""))
			locations.append(location)
	locations.append_array(_world_object_item_locations(instance_id))
	locations.append_array(_deployed_hex_item_locations(instance_id))
	return locations


func transfer_item_to_entity(entity_id: String, item_state: Dictionary) -> bool:
	if store == null or item_state.is_empty():
		return false
	var is_player := entity_id == "player"
	var record := _record_for_entity(entity_id) if not is_player else store.player_record
	if record == null:
		return false
	var normalized := item_state.duplicate(true)
	var instance_id := str(normalized.get("instance_id", ""))
	if instance_id.is_empty():
		return false
	var locations := find_all_item_ownership(instance_id)
	# A transfer must consume exactly one existing ownership location.  Item
	# creation belongs to add_ground_items()/explicit materialization, not this
	# API; accepting zero locations here made forged or stale item payloads look
	# like valid transfers.
	if locations.size() != 1:
		return false
	if not _can_append_to_runtime(record.runtime, instance_id):
		return false
	var transaction := store.capture_reconciliation_snapshot()
	if remove_item_instance(instance_id) <= 0:
		store.restore_reconciliation_snapshot(transaction)
		return false
	normalized["owner_id"] = entity_id
	normalized["physical_location"] = "inventory"
	normalized.erase("container_instance_id")
	normalized["equipped_slot"] = GameEnums.EquipmentSlot.NONE
	_append_to_runtime(record.runtime, normalized)
	record.revision += 1
	record.last_simulated_minute = store.world_time_minutes
	if is_player:
		store.player_revision = maxi(store.player_revision, record.revision)
	else:
		store.entity_records[entity_id] = record
	var integrity_errors := store.validate_integrity()
	if not integrity_errors.is_empty():
		store.restore_reconciliation_snapshot(transaction)
		return false
	return true


func transfer_ground_item_to_entity(
	coords: Vector2i,
	instance_id: String,
	entity_id: String
) -> bool:
	if store == null or instance_id.is_empty():
		return false
	var locations := find_all_item_ownership(instance_id)
	if locations.size() != 1:
		return false
	var source: Dictionary = locations[0]
	if source.get("location", "") != "ground" or source.get("coords") != coords:
		return false
	var item_state: Dictionary = {}
	for value in store.ground_item_records.get(coords, []):
		if value is Dictionary:
			item_state = _find_nested_item_state(value, instance_id)
			if not item_state.is_empty():
				break
	return transfer_item_to_entity(entity_id, item_state)


func transfer_ground_item_to_entity_with_runtime(
	coords: Vector2i,
	instance_id: String,
	entity_id: String,
	destination_runtime: Dictionary
) -> bool:
	if store == null or instance_id.is_empty() or destination_runtime.is_empty():
		return false
	var is_player := entity_id == "player"
	var record := store.player_record if is_player else _record_for_entity(entity_id)
	if record == null:
		return false
	var locations := find_all_item_ownership(instance_id)
	if locations.size() != 1:
		return false
	var source: Dictionary = locations[0]
	if source.get("location", "") != "ground" or source.get("coords") != coords:
		return false
	if runtime_item_count(destination_runtime, instance_id) != 1:
		return false
	var transaction := store.capture_reconciliation_snapshot()
	if not _remove_ground_instance(coords, instance_id):
		return false
	record.runtime = destination_runtime.duplicate(true)
	record.revision += 1
	record.last_simulated_minute = store.world_time_minutes
	if is_player:
		store.player_revision = maxi(store.player_revision, record.revision)
	else:
		store.entity_records[entity_id] = record
	var integrity_errors := store.validate_integrity()
	if not integrity_errors.is_empty():
		store.restore_reconciliation_snapshot(transaction)
		return false
	return true


func commit_entity_runtime_with_ground_items(
	entity_id: String,
	destination_runtime: Dictionary,
	coords: Vector2i,
	ground_items: Array
) -> bool:
	if store == null or destination_runtime.is_empty() or ground_items.is_empty():
		return false
	var is_player := entity_id == "player"
	var record := store.player_record if is_player else _record_for_entity(entity_id)
	if record == null:
		return false
	var incoming_ids: Dictionary = {}
	for item_value in ground_items:
		if not item_value is Dictionary:
			return false
		var instance_id := str(item_value.get("instance_id", ""))
		if instance_id.is_empty() or incoming_ids.has(instance_id):
			return false
		incoming_ids[instance_id] = true
		if runtime_item_count(destination_runtime, instance_id) != 0:
			return false
		var locations := find_all_item_ownership(instance_id)
		if locations.size() != 1:
			return false
		var source: Dictionary = locations[0]
		if source.get("location", "") != "inventory" or source.get("owner_id", "") != entity_id:
			return false
	var transaction := store.capture_reconciliation_snapshot()
	record.runtime = destination_runtime.duplicate(true)
	record.revision += 1
	record.last_simulated_minute = store.world_time_minutes
	if is_player:
		store.player_revision = maxi(store.player_revision, record.revision)
	else:
		store.entity_records[entity_id] = record
	if not store.add_ground_items(coords, ground_items):
		store.restore_reconciliation_snapshot(transaction)
		return false
	var integrity_errors := store.validate_integrity()
	if not integrity_errors.is_empty():
		store.restore_reconciliation_snapshot(transaction)
		return false
	return true


func commit_entity_runtime_with_ground_delta(
	entity_id: String,
	destination_runtime: Dictionary,
	coords: Vector2i,
	ground_remove_ids: Array,
	ground_additions: Array
) -> bool:
	if store == null or destination_runtime.is_empty():
		return false
	var is_player := entity_id == "player"
	var record := store.player_record if is_player else _record_for_entity(entity_id)
	if record == null:
		return false
	var removed_ids: Dictionary = {}
	for instance_value in ground_remove_ids:
		var instance_id := str(instance_value)
		if instance_id.is_empty() or removed_ids.has(instance_id):
			return false
		var locations := find_all_item_ownership(instance_id)
		if locations.size() != 1:
			return false
		var source: Dictionary = locations[0]
		if source.get("location", "") != "ground" or source.get("coords") != coords:
			return false
		removed_ids[instance_id] = true
	var addition_ids: Dictionary = {}
	for item_value in ground_additions:
		if not item_value is Dictionary:
			return false
		var instance_id := str(item_value.get("instance_id", ""))
		if (
			instance_id.is_empty()
			or addition_ids.has(instance_id)
			or removed_ids.has(instance_id)
			or runtime_item_count(destination_runtime, instance_id) != 0
		):
			return false
		var locations := find_all_item_ownership(instance_id)
		if locations.size() != 1:
			return false
		var source: Dictionary = locations[0]
		if source.get("location", "") != "inventory" or source.get("owner_id", "") != entity_id:
			return false
		addition_ids[instance_id] = true

	var transaction := store.capture_reconciliation_snapshot()
	record.runtime = destination_runtime.duplicate(true)
	record.revision += 1
	record.last_simulated_minute = store.world_time_minutes
	if is_player:
		store.player_revision = maxi(store.player_revision, record.revision)
	else:
		store.entity_records[entity_id] = record
	for instance_id in removed_ids:
		if not _remove_ground_instance(coords, str(instance_id)):
			store.restore_reconciliation_snapshot(transaction)
			return false
	if not ground_additions.is_empty() and not store.add_ground_items(
		coords,
		ground_additions
	):
		store.restore_reconciliation_snapshot(transaction)
		return false
	var integrity_errors := store.validate_integrity()
	if not integrity_errors.is_empty():
		store.restore_reconciliation_snapshot(transaction)
		return false
	return true


func remove_ground_item(coords: Vector2i, instance_id: String) -> Dictionary:
	if store == null or instance_id.is_empty():
		return {}
	var locations := find_all_item_ownership(instance_id)
	if locations.size() != 1:
		push_error(
			"[ITEM LEDGER] Cannot remove ground item %s: ownership locations=%s"
			% [instance_id, str(locations)]
		)
		return {}
	var source: Dictionary = locations[0]
	if source.get("location", "") != "ground" or source.get("coords") != coords:
		return {}
	var item_state: Dictionary = {}
	for item_value in store.ground_item_records.get(coords, []):
		item_state = _find_nested_item_state(item_value, instance_id)
		if not item_state.is_empty():
			break
	if item_state.is_empty():
		return {}
	var transaction := store.capture_reconciliation_snapshot()
	if not _remove_ground_instance(coords, instance_id):
		return {}
	var integrity_errors := store.validate_integrity()
	if not integrity_errors.is_empty():
		push_error(
			"[ITEM LEDGER] Ground removal invalidated state: %s"
			% "; ".join(integrity_errors)
		)
		store.restore_reconciliation_snapshot(transaction)
		return {}
	return item_state


func runtime_item_count(runtime: Dictionary, instance_id: String) -> int:
	return _runtime_item_locations(runtime, instance_id).size()


func runtime_item_ids(runtime: Dictionary) -> Array[String]:
	var ids: Array[String] = []
	_collect_runtime_item_ids(runtime.get("inventory_items", []), ids)
	var inventory_value: Variant = runtime.get("inventory", {})
	if inventory_value is Dictionary:
		var inventory: Dictionary = inventory_value
		_collect_runtime_item_ids(inventory.get("equipment", {}), ids)
		_collect_runtime_item_ids(inventory.get("backpack", []), ids)
	return ids


func _collect_runtime_item_ids(value: Variant, ids: Array[String]) -> void:
	if value is Dictionary:
		var dictionary: Dictionary = value
		if dictionary.has("instance_id"):
			ids.append(str(dictionary.get("instance_id", "")))
		for child in dictionary.values():
			_collect_runtime_item_ids(child, ids)
	elif value is Array:
		for child in value:
			_collect_runtime_item_ids(child, ids)


func remove_item_instance(instance_id: String) -> int:
	var removed := 0
	if store == null or instance_id.is_empty():
		return removed
	for coords in store.ground_item_records.keys().duplicate():
		var items: Array = store.ground_item_records[coords]
		for index in range(items.size() - 1, -1, -1):
			var item_value = items[index]
			if item_value is Dictionary and str(item_value.get("instance_id", "")) == instance_id:
				items.remove_at(index)
				removed += 1
				continue
			if item_value is Dictionary:
				var item_copy: Dictionary = item_value.duplicate(true)
				if _strip_item_instances(item_copy, instance_id):
					items[index] = item_copy
					removed += 1
		if items.is_empty():
			store.ground_item_records.erase(coords)
	if store.player_record != null:
		if _remove_from_runtime(store.player_record.runtime, instance_id):
			store.player_record.revision += 1
			store.player_revision = maxi(store.player_revision, store.player_record.revision)
			removed += 1
	for record_value in store.entity_records.values():
		var record := record_value as EntityRecord
		if record != null and _remove_from_runtime(record.runtime, instance_id):
			record.revision += 1
			record.last_simulated_minute = store.world_time_minutes
			removed += 1
	removed += _remove_item_from_world_objects(instance_id)
	return removed


func _remove_ground_instance(coords: Vector2i, instance_id: String) -> bool:
	if not store.ground_item_records.has(coords):
		return false
	var items: Array = store.ground_item_records[coords]
	for index in range(items.size() - 1, -1, -1):
		var item_value = items[index]
		if item_value is Dictionary and str(item_value.get("instance_id", "")) == instance_id:
			items.remove_at(index)
			if items.is_empty():
				store.ground_item_records.erase(coords)
			return true
		if item_value is Dictionary:
			var item_copy: Dictionary = item_value.duplicate(true)
			if _strip_item_instances(item_copy, instance_id):
				items[index] = item_copy
				return true
	return false


func _find_nested_item_state(value: Variant, instance_id: String) -> Dictionary:
	if value is Dictionary:
		var dictionary: Dictionary = value
		if str(dictionary.get("instance_id", "")) == instance_id:
			return dictionary.duplicate(true)
		for child in dictionary.values():
			var nested_dictionary := _find_nested_item_state(child, instance_id)
			if not nested_dictionary.is_empty():
				return nested_dictionary
	elif value is Array:
		for child in value:
			var nested_array := _find_nested_item_state(child, instance_id)
			if not nested_array.is_empty():
				return nested_array
	return {}


func _world_object_item_locations(instance_id: String) -> Array[Dictionary]:
	var locations: Array[Dictionary] = []
	for coords in store.hex_records.keys():
		var hex := store.hex_records[coords] as HexRecord
		if hex == null:
			continue
		for index in range(hex.world_objects.size()):
			var object_value = hex.world_objects[index]
			_collect_world_object_locations(
				object_value,
				instance_id,
				"world_object:%s:%d" % [str(coords), index],
				coords,
				locations
			)
	return locations


func _deployed_hex_item_locations(instance_id: String) -> Array[Dictionary]:
	var locations: Array[Dictionary] = []
	for coords in store.hex_records.keys():
		var hex := store.hex_records[coords] as HexRecord
		if hex == null:
			continue
		for index in range(hex.camp_item_states.size()):
			_collect_deployed_item_locations(
				hex.camp_item_states[index],
				instance_id,
				"deployed_camp",
				coords,
				"camp_item_states[%d]" % index,
				locations
			)
		for index in range(hex.camp_traps.size()):
			_collect_deployed_item_locations(
				hex.camp_traps[index],
				instance_id,
				"deployed_trap",
				coords,
				"camp_traps[%d]" % index,
				locations
			)
	return locations


func _collect_deployed_item_locations(
	value: Variant,
	instance_id: String,
	location: String,
	coords: Vector2i,
	container: String,
	locations: Array[Dictionary]
) -> void:
	if value is Dictionary:
		var dictionary: Dictionary = value
		if str(dictionary.get("instance_id", "")) == instance_id:
			locations.append({
				"location": location,
				"coords": coords,
				"owner_id": "",
				"container": container,
			})
		for key in dictionary.keys():
			_collect_deployed_item_locations(
				dictionary[key],
				instance_id,
				location,
				coords,
				"%s.%s" % [container, str(key)],
				locations
			)
	elif value is Array:
		for index in range(value.size()):
			_collect_deployed_item_locations(
				value[index],
				instance_id,
				location,
				coords,
				"%s[%d]" % [container, index],
				locations
			)


func _collect_world_object_locations(
	value: Variant,
	instance_id: String,
	location: String,
	coords: Vector2i,
	locations: Array[Dictionary]
) -> void:
	if value is Dictionary:
		var dictionary: Dictionary = value
		if str(dictionary.get("instance_id", "")) == instance_id:
			locations.append({
				"location": "world_object",
				"coords": coords,
				"object_id": str(dictionary.get("object_id", "")),
				"owner_id": str(dictionary.get("owner_id", "")),
				"container": location,
			})
		for key in dictionary.keys():
			_collect_world_object_locations(
				dictionary[key], instance_id, "%s.%s" % [location, str(key)], coords, locations
			)
	elif value is Array:
		for index in range(value.size()):
			_collect_world_object_locations(
				value[index], instance_id, "%s[%d]" % [location, index], coords, locations
			)


func _remove_item_from_world_objects(instance_id: String) -> int:
	var removed := 0
	for coords in store.hex_records.keys():
		var hex := store.hex_records[coords] as HexRecord
		if hex == null:
			continue
		var changed := false
		for index in range(hex.world_objects.size() - 1, -1, -1):
			var object_value = hex.world_objects[index]
			if not object_value is Dictionary:
				continue
			if str(object_value.get("instance_id", "")) == instance_id:
				hex.world_objects.remove_at(index)
				changed = true
				removed += 1
				continue
			var object_copy: Dictionary = object_value.duplicate(true)
			if _strip_item_instances(object_copy, instance_id):
				hex.world_objects[index] = object_copy
				changed = true
				removed += 1
		for index in range(hex.camp_item_states.size() - 1, -1, -1):
			var camp_value: Variant = hex.camp_item_states[index]
			if not camp_value is Dictionary:
				continue
			if str(camp_value.get("instance_id", "")) == instance_id:
				hex.camp_item_states.remove_at(index)
				if hex.sleep_gear_instance_id == instance_id:
					hex.sleep_gear_instance_id = ""
				changed = true
				removed += 1
				continue
			var camp_copy: Dictionary = camp_value.duplicate(true)
			if _strip_item_instances(camp_copy, instance_id):
				hex.camp_item_states[index] = camp_copy
				changed = true
				removed += 1
		for index in range(hex.camp_traps.size() - 1, -1, -1):
			var trap_value: Variant = hex.camp_traps[index]
			if not trap_value is Dictionary:
				continue
			if str(trap_value.get("instance_id", "")) == instance_id:
				hex.camp_traps.remove_at(index)
				changed = true
				removed += 1
				continue
			var trap_copy: Dictionary = trap_value.duplicate(true)
			if _strip_item_instances(trap_copy, instance_id):
				hex.camp_traps[index] = trap_copy
				changed = true
				removed += 1
		if changed:
			hex.last_simulated_minute = store.world_time_minutes
			store.hex_records[coords] = hex
	return removed


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
				if key == "fitted_magazine_state":
					dictionary["fitted_magazine_instance_id"] = ""
				elif key == "fitted_attachment_states":
					_remove_attachment_reference(
						dictionary, str(child.get("instance_id", ""))
					)
				changed = true
				continue
			if child is Array:
				for index in range(child.size() - 1, -1, -1):
					var item = child[index]
					if item is Dictionary and str(item.get("instance_id", "")) == instance_id:
						if key == "fitted_attachment_states":
							_remove_attachment_reference(dictionary, instance_id)
						child.remove_at(index)
						changed = true
					elif key == "fitted_attachment_instance_ids" and str(item) == instance_id:
						child.remove_at(index)
						changed = true
					elif _strip_item_instances(item, instance_id):
						changed = true
				dictionary[key] = child
			elif child is Dictionary and _strip_item_instances(child, instance_id):
				changed = true
			if key == "fitted_attachment_instance_ids" and child is Array:
				for index in range(child.size() - 1, -1, -1):
					if str(child[index]) == instance_id:
						child.remove_at(index)
						changed = true
				dictionary[key] = child
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


func _remove_attachment_reference(dictionary: Dictionary, instance_id: String) -> void:
	var ids: Array = dictionary.get("fitted_attachment_instance_ids", []).duplicate()
	for index in range(ids.size() - 1, -1, -1):
		if str(ids[index]) == instance_id:
			ids.remove_at(index)
	dictionary["fitted_attachment_instance_ids"] = ids


func _runtime_item_location(runtime: Dictionary, instance_id: String) -> Dictionary:
	var locations := _runtime_item_locations(runtime, instance_id)
	return locations[0] if not locations.is_empty() else {}


func _runtime_item_locations(runtime: Dictionary, instance_id: String) -> Array[Dictionary]:
	var locations: Array[Dictionary] = []
	_collect_runtime_item_locations(
		runtime.get("inventory_items", []), instance_id, "inventory_items", locations
	)
	var inventory_value: Variant = runtime.get("inventory", {})
	if inventory_value is Dictionary:
		var inventory: Dictionary = inventory_value
		var equipment_value: Variant = inventory.get("equipment", {})
		if equipment_value is Dictionary:
			var equipment: Dictionary = equipment_value
			for slot in equipment.keys():
				_collect_runtime_item_locations(
					equipment[slot], instance_id, "equipment:%s" % str(slot), locations
				)
		_collect_runtime_item_locations(
			inventory.get("backpack", []), instance_id, "backpack", locations
		)
	return locations


func _collect_runtime_item_locations(
	value: Variant,
	instance_id: String,
	location: String,
	locations: Array[Dictionary]
) -> void:
	if value is Dictionary:
		var dictionary: Dictionary = value
		if str(dictionary.get("instance_id", "")) == instance_id:
			locations.append({"container": location})
		for key in dictionary.keys():
			_collect_runtime_item_locations(
				dictionary[key], instance_id, "%s.%s" % [location, str(key)], locations
			)
	elif value is Array:
		for index in range(value.size()):
			_collect_runtime_item_locations(
				value[index], instance_id, "%s[%d]" % [location, index], locations
			)


func _remove_from_runtime(runtime: Dictionary, instance_id: String) -> bool:
	var changed := false
	if runtime.has("inventory_items"):
		var macro_items: Array = runtime.get("inventory_items", []).duplicate(true)
		changed = _remove_item_from_array(macro_items, instance_id) or changed
		runtime["inventory_items"] = macro_items
	if runtime.has("inventory"):
		var inventory_value: Variant = runtime.get("inventory", {})
		if not inventory_value is Dictionary:
			return changed
		var inventory: Dictionary = (inventory_value as Dictionary).duplicate(true)
		var equipment_value: Variant = inventory.get("equipment", {})
		var equipment: Dictionary = (
			(equipment_value as Dictionary).duplicate(true)
			if equipment_value is Dictionary
			else {}
		)
		for slot in equipment.keys().duplicate():
			var equipped = equipment[slot]
			if equipped is Dictionary and str(equipped.get("instance_id", "")) == instance_id:
				equipment.erase(slot)
				changed = true
			else:
				if _strip_item_instances(equipped, instance_id):
					equipment[slot] = equipped
					changed = true
		var backpack_value: Variant = inventory.get("backpack", [])
		var backpack: Array = (
			(backpack_value as Array).duplicate(true)
			if backpack_value is Array
			else []
		)
		changed = _remove_item_from_array(backpack, instance_id) or changed
		inventory["equipment"] = equipment
		inventory["backpack"] = backpack
		runtime["inventory"] = inventory
	return changed


func _remove_item_from_array(items: Array, instance_id: String) -> bool:
	var changed := false
	for index in range(items.size() - 1, -1, -1):
		var item_value = items[index]
		if item_value is Dictionary and str(item_value.get("instance_id", "")) == instance_id:
			items.remove_at(index)
			changed = true
		elif _strip_item_instances(item_value, instance_id):
			items[index] = item_value
			changed = true
	return changed


func _can_append_to_runtime(runtime: Dictionary, instance_id: String) -> bool:
	return _runtime_item_location(runtime, instance_id).is_empty()


func _append_to_runtime(runtime: Dictionary, item_state: Dictionary) -> void:
	if runtime.has("inventory"):
		var inventory_value: Variant = runtime.get("inventory", {})
		if not inventory_value is Dictionary:
			return
		var inventory: Dictionary = (inventory_value as Dictionary).duplicate(true)
		var backpack_value: Variant = inventory.get("backpack", [])
		var backpack: Array = (
			(backpack_value as Array).duplicate(true)
			if backpack_value is Array
			else []
		)
		backpack.append(item_state.duplicate(true))
		inventory["backpack"] = backpack
		runtime["inventory"] = inventory
		return
	var carried: Array = runtime.get("inventory_items", []).duplicate(true)
	carried.append(item_state.duplicate(true))
	runtime["inventory_items"] = carried


func validate_integrity() -> Array[String]:
	var errors: Array[String] = []
	var locations_by_id: Dictionary = {}
	for coords in store.ground_item_records.keys():
		for index in range(store.ground_item_records[coords].size()):
			_collect_nested_item_locations(
				locations_by_id,
				store.ground_item_records[coords][index],
				"ground:%s:%d" % [str(coords), index],
				errors
			)
	if store.player_record != null:
		_register_runtime_items(
			locations_by_id, store.player_record.runtime, "player", errors
		)
	for record_value in store.entity_records.values():
		var record := record_value as EntityRecord
		if record != null:
			_register_runtime_items(
				locations_by_id, record.runtime, record.entity_id, errors
			)
	for coords in store.hex_records.keys():
		var hex := store.hex_records[coords] as HexRecord
		if hex == null:
			continue
		for object_value in hex.world_objects:
			_collect_nested_item_locations(
				locations_by_id,
				object_value,
				"world_object:%s" % str(coords),
				errors
			)
	for instance_id in locations_by_id.keys():
		var locations: Array = locations_by_id[instance_id]
		if locations.size() > 1:
			errors.append(
				"Item instance %s has multiple owners: %s"
				% [instance_id, ", ".join(locations)]
			)
	return errors


func _register_runtime_items(
	locations_by_id: Dictionary,
	runtime: Dictionary,
	owner_id: String,
	errors: Array[String]
) -> void:
	_collect_runtime_integrity_locations(
		locations_by_id, runtime.get("inventory_items", []), "%s:inventory_items" % owner_id, errors
	)
	var inventory_value: Variant = runtime.get("inventory", {})
	if not inventory_value is Dictionary:
		if runtime.has("inventory"):
			errors.append("Runtime inventory is not a Dictionary: %s" % owner_id)
		return
	var inventory: Dictionary = inventory_value
	var equipment_value: Variant = inventory.get("equipment", {})
	if equipment_value is Dictionary:
		var equipment: Dictionary = equipment_value
		for slot in equipment.keys():
			_collect_runtime_integrity_locations(
				locations_by_id,
				equipment[slot],
				"%s:equipment:%s" % [owner_id, str(slot)],
				errors
			)
	else:
		errors.append("Runtime equipment is not a Dictionary: %s" % owner_id)
	var backpack_value: Variant = inventory.get("backpack", [])
	if backpack_value is Array:
		_collect_runtime_integrity_locations(
			locations_by_id, backpack_value, "%s:backpack" % owner_id, errors
		)
	else:
		errors.append("Runtime backpack is not an Array: %s" % owner_id)


func _collect_runtime_integrity_locations(
	locations_by_id: Dictionary,
	value: Variant,
	location: String,
	errors: Array[String]
) -> void:
	if value is Dictionary:
		if (value as Dictionary).has("instance_id"):
			_register_integrity_location(locations_by_id, value, location, errors)
		for key in (value as Dictionary).keys():
			_collect_runtime_integrity_locations(
				locations_by_id,
				(value as Dictionary)[key],
				"%s.%s" % [location, str(key)],
				errors
			)
	elif value is Array:
		for index in range(value.size()):
			_collect_runtime_integrity_locations(
				locations_by_id,
				value[index],
				"%s[%d]" % [location, index],
				errors
			)


func _register_integrity_location(
	locations_by_id: Dictionary,
	value: Variant,
	location: String,
	errors: Array[String]
) -> void:
	if not value is Dictionary:
		return
	var instance_id := str(value.get("instance_id", ""))
	if instance_id.is_empty():
		errors.append("Item at %s has no instance_id." % location)
		return
	if not locations_by_id.has(instance_id):
		locations_by_id[instance_id] = []
	locations_by_id[instance_id].append(location)


func _collect_ground_item_locations(
	value: Variant,
	instance_id: String,
	coords: Vector2i,
	location: String,
	locations: Array[Dictionary]
) -> void:
	if value is Dictionary:
		var dictionary: Dictionary = value
		if str(dictionary.get("instance_id", "")) == instance_id:
			locations.append({
				"location": "ground",
				"coords": coords,
				"owner_id": "",
				"container": location,
			})
		for key in dictionary.keys():
			_collect_ground_item_locations(
				dictionary[key], instance_id, coords, "%s.%s" % [location, str(key)], locations
			)
	elif value is Array:
		for index in range(value.size()):
			_collect_ground_item_locations(
				value[index], instance_id, coords, "%s[%d]" % [location, index], locations
			)


func _collect_nested_item_locations(
	locations_by_id: Dictionary,
	value: Variant,
	location: String,
	errors: Array[String]
) -> void:
	if value is Dictionary:
		var dictionary: Dictionary = value
		if dictionary.has("instance_id"):
			_register_integrity_location(
				locations_by_id, dictionary, location, errors
			)
		for child in dictionary.values():
			_collect_nested_item_locations(
				locations_by_id, child, location, errors
			)
	elif value is Array:
		for child in value:
			_collect_nested_item_locations(
				locations_by_id, child, location, errors
			)
