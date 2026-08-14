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
@export var random_draws: Array[Dictionary] = []
@export var wound_events: Array[Dictionary] = []
@export var item_receipts: Array[Dictionary] = []
@export var terrain_mutations: Array[Dictionary] = []
@export var presentation_events: Array[Dictionary] = []
@export var presentation_sequence: CombatPresentationSequence
@export var timeline_id: String = ""
@export var result_events: Array[Dictionary] = []
@export var movement_steps_completed: int = 0
@export var action_executed: bool = false
@export var interrupted: bool = false
@export var message: String = ""
@export var decision_trace: Array[Dictionary] = []
@export var stance_events: Array[Dictionary] = []
@export var relation_events: Array[Dictionary] = []
@export var communication_receipts: Array[Dictionary] = []
@export var occupancy_transitions: Array[Dictionary] = []
@export var ai_replan_requests: Array[Dictionary] = []


func to_dict() -> Dictionary:
	return {
		"committed": committed,
		"actor_id": actor_id,
		"action_id": action_id,
		"ap_spent": ap_spent,
		"actor_changes": actor_changes.duplicate(true),
		"sector_changes": sector_changes.duplicate(true),
		"rolls": rolls.duplicate(true),
		"random_draws": random_draws.duplicate(true),
		"wound_events": wound_events.duplicate(true),
		"item_receipts": item_receipts.duplicate(true),
		"terrain_mutations": terrain_mutations.duplicate(true),
		"presentation_events": presentation_events.duplicate(true),
		"presentation_sequence": (
			presentation_sequence.to_dict() if presentation_sequence != null else {}
		),
		"timeline_id": timeline_id,
		"result_events": result_events.duplicate(true),
		"movement_steps_completed": movement_steps_completed,
		"action_executed": action_executed,
		"interrupted": interrupted,
		"message": message,
		"decision_trace": decision_trace.duplicate(true),
		"stance_events": stance_events.duplicate(true),
		"relation_events": relation_events.duplicate(true),
		"communication_receipts": communication_receipts.duplicate(true),
		"occupancy_transitions": occupancy_transitions.duplicate(true),
		"ai_replan_requests": ai_replan_requests.duplicate(true),
	}
