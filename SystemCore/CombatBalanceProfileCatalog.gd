@tool
extends Resource
class_name CombatBalanceProfileCatalog

## Encounter balance is selected by ID at the handoff boundary.  Keeping the
## catalog data-authored prevents CombatBoard and AI from accumulating
## per-encounter magic-number branches.

@export var profiles: Array[CombatBalanceProfile] = []
var _index: Dictionary = {}


func profile_for_id(profile_id: String) -> CombatBalanceProfile:
	_ensure_index()
	return _index.get(profile_id, _index.get("default_tactical")) as CombatBalanceProfile


func ids() -> PackedStringArray:
	var result := PackedStringArray()
	for profile in profiles:
		if profile != null and not profile.profile_id.is_empty():
			result.append(profile.profile_id)
	return result


func _ensure_index() -> void:
	if _index.size() == profiles.size():
		return
	_index.clear()
	for profile in profiles:
		if profile != null and not profile.profile_id.is_empty():
			_index[profile.profile_id] = profile


static func load_default() -> CombatBalanceProfileCatalog:
	return load("res://SystemCore/default_combat_balance_catalog.tres") as CombatBalanceProfileCatalog
