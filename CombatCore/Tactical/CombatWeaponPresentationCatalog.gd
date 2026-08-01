extends Resource
class_name CombatWeaponPresentationCatalog

@export var definitions: Array[CombatWeaponPresentationDefinition] = []


func definition_for(weapon_id: String) -> CombatWeaponPresentationDefinition:
	for definition in definitions:
		if definition != null and definition.weapon_id == weapon_id:
			return definition
	return null


func duration_for(weapon_id: String, action_id: String) -> float:
	var definition := definition_for(weapon_id)
	return definition.duration_for_action(action_id) if definition != null else 0.0

