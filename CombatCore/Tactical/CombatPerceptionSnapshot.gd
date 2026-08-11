extends RefCounted
class_name CombatPerceptionSnapshot

## Immutable evaluation input.  The builder owns the only construction path;
## consumers receive duplicated neutral dictionaries rather than live nodes.

var revision: int = 0
var encounter_seed: String = ""
var round: int = 0
var actor: Dictionary = {}
var hard_facts: Dictionary = {}
var known_actors: Dictionary = {}
var relationships: Dictionary = {}
var sectors: Dictionary = {}
var objects: Dictionary = {}
var hazards: Dictionary = {}
var exits: Dictionary = {}
var capabilities: Dictionary = {}
var communication: Dictionary = {}
var previous_intent: Dictionary = {}
var reevaluation_trigger: String = "initial"
var frozen: bool = true


func duplicate_snapshot():
	var copy = (load("res://CombatCore/Tactical/CombatPerceptionSnapshot.gd") as Script).new()
	copy.revision = revision
	copy.encounter_seed = encounter_seed
	copy.round = round
	copy.actor = actor.duplicate(true)
	copy.hard_facts = hard_facts.duplicate(true)
	copy.known_actors = {}
	for actor_id in known_actors.keys():
		var observed = known_actors[actor_id]
		copy.known_actors[actor_id] = observed.duplicate_observation() if observed != null and observed.has_method("duplicate_observation") else observed.duplicate(true)
	copy.relationships = relationships.duplicate(true)
	copy.sectors = sectors.duplicate(true)
	copy.objects = objects.duplicate(true)
	copy.hazards = hazards.duplicate(true)
	copy.exits = exits.duplicate(true)
	copy.capabilities = capabilities.duplicate(true)
	copy.communication = communication.duplicate(true)
	copy.previous_intent = previous_intent.duplicate(true)
	copy.reevaluation_trigger = reevaluation_trigger
	copy.frozen = true
	return copy


func to_dict() -> Dictionary:
	var observed: Dictionary = {}
	for actor_id in known_actors.keys():
		var value = known_actors[actor_id]
		observed[actor_id] = value.to_dict() if value != null and value.has_method("to_dict") else value.duplicate(true)
	return {
		"revision": revision,
		"encounter_seed": encounter_seed,
		"round": round,
		"actor": actor.duplicate(true),
		"hard_facts": hard_facts.duplicate(true),
		"known_actors": observed,
		"relationships": relationships.duplicate(true),
		"sectors": sectors.duplicate(true),
		"objects": objects.duplicate(true),
		"hazards": hazards.duplicate(true),
		"exits": exits.duplicate(true),
		"capabilities": capabilities.duplicate(true),
		"communication": communication.duplicate(true),
		"previous_intent": previous_intent.duplicate(true),
		"reevaluation_trigger": reevaluation_trigger,
	}
