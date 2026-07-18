extends Resource
class_name Wound

## Persistent injury record. Limb HP describes structural integrity; wounds
## describe what happened to the tissue and what continues to affect the actor.

var wound_id: String = ""
var wound_type: GameEnums.WoundType = GameEnums.WoundType.BRUISE
var severity: float = 0.0
var bleeding_rate: float = 0.0
var pain: float = 0.0
var contamination: float = 0.0
var treated: bool = false
var age_minutes: int = 0


func active_bleeding_rate() -> float:
	return maxf(0.0, bleeding_rate)


func apply_treatment(potency: float) -> float:
	var before := active_bleeding_rate()
	bleeding_rate = maxf(0.0, bleeding_rate - maxf(0.0, potency) * 0.1)
	treated = true
	contamination = maxf(0.0, contamination - maxf(0.0, potency) * 0.25)
	return before - active_bleeding_rate()


func process_recovery(tick_scale: float, recovery_quality: float) -> void:
	age_minutes += int(roundf(15.0 * tick_scale))
	if active_bleeding_rate() > 0.0 and not treated:
		contamination = minf(GameEnums.SCALE_MAX, contamination + 0.08 * tick_scale)
		return
	var contamination_modifier := clampf(1.0 - contamination / 16.0, 0.25, 1.0)
	var healing := 0.035 * tick_scale * clampf(recovery_quality, 0.25, 1.0) * contamination_modifier
	severity = maxf(0.0, severity - healing)
	pain = maxf(0.0, pain - healing * 1.25)
	if treated:
		contamination = maxf(0.0, contamination - 0.04 * tick_scale)
	if contamination >= 8.0:
		pain = minf(GameEnums.SCALE_MAX, pain + 0.015 * tick_scale)


func display_name() -> String:
	return str(GameEnums.WoundType.keys()[wound_type]).replace("_", " ").capitalize()


func to_dict() -> Dictionary:
	return {
		"wound_id": wound_id,
		"wound_type": int(wound_type),
		"severity": severity,
		"bleeding_rate": bleeding_rate,
		"pain": pain,
		"contamination": contamination,
		"treated": treated,
		"age_minutes": age_minutes,
	}


static func from_dict(data: Dictionary) -> Wound:
	var wound := Wound.new()
	wound.wound_id = str(data.get("wound_id", ""))
	wound.wound_type = int(data.get("wound_type", GameEnums.WoundType.BRUISE)) as GameEnums.WoundType
	wound.severity = clampf(float(data.get("severity", 0.0)), 0.0, GameEnums.SCALE_MAX)
	wound.bleeding_rate = maxf(0.0, float(data.get("bleeding_rate", 0.0)))
	wound.pain = clampf(float(data.get("pain", 0.0)), 0.0, GameEnums.SCALE_MAX)
	wound.contamination = clampf(float(data.get("contamination", 0.0)), 0.0, GameEnums.SCALE_MAX)
	wound.treated = bool(data.get("treated", false))
	wound.age_minutes = maxi(0, int(data.get("age_minutes", 0)))
	return wound
