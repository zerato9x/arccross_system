extends Resource
class_name CombatActionOutcome

## Atomic committed result. Presentation consumes this record but cannot edit it.

@export var committed: bool = false
@export var actor_id: String = ""
@export var action_id: String = ""
@export var ap_spent: int = 0
@export var actor_changes: Array[Dictionary] = []
@export var sector_changes: Array[Dictionary] = []
@export var rolls: Array[Dictionary] = []
@export var wound_events: Array[Dictionary] = []
@export var item_receipts: Array[Dictionary] = []
@export var reactions: Array[Dictionary] = []
@export var terrain_mutations: Array[Dictionary] = []
@export var presentation_sequence: CombatPresentationSequence
@export var message: String = ""


func to_dict() -> Dictionary:
	return {
		"committed": committed,
		"actor_id": actor_id,
		"action_id": action_id,
		"ap_spent": ap_spent,
		"actor_changes": actor_changes.duplicate(true),
		"sector_changes": sector_changes.duplicate(true),
		"rolls": rolls.duplicate(true),
		"wound_events": wound_events.duplicate(true),
		"item_receipts": item_receipts.duplicate(true),
		"reactions": reactions.duplicate(true),
		"terrain_mutations": terrain_mutations.duplicate(true),
		"presentation_sequence": (
			presentation_sequence.to_dict() if presentation_sequence != null else {}
		),
		"message": message,
	}
