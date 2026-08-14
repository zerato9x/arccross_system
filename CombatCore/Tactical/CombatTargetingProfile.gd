extends Resource
class_name CombatTargetingProfile

## Authored body-region exposure and specialized-attack difficulty.

@export var profile_id: String = "humanoid_default"
@export var automatic_region_weights: Dictionary = {
	GameEnums.LimbRegion.HEAD: 1.0,
	GameEnums.LimbRegion.UPPER_TORSO: 3.0,
	GameEnums.LimbRegion.LOWER_TORSO: 2.0,
	GameEnums.LimbRegion.LEFT_ARM: 1.0,
	GameEnums.LimbRegion.RIGHT_ARM: 1.0,
	GameEnums.LimbRegion.LEFT_LEG: 1.0,
	GameEnums.LimbRegion.RIGHT_LEG: 1.0,
}
@export var region_accuracy_modifiers: Dictionary = {
	GameEnums.LimbRegion.HEAD: -0.22,
	GameEnums.LimbRegion.UPPER_TORSO: 0.08,
	GameEnums.LimbRegion.LOWER_TORSO: 0.04,
	GameEnums.LimbRegion.LEFT_ARM: -0.10,
	GameEnums.LimbRegion.RIGHT_ARM: -0.10,
	GameEnums.LimbRegion.LEFT_LEG: -0.08,
	GameEnums.LimbRegion.RIGHT_LEG: -0.08,
}


func accuracy_modifier(region: int) -> float:
	return float(region_accuracy_modifiers.get(region, -0.12))


func weighted_regions() -> Array[int]:
	var result: Array[int] = []
	for raw_region in automatic_region_weights:
		var repeats := maxi(1, roundi(float(automatic_region_weights[raw_region]) * 4.0))
		for _index in range(repeats):
			result.append(int(raw_region))
	return result
