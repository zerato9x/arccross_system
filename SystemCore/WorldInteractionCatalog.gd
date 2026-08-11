@tool
extends WorldActionCatalog
class_name WorldInteractionCatalog

@export var object_definitions: Array[WorldObjectDefinition] = []

var _object_index: Dictionary = {}
var _object_index_ready: bool = false


func _ensure_object_index() -> void:
	if _object_index_ready:
		return
	_object_index.clear()
	for definition in object_definitions:
		if definition != null and not definition.definition_id.is_empty():
			_object_index[definition.definition_id] = definition
	_object_index_ready = true


func object_for_id(definition_id: String) -> WorldObjectDefinition:
	_ensure_object_index()
	return _object_index.get(definition_id) as WorldObjectDefinition


func validate_object_ids() -> Array[String]:
	var errors: Array[String] = []
	var seen: Dictionary = {}
	for definition in object_definitions:
		if definition == null:
			errors.append("null object definition")
			continue
		if definition.definition_id.is_empty():
			errors.append("object with empty ID")
		elif seen.has(definition.definition_id):
			errors.append("duplicate object ID: %s" % definition.definition_id)
		else:
			seen[definition.definition_id] = true
	return errors


func validate_references() -> Array[String]:
	var errors: Array[String] = []
	for definition in object_definitions:
		if definition == null:
			continue
		for affordance_id in definition.affordance_ids:
			if action_for_id(affordance_id) == null and action_for_verb(affordance_id) == null:
				errors.append(
					"object %s references missing action %s"
					% [definition.definition_id, affordance_id]
				)
	return errors
