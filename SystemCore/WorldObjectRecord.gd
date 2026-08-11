extends Resource
class_name WorldObjectRecord

## Actor-neutral persistent world object. Components stay as neutral payloads so
## SystemCore does not depend on WorldCore presentation or BiologicalCore.

@export var object_id: String = ""
@export var node_id: String = ""
@export var coords: Vector2i = Vector2i.ZERO
@export var definition_id: String = ""
@export var condition: float = 1.0
@export var owner_id: String = ""
@export var faction: int = GameEnums.Faction.UNALIGNED
@export var revision: int = 0
@export var last_simulated_minute: int = 0

## Component id -> neutral component state. Components are the source of
## affordances; presentation must not manufacture verbs from object labels.
var components: Dictionary = {}
var runtime: Dictionary = {}

func bump_revision() -> int:
	revision += 1
	return revision

func has_component(component_id: String) -> bool:
	return components.has(component_id)

func component(component_id: String) -> Dictionary:
	var value: Variant = components.get(component_id, {})
	return value.duplicate(true) if value is Dictionary else {}

func set_component(component_id: String, state: Dictionary) -> void:
	components[component_id] = state.duplicate(true)
	bump_revision()

func to_dict() -> Dictionary:
	return {
		"object_id": object_id,
		"node_id": node_id,
		"coords": coords,
		"definition_id": definition_id,
		"condition": condition,
		"owner_id": owner_id,
		"faction": faction,
		"revision": revision,
		"last_simulated_minute": last_simulated_minute,
		"components": components.duplicate(true),
		"runtime": runtime.duplicate(true),
	}

static func from_dict(data: Dictionary) -> WorldObjectRecord:
	var record := WorldObjectRecord.new()
	record.object_id = str(data.get("object_id", ""))
	record.node_id = str(data.get("node_id", ""))
	record.coords = data.get("coords", Vector2i.ZERO)
	record.definition_id = str(data.get("definition_id", ""))
	record.condition = clampf(float(data.get("condition", 1.0)), 0.0, 1.0)
	record.owner_id = str(data.get("owner_id", ""))
	record.faction = int(data.get("faction", GameEnums.Faction.UNALIGNED))
	record.revision = maxi(0, int(data.get("revision", 0)))
	record.last_simulated_minute = maxi(0, int(data.get("last_simulated_minute", 0)))
	record.components = data.get("components", {}).duplicate(true)
	record.runtime = data.get("runtime", {}).duplicate(true)
	return record
