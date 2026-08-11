@tool
extends Resource
class_name ShelterProgressionProfile

## Authored state machine for permanent shelter service. The transition
## algorithm remains code-owned; thresholds, stage order, and component
## presentation state live in this Resource.

@export var profile_id: String = "north_r2_shelter"
@export var initial_state: String = "ruined"
@export var habitable_state: String = "habitable"
@export var overrun_state: String = "repaired_overrun"
@export var secured_state: String = "secured"
@export var secured_damaged_state: String = "secured_damaged"
@export var ecology_offsets: Dictionary = {
	"north_r2_shelter": [Vector2i(2, 0), Vector2i(1, -1), Vector2i(-1, 1)],
	"north_random_2": [Vector2i(-2, 0), Vector2i(-1, 1)],
}
@export var ecology_template_prefix: String = "craven_shelter_approach"
@export var ecology_squad_prefix: String = "craven_shelter_approach"
@export var habitable_stage: int = 2
@export var overrun_stage: int = 4
@export var secure_without_hostile_stage: int = 4
@export var stages: Array[String] = [
	"roof", "access", "power", "water", "storage", "bed"
]
@export var stage_state_overrides: Dictionary = {
	"default": "usable",
	"power": "online",
	"water": "online",
}
@export var stage_integrity: float = 0.85
@export var state_component_patches: Dictionary = {
	"habitable": {
		"roof": {"integrity": 0.82},
		"door": {"integrity": 0.70, "state": "closed"},
		"bed": {"count": 1, "state": "usable"},
	},
	"repaired_overrun": {
		"roof": {"integrity": 0.92},
		"door": {"integrity": 0.85, "state": "barricaded"},
		"power": {"state": "online"},
		"water": {"state": "online"},
		"bed": {"count": 1, "state": "usable"},
	},
	"secured": {
		"roof": {"integrity": 1.0},
		"door": {"integrity": 1.0, "state": "secured"},
		"power": {"state": "online"},
		"water": {"state": "online"},
		"storage": {"state": "usable"},
		"bed": {"count": 1, "state": "usable"},
	},
	"secured_damaged": {
		"roof": {"integrity": 0.90},
		"door": {"integrity": 0.75, "state": "secured"},
		"power": {"state": "online"},
		"water": {"state": "online"},
		"bed": {"count": 1, "state": "usable"},
		"storage": {"state": "damaged"},
	},
}


func stage_name(stage_index: int) -> String:
	if stages.is_empty():
		return ""
	return str(stages[clampi(stage_index, 0, stages.size() - 1)])


func state_for_stage(service_stage: int, hostile_present: bool) -> String:
	if service_stage >= secure_without_hostile_stage and not hostile_present:
		return secured_state
	if service_stage >= overrun_stage:
		return overrun_state if hostile_present else secured_state
	if service_stage >= habitable_stage:
		return habitable_state
	return initial_state


func state_after_player_defeat(current_state: String) -> String:
	if current_state in [secured_state, secured_damaged_state]:
		return current_state
	return overrun_state if current_state != initial_state else initial_state


func ecology_for_node(node_id: String) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for coords in ecology_offsets.get(node_id, []):
		if coords is Vector2i:
			result.append(coords)
	return result


func apply_component_patches(components: Dictionary, state: String) -> void:
	var patches: Dictionary = state_component_patches.get(state, {})
	for component_id in patches.keys():
		var patch: Variant = patches[component_id]
		if not patch is Dictionary:
			continue
		var component: Dictionary = components.get(component_id, {}).duplicate(true)
		component.merge(patch, true)
		components[component_id] = component
