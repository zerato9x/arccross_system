extends Resource
class_name CombatResultRecord

@export var encounter_id: String = ""
@export var source_coords: Vector2i = Vector2i.ZERO
@export var outcome: int = GameEnums.CombatOutcome.DRAW
@export var reason: String = "mutual_incapacity"
@export var actor_runtime_updates: Array[Dictionary] = []
@export var participant_results: Array[Dictionary] = []
@export var participant_contexts: Dictionary = {}
@export var escaped_actor_ids: Array[String] = []
@export var withdrawn_actor_ids: Array[String] = []
@export var item_transfer_receipts: Array[Dictionary] = []
@export var body_locations: Array[Dictionary] = []
## Non-lethal terminal handoffs stay distinct from bodies.  A captive or
## surrendered actor still owns their inventory and can be handed to the macro
## conversation layer without being mistaken for a dead entity.
@export var incapacitated_locations: Array[Dictionary] = []
@export var surrendered_actor_ids: Array[String] = []
@export var surrendered_locations: Array[Dictionary] = []
@export var ground_items: Array[Dictionary] = []
@export var environment_patch: Dictionary = {}
@export var trap_outcomes: Array[Dictionary] = []
@export var elapsed_minutes: int = 0
@export var escape_edge: String = ""
@export var relationship_state: Dictionary = {}
@export var communication_points_spent: int = 0
@export var communication_points_remaining: int = 0
## Legacy aliases retained for save/runtime readers.
var squad_points_spent: int:
	get: return communication_points_spent
	set(value): communication_points_spent = maxi(0, value)
var squad_points_remaining: int:
	get: return communication_points_remaining
	set(value): communication_points_remaining = clampi(value, 0, 12)


func to_dict() -> Dictionary:
	return {
		"encounter_id": encounter_id,
		"source_coords": source_coords,
		"outcome": outcome,
		"reason": reason,
		"actor_runtime_updates": actor_runtime_updates.duplicate(true),
		"participant_results": participant_results.duplicate(true),
		"participant_contexts": participant_contexts.duplicate(true),
		"escaped_actor_ids": escaped_actor_ids.duplicate(),
		"withdrawn_actor_ids": withdrawn_actor_ids.duplicate(),
		"item_transfer_receipts": item_transfer_receipts.duplicate(true),
		"body_locations": body_locations.duplicate(true),
		"incapacitated_locations": incapacitated_locations.duplicate(true),
		"surrendered_actor_ids": surrendered_actor_ids.duplicate(),
		"surrendered_locations": surrendered_locations.duplicate(true),
		"ground_items": ground_items.duplicate(true),
		"environment_patch": environment_patch.duplicate(true),
		"trap_outcomes": trap_outcomes.duplicate(true),
		"elapsed_minutes": elapsed_minutes,
		"escape_edge": escape_edge,
		"relationship_state": relationship_state.duplicate(true),
		"communication_points_spent": communication_points_spent,
		"communication_points_remaining": communication_points_remaining,
		"squad_points_spent": communication_points_spent,
		"squad_points_remaining": communication_points_remaining,
	}


static func from_dict(data: Dictionary) -> CombatResultRecord:
	var record := CombatResultRecord.new()
	record.encounter_id = str(data.get("encounter_id", ""))
	record.source_coords = data.get("source_coords", Vector2i.ZERO)
	record.outcome = int(data.get("outcome", GameEnums.CombatOutcome.DRAW))
	record.reason = str(data.get("reason", "mutual_incapacity"))
	for raw_update in data.get("actor_runtime_updates", []):
		if raw_update is Dictionary:
			record.actor_runtime_updates.append((raw_update as Dictionary).duplicate(true))
	for raw_result in data.get("participant_results", []):
		if raw_result is Dictionary:
			record.participant_results.append((raw_result as Dictionary).duplicate(true))
	record.participant_contexts = data.get("participant_contexts", {}).duplicate(true)
	for actor_id in data.get("escaped_actor_ids", []):
		record.escaped_actor_ids.append(str(actor_id))
	for actor_id in data.get("withdrawn_actor_ids", []):
		record.withdrawn_actor_ids.append(str(actor_id))
	record.item_transfer_receipts = data.get("item_transfer_receipts", []).duplicate(true)
	record.body_locations = data.get("body_locations", []).duplicate(true)
	record.incapacitated_locations = data.get("incapacitated_locations", []).duplicate(true)
	for actor_id in data.get("surrendered_actor_ids", []):
		record.surrendered_actor_ids.append(str(actor_id))
	record.surrendered_locations = data.get("surrendered_locations", []).duplicate(true)
	record.ground_items = data.get("ground_items", []).duplicate(true)
	record.environment_patch = data.get("environment_patch", {}).duplicate(true)
	record.trap_outcomes = data.get("trap_outcomes", []).duplicate(true)
	record.elapsed_minutes = int(data.get("elapsed_minutes", 0))
	record.escape_edge = str(data.get("escape_edge", ""))
	record.relationship_state = data.get("relationship_state", {}).duplicate(true)
	record.communication_points_spent = int(data.get(
		"communication_points_spent",
		data.get("squad_points_spent", 0)
	))
	record.communication_points_remaining = clampi(int(data.get(
		"communication_points_remaining",
		data.get("squad_points_remaining", 0)
	)), 0, 12)
	return record
