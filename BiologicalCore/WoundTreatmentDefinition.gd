extends Resource
class_name WoundTreatmentDefinition

@export var wound_type: GameEnums.WoundType = GameEnums.WoundType.BRUISE
@export var care_label: String
@export_multiline var instructions: String
@export var required_effect: int = -1
@export var recommended_item_ids: Array[String] = []
@export var currently_treatable := true


func to_descriptor() -> Dictionary:
	return {
		"care_label": care_label,
		"instructions": instructions,
		"required_effect": required_effect,
		"recommended_item_ids": recommended_item_ids.duplicate(),
		"currently_treatable": currently_treatable,
	}

