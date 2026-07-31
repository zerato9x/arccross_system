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
@export var final_facing: String = ""
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
		"final_facing": final_facing,
		"metadata": metadata.duplicate(true),
	}
