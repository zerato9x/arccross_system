extends RefCounted
class_name IdentityCatalog

const OCCUPATION_PATHS := {
	"scavenger": "res://BiologicalCore/Identity/Occupations/scavenger.tres",
}

const TRAIT_PATHS := {
	"field_sense": "res://BiologicalCore/Identity/Traits/field_sense.tres",
}

const FLAW_PATHS := {
	"light_sleeper": "res://BiologicalCore/Identity/Flaws/light_sleeper.tres",
}


static func occupation_descriptor(occupation_id: String) -> Dictionary:
	return _descriptor_from_path(OCCUPATION_PATHS.get(occupation_id, ""), occupation_id)


static func trait_descriptor(trait_id: String) -> Dictionary:
	return _descriptor_from_path(TRAIT_PATHS.get(trait_id, ""), trait_id)


static func flaw_descriptor(flaw_id: String) -> Dictionary:
	return _descriptor_from_path(FLAW_PATHS.get(flaw_id, ""), flaw_id)


static func occupation_descriptors(occupation_id: String) -> Array:
	if occupation_id.is_empty():
		return []
	return [occupation_descriptor(occupation_id)]


static func trait_descriptors(trait_ids: PackedStringArray) -> Array:
	var result: Array = []
	for trait_id in trait_ids:
		if str(trait_id).is_empty():
			continue
		result.append(trait_descriptor(str(trait_id)))
	return result


static func flaw_descriptors(flaw_ids: PackedStringArray) -> Array:
	var result: Array = []
	for flaw_id in flaw_ids:
		if str(flaw_id).is_empty():
			continue
		result.append(flaw_descriptor(str(flaw_id)))
	return result


static func _descriptor_from_path(path: String, fallback_id: String) -> Dictionary:
	if path.is_empty() or not ResourceLoader.exists(path):
		return {
			"id": fallback_id,
			"display_name": fallback_id.replace("_", " ").capitalize(),
			"summary": "",
		}
	var resource := load(path)
	if resource == null:
		return {
			"id": fallback_id,
			"display_name": fallback_id.replace("_", " ").capitalize(),
			"summary": "",
		}
	return {
		"id": str(resource.get("id")),
		"display_name": str(resource.get("display_name")),
		"summary": str(resource.get("summary")),
	}
