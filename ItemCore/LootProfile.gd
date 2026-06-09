extends Resource
class_name LootProfile

@export var profile_id: String = ""
@export_range(1, 12) var max_searches: int = 4
@export_range(1, 12) var max_items_per_search: int = 3
@export var entries: Array[LootEntry] = []

func to_descriptor() -> Dictionary:
	var entry_descriptors: Array = []
	for entry in entries:
		if entry and not entry.item_id.is_empty() and entry.weight > 0.0:
			entry_descriptors.append(entry.to_descriptor())
	return {
		"profile_id": profile_id,
		"max_searches": max_searches,
		"max_items_per_search": max_items_per_search,
		"entries": entry_descriptors,
	}
