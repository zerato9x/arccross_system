extends Resource
class_name CombatHandoffRecord

enum Status { ACTIVE, APPLIED, CANCELLED }

@export var encounter_id: String = ""
@export var source_coords: Vector2i = Vector2i.ZERO
@export var topology_id: String = "squad_7x5"
@export var actor_ids: Array[String] = []
@export var participant_contexts: Dictionary = {}
@export var participant_revisions: Dictionary = {}
@export var initial_ground_item_ids: Array[String] = []
@export var status: Status = Status.ACTIVE


func to_dict() -> Dictionary:
	return {
		"encounter_id": encounter_id,
		"source_coords": source_coords,
		"topology_id": topology_id,
		"actor_ids": actor_ids.duplicate(),
		"participant_contexts": participant_contexts.duplicate(true),
		"participant_revisions": participant_revisions.duplicate(true),
		"initial_ground_item_ids": initial_ground_item_ids.duplicate(),
		"status": int(status),
	}


static func from_dict(data: Dictionary) -> CombatHandoffRecord:
	var record := CombatHandoffRecord.new()
	record.encounter_id = str(data.get("encounter_id", ""))
	record.source_coords = data.get("source_coords", Vector2i.ZERO)
	record.topology_id = str(data.get("topology_id", "squad_7x5"))
	for actor_id in data.get("actor_ids", []):
		record.actor_ids.append(str(actor_id))
	record.participant_contexts = data.get("participant_contexts", {}).duplicate(true)
	record.participant_revisions = data.get("participant_revisions", {}).duplicate(true)
	for instance_id in data.get("initial_ground_item_ids", []):
		record.initial_ground_item_ids.append(str(instance_id))
	record.status = clampi(
		int(data.get("status", Status.ACTIVE)),
		Status.ACTIVE,
		Status.CANCELLED
	) as Status
	return record
