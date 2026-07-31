extends Resource
class_name NpcPlotDeploymentDefinition

@export var deployment_id: String = ""
@export var run_once_key: String = ""
@export var required_any_codex_ids: PackedStringArray = []
@export var allowed_node_ids: PackedStringArray = []
@export var actor_name: String = "Emergent Actor"
@export var role_id: String = "plot_agent"
@export var dialogue_id: String = ""
@export var faction: GameEnums.Faction = GameEnums.Faction.UNALIGNED
@export var world_status: GameEnums.EntityWorldStatus = GameEnums.EntityWorldStatus.CEASEFIRE
@export_range(1, 12) var minimum_spawn_distance: int = 3
@export_range(1, 12) var maximum_spawn_distance: int = 5
@export var visual_mode: String = "equipment_rig"
@export_file("*.png") var token_sprite_path: String = ""


func is_eligible(codex_ids: Array, node_id: String, run_flags: Dictionary) -> bool:
	if not run_once_key.is_empty() and bool(run_flags.get(run_once_key, false)):
		return false
	if not allowed_node_ids.is_empty() and not allowed_node_ids.has(node_id):
		return false
	if required_any_codex_ids.is_empty():
		return true
	for entry_id in required_any_codex_ids:
		if codex_ids.has(entry_id):
			return true
	return false
