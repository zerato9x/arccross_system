extends Resource
class_name CombatActorState

## Encounter-local actor state. Biological wounds and inventory remain owned by
## their existing systems; this resource contains only tactical projection.

const SCHEMA_VERSION := 1

@export var schema_version: int = SCHEMA_VERSION
@export_range(0.0, 12.0) var stance: float = 12.0
@export_range(0.0, 12.0) var max_stance: float = 12.0
@export var broken: bool = false
@export var incapacitated: bool = false
@export var surrendered: bool = false
@export var cover_object_id: String = ""
@export var communication_order: String = ""
@export var last_action_signature: String = ""
@export var activation_lost: bool = false
## Coarse public AI intent. Detailed evaluator traces remain outside encounter
## state and are published only through the Lab/debug signal.
@export var public_intent: Dictionary = {}
@export var intent_revision: int = 0


func reconcile() -> void:
	max_stance = clampf(max_stance, 0.0, 12.0)
	stance = clampf(stance, 0.0, max_stance)
	broken = stance <= 0.0 and not incapacitated and not surrendered


func to_dict() -> Dictionary:
	return {
		"schema_version": schema_version,
		"stance": stance,
		"max_stance": max_stance,
		"broken": broken,
		"incapacitated": incapacitated,
		"surrendered": surrendered,
		"cover_object_id": cover_object_id,
		"communication_order": communication_order,
		"last_action_signature": last_action_signature,
		"activation_lost": activation_lost,
		"public_intent": public_intent.duplicate(true),
		"intent_revision": intent_revision,
	}


static func from_runtime(payload: Dictionary) -> CombatActorState:
	var error := compatibility_error(payload)
	if not error.is_empty():
		push_error("[COMBAT SCHEMA] " + error)
		return null
	var state := CombatActorState.new()
	state.schema_version = SCHEMA_VERSION
	state.stance = float(payload.get("stance", 12.0))
	state.max_stance = float(payload.get("max_stance", 12.0))
	state.broken = bool(payload.get("broken", false))
	state.incapacitated = bool(payload.get("incapacitated", false))
	state.surrendered = bool(payload.get("surrendered", false))
	state.cover_object_id = str(payload.get("cover_object_id", ""))
	state.communication_order = str(payload.get("communication_order", ""))
	state.last_action_signature = str(payload.get("last_action_signature", ""))
	state.activation_lost = bool(payload.get("activation_lost", false))
	state.public_intent = payload.get("public_intent", {}).duplicate(true)
	state.intent_revision = int(payload.get("intent_revision", 0))
	state.reconcile()
	return state


static func compatibility_error(payload: Dictionary) -> String:
	# An empty payload is the runtime representation of a newly created actor.
	# Any populated snapshot must identify the exact tactical schema it uses;
	# silently normalising old state is how retired combat authority sneaks back.
	if payload.is_empty():
		return ""
	if not payload.has("schema_version"):
		return "Combat actor snapshot has no schema_version; start a new combat encounter."
	var found_version := int(payload.get("schema_version", -1))
	if found_version != SCHEMA_VERSION:
		return "Combat actor snapshot schema %d is incompatible with current schema %d; start a new combat encounter." % [
			found_version,
			SCHEMA_VERSION,
		]
	for retired_field in [
		"actor_facing",
		"facing",
		"final_facing",
		"posture",
		"postures",
		"reserved_ap",
		"reaction_ap",
		"reaction_threat_ids",
		"ordered_reaction_steps",
	]:
		if payload.has(retired_field):
			return "Combat actor snapshot contains retired field '%s'; start a new combat encounter." % retired_field
	return ""
