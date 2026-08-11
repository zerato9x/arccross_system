@tool
extends Resource
class_name CombatTopologyCatalog

## Combat-owned resolver for topology Resources.  The profile remains a
## neutral data contract; only the combat application layer knows where its
## authored catalog is stored.

const ROOT_PATH := "res://CombatCore/Tactical/Topologies"
const DEFAULT_ID := "squad_7x5"
const DEFAULT_CATALOG_PATH := "res://CombatCore/Tactical/default_combat_topology_catalog.tres"

@export var profiles: Array[CombatTopologyProfile] = []
var _profile_index: Dictionary = {}


func _ensure_index() -> void:
	if _profile_index.size() == profiles.size():
		return
	_profile_index.clear()
	for profile in profiles:
		if profile != null and not profile.topology_id.is_empty():
			_profile_index[profile.topology_id] = profile


func profile_for_id(profile_id: String) -> CombatTopologyProfile:
	_ensure_index()
	return _profile_index.get(profile_id) as CombatTopologyProfile


static func load_profile(requested_id: String) -> CombatTopologyProfile:
	var profile_id := requested_id if not requested_id.is_empty() else DEFAULT_ID
	var catalog := load(DEFAULT_CATALOG_PATH) as CombatTopologyCatalog
	if catalog != null:
		# Resource-backed catalogs may be loaded as placeholder instances by the
		# editor fallback runtime, so static resolution reads the authored array
		# directly and does not invoke a method on the loaded catalog resource.
		for authored in catalog.profiles:
			if authored != null and authored.topology_id == profile_id:
				return authored
	var path := "%s/%s.tres" % [ROOT_PATH, profile_id]
	if not ResourceLoader.exists(path):
		push_warning("Unknown combat topology '%s'; using %s." % [profile_id, DEFAULT_ID])
		path = "%s/%s.tres" % [ROOT_PATH, DEFAULT_ID]
	return load(path) as CombatTopologyProfile
