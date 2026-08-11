extends Resource
class_name NpcBehaviorState

const SCHEMA_VERSION := 2
const RUNTIME_KEY := "npc_behavior"

@export var schema_version: int = SCHEMA_VERSION
@export var profile_id: String = ""
@export_range(0.0, 12.0, 0.1) var survival_pressure: float = 0.0
## Encounter instructions are persistent bias, not direct player control.
@export var combat_instruction: String = ""
@export var current_motive: String = ""
@export var current_subject_id: String = ""
@export var last_intent_revision: int = 0
## Compact replay/debug evidence retained with the neutral behavior record.
@export var last_decision_trace: Dictionary = {}
var decision_memory: Dictionary = {}


func to_dict() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"profile_id": profile_id,
		"survival_pressure": clampf(survival_pressure, 0.0, GameEnums.SCALE_MAX),
		"combat_instruction": combat_instruction,
		"current_motive": current_motive,
		"current_subject_id": current_subject_id,
		"last_intent_revision": last_intent_revision,
		"last_decision_trace": last_decision_trace.duplicate(true),
		"decision_memory": decision_memory.duplicate(true),
	}


static func from_runtime(runtime: Dictionary, definition: Dictionary = {}):
	# Load through the script resource so cold editor sessions do not depend on
	# the global class cache being refreshed before combat starts.
	var state = (load("res://SystemCore/NpcBehaviorState.gd") as Script).new()
	var payload: Dictionary = runtime.get(RUNTIME_KEY, {})
	state.schema_version = maxi(1, int(payload.get("schema_version", SCHEMA_VERSION)))
	state.profile_id = str(payload.get("profile_id", ""))
	state.survival_pressure = clampf(
		float(payload.get("survival_pressure", _legacy_pressure(runtime))),
		0.0,
		GameEnums.SCALE_MAX
	)
	state.combat_instruction = str(payload.get("combat_instruction", payload.get("instruction", "")))
	state.current_motive = str(payload.get("current_motive", payload.get("decision_memory", {}).get("current_motive", "")))
	state.current_subject_id = str(payload.get("current_subject_id", payload.get("decision_memory", {}).get("current_subject_id", "")))
	state.last_intent_revision = int(payload.get("last_intent_revision", payload.get("decision_memory", {}).get("last_intent_revision", 0)))
	state.last_decision_trace = payload.get("last_decision_trace", {}).duplicate(true)
	state.decision_memory = payload.get("decision_memory", {}).duplicate(true)
	if state.profile_id.is_empty():
		state.profile_id = _profile_id_for(definition, runtime)
	return state


static func ensure_runtime(runtime: Dictionary, definition: Dictionary = {}) -> Dictionary:
	var result := runtime.duplicate(true)
	result[RUNTIME_KEY] = from_runtime(result, definition).to_dict()
	return result


static func _legacy_pressure(runtime: Dictionary) -> float:
	# Older macro records stored three simulation meters. They remain intact for
	# compatibility, but AI consumes one explicit pressure value from now on.
	var biology: Dictionary = runtime.get("biology", {})
	if biology.is_empty():
		return 0.0
	var hunger_pressure := GameEnums.SCALE_MAX - float(biology.get("hunger", GameEnums.SCALE_MAX))
	var thirst_pressure := GameEnums.SCALE_MAX - float(biology.get("thirst", GameEnums.SCALE_MAX))
	var fatigue_pressure := float(biology.get("fatigue", 0.0))
	var wound_pressure := float(biology.get("wounds", 0.0))
	return clampf(maxf(maxf(hunger_pressure, thirst_pressure), maxf(fatigue_pressure, wound_pressure)), 0.0, GameEnums.SCALE_MAX)


static func _profile_id_for(definition: Dictionary, runtime: Dictionary) -> String:
	var role_id := str(runtime.get("npc_role_id", definition.get("npc_role_id", "")))
	var role_profiles := {
		"patrol": "marksman", "raider": "opportunist", "resident": "defender",
		"salvager": "opportunist", "scavenger": "opportunist", "sentry": "defender",
		"stalker": "brute", "technician": "defender",
	}
	if role_profiles.has(role_id):
		return str(role_profiles[role_id])
	match int(definition.get("combat_tactic", GameEnums.CombatTactic.BRUTE)):
		GameEnums.CombatTactic.MARKSMAN:
			return "marksman"
		GameEnums.CombatTactic.OPPORTUNIST:
			return "opportunist"
		GameEnums.CombatTactic.DEFENDER:
			return "defender"
		_:
			return "brute"
