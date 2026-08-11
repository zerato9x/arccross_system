extends Resource
class_name HumanoidEquipmentVisualCatalog

@export var item_directories: Dictionary = {}
@export var weapon_muzzle_anchors: Dictionary = {}


func directory_for(item_id: String) -> String:
	return str(item_directories.get(item_id, ""))


func muzzle_anchor_for(item_id: String, direction_row: int) -> Vector2:
	var directory := directory_for(item_id)
	var anchors: Variant = weapon_muzzle_anchors.get(directory, [])
	if anchors is Array and not anchors.is_empty():
		return anchors[posmod(direction_row, anchors.size())]
	return Vector2(-1.0, -1.0)


func has_muzzle_profile(item_id: String) -> bool:
	var anchors: Variant = weapon_muzzle_anchors.get(directory_for(item_id), [])
	return anchors is Array and anchors.size() == HumanoidVisualCatalog.DIRECTION_ROWS
