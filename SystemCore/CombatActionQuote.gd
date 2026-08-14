extends Resource
class_name CombatActionQuote

## Read-only result of validating and pricing one tactical request.

@export var legal: bool = false
@export var denial_code: String = ""
@export var denial_message: String = ""
@export var actor_id: String = ""
@export var action_id: String = ""
@export var origin_sector: Vector2i = Vector2i(-1, -1)
@export var projected_origin: Vector2i = Vector2i(-1, -1)
@export var target_sector: Vector2i = Vector2i(-1, -1)
@export var shove_direction: String = ""
@export var path: Array[Vector2i] = []
@export var approach_path: Array[Vector2i] = []
@export var ap_cost: int = 0
@export var movement_cost: int = 0
@export var movement_ap_cost: int = 0
@export var action_ap_cost: int = 0
@export var movement_step_costs: Array[int] = []
@export var has_line_of_sight: bool = false
@export var cover_strength: float = 0.0
@export var range_cells: int = 0
@export var predicted_displacement: Array[Dictionary] = []
@export var collision_preview: Dictionary = {}
@export var presentation_profile_id: String = ""
@export var forecast: CombatForecastRecord
@export var resulting_occupancy: String = ""
@export var collateral_risk: float = 0.0
@export var stance_forecast: Dictionary = {}
@export var relation_consequence: Dictionary = {}
@export var communication_acceptance_forecast: Dictionary = {}
@export var planning_uncertain: bool = false


func deny(code: String, message: String) -> CombatActionQuote:
	legal = false
	denial_code = code
	denial_message = message
	return self


func allow() -> CombatActionQuote:
	legal = true
	denial_code = ""
	denial_message = ""
	return self


func to_dict() -> Dictionary:
	return {
		"legal": legal,
		"denial_code": denial_code,
		"denial_message": denial_message,
		"actor_id": actor_id,
		"action_id": action_id,
		"origin_sector": origin_sector,
		"projected_origin": projected_origin,
		"target_sector": target_sector,
		"shove_direction": shove_direction,
		"path": path.duplicate(),
		"approach_path": approach_path.duplicate(),
		"ap_cost": ap_cost,
		"movement_cost": movement_cost,
		"movement_ap_cost": movement_ap_cost,
		"action_ap_cost": action_ap_cost,
		"movement_step_costs": movement_step_costs.duplicate(),
		"has_line_of_sight": has_line_of_sight,
		"cover_strength": cover_strength,
		"range_cells": range_cells,
		"predicted_displacement": predicted_displacement.duplicate(true),
		"collision_preview": collision_preview.duplicate(true),
		"presentation_profile_id": presentation_profile_id,
		"resulting_occupancy": resulting_occupancy,
		"collateral_risk": collateral_risk,
		"stance_forecast": stance_forecast.duplicate(true),
		"relation_consequence": relation_consequence.duplicate(true),
		"communication_acceptance_forecast": communication_acceptance_forecast.duplicate(true),
		"planning_uncertain": planning_uncertain,
		"forecast": forecast.to_dict() if forecast != null else {},
	}
