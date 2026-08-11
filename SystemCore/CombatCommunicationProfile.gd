extends Resource
class_name CombatCommunicationProfile

## Data-authored social resolution. The resolver consumes plain projections so
## macro negotiation and tactical combat can share this contract without
## importing either application layer.

@export var profile_id: String = "default_communication"
@export_range(0, 12) var base_communication_points: int = 0
## Legacy resource key retained for deterministic loading of older profiles.
@export_range(0, 12) var base_squad_points: int = 2
@export var will_divisor: int = 3
@export var morale_modifiers: Dictionary = {"critical": -1, "normal": 0, "confident": 1}
@export var cohesion_modifiers: Dictionary = {"isolated": -1, "normal": 0, "cohesive": 2}
@export_range(0, 2) var biological_crisis_penalty: int = 2
@export var intent_biases: Dictionary = {
	"offense": 1.0,
	"defense": 0.5,
	"support": 0.25,
	"flee": -0.5,
	"threaten": 0.0,
	"ceasefire": 1.0,
}
@export var agenda_biases: Dictionary = {
	"survivalist": 1.5,
	"belligerent": 0.5,
	"zealot": -2.0,
	"mindless": -99.0,
}
@export_range(-12.0, 12.0) var acceptance_threshold: float = 0.0


func intent_bias(intent: String) -> float:
	return float(intent_biases.get(intent, 0.0))


func agenda_bias(agenda: String) -> float:
	return float(agenda_biases.get(agenda.to_lower(), 0.0))


func morale_modifier(morale_band: String) -> int:
	return int(morale_modifiers.get(morale_band, 0))


func cohesion_modifier(cohesion_band: String) -> int:
	return int(cohesion_modifiers.get(cohesion_band, 0))


func resolved_base_communication_points() -> int:
	if base_communication_points != 0 or base_squad_points == 0:
		return clampi(base_communication_points, 0, 12)
	return clampi(base_squad_points, 0, 12)
