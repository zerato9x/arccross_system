extends Resource
class_name CombatLabRosterCatalog

## Data-authored participant presets for the Combat Lab.
##
## The Lab deliberately consumes dictionaries here rather than fabricating
## tactical policy in its scene script.  A preset describes who is present;
## the normal encounter builder, relationship ledger, and AI remain the
## authorities for how that participant behaves.
@export var presets: Array[Dictionary] = []


func preset_for_id(preset_id: String) -> Dictionary:
	for preset in presets:
		if str(preset.get("preset_id", "")) == preset_id:
			return preset.duplicate(true)
	return {}


func ordered_presets() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for preset in presets:
		if not str(preset.get("preset_id", "")).is_empty():
			result.append(preset.duplicate(true))
	return result
