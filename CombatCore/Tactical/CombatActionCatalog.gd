@tool
extends Resource
class_name CombatActionCatalog

@export var definitions: Array[CombatActionDefinition] = []

var _by_id: Dictionary = {}

func is_player_visible(action_id: String) -> bool:
	var entry := definition(action_id)
	return entry != null and entry.visibility_tier != "compatibility"


func player_definitions() -> Array[CombatActionDefinition]:
	var result: Array[CombatActionDefinition] = []
	for entry in all():
		if entry != null and is_player_visible(entry.action_id):
			result.append(entry)
	return result


func canonical_definitions() -> Array[CombatActionDefinition]:
	"""Return authored entries that belong to the unified combat model."""
	var result: Array[CombatActionDefinition] = []
	for entry in all():
		if entry != null and is_player_visible(entry.action_id):
			result.append(entry)
	return result


func is_ai_visible(action_id: String) -> bool:
	var entry := definition(action_id)
	return entry != null and entry.visibility_tier != "compatibility"


func definition(action_id: String) -> CombatActionDefinition:
	if _by_id.size() != definitions.size():
		_rebuild_index()
	return _by_id.get(action_id) as CombatActionDefinition


func all() -> Array[CombatActionDefinition]:
	return definitions.duplicate()


func weapon_action_validation_error(weapon: ItemData) -> String:
	if weapon == null:
		return "Weapon action projection requires an ItemData weapon."
	for action_id in weapon.combat_action_ids():
		var entry := definition(action_id)
		if entry == null:
			return "Weapon '%s' (%s) declares unknown combat action '%s'." % [
				weapon.display_name,
				weapon.id,
				action_id,
			]
		if not entry.is_weapon_action():
			return "Weapon '%s' (%s) declares non-weapon combat action '%s'." % [
				weapon.display_name,
				weapon.id,
				action_id,
			]
		if weapon.is_melee() != entry.is_melee_weapon_action():
			return "Weapon '%s' (%s) declares incompatible combat action '%s'." % [
				weapon.display_name,
				weapon.id,
				action_id,
			]
		if entry.resolver_id != "weapon_attack":
			return "Weapon '%s' (%s) declares action '%s' without the canonical weapon_attack resolver." % [
				weapon.display_name,
				weapon.id,
				action_id,
			]
	return ""


func weapon_action_definitions(weapon: ItemData) -> Array[CombatActionDefinition]:
	var result: Array[CombatActionDefinition] = []
	var validation_error := weapon_action_validation_error(weapon)
	if not validation_error.is_empty():
		push_error(validation_error)
		return result
	for action_id in weapon.combat_action_ids():
		result.append(definition(action_id))
	return result


func _rebuild_index() -> void:
	_by_id.clear()
	for entry in definitions:
		if entry == null or entry.action_id.is_empty():
			continue
		if _by_id.has(entry.action_id):
			push_error("Duplicate combat action ID: %s" % entry.action_id)
			continue
		_by_id[entry.action_id] = entry
