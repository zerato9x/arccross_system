@tool
extends Resource
class_name ItemConditionProfile

@export var profile_id: String = "default"
@export var condition_thresholds: Dictionary = {
	"critical": 3.0,
	"damaged": 6.0,
	"worn": 9.0,
}
@export var grade_multipliers: Dictionary = {}
@export var wear_rates: Dictionary = {}
@export var tool_method_wear: Dictionary = {}
@export var fault_chances: Dictionary = {}
## Repair recipes, caps, material units, and field/camp restoration amounts are
## authored here so InventorySystem does not encode item IDs or balance values.
@export var repair_costs: Dictionary = {}
@export var readiness_threshold: float = 0.25


func grade_for_condition(condition: float) -> String:
	if condition <= 0.0:
		return "Broken"
	if condition < float(condition_thresholds.get("critical", 3.0)):
		return "Critical"
	if condition < float(condition_thresholds.get("damaged", 6.0)):
		return "Damaged"
	if condition < float(condition_thresholds.get("worn", 9.0)):
		return "Worn"
	return "Fine"


func band_for_condition(condition: float) -> String:
	return grade_for_condition(condition)


func wear_rate(action_id: String, fallback: float = 0.0) -> float:
	return maxf(0.0, float(wear_rates.get(action_id, fallback)))


func tool_wear_for_method(method_id: String, fallback: float = 0.0) -> float:
	return maxf(0.0, float(tool_method_wear.get(method_id, fallback)))


func repair_recipe(domain: int) -> Dictionary:
	var recipes_variant = repair_costs.get("recipes", {})
	if not recipes_variant is Dictionary:
		return {}
	var recipe = recipes_variant.get(str(domain), recipes_variant.get(domain, {}))
	return recipe.duplicate(true) if recipe is Dictionary else {}


func universal_repair_recipe() -> Dictionary:
	var recipe = repair_costs.get("universal", {})
	return recipe.duplicate(true) if recipe is Dictionary else {}


func repair_material_units() -> int:
	return maxi(1, int(repair_costs.get("material_units", 1)))


func repair_cap(context: String, universal: bool, unique_field_repair: bool) -> float:
	if universal:
		return float(repair_costs.get("universal_cap", 6.0))
	var context_key := "camp_cap" if context.to_lower() == "camp" else "field_cap"
	var cap := float(repair_costs.get(context_key, 12.0 if context_key == "camp_cap" else 8.0))
	if unique_field_repair and context_key == "field_cap":
		cap = minf(cap, float(repair_costs.get("unique_field_cap", 6.0)))
	return cap


func repair_amount(context: String) -> float:
	var context_key := "camp_amount" if context.to_lower() == "camp" else "field_amount"
	return float(repair_costs.get(context_key, 4.0 if context_key == "camp_amount" else 2.0))
