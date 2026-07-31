extends Resource
class_name NpcLoadoutCatalog

const DEFAULT_PATH := "res://ItemCore/npc_loadout_profiles.tres"

@export var profiles: Array[NpcLoadoutProfile] = []


func for_role(role_id: String) -> NpcLoadoutProfile:
	for profile in profiles:
		if profile != null and profile.supports_role(role_id):
			return profile
	return null


static func data() -> NpcLoadoutCatalog:
	return load(DEFAULT_PATH) as NpcLoadoutCatalog
