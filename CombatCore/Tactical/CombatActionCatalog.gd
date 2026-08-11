@tool
extends Resource
class_name CombatActionCatalog

@export var definitions: Array[CombatActionDefinition] = []

var _by_id: Dictionary = {}

const RETIRED_PLAYER_ACTIONS := {
	"stand": true,
	"crouch": true,
	"disengage": true,
	"aimed_strike": true,
	"aimed_fire": true,
	"clear_malfunction": true,
	"block": true,
	"dodge": true,
	"opportunity_strike": true,
}


func is_player_visible(action_id: String) -> bool:
	if RETIRED_PLAYER_ACTIONS.has(action_id):
		return false
	var entry := definition(action_id)
	return entry != null and entry.visibility_tier != "compatibility"


func player_definitions() -> Array[CombatActionDefinition]:
	var result: Array[CombatActionDefinition] = []
	for entry in all():
		if entry != null and is_player_visible(entry.action_id):
			result.append(entry)
	return result


func canonical_definitions() -> Array[CombatActionDefinition]:
	"""Return authored entries that belong to the unified combat model.

	Compatibility resolvers remain loadable for old replay/save callers, but
	new HUD, AI, and catalog tooling should consume this projection instead of
	filtering retired IDs independently.
	"""
	var result: Array[CombatActionDefinition] = []
	for entry in all():
		if entry != null and is_player_visible(entry.action_id):
			result.append(entry)
	return result


func is_ai_visible(action_id: String) -> bool:
	var entry := definition(action_id)
	return entry != null and entry.visibility_tier != "compatibility" and action_id not in RETIRED_PLAYER_ACTIONS


func definition(action_id: String) -> CombatActionDefinition:
	if _by_id.size() != definitions.size():
		_rebuild_index()
	return _by_id.get(action_id) as CombatActionDefinition


func all() -> Array[CombatActionDefinition]:
	return definitions.duplicate()


func _rebuild_index() -> void:
	_by_id.clear()
	for entry in definitions:
		if entry == null or entry.action_id.is_empty():
			continue
		if _by_id.has(entry.action_id):
			push_error("Duplicate combat action ID: %s" % entry.action_id)
			continue
		_by_id[entry.action_id] = entry
