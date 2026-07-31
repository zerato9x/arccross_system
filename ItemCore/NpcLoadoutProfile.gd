extends Resource
class_name NpcLoadoutProfile

@export var profile_id: String = ""
@export var role_ids: PackedStringArray = []
@export var slot_pools: Dictionary = {}
@export var starting_item_pool: Array[Dictionary] = []
@export_range(0, 8) var starting_item_min: int = 0
@export_range(0, 8) var starting_item_max: int = 1


func supports_role(role_id: String) -> bool:
	return role_ids.has(role_id)
