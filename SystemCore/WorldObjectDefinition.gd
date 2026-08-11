@tool
extends Resource
class_name WorldObjectDefinition

## Physical object authoring data. Runtime records keep only definition_id and
## mutable neutral components.

@export var definition_id: String = ""
@export var label: String = ""
@export var component_ids: Array[String] = []
@export var affordance_ids: Array[String] = []
@export var default_components: Dictionary = {}
@export var presentation: Dictionary = {}


func supports_component(component_id: String) -> bool:
	return component_ids.has(component_id)
