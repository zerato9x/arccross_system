extends Resource
class_name CampaignMilestoneDefinition

@export var id: String = ""
@export var required_core_ids: PackedStringArray = []
@export var required_state_key: String = "restored"
@export var completion_event_id: String = ""


func is_satisfied(core_states: Dictionary) -> bool:
	if required_core_ids.is_empty():
		return false
	for core_id in required_core_ids:
		var state: Dictionary = core_states.get(str(core_id), {})
		if not bool(state.get(required_state_key, false)):
			return false
	return true
