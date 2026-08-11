extends RefCounted
class_name ItemConditionRules

## Combat-independent item wear and fault resolver shared by every scheduler.
const DEFAULT_PROFILE: ItemConditionProfile = preload(
	"res://ItemCore/default_item_condition_profile.tres"
)
const EVENT_FIREARM := "firearm"
const EVENT_MELEE := "melee"
const EVENT_ARMOR := "armor"
const EVENT_SHIELD := "shield"
const EVENT_TOOL := "tool"

const CONDITION_FINE := "Fine"
const CONDITION_WORN := "Worn"
const CONDITION_DAMAGED := "Damaged"
const CONDITION_CRITICAL := "Critical"
const CONDITION_BROKEN := "Broken"

const EVENT_WEAR := {
	EVENT_FIREARM: 0.10,
	EVENT_MELEE: 0.20,
	EVENT_ARMOR: 0.15,
	EVENT_SHIELD: 0.15,
	EVENT_TOOL: 0.25,
}

const GRADE_WEAR_MULTIPLIER := {
	GameEnums.ItemGrade.IMPROVISED: 1.25,
	GameEnums.ItemGrade.CIVILIAN: 1.0,
	GameEnums.ItemGrade.SERVICE: 0.8,
	GameEnums.ItemGrade.CARBON: 0.65,
	GameEnums.ItemGrade.UNIQUE: 0.5,
}

static func condition_band(condition: float) -> String:
	return DEFAULT_PROFILE.band_for_condition(condition)

static func fault_chance(condition: float) -> float:
	return float(DEFAULT_PROFILE.fault_chances.get(condition_band(condition), 0.0))

static func grade_wear_multiplier(grade: GameEnums.ItemGrade) -> float:
	return float(DEFAULT_PROFILE.grade_multipliers.get(int(grade), GRADE_WEAR_MULTIPLIER.get(grade, 1.0)))


static func repair_recipe(domain: int) -> Dictionary:
	return DEFAULT_PROFILE.repair_recipe(domain)


static func universal_repair_recipe() -> Dictionary:
	return DEFAULT_PROFILE.universal_repair_recipe()


static func repair_material_units() -> int:
	return DEFAULT_PROFILE.repair_material_units()


static func repair_cap(context: String, universal: bool, unique_field_repair: bool) -> float:
	return DEFAULT_PROFILE.repair_cap(context, universal, unique_field_repair)


static func repair_amount(context: String) -> float:
	return DEFAULT_PROFILE.repair_amount(context)


static func tool_wear_for_method(method_id: String, fallback: float = 0.0) -> float:
	return DEFAULT_PROFILE.tool_wear_for_method(method_id, fallback)

static func readiness_descriptor(item: ItemData) -> Dictionary:
	if item == null:
		return {"ready": false, "reason": "missing"}
	if item.condition_enabled and item.current_condition <= 0.0:
		return {"ready": false, "reason": "broken"}
	if item.is_ranged() and item.is_jammed:
		return {"ready": false, "reason": "jammed"}
	if item.is_ranged() and item.current_magazine <= 0:
		return {"ready": false, "reason": "empty"}
	return {"ready": true, "reason": "ready"}

## Mutates the supplied runtime item exactly once. Passing roll_override makes
## cross-mode parity tests deterministic; production callers omit it.
static func resolve_use(
	item: ItemData,
	event_kind: String,
	roll_override: float = -1.0
) -> Dictionary:
	var before := 0.0 if item == null else item.current_condition
	var band := condition_band(before)
	var chance := fault_chance(before)
	var outcome := {
		"instance_id": "" if item == null else item.instance_id,
		"condition_before": before,
		"condition_after": before,
		"condition_band": band,
		"fault_chance": chance,
		"faulted": false,
		"fault_kind": "",
		"performance_multiplier": 1.0,
		"malfunction_state": false if item == null else item.is_jammed,
		"broke": before <= 0.0,
	}
	if item == null or not item.condition_enabled or before <= 0.0:
		if before <= 0.0:
			outcome["performance_multiplier"] = 0.0
		return outcome

	var roll := randf() if roll_override < 0.0 else clampf(roll_override, 0.0, 1.0)
	var faulted := chance > 0.0 and roll < chance
	var wear := float(DEFAULT_PROFILE.wear_rates.get(
		event_kind,
		EVENT_WEAR.get(event_kind, 0.0)
	))
	wear *= grade_wear_multiplier(item.item_grade)
	item.current_condition = clampf(before - wear, 0.0, GameEnums.SCALE_MAX)

	outcome["condition_after"] = item.current_condition
	outcome["faulted"] = faulted
	outcome["broke"] = item.current_condition <= 0.0
	if faulted:
		outcome["fault_kind"] = event_kind
		match event_kind:
			EVENT_FIREARM:
				item.is_jammed = true
				outcome["performance_multiplier"] = 0.0
			EVENT_MELEE, EVENT_ARMOR, EVENT_SHIELD:
				outcome["performance_multiplier"] = 0.5
			EVENT_TOOL:
				outcome["performance_multiplier"] = 0.0
	outcome["malfunction_state"] = item.is_jammed
	return outcome

static func clear_malfunction(item: ItemData) -> bool:
	if item == null or not item.is_ranged() or item.current_condition <= 0.0:
		return false
	if not item.is_jammed:
		return false
	item.is_jammed = false
	return true
