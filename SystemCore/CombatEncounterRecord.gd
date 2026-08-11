extends Resource
class_name CombatEncounterRecord

@export var encounter_id: String = ""
@export var topology_id: String = "squad_7x5"
@export var source_coords: Vector2i = Vector2i.ZERO
@export var approach_from: Vector2i = Vector2i.ZERO
@export var initiator_id: String = ""
@export var context: int = GameEnums.EncounterContext.NEUTRAL_MEET
@export var ambush_position: int = GameEnums.AmbushPosition.STANDARD
@export var world_seed: String = ""
@export var world_time: Dictionary = {}
@export var combat_seed: int = 0
@export var relationship_state: Dictionary = {}
## Canonical encounter communication pool.  CP is spent on communication
## actions; it is not an ally-control resource.
@export_range(0, 12) var communication_points: int = 0
## Optional authored seed inputs. An empty dictionary means derive these from
## the player at encounter construction; a populated dictionary is replayable
## and can deliberately author a zero-point encounter.
@export var communication_point_inputs: Dictionary = {}
## Legacy serialized aliases.  Keep these fields readable so old encounters
## continue to hydrate, but all new code should use the CP names above.
@export_range(0, 12) var squad_points: int = 0
@export var squad_point_inputs: Dictionary = {}
@export var balance_profile_id: String = "default_tactical"
## Optional authored deployment. Keys are actor IDs and values are Vector2i
## sectors (or serializable {"x", "y"} dictionaries). When absent, the
## topology's data-authored deployment lanes are used.
@export var actor_starting_sectors: Dictionary = {}
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
		"combat_seed": combat_seed,
		"relationship_state": relationship_state.duplicate(true),
		"communication_points": resolved_communication_points(),
		"communication_point_inputs": resolved_communication_point_inputs().duplicate(true),
		# Compatibility keys remain in serialized runtime records for older
		# handoff/save readers. They mirror the canonical CP values.
		"squad_points": resolved_communication_points(),
		"squad_point_inputs": resolved_communication_point_inputs().duplicate(true),
		"balance_profile_id": balance_profile_id,
		"actor_starting_sectors": actor_starting_sectors.duplicate(true),
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
	record.topology_id = str(data.get("topology_id", "squad_7x5"))
	record.source_coords = data.get("source_coords", Vector2i.ZERO)
	record.approach_from = data.get("approach_from", Vector2i.ZERO)
	record.initiator_id = str(data.get("initiator_id", ""))
	record.context = int(data.get("context", GameEnums.EncounterContext.NEUTRAL_MEET))
	record.ambush_position = int(data.get("ambush_position", GameEnums.AmbushPosition.STANDARD))
	record.world_seed = str(data.get("world_seed", ""))
	record.world_time = data.get("world_time", {}).duplicate(true)
	record.combat_seed = int(data.get("combat_seed", 0))
	record.relationship_state = data.get("relationship_state", {}).duplicate(true)
	var has_cp := data.has("communication_points")
	record.communication_points = clampi(
		int(data.get("communication_points", data.get("squad_points", 0))),
		0,
		12
	)
	record.squad_points = clampi(int(data.get("squad_points", record.communication_points)), 0, 12)
	record.communication_point_inputs = data.get(
		"communication_point_inputs",
		data.get("squad_point_inputs", {})
	).duplicate(true)
	record.squad_point_inputs = data.get(
		"squad_point_inputs",
		record.communication_point_inputs
	).duplicate(true)
	if not has_cp and data.has("squad_points"):
		record.communication_points = record.squad_points
	record.balance_profile_id = str(data.get("balance_profile_id", "default_tactical"))
	record.actor_starting_sectors = data.get("actor_starting_sectors", {}).duplicate(true)
	var center_data: Dictionary = data.get("center_hex", {})
	if not center_data.is_empty():
		record.center_hex = HexRecord.from_dict(center_data)
	for neighbor_data in data.get("neighbor_hexes", []):
		if neighbor_data is Dictionary and not neighbor_data.is_empty():
			record.neighbor_hexes.append(HexRecord.from_dict(neighbor_data))
		else:
			record.neighbor_hexes.append(null)
	# Rebuild typed arrays element-by-element.  A legacy payload often omits
	# these fields entirely, and assigning the untyped Array returned by
	# Dictionary.get() directly raises at runtime under Godot's typed-array
	# checks before the CP migration can complete.
	for raw_actor in data.get("actors", []):
		if raw_actor is Dictionary:
			record.actors.append((raw_actor as Dictionary).duplicate(true))
	for raw_trap in data.get("traps", []):
		if raw_trap is Dictionary:
			record.traps.append((raw_trap as Dictionary).duplicate(true))
	for raw_item in data.get("ground_items", []):
		if raw_item is Dictionary:
			record.ground_items.append((raw_item as Dictionary).duplicate(true))
	record.presentation = data.get("presentation", {}).duplicate(true)
	return record


func resolved_communication_points() -> int:
	# A non-zero canonical value always wins.  The legacy value is only used
	# when hydrating old resources that predate the CP field.
	if communication_points != 0 or squad_points == 0:
		return clampi(communication_points, 0, 12)
	return clampi(squad_points, 0, 12)


func resolved_communication_point_inputs() -> Dictionary:
	if not communication_point_inputs.is_empty() or squad_point_inputs.is_empty():
		return communication_point_inputs
	return squad_point_inputs
