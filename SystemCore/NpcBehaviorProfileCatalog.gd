@tool
extends Resource
class_name NpcBehaviorProfileCatalog

const DEFAULT_CATALOG_PATH := "res://SystemCore/default_npc_behavior_profiles.tres"
const _NpcBehaviorProfile := preload("res://SystemCore/NpcBehaviorProfile.gd")

@export var profiles: Array[Resource] = []
@export var role_aliases: Dictionary = {}
var _index: Dictionary = {}


func profile_for_id(profile_id: String) -> Resource:
	_ensure_index()
	return _index.get(profile_id, _index.get("default")) as Resource


func profile_ids() -> PackedStringArray:
	## Stable catalog introspection used by validation and tooling. Keep the
	## return order authored rather than leaking Dictionary iteration order.
	var result := PackedStringArray()
	for profile in profiles:
		if profile != null and not profile.profile_id.is_empty():
			result.append(str(profile.profile_id))
	return result


func profile_for_role(role_id: String) -> Resource:
	var profile_id := str(role_aliases.get(role_id, role_id))
	return profile_for_id(profile_id)


func profile_for(definition: Dictionary, runtime: Dictionary = {}) -> Resource:
	var payload: Dictionary = runtime.get("npc_behavior", {})
	var profile_id := str(payload.get("profile_id", ""))
	if profile_id.is_empty():
		profile_id = profile_id_for(definition, runtime)
	return profile_for_id(profile_id)


func _ensure_index() -> void:
	if _index.size() == profiles.size():
		return
	_index.clear()
	for profile in profiles:
		if profile != null and not profile.profile_id.is_empty():
			_index[profile.profile_id] = profile


static func load_default() -> Resource:
	return load(DEFAULT_CATALOG_PATH) as Resource


static func profile_id_for(definition: Dictionary, runtime: Dictionary = {}) -> String:
	var role_id := str(runtime.get("npc_role_id", definition.get("npc_role_id", "")))
	var catalog := load_default()
	if catalog != null and catalog.role_aliases.has(role_id):
		return str(catalog.role_aliases[role_id])
	match int(definition.get("combat_tactic", GameEnums.CombatTactic.BRUTE)):
		GameEnums.CombatTactic.MARKSMAN:
			return "marksman"
		GameEnums.CombatTactic.OPPORTUNIST:
			return "opportunist"
		GameEnums.CombatTactic.DEFENDER:
			return "defender"
		_:
			return "brute"
