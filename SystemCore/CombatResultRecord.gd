extends Resource
class_name CombatResultRecord

@export var encounter_id: String = ""
@export var source_coords: Vector2i = Vector2i.ZERO
@export var outcome: int = GameEnums.CombatOutcome.DRAW
@export var reason: String = "mutual_incapacity"
@export var actor_runtime_updates: Array[Dictionary] = []
@export var item_transfer_receipts: Array[Dictionary] = []
@export var body_locations: Array[Dictionary] = []
@export var ground_items: Array[Dictionary] = []
@export var environment_patch: Dictionary = {}
@export var trap_outcomes: Array[Dictionary] = []
@export var elapsed_minutes: int = 0
@export var escape_edge: String = ""


func to_dict() -> Dictionary:
	return {
		"encounter_id": encounter_id,
		"source_coords": source_coords,
		"outcome": outcome,
		"reason": reason,
		"actor_runtime_updates": actor_runtime_updates.duplicate(true),
		"item_transfer_receipts": item_transfer_receipts.duplicate(true),
		"body_locations": body_locations.duplicate(true),
		"ground_items": ground_items.duplicate(true),
		"environment_patch": environment_patch.duplicate(true),
		"trap_outcomes": trap_outcomes.duplicate(true),
		"elapsed_minutes": elapsed_minutes,
		"escape_edge": escape_edge,
	}


static func from_dict(data: Dictionary) -> CombatResultRecord:
	var record := CombatResultRecord.new()
	record.encounter_id = str(data.get("encounter_id", ""))
	record.source_coords = data.get("source_coords", Vector2i.ZERO)
	record.outcome = int(data.get("outcome", GameEnums.CombatOutcome.DRAW))
	record.reason = str(data.get("reason", "mutual_incapacity"))
	record.actor_runtime_updates = data.get("actor_runtime_updates", []).duplicate(true)
	record.item_transfer_receipts = data.get("item_transfer_receipts", []).duplicate(true)
	record.body_locations = data.get("body_locations", []).duplicate(true)
	record.ground_items = data.get("ground_items", []).duplicate(true)
	record.environment_patch = data.get("environment_patch", {}).duplicate(true)
	record.trap_outcomes = data.get("trap_outcomes", []).duplicate(true)
	record.elapsed_minutes = int(data.get("elapsed_minutes", 0))
	record.escape_edge = str(data.get("escape_edge", ""))
	return record
