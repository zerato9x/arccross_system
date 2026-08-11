extends Resource
class_name EntityRecord

const _NpcBehaviorState := preload("res://SystemCore/NpcBehaviorState.gd")

## Typed neutral entity record. Replaces the untyped Dictionary that previously
## flowed between domains. Only references GameEnums and engine primitives so
## SystemCore remains domain-neutral.

@export var entity_id: String = ""
@export var kind: GameEnums.RuntimeEntityKind = GameEnums.RuntimeEntityKind.NPC
@export var life_state: GameEnums.EntityLifeState = GameEnums.EntityLifeState.ALIVE
@export var world_status: GameEnums.EntityWorldStatus = GameEnums.EntityWorldStatus.HOSTILE
@export var coords: Vector2i = Vector2i.ZERO
@export var owner_id: String = ""
@export var revision: int = 0
@export var last_simulated_minute: int = 0

## Cross-domain definition payload. Remains a Dictionary so SystemCore does not
## import BiologicalCore types.
var definition: Dictionary = {}

## Cross-domain runtime snapshot. Populated after combat or world actions.
## Remains a Dictionary for the same neutrality reason.
var runtime: Dictionary = {}

## Knowledge is deliberately neutral: clues, remembered directions, and
## confidence are consumed by WorldCore without requiring a dialogue system.
var knowledge: Dictionary = {}

## Negotiation state used by WorldCore macro interactions.
var negotiation_attempts: int = 0

func to_dict() -> Dictionary:
	var runtime_snapshot := runtime.duplicate(true)
	if kind == GameEnums.RuntimeEntityKind.NPC:
		runtime_snapshot = _NpcBehaviorState.ensure_runtime(runtime_snapshot, definition)
	return {
		"entity_id": entity_id,
		"kind": kind,
		"life_state": life_state,
		"world_status": world_status,
		"coords": coords,
		"owner_id": owner_id,
		"revision": revision,
		"last_simulated_minute": last_simulated_minute,
		"definition": definition.duplicate(true),
		"runtime": runtime_snapshot,
		"knowledge": knowledge.duplicate(true),
		"negotiation_attempts": negotiation_attempts,
	}

static func from_dict(data: Dictionary) -> EntityRecord:
	var record := EntityRecord.new()
	record.entity_id = data.get("entity_id", "")
	record.kind = data.get("kind", GameEnums.RuntimeEntityKind.NPC)
	record.life_state = data.get("life_state", GameEnums.EntityLifeState.ALIVE)
	record.world_status = data.get("world_status", GameEnums.EntityWorldStatus.HOSTILE)
	record.coords = data.get("coords", Vector2i.ZERO)
	record.owner_id = str(data.get("owner_id", ""))
	record.revision = maxi(0, int(data.get("revision", 0)))
	record.last_simulated_minute = maxi(0, int(data.get("last_simulated_minute", 0)))
	record.definition = data.get("definition", {}).duplicate(true)
	record.runtime = data.get("runtime", {}).duplicate(true)
	if record.kind == GameEnums.RuntimeEntityKind.NPC:
		record.runtime = _NpcBehaviorState.ensure_runtime(record.runtime, record.definition)
	record.knowledge = data.get("knowledge", {}).duplicate(true)
	record.negotiation_attempts = int(data.get("negotiation_attempts", 0))
	return record
