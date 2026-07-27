extends RefCounted
class_name MacroInteractionState

## Shared pending-interaction bag for macro sessions (POI, events,
## entity collision). MacroGameManager owns one instance; coordinators
## may share the same reference instead of duplicating the dict.

var data: Dictionary = {}


func clear() -> void:
	data.clear()


func is_empty() -> bool:
	return data.is_empty()


func get_type() -> int:
	return int(data.get("type", GameEnums.MacroInteractionType.NONE))


func get_value(key: String, default: Variant = null) -> Variant:
	return data.get(key, default)


func set_value(key: String, value: Variant) -> void:
	data[key] = value


func erase(key: String) -> bool:
	return data.erase(key)


func has_key(key: String) -> bool:
	return data.has(key)


func duplicate_data() -> Dictionary:
	return data.duplicate(true)


func replace(new_data: Dictionary) -> void:
	data = new_data
