extends Resource
class_name NpcRoleCatalog

const DEFAULT_PATH := "res://WorldCore/npc_roles.tres"

@export var roles: Array[NpcRoleDefinition] = []


func get_role(role_id: String) -> NpcRoleDefinition:
	for role in roles:
		if role != null and role.role_id == role_id:
			return role
	return null


func descriptor(role_id: String) -> Dictionary:
	var role := get_role(role_id)
	return role.to_descriptor() if role != null else {}


static func data() -> NpcRoleCatalog:
	return load(DEFAULT_PATH) as NpcRoleCatalog
