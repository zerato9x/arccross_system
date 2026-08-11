@tool
extends Resource
class_name WorldActionCatalog

@export var actions: Array[WorldActionDefinition] = []

var _action_index: Dictionary = {}
var _index_ready: bool = false


func _ensure_index() -> void:
	if _index_ready:
		return
	_action_index.clear()
	for definition in actions:
		if definition == null:
			continue
		if not definition.action_id.is_empty():
			_action_index[definition.action_id] = definition
		if not definition.verb_id.is_empty():
			_action_index["verb:%s" % definition.verb_id] = definition
	_index_ready = true


func action_for_id(action_id: String) -> WorldActionDefinition:
	_ensure_index()
	return _action_index.get(action_id) as WorldActionDefinition


func action_for_verb(verb_id: String) -> WorldActionDefinition:
	_ensure_index()
	return _action_index.get("verb:%s" % verb_id) as WorldActionDefinition


func action_ids() -> PackedStringArray:
	_ensure_index()
	var ids := PackedStringArray()
	for definition in actions:
		if definition != null and not definition.action_id.is_empty():
			ids.append(definition.action_id)
	return ids


func validate_ids() -> Array[String]:
	var errors: Array[String] = []
	var seen: Dictionary = {}
	var seen_verbs: Dictionary = {}
	for definition in actions:
		if definition == null:
			errors.append("null action definition")
			continue
		if definition.action_id.is_empty():
			errors.append("action with empty ID")
		elif seen.has(definition.action_id):
			errors.append("duplicate action ID: %s" % definition.action_id)
		else:
			seen[definition.action_id] = true
		if not definition.verb_id.is_empty():
			if seen_verbs.has(definition.verb_id):
				errors.append("duplicate action verb ID: %s" % definition.verb_id)
			else:
				seen_verbs[definition.verb_id] = true
	return errors
