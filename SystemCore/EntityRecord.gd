extends Resource
class_name EntityRecord

## Typed neutral entity record. Replaces the untyped Dictionary that previously
## flowed between domains. Only references GameEnums and engine primitives so
## SystemCore remains domain-neutral.

@export var entity_id: String = ""
@export var kind: GameEnums.RuntimeEntityKind = GameEnums.RuntimeEntityKind.NPC
@export var life_state: GameEnums.EntityLifeState = GameEnums.EntityLifeState.ALIVE
@export var world_status: GameEnums.EntityWorldStatus = GameEnums.EntityWorldStatus.HOSTILE
@export var coords: Vector2i = Vector2i.ZERO

## Cross-domain definition payload. Remains a Dictionary so SystemCore does not
## import BiologicalCore types.
var definition: Dictionary = {}

## Cross-domain runtime snapshot. Populated after combat or world actions.
## Remains a Dictionary for the same neutrality reason.
var runtime: Dictionary = {}

## Negotiation state used by WorldCore macro interactions.
var negotiation_attempts: int = 0

func to_dict() -> Dictionary:
	return {
		"entity_id": entity_id,
		"kind": kind,
		"life_state": life_state,
		"world_status": world_status,
		"coords": coords,
		"definition": definition.duplicate(true),
		"runtime": runtime.duplicate(true),
		"negotiation_attempts": negotiation_attempts,
	}

static func from_dict(data: Dictionary) -> EntityRecord:
	var record := EntityRecord.new()
	record.entity_id = data.get("entity_id", "")
	record.kind = data.get("kind", GameEnums.RuntimeEntityKind.NPC)
	record.life_state = data.get("life_state", GameEnums.EntityLifeState.ALIVE)
	record.world_status = data.get("world_status", GameEnums.EntityWorldStatus.HOSTILE)
	record.coords = data.get("coords", Vector2i.ZERO)
	record.definition = data.get("definition", {}).duplicate(true)
	record.runtime = data.get("runtime", {}).duplicate(true)
	record.negotiation_attempts = int(data.get("negotiation_attempts", 0))
	return record
