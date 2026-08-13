extends Resource
class_name CombatForecastRecord

## Read-only, RNG-free combat forecast shared by player presentation and AI.

@export var hit_probability: float = 0.0
@export var target_body_region: int = -1
@export var probable_body_regions: Array[int] = []
@export var attack_arc: String = "front"
@export var armor_protection: float = 0.0
@export var armor_penetration: float = 0.0
@export var armor_result: String = "none"
@export var expected_post_armor_trauma: float = 0.0
@export var expected_wound_severity: float = 0.0
@export var bleeding_pressure: float = 0.0
@export_range(0.0, 1.0) var incapacity_probability: float = 0.0
@export var bleeding_risk: String = "none"
@export var severe_wound_risk: String = "none"
@export var incapacity_risk: String = "none"
@export var notes: Array[String] = []


func to_dict() -> Dictionary:
	return {
		"hit_probability": hit_probability,
		"target_body_region": target_body_region,
		"probable_body_regions": probable_body_regions.duplicate(),
		"attack_arc": attack_arc,
		"armor_protection": armor_protection,
		"armor_penetration": armor_penetration,
		"armor_result": armor_result,
		"expected_post_armor_trauma": expected_post_armor_trauma,
		"expected_wound_severity": expected_wound_severity,
		"bleeding_pressure": bleeding_pressure,
		"incapacity_probability": incapacity_probability,
		"bleeding_risk": bleeding_risk,
		"severe_wound_risk": severe_wound_risk,
		"incapacity_risk": incapacity_risk,
		"notes": notes.duplicate(),
	}
