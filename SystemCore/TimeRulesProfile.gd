@tool
extends Resource
class_name TimeRulesProfile

@export var profile_id: String = "default"
@export var action_minutes: Dictionary = {}
@export var travel_minutes_per_step: int = 15
@export var camp_minutes: int = 60
@export var sleep_minutes: int = 360


func minutes_for(action_id: String, fallback: int = 0) -> int:
	return maxi(0, int(action_minutes.get(action_id, fallback)))
