extends Resource
class_name Route1LandmarkDefinition

@export var arm_id: String = ""
@export var poi_id: String = ""
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var landmark_id: String = "warehouse_b"
@export var loot_profile_id: String = "loot_plains"
@export var evidence_item_id: String = ""
@export var sleep_anchor: String = ""
@export var inhabited: bool = false


func to_descriptor() -> Dictionary:
	return {
		"arm_id": arm_id,
		"poi_id": poi_id,
		"display_name": display_name,
		"description": description,
		"landmark_id": landmark_id,
		"loot_profile_id": loot_profile_id,
		"evidence_item_id": evidence_item_id,
		"sleep_anchor": sleep_anchor,
		"inhabited": inhabited,
	}
