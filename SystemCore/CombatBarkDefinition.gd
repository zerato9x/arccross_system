@tool
extends Resource
class_name CombatBarkDefinition

## Sparse authored presentation bark. Dialogue authority remains in the
## communication resolver; this resource only chooses a readable line.

@export var dialogue_id: String = ""
@export var role_id: String = ""
@export var faction_id: String = ""
@export var event_id: String = ""
@export var priority: int = 0
@export var lines: Array[String] = []


func matches(actor: Dictionary, event: String, requested_dialogue_id: String = "") -> bool:
	if not requested_dialogue_id.is_empty() and not dialogue_id.is_empty() and dialogue_id != requested_dialogue_id and not dialogue_id.begins_with("generic_"):
		return false
	if not event_id.is_empty() and event_id != event:
		return false
	var role := str(actor.get("role_id", actor.get("npc_role_id", "")))
	var faction := str(actor.get("faction_id", actor.get("faction", "")))
	if not role_id.is_empty() and role_id != role:
		return false
	if not faction_id.is_empty() and faction_id != faction:
		return false
	return not lines.is_empty()
