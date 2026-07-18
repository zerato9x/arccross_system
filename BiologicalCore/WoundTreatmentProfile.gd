extends Resource
class_name WoundTreatmentProfile

@export var definitions: Array[Resource] = []


func descriptor_for(wound_type: int) -> Dictionary:
	for resource in definitions:
		var definition := resource as WoundTreatmentDefinition
		if definition != null and int(definition.wound_type) == wound_type:
			return definition.to_descriptor()
	return {
		"care_label": "CLINICAL ASSESSMENT",
		"instructions": "No authored treatment protocol exists for this wound.",
		"required_effect": -1,
		"recommended_item_ids": [],
		"currently_treatable": false,
	}

