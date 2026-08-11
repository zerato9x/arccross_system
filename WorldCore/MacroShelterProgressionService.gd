extends RefCounted
class_name MacroShelterProgressionService

## Pure transition kernel for authored shelter state. Callers provide a copy of
## the WorldObjectRecord and persist it through RuntimeStateStore afterwards.

const DEFAULT_PROFILE: ShelterProgressionProfile = preload(
	"res://WorldCore/default_shelter_progression_profile.tres"
)

var profile: ShelterProgressionProfile


func _init(value: ShelterProgressionProfile = null) -> void:
	profile = value if value != null else DEFAULT_PROFILE


func apply_repair(target: WorldObjectRecord, hostile_present: bool) -> Dictionary:
	if target == null or not target.has_component("shelter"):
		return {}
	var repairable := target.component("repairable")
	var stages: Array = repairable.get("stages", profile.stages)
	if stages.is_empty():
		stages = profile.stages.duplicate()
	var service_stage := int(target.runtime.get("service_stage", 0)) + 1
	target.runtime["service_stage"] = service_stage
	var stage_index := mini(service_stage - 1, stages.size() - 1)
	if stage_index >= 0 and not stages.is_empty():
		var stage_name := str(stages[stage_index])
		if target.has_component(stage_name):
			var component := target.component(stage_name)
			if component.has("state"):
				component["state"] = str(
					profile.stage_state_overrides.get(
						stage_name,
						profile.stage_state_overrides.get("default", "usable")
					)
				)
			if component.has("integrity"):
				component["integrity"] = profile.stage_integrity
			target.components[stage_name] = component
	var next_state := profile.state_for_stage(service_stage, hostile_present)
	var shelter := target.component("shelter")
	shelter["state"] = next_state
	target.components["shelter"] = shelter
	if target.has_component("structure"):
		var structure := target.component("structure")
		structure["state"] = next_state
		target.components["structure"] = structure
	return {
		"state": next_state,
		"service_stage": service_stage,
		"stage_name": str(stages[stage_index]) if stage_index >= 0 else "",
		"complete": service_stage >= stages.size(),
	}


func preserve_after_player_defeat(target: WorldObjectRecord) -> Dictionary:
	if target == null or not target.has_component("shelter"):
		return {}
	var shelter := target.component("shelter")
	var state := str(shelter.get("state", profile.initial_state))
	var next_state := profile.state_after_player_defeat(state)
	if next_state == state:
		return {"state": state, "service_stage": int(target.runtime.get("service_stage", 0))}
	shelter["state"] = next_state
	target.components["shelter"] = shelter
	if target.has_component("structure"):
		var structure := target.component("structure")
		structure["state"] = next_state
		target.components["structure"] = structure
	return {
		"state": next_state,
		"service_stage": int(target.runtime.get("service_stage", 0)),
	}


func reconcile_after_hostile_change(
	target: WorldObjectRecord,
	hostile_present: bool
) -> Dictionary:
	if target == null or not target.has_component("shelter") or hostile_present:
		return {}
	var state := str(target.component("shelter").get("state", profile.initial_state))
	var service_stage := int(target.runtime.get("service_stage", 0))
	if state != profile.overrun_state or service_stage < profile.stages.size():
		return {}
	var shelter := target.component("shelter")
	shelter["state"] = profile.secured_state
	target.components["shelter"] = shelter
	if target.has_component("structure"):
		var structure := target.component("structure")
		structure["state"] = profile.secured_state
		target.components["structure"] = structure
	return {"state": profile.secured_state, "service_stage": service_stage}
