extends Resource
class_name HumanoidEquipmentVisualCatalog

@export var item_directories: Dictionary = {}


func directory_for(item_id: String) -> String:
	return str(item_directories.get(item_id, ""))
