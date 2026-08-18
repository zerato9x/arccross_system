extends Resource
class_name CombatApplicationReceipt

@export var encounter_id: String = ""
@export var source_coords: Vector2i = Vector2i.ZERO
@export var applied: bool = false
@export var idempotent: bool = false
@export var error: String = ""
@export var player_runtime: Dictionary = {}
@export var participant_actions: Array[Dictionary] = []
@export var ground_items: Array[Dictionary] = []
@export var hostile_roster_changed: bool = false
@export var should_retreat_player: bool = false


func to_dict() -> Dictionary:
	return {
		"encounter_id": encounter_id,
		"source_coords": source_coords,
		"applied": applied,
		"idempotent": idempotent,
		"error": error,
		"player_runtime": player_runtime.duplicate(true),
		"participant_actions": participant_actions.duplicate(true),
		"ground_items": ground_items.duplicate(true),
		"hostile_roster_changed": hostile_roster_changed,
		"should_retreat_player": should_retreat_player,
	}
