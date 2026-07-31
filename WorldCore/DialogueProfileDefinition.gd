extends Resource
class_name DialogueProfileDefinition

@export var dialogue_id: String = "generic"
@export var match_prefix: bool = false
@export var title: String = "ASK"
@export_multiline var body: String = ""
@export var choices: Array[Dictionary] = []


func matches(candidate_id: String) -> bool:
	return candidate_id.begins_with(dialogue_id) if match_prefix else candidate_id == dialogue_id


func build(candidate_id: String) -> Dictionary:
	var suffix := candidate_id.trim_prefix(dialogue_id) if match_prefix else ""
	var tokens := {
		"{SUFFIX}": suffix,
		"{ARM}": suffix.capitalize(),
		"{ARM_UPPER}": suffix.to_upper(),
	}
	return _expand({"title": title, "body": body, "choices": choices.duplicate(true)}, tokens)


func _expand(value: Variant, tokens: Dictionary) -> Variant:
	if value is String:
		var expanded: String = value
		for token in tokens.keys():
			expanded = expanded.replace(str(token), str(tokens[token]))
		return expanded
	if value is Array:
		var expanded_array: Array = []
		for child in value:
			expanded_array.append(_expand(child, tokens))
		return expanded_array
	if value is Dictionary:
		var expanded_dictionary: Dictionary = {}
		for key in value.keys():
			expanded_dictionary[key] = _expand(value[key], tokens)
		return expanded_dictionary
	return value
