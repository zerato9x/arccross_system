extends Resource
class_name LootEntry

@export var item_id: String = ""
@export_range(0.0, 120.0) var weight: float = 1.0
@export_range(1, 12) var quantity_min: int = 1
@export_range(1, 12) var quantity_max: int = 1
@export_range(0.0, 12.0) var condition_min: float = 6.0
@export_range(0.0, 12.0) var condition_max: float = 12.0
@export var once_key: String = ""
@export var region_tags: PackedStringArray = []

func to_descriptor() -> Dictionary:
	return {
		"item_id": item_id,
		"weight": maxf(0.0, weight),
		"quantity_min": maxi(1, quantity_min),
		"quantity_max": maxi(quantity_min, quantity_max),
		"condition_min": clampf(condition_min, 0.0, 12.0),
		"condition_max": clampf(condition_max, condition_min, 12.0),
		"once_key": once_key,
		"region_tags": Array(region_tags),
	}
