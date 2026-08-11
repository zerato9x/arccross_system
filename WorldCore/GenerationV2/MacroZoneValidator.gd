extends RefCounted
class_name MacroZoneValidator

## Validation boundary for generated composition. Algorithmic validators still
## live beside the planner; this service prevents invalid plans from being
## silently accepted by the runtime shell.

func validate_plan(plan: GeneratedZonePlan) -> PackedStringArray:
	if plan == null:
		return PackedStringArray(["Generated zone plan is missing."])
	return plan.validation_errors.duplicate()


func is_valid(plan: GeneratedZonePlan) -> bool:
	return validate_plan(plan).is_empty()
