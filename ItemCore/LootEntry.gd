extends Resource
class_name LootEntry

@export var item_id: String = ""
@export_range(0.0, 120.0) var weight: float = 1.0

func to_descriptor() -> Dictionary:
	return {
		"item_id": item_id,
		"weight": maxf(0.0, weight),
	}
