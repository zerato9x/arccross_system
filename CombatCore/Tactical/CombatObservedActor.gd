extends RefCounted
class_name CombatObservedActor

## Actor projection visible to one evaluator. Unknown values remain unknown;
## they are not filled with authoritative defaults.

var actor_id: String = ""
var knowledge_state: String = "unknown"
var sector: Vector2i = Vector2i(-1, -1)
var last_known_sector: Vector2i = Vector2i(-1, -1)
var relation: int = 0
var visible_condition: String = "unknown"
var _observable_wounds: Array[Dictionary] = []
var _observable_weapon: Dictionary = {}
var _public_intent: Dictionary = {}
var distance: int = -1
var line_of_sight: bool = false
var cover: float = 0.0
var engagement: bool = false
var threat_estimate: float = 0.0
var observation_revision: int = -1
var confidence: float = 0.0

var observable_wounds: Array[Dictionary]:
	get: return _observable_wounds.duplicate(true)
	set(value): _observable_wounds = value.duplicate(true)
var observable_weapon: Dictionary:
	get: return _observable_weapon.duplicate(true)
	set(value): _observable_weapon = value.duplicate(true)
var public_intent: Dictionary:
	get: return _public_intent.duplicate(true)
	set(value): _public_intent = value.duplicate(true)


func duplicate_observation():
	var copy = (load("res://CombatCore/Tactical/CombatObservedActor.gd") as Script).new()
	copy.actor_id = actor_id
	copy.knowledge_state = knowledge_state
	copy.sector = sector
	copy.last_known_sector = last_known_sector
	copy.relation = relation
	copy.visible_condition = visible_condition
	copy.observable_wounds = observable_wounds.duplicate(true)
	copy.observable_weapon = observable_weapon.duplicate(true)
	copy.public_intent = public_intent.duplicate(true)
	copy.distance = distance
	copy.line_of_sight = line_of_sight
	copy.cover = cover
	copy.engagement = engagement
	copy.threat_estimate = threat_estimate
	copy.observation_revision = observation_revision
	copy.confidence = confidence
	return copy


func to_dict() -> Dictionary:
	return {
		"actor_id": actor_id,
		"knowledge_state": knowledge_state,
		"sector": sector,
		"last_known_sector": last_known_sector,
		"relation": relation,
		"visible_condition": visible_condition,
		"observable_wounds": observable_wounds.duplicate(true),
		"observable_weapon": observable_weapon.duplicate(true),
		"public_intent": public_intent.duplicate(true),
		"distance": distance,
		"line_of_sight": line_of_sight,
		"cover": cover,
		"engagement": engagement,
		"threat_estimate": threat_estimate,
		"observation_revision": observation_revision,
		"confidence": confidence,
	}
