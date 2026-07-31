extends Resource
class_name DialogueCatalog

const DEFAULT_PATH := "res://WorldCore/dialogue_profiles.tres"

@export var profiles: Array[DialogueProfileDefinition] = []


func resolve(dialogue_id: String) -> Dictionary:
	for profile in profiles:
		if profile != null and profile.matches(dialogue_id):
			return profile.build(dialogue_id)
	return {}


static func data() -> DialogueCatalog:
	return load(DEFAULT_PATH) as DialogueCatalog
