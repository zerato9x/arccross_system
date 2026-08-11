extends RefCounted
class_name RuntimeRecordRepository

## Neutral record flattening/reconstruction helpers shared by run saves and
## node-scoped snapshots. The store remains the mutation authority.

static func capture_entities(records: Dictionary) -> Array:
	var result: Array = []
	for record in records.values():
		if record is EntityRecord:
			result.append(record.to_dict())
	return result


static func capture_hexes(records: Dictionary) -> Array:
	var result: Array = []
	for coords in records.keys():
		var record := records[coords] as HexRecord
		if record != null:
			result.append({"coords": coords, "record": record.to_dict()})
	return result


static func capture_ground_items(records: Dictionary) -> Array:
	var result: Array = []
	for coords in records.keys():
		result.append({
			"coords": coords,
			"items": records[coords].duplicate(true),
		})
	return result


static func restore_entities(
	entries: Array,
	register_callback: Callable
) -> void:
	if not register_callback.is_valid():
		return
	for record_data in entries:
		if record_data is Dictionary:
			register_callback.call(EntityRecord.from_dict(record_data))


static func restore_hexes(entries: Array) -> Dictionary:
	var result: Dictionary = {}
	for entry in entries:
		if not entry is Dictionary:
			continue
		var coords: Variant = entry.get("coords")
		if coords is Vector2i:
			result[coords] = HexRecord.from_dict(entry.get("record", {}))
	return result


static func restore_ground_items(entries: Array) -> Dictionary:
	var result: Dictionary = {}
	for entry in entries:
		if not entry is Dictionary:
			continue
		var coords: Variant = entry.get("coords")
		if coords is Vector2i:
			result[coords] = entry.get("items", []).duplicate(true)
	return result
