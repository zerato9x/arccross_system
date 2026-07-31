extends Resource
class_name SearchSiteDefinition

@export var site_id: String = ""
@export var display_name: String = "Roadside Rubble"
@export_multiline var description: String = "A finite pocket of roadside salvage."
@export var loot_profile_id: String = "loot_plains"
@export var requirements: Dictionary = {}
@export var metric_modifiers: Dictionary = {
	"loot": -2.0,
	"safety": -0.5,
	"sneak": 0.0,
}
@export var marker_kind: String = "salvage"
@export var quest_protected: bool = false
@export var assignment_arm_ids: PackedStringArray = []
@export_range(1, 12) var assignment_count: int = 1
@export var assignment_order: int = 0


func to_descriptor() -> Dictionary:
	return {
		"id": site_id,
		"label": display_name,
		"description": description,
		"loot_profile_id": loot_profile_id,
		"requirements": requirements.duplicate(true),
		"metric_modifiers": metric_modifiers.duplicate(true),
		"marker_kind": marker_kind,
		"quest_protected": quest_protected,
		"assignment_arm_ids": Array(assignment_arm_ids),
		"assignment_count": assignment_count,
		"assignment_order": assignment_order,
	}
