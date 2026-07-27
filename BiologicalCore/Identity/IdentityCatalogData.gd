extends Resource
class_name IdentityCatalogData

@export var occupations: Array[OccupationDefinition] = []
@export var traits: Array[TraitDefinition] = []
@export var flaws: Array[FlawDefinition] = []
@export_range(1, 8) var occupation_selection_count: int = 1
@export_range(1, 8) var trait_selection_count: int = 1
@export_range(1, 8) var flaw_selection_count: int = 1


func validate() -> PackedStringArray:
	var failures := PackedStringArray()
	_validate_entries("occupation", occupations, failures)
	_validate_entries("trait", traits, failures)
	_validate_entries("flaw", flaws, failures)
	return failures


func _validate_entries(kind: String, entries: Array, failures: PackedStringArray) -> void:
	var seen: Dictionary = {}
	for entry in entries:
		if entry == null:
			failures.append("%s catalog contains a null entry." % kind)
			continue
		var entry_id := str(entry.get("id"))
		if entry_id.is_empty():
			failures.append("%s catalog contains an empty id." % kind)
		elif seen.has(entry_id):
			failures.append("Duplicate %s id: %s" % [kind, entry_id])
		else:
			seen[entry_id] = true
