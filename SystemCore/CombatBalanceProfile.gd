extends Resource
class_name CombatBalanceProfile

## Data-authored tactical balance. Keep formula inputs here instead of hiding
## combat tuning in scene/controller conditionals.

@export var profile_id: String = "default_tactical"
@export_range(0.0, 12.0) var base_stance: float = 6.0
@export_range(0.0, 12.0) var brawn_stance_weight: float = 0.5
@export_range(0.0, 12.0) var fortitude_stance_weight: float = 0.5
@export_range(0.0, 12.0) var will_stance_weight: float = 0.0
@export_range(0.0, 12.0) var critical_margin: float = 4.0
@export_range(0.0, 12.0) var collision_stance_damage: float = 2.0
@export_range(0.0, 12.0) var shove_stance_damage: float = 2.0
@export_range(0.0, 12.0) var collision_wound_min: float = 1.0
@export_range(0.0, 12.0) var collision_wound_max: float = 5.0
@export_range(0.0, 2.0) var collision_wound_per_margin: float = 0.35
@export_range(0.0, 1.0) var crowded_collateral_risk: float = 0.25
@export_range(0.0, 1.0) var crowded_collateral_multiplier: float = 0.5
@export_range(0.0, 12.0) var off_balance_margin: float = 4.0
@export_range(0.0, 12.0) var communication_point_base: int = 0
## Legacy balance key retained for older authored profiles.
@export_range(0.0, 12.0) var squad_point_base: int = 2
## AP pricing is encounter data, not controller magic. Each category contains
## FLUID, LABORED, and AGONIZING tier costs in that order.
@export var ap_costs_by_category: Dictionary = {
	"quick": [1, 2, 3],
	"minor": [2, 3, 4],
	"major": [3, 4, 6],
	"heavy": [4, 6, 12],
}
@export_range(1.0, 3.0) var critical_stance_multiplier: float = 1.5
@export_range(0.0, 1.0) var broken_recovery_ratio: float = 0.25
@export_range(0.0, 12.0) var broken_recovery_minimum: float = 1.0


func resolved_communication_point_base() -> int:
	if communication_point_base != 0 or squad_point_base == 0:
		return clampi(int(communication_point_base), 0, 12)
	return clampi(int(squad_point_base), 0, 12)


func stance_for(brawn: int, fortitude: int, will: int, equipment_modifier: float = 0.0) -> float:
	return clampf(
		base_stance
			+ float(brawn) * brawn_stance_weight
			+ float(fortitude) * fortitude_stance_weight
			+ float(will) * will_stance_weight
			+ equipment_modifier,
		0.0,
		12.0
	)


func critical_stance_damage(amount: float) -> float:
	return maxf(0.0, amount) * critical_stance_multiplier


func recovery_stance(max_value: float) -> float:
	return clampf(maxf(broken_recovery_minimum, max_value * broken_recovery_ratio), 0.0, max_value)


func action_ap_cost(ap_category: String, kinetic_tier: int, remaining_ap: int) -> int:
	if ap_category == "free":
		return 0
	if ap_category == "committed":
		return maxi(0, remaining_ap)
	var authored: Variant = ap_costs_by_category.get(ap_category, [0, 0, 0])
	if not authored is Array or (authored as Array).is_empty():
		return 0
	var values: Array = authored
	var tier := clampi(kinetic_tier, 0, values.size() - 1)
	return int(values[tier])
