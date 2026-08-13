extends Resource
class_name NpcBehaviorState

const SCHEMA_VERSION := 3
const RUNTIME_KEY := "npc_behavior"

@export var schema_version: int = SCHEMA_VERSION
@export var profile_id: String = ""
@export_range(0.0, 12.0, 0.1) var survival_pressure: float = 0.0
## Encounter instructions are persistent bias, not direct player control.
@export var combat_instruction: String = ""
@export var current_motive: String = ""
@export var current_subject_id: String = ""
@export var last_intent_revision: int = 0
@export var motive_revision: int = 0
@export var commitment_subject_id: String = ""
@export var escape_direction: Vector2i = Vector2i.ZERO
@export var return_policy: String = "origin"
@export var recent_sectors: Array[Vector2i] = []
@export var recent_action_signatures: Array[String] = []
@export var recent_problem_signatures: Array[String] = []
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
		"motive_revision": motive_revision,
		"commitment_subject_id": commitment_subject_id,
		"escape_direction": escape_direction,
		"return_policy": return_policy,
		"recent_sectors": recent_sectors.duplicate(),
		"recent_action_signatures": recent_action_signatures.duplicate(),
		"recent_problem_signatures": recent_problem_signatures.duplicate(),
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
	state.motive_revision = int(payload.get("motive_revision", payload.get("decision_memory", {}).get("motive_revision", 0)))
	state.commitment_subject_id = str(payload.get("commitment_subject_id", payload.get("decision_memory", {}).get("commitment_subject_id", "")))
	state.escape_direction = payload.get("escape_direction", payload.get("decision_memory", {}).get("escape_direction", Vector2i.ZERO))
	state.return_policy = str(payload.get("return_policy", payload.get("decision_memory", {}).get("return_policy", "origin")))
	for raw_sector in payload.get("recent_sectors", payload.get("decision_memory", {}).get("recent_sectors", [])):
		if raw_sector is Vector2i:
			state.recent_sectors.append(raw_sector)
		elif raw_sector is Dictionary:
			state.recent_sectors.append(Vector2i(int(raw_sector.get("x", 0)), int(raw_sector.get("y", 0))))
	for raw_signature in payload.get("recent_action_signatures", payload.get("decision_memory", {}).get("recent_action_signatures", [])):
		state.recent_action_signatures.append(str(raw_signature))
	for raw_signature in payload.get("recent_problem_signatures", payload.get("decision_memory", {}).get("recent_problem_signatures", [])):
		state.recent_problem_signatures.append(str(raw_signature))
	state.recent_sectors = _last_three_vectors(state.recent_sectors)
	state.recent_action_signatures = _last_three_strings(state.recent_action_signatures)
	state.recent_problem_signatures = _last_three_strings(state.recent_problem_signatures)
	state.last_decision_trace = payload.get("last_decision_trace", {}).duplicate(true)
	state.decision_memory = payload.get("decision_memory", {}).duplicate(true)
	if state.profile_id.is_empty():
		state.profile_id = _profile_id_for(definition, runtime)
	return state


func remember_decision(sector: Vector2i, action_signature: String, problem_signature: String) -> void:
	_recent_append_vector(recent_sectors, sector)
	_recent_append_string(recent_action_signatures, action_signature)
	_recent_append_string(recent_problem_signatures, problem_signature)


func _recent_append_vector(values: Array[Vector2i], value: Vector2i) -> void:
	values.append(value)
	while values.size() > 3:
		values.pop_front()


func _recent_append_string(values: Array[String], value: String) -> void:
	values.append(value)
	while values.size() > 3:
		values.pop_front()


static func _last_three_vectors(values: Array[Vector2i]) -> Array[Vector2i]:
	while values.size() > 3:
		values.pop_front()
	return values


static func _last_three_strings(values: Array[String]) -> Array[String]:
	while values.size() > 3:
		values.pop_front()
	return values


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
