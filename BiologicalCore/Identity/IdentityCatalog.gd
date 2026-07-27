extends RefCounted
class_name IdentityCatalog

const CATALOG_PATH := "res://BiologicalCore/Identity/identity_catalog.tres"


static func data() -> IdentityCatalogData:
	return load(CATALOG_PATH) as IdentityCatalogData


static func occupation_definitions() -> Array[OccupationDefinition]:
	var catalog := data()
	return catalog.occupations if catalog != null else []


static func trait_definitions() -> Array[TraitDefinition]:
	var catalog := data()
	return catalog.traits if catalog != null else []


static func flaw_definitions() -> Array[FlawDefinition]:
	var catalog := data()
	return catalog.flaws if catalog != null else []


static func occupation_definition(occupation_id: String) -> OccupationDefinition:
	return _find_definition(occupation_definitions(), occupation_id) as OccupationDefinition


static func trait_definition(trait_id: String) -> TraitDefinition:
	return _find_definition(trait_definitions(), trait_id) as TraitDefinition


static func flaw_definition(flaw_id: String) -> FlawDefinition:
	return _find_definition(flaw_definitions(), flaw_id) as FlawDefinition


static func occupation_descriptor(occupation_id: String) -> Dictionary:
	return _descriptor(occupation_definition(occupation_id), occupation_id)


static func trait_descriptor(trait_id: String) -> Dictionary:
	return _descriptor(trait_definition(trait_id), trait_id)


static func flaw_descriptor(flaw_id: String) -> Dictionary:
	return _descriptor(flaw_definition(flaw_id), flaw_id)


static func all_occupation_descriptors() -> Array[Dictionary]:
	return _all_descriptors(occupation_definitions())


static func all_trait_descriptors() -> Array[Dictionary]:
	return _all_descriptors(trait_definitions())


static func all_flaw_descriptors() -> Array[Dictionary]:
	return _all_descriptors(flaw_definitions())


static func occupation_descriptors(occupation_id: String) -> Array:
	return [] if occupation_id.is_empty() else [occupation_descriptor(occupation_id)]


static func trait_descriptors(trait_ids: PackedStringArray) -> Array:
	return _selected_descriptors(trait_ids, "trait")


static func flaw_descriptors(flaw_ids: PackedStringArray) -> Array:
	return _selected_descriptors(flaw_ids, "flaw")


static func validate_selection(
	occupation_id: String,
	trait_ids: PackedStringArray,
	flaw_ids: PackedStringArray
) -> PackedStringArray:
	var failures := PackedStringArray()
	var catalog := data()
	if catalog == null:
		failures.append("Identity catalog is unavailable.")
		return failures
	if occupation_definition(occupation_id) == null:
		failures.append("Unknown occupation: %s" % occupation_id)
	if trait_ids.size() != catalog.trait_selection_count:
		failures.append("Select exactly %d trait(s)." % catalog.trait_selection_count)
	if flaw_ids.size() != catalog.flaw_selection_count:
		failures.append("Select exactly %d flaw(s)." % catalog.flaw_selection_count)
	for trait_id in trait_ids:
		if trait_definition(trait_id) == null:
			failures.append("Unknown trait: %s" % trait_id)
	for flaw_id in flaw_ids:
		if flaw_definition(flaw_id) == null:
			failures.append("Unknown flaw: %s" % flaw_id)
	return failures


static func capability_ids_for_selection(
	occupation_id: String,
	trait_ids: PackedStringArray,
	flaw_ids: PackedStringArray
) -> PackedStringArray:
	var result := PackedStringArray()
	var definitions: Array = [occupation_definition(occupation_id)]
	for trait_id in trait_ids:
		definitions.append(trait_definition(trait_id))
	for flaw_id in flaw_ids:
		definitions.append(flaw_definition(flaw_id))
	for definition in definitions:
		if definition == null:
			continue
		for capability_id in definition.get("grants_capability_ids"):
			var value := str(capability_id)
			if not value.is_empty() and not result.has(value):
				result.append(value)
	return result


static func _find_definition(entries: Array, entry_id: String) -> Resource:
	for entry in entries:
		if entry != null and str(entry.get("id")) == entry_id:
			return entry
	return null


static func _all_descriptors(entries: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry in entries:
		if entry != null:
			result.append(_descriptor(entry, str(entry.get("id"))))
	return result


static func _selected_descriptors(ids: PackedStringArray, kind: String) -> Array:
	var result: Array = []
	for entry_id in ids:
		if str(entry_id).is_empty():
			continue
		result.append(
			trait_descriptor(entry_id)
			if kind == "trait"
			else flaw_descriptor(entry_id)
		)
	return result


static func _descriptor(resource: Resource, fallback_id: String) -> Dictionary:
	if resource == null:
		return {
			"id": fallback_id,
			"display_name": fallback_id.replace("_", " ").capitalize(),
			"summary": "",
			"grants_capability_ids": [],
			"rule_tag_ids": [],
		}
	var result := {
		"id": str(resource.get("id")),
		"display_name": str(resource.get("display_name")),
		"summary": str(resource.get("summary")),
		"grants_capability_ids": Array(resource.get("grants_capability_ids")),
		"rule_tag_ids": Array(resource.get("rule_tag_ids")),
	}
	if resource is OccupationDefinition:
		result["exile_text"] = resource.exile_text
	return result
