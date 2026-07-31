extends Resource
class_name CombatActionCatalog

@export var definitions: Array[CombatActionDefinition] = []

var _by_id: Dictionary = {}


func definition(action_id: String) -> CombatActionDefinition:
	if _by_id.size() != definitions.size():
		_rebuild_index()
	return _by_id.get(action_id) as CombatActionDefinition


func all() -> Array[CombatActionDefinition]:
	return definitions.duplicate()


func _rebuild_index() -> void:
	_by_id.clear()
	for entry in definitions:
		if entry == null or entry.action_id.is_empty():
			continue
		if _by_id.has(entry.action_id):
			push_error("Duplicate combat action ID: %s" % entry.action_id)
			continue
		_by_id[entry.action_id] = entry
