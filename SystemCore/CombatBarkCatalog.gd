@tool
extends Resource
class_name CombatBarkCatalog

@export var definitions: Array[CombatBarkDefinition] = []


func candidates(actor: Dictionary, event: String, dialogue_id: String = "") -> Array[CombatBarkDefinition]:
	var result: Array[CombatBarkDefinition] = []
	for definition in definitions:
		if definition != null and definition.matches(actor, event, dialogue_id):
			result.append(definition)
	result.sort_custom(func(left, right):
		if left.priority != right.priority:
			return left.priority > right.priority
		return left.dialogue_id < right.dialogue_id
	)
	return result
