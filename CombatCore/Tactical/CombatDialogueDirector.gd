extends RefCounted
class_name CombatDialogueDirector

const DEFAULT_CATALOG := preload("res://CombatCore/Tactical/default_combat_barks.tres")

var catalog: CombatBarkCatalog
var _last_round_by_actor: Dictionary = {}
var _last_event_by_actor: Dictionary = {}
var _active: Dictionary = {}


func configure(value: CombatBarkCatalog = null) -> void:
	catalog = value if value != null else DEFAULT_CATALOG


func request_bark(
	actor: Dictionary,
	event: String,
	encounter_seed: String,
	revision: int,
	round_index: int = 0,
	requested_dialogue_id: String = "",
	priority: int = 0
) -> Dictionary:
	if catalog == null or actor.is_empty() or event.is_empty():
		return {}
	var actor_id := str(actor.get("actor_id", ""))
	if actor_id.is_empty():
		return {}
	var last_round := int(_last_round_by_actor.get(actor_id, -1000))
	var same_event := str(_last_event_by_actor.get(actor_id, "")) == event
	var communication_event := event in ["accepted_order", "refused_order", "relation_change", "surrender", "escape", "first_contact"]
	if round_index - last_round < 2 and not (communication_event and priority > 0):
		return {}
	if same_event and priority <= int(_active.get("priority", 0)):
		return {}
	var matches := catalog.candidates(actor, event, requested_dialogue_id)
	if matches.is_empty():
		return {}
	var seed_value := "%s|%s|%s|%d" % [encounter_seed, actor_id, event, revision]
	var index := posmod(seed_value.hash(), matches.size())
	var definition := matches[index]
	var line_index := posmod((seed_value + "|line").hash(), definition.lines.size())
	var result := {
		"actor_id": actor_id,
		"dialogue_id": definition.dialogue_id,
		"event": event,
		"text": definition.lines[line_index],
		"priority": maxi(priority, definition.priority),
		"round": round_index,
		"revision": revision,
	}
	_last_round_by_actor[actor_id] = round_index
	_last_event_by_actor[actor_id] = event
	_active = result.duplicate(true)
	return result


func clear() -> void:
	_active.clear()


func active() -> Dictionary:
	return _active.duplicate(true)
