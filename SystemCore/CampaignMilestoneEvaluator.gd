extends RefCounted
class_name CampaignMilestoneEvaluator

const MILESTONE_PATH := "res://SystemCore/central_unlock_milestone.tres"


static func evaluate(core_states: Dictionary) -> CampaignMilestoneDefinition:
	var milestone := load(MILESTONE_PATH) as CampaignMilestoneDefinition
	if milestone == null or not milestone.is_satisfied(core_states):
		return null
	return milestone
