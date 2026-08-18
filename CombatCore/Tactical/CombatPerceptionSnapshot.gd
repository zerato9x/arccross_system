extends RefCounted
class_name CombatPerceptionSnapshot

## Immutable evaluation input.  The builder owns the only construction path;
## consumers receive duplicated neutral dictionaries rather than live nodes.

var revision: int = 0
var encounter_seed: String = ""
var round_index: int = 0
var _actor: Dictionary = {}
var _hard_facts: Dictionary = {}
var _known_actors: Dictionary = {}
var _relationships: Dictionary = {}
var _sectors: Dictionary = {}
var _objects: Dictionary = {}
var _hazards: Dictionary = {}
var _exits: Dictionary = {}
var _capabilities: Dictionary = {}
var _communication: Dictionary = {}
var _previous_intent: Dictionary = {}
var reevaluation_trigger: String = "initial"
var frozen: bool = true

## Public projections are defensive copies. Builders may assign a complete
## projection, but evaluators cannot mutate the sealed observation by editing
## a returned dictionary.
var actor: Dictionary:
	get: return _actor.duplicate(true)
	set(value): _actor = value.duplicate(true)
var hard_facts: Dictionary:
	get: return _hard_facts.duplicate(true)
	set(value): _hard_facts = value.duplicate(true)
var known_actors: Dictionary:
	get: return _duplicate_known_actors(_known_actors)
	set(value): _known_actors = _copy_known_actors(value)
var relationships: Dictionary:
	get: return _relationships.duplicate(true)
	set(value): _relationships = value.duplicate(true)
var sectors: Dictionary:
	get: return _sectors.duplicate(true)
	set(value): _sectors = value.duplicate(true)
var objects: Dictionary:
	get: return _objects.duplicate(true)
	set(value): _objects = value.duplicate(true)
var hazards: Dictionary:
	get: return _hazards.duplicate(true)
	set(value): _hazards = value.duplicate(true)
var exits: Dictionary:
	get: return _exits.duplicate(true)
	set(value): _exits = value.duplicate(true)
var capabilities: Dictionary:
	get: return _capabilities.duplicate(true)
	set(value): _capabilities = value.duplicate(true)
var communication: Dictionary:
	get: return _communication.duplicate(true)
	set(value): _communication = value.duplicate(true)
var previous_intent: Dictionary:
	get: return _previous_intent.duplicate(true)
	set(value): _previous_intent = value.duplicate(true)


func mutable_actor_projection() -> Dictionary:
	return _actor.duplicate(true)


func mutable_communication_projection() -> Dictionary:
	return _communication.duplicate(true)


func duplicate_snapshot():
	var copy = (load("res://CombatCore/Tactical/CombatPerceptionSnapshot.gd") as Script).new()
	copy.revision = revision
	copy.encounter_seed = encounter_seed
	copy.round_index = round_index
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


static func _copy_known_actors(source: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for actor_id in source.keys():
		var observed = source[actor_id]
		result[actor_id] = observed.duplicate_observation() if observed != null and observed.has_method("duplicate_observation") else observed.duplicate(true)
	return result


static func _duplicate_known_actors(source: Dictionary) -> Dictionary:
	return _copy_known_actors(source)


func to_dict() -> Dictionary:
	var observed: Dictionary = {}
	for actor_id in known_actors.keys():
		var value = known_actors[actor_id]
		observed[actor_id] = value.to_dict() if value != null and value.has_method("to_dict") else value.duplicate(true)
	return {
		"revision": revision,
		"encounter_seed": encounter_seed,
		"round": round_index,
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
