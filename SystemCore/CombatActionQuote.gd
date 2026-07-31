extends Resource
class_name CombatActionQuote

## Read-only result of validating and pricing one tactical request.

@export var legal: bool = false
@export var denial_code: String = ""
@export var denial_message: String = ""
@export var actor_id: String = ""
@export var action_id: String = ""
@export var origin_sector: Vector2i = Vector2i(-1, -1)
@export var target_sector: Vector2i = Vector2i(-1, -1)
@export var path: Array[Vector2i] = []
@export var final_facing: String = ""
@export var ap_cost: int = 0
@export var movement_cost: int = 0
@export var has_line_of_sight: bool = false
@export var cover_strength: float = 0.0
@export var range_cells: int = 0
@export var reaction_threat_ids: Array[String] = []
@export var predicted_displacement: Array[Dictionary] = []
@export var collision_preview: Dictionary = {}
@export var presentation_profile_id: String = ""
@export var forecast: CombatForecastRecord


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
		"target_sector": target_sector,
		"path": path.duplicate(),
		"final_facing": final_facing,
		"ap_cost": ap_cost,
		"movement_cost": movement_cost,
		"has_line_of_sight": has_line_of_sight,
		"cover_strength": cover_strength,
		"range_cells": range_cells,
		"reaction_threat_ids": reaction_threat_ids.duplicate(),
		"predicted_displacement": predicted_displacement.duplicate(true),
		"collision_preview": collision_preview.duplicate(true),
		"presentation_profile_id": presentation_profile_id,
		"forecast": forecast.to_dict() if forecast != null else {},
	}
