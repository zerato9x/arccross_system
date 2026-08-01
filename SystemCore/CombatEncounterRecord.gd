extends Resource
class_name CombatEncounterRecord

@export var encounter_id: String = ""
@export var topology_id: String = "duel_12x1"
@export var source_coords: Vector2i = Vector2i.ZERO
@export var approach_from: Vector2i = Vector2i.ZERO
@export var initiator_id: String = ""
@export var context: int = GameEnums.EncounterContext.NEUTRAL_MEET
@export var ambush_position: int = GameEnums.AmbushPosition.STANDARD
@export var world_seed: String = ""
@export var world_time: Dictionary = {}
@export var center_hex: HexRecord
@export var neighbor_hexes: Array[HexRecord] = []
@export var actors: Array[Dictionary] = []
@export var traps: Array[Dictionary] = []
@export var ground_items: Array[Dictionary] = []
@export var presentation: Dictionary = {}


func to_dict() -> Dictionary:
	var neighbors: Array = []
	for record in neighbor_hexes:
		neighbors.append(record.to_dict() if record != null else {})
	return {
		"encounter_id": encounter_id,
		"topology_id": topology_id,
		"source_coords": source_coords,
		"approach_from": approach_from,
		"initiator_id": initiator_id,
		"context": context,
		"ambush_position": ambush_position,
		"world_seed": world_seed,
		"world_time": world_time.duplicate(true),
		"center_hex": center_hex.to_dict() if center_hex != null else {},
		"neighbor_hexes": neighbors,
		"actors": actors.duplicate(true),
		"traps": traps.duplicate(true),
		"ground_items": ground_items.duplicate(true),
		"presentation": presentation.duplicate(true),
	}


static func from_dict(data: Dictionary) -> CombatEncounterRecord:
	var record := CombatEncounterRecord.new()
	record.encounter_id = str(data.get("encounter_id", ""))
	record.topology_id = str(data.get("topology_id", "duel_12x1"))
	record.source_coords = data.get("source_coords", Vector2i.ZERO)
	record.approach_from = data.get("approach_from", Vector2i.ZERO)
	record.initiator_id = str(data.get("initiator_id", ""))
	record.context = int(data.get("context", GameEnums.EncounterContext.NEUTRAL_MEET))
	record.ambush_position = int(data.get("ambush_position", GameEnums.AmbushPosition.STANDARD))
	record.world_seed = str(data.get("world_seed", ""))
	record.world_time = data.get("world_time", {}).duplicate(true)
	var center_data: Dictionary = data.get("center_hex", {})
	if not center_data.is_empty():
		record.center_hex = HexRecord.from_dict(center_data)
	for neighbor_data in data.get("neighbor_hexes", []):
		if neighbor_data is Dictionary and not neighbor_data.is_empty():
			record.neighbor_hexes.append(HexRecord.from_dict(neighbor_data))
		else:
			record.neighbor_hexes.append(null)
	record.actors = data.get("actors", []).duplicate(true)
	record.traps = data.get("traps", []).duplicate(true)
	record.ground_items = data.get("ground_items", []).duplicate(true)
	record.presentation = data.get("presentation", {}).duplicate(true)
	return record
