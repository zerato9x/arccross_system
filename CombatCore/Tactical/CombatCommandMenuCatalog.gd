extends Resource
class_name CombatCommandMenuCatalog

@export var families: Array[CombatCommandFamilyDefinition] = []


func definition(family_id: String) -> CombatCommandFamilyDefinition:
	for family in families:
		if family != null and family.family_id == family_id:
			return family
	return null


func ordered_ids() -> Array[String]:
	var ordered := families.duplicate()
	ordered.sort_custom(func(left: CombatCommandFamilyDefinition, right: CombatCommandFamilyDefinition) -> bool:
		return left.order < right.order
	)
	var result: Array[String] = []
	for family in ordered:
		if family != null:
			result.append(family.family_id)
	return result
