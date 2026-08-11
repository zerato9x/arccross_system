@tool
extends Resource
class_name WorldActionDefinition

## Stable, authorable world-action metadata.  Algorithms stay in the kernel;
## this resource owns labels, requirements, costs, effects, and presentation.

@export var action_id: String = ""
@export var verb_id: String = ""
@export var label: String = ""
@export_multiline var description: String = ""
@export var task_profile_id: String = ""
@export var required_components: Array[String] = []
@export var requirements: Array[String] = []
@export var method_ids: Array[String] = []
@export var elapsed_minutes: int = 0
@export var exertion: float = 0.0
@export var noise_intensity: float = 0.0
@export var effect_payload: Dictionary = {}
@export var presentation: Dictionary = {}


func has_component_requirement(component_id: String) -> bool:
	return required_components.has(component_id)


func requirement_payload() -> Dictionary:
	return {"capabilities": requirements.duplicate()}
