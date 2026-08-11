extends RefCounted
class_name CombatActionLegality

## Pure action requirement checks. Board-specific targeting remains in the
## controller because it needs the live quote and arena state.

func validate_requirements(
	actor: HumanoidCore,
	definition: CombatActionDefinition
) -> Dictionary:
	if actor == null or definition == null:
		return {"code": "missing_requirement_context", "message": "Action context is incomplete."}
	for tag in definition.required_limb_tags:
		if tag == "one_arm" and not actor.body.has_functional_arms():
			return {"code": "functional_arm_required", "message": "A functional arm is required."}
		if tag == "two_arms" and functional_arm_count(actor) < 2:
			return {"code": "two_arms_required", "message": "Two functional arms are required."}
		if tag == "legs" and actor.body.are_both_legs_disabled():
			return {"code": "functional_leg_required", "message": "A functional leg is required."}
	for tag in definition.required_equipment_tags:
		if tag == "ranged_weapon" and actor.inventory.get_active_weapon(false) == null:
			return {"code": "ranged_weapon_required", "message": "Ready a functional ranged weapon."}
	return {}


func functional_arm_count(actor: HumanoidCore) -> int:
	if actor == null or actor.body == null:
		return 0
	var count := 0
	for region in [GameEnums.LimbRegion.LEFT_ARM, GameEnums.LimbRegion.RIGHT_ARM]:
		if actor.body.get_limb_function(region) > 0.0:
			count += 1
	return count


func path_denial(code: String) -> String:
	return {
		"actor_not_on_board": "The actor is not on the board.",
		"path_out_of_bounds": "The path leaves the arena.",
		"path_not_orthogonal": "Movement paths must use orthogonal steps.",
		"path_blocked": "An obstacle or actor blocks the path.",
		"empty_path": "Select at least one destination sector.",
	}.get(code, "The selected path is invalid.")
