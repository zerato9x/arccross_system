extends Resource
class_name CombatActionRequest

@export var actor_id: String = ""
@export var action_id: String = ""
@export var target_actor_id: String = ""
@export var target_sector: Vector2i = Vector2i(-1, -1)
@export var target_item_instance_id: String = ""
@export var target_wound_id: String = ""
@export var target_body_region: int = -1
@export var path: Array[Vector2i] = []
## Movement cells staged before a contextual action. `path` remains the
## compatibility field used by older movement-only callers.
@export var approach_path: Array[Vector2i] = []
@export var projected_origin: Vector2i = Vector2i(-1, -1)
@export var movement_ap_cost: int = 0
@export var action_ap_cost: int = 0
@export var shove_direction: String = ""
@export var communication_intent: String = ""
@export var declared_neutral_attack_confirmation: bool = false
@export var metadata: Dictionary = {}


func to_dict() -> Dictionary:
	return {
		"actor_id": actor_id,
		"action_id": action_id,
		"target_actor_id": target_actor_id,
		"target_sector": target_sector,
		"target_item_instance_id": target_item_instance_id,
		"target_wound_id": target_wound_id,
		"target_body_region": target_body_region,
		"path": path.duplicate(),
		"approach_path": approach_path.duplicate(),
		"projected_origin": projected_origin,
		"movement_ap_cost": movement_ap_cost,
		"action_ap_cost": action_ap_cost,
		"shove_direction": shove_direction,
		"communication_intent": communication_intent,
		"declared_neutral_attack_confirmation": declared_neutral_attack_confirmation,
		"metadata": metadata.duplicate(true),
	}
