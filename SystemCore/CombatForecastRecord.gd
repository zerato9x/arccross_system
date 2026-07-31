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
		"bleeding_risk": bleeding_risk,
		"severe_wound_risk": severe_wound_risk,
		"incapacity_risk": incapacity_risk,
		"notes": notes.duplicate(),
	}
