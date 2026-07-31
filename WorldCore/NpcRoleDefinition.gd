extends Resource
class_name NpcRoleDefinition

@export var role_id: String = "drifter"
@export var display_name: String = "Drifter"
@export_multiline var description: String = ""
@export var default_goal_id: String = "roam"
@export var goal_weights: Dictionary = {"roam": 1.0}
@export_range(0, 24) var detection_radius: int = 5
@export_range(0, 24) var pursuit_radius: int = 6
@export var stationary: bool = false
@export var plot_actor: bool = false
@export var investigates_noise: bool = false
@export var can_scavenge: bool = false
@export var visual_mode: String = "equipment_rig"
@export_file("*.png") var token_sprite_path: String = ""


func to_descriptor() -> Dictionary:
	return {
		"role_id": role_id,
		"display_name": display_name,
		"description": description,
		"default_goal_id": default_goal_id,
		"goal_weights": goal_weights.duplicate(true),
		"detection_radius": detection_radius,
		"pursuit_radius": pursuit_radius,
		"stationary": stationary,
		"plot_actor": plot_actor,
		"investigates_noise": investigates_noise,
		"can_scavenge": can_scavenge,
		"visual_mode": visual_mode,
		"token_sprite_path": token_sprite_path,
	}
