extends RefCounted
class_name MetaMutationService

## Pure profile mutations used by the store's signal/save wrapper.

static func merged_patch(existing: Dictionary, patch: Dictionary) -> Dictionary:
	var merged := existing.duplicate(true)
	merged.merge(patch, true)
	return merged


static func set_state(existing: Dictionary, next_state: Dictionary) -> Dictionary:
	return next_state.duplicate(true) if existing != next_state else existing.duplicate(true)
