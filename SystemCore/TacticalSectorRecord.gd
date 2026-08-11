extends Resource
class_name TacticalSectorRecord

## Neutral, serializable tactical sector. Gameplay domains may add runtime
## projections, but the cross-domain contract remains data-only.

@export var index: int = -1
@export var coords: Vector2i = Vector2i.ZERO
@export var surface_id: String = "plains"
@export var surface_label: String = "PLAINS"
@export var ground_asset_path: String = ""
@export var overlay_asset_path: String = ""
@export var movement_modifier: int = 0
@export var elevation: int = 0
@export_range(0.0, 1.0) var visibility_penalty: float = 0.0
@export_range(0.0, 1.0) var concealment: float = 0.0
@export var opaque: bool = false
@export var blocked: bool = false
@export var spawnable: bool = true
@export var escape_side: String = ""
@export var territory_side: String = "neutral"
@export var cover_edges: Dictionary = {}
@export var object_state: Dictionary = {}
@export var hazard_state: Dictionary = {}
@export var trap_state: Dictionary = {}
@export var occupant_ids: Array[String] = []
@export var ground_item_instance_ids: Array[String] = []
@export var body_entity_ids: Array[String] = []
## Non-active actors are kept in explicit handoff layers instead of occupying
## one of the two tactical actor slots.  This preserves the sector location
## for captives/surrenders while keeping movement capacity about active actors.
@export var incapacitated_entity_ids: Array[String] = []
@export var surrendered_entity_ids: Array[String] = []


func to_dict() -> Dictionary:
	return {
		"index": index,
		"coords": coords,
		"surface_id": surface_id,
		"surface_label": surface_label,
		"ground_asset_path": ground_asset_path,
		"overlay_asset_path": overlay_asset_path,
		"movement_modifier": movement_modifier,
		"elevation": elevation,
		"visibility_penalty": visibility_penalty,
		"concealment": concealment,
		"opaque": opaque,
		"blocked": blocked,
		"spawnable": spawnable,
		"escape_side": escape_side,
		"territory_side": territory_side,
		"cover_edges": cover_edges.duplicate(true),
		"object_state": object_state.duplicate(true),
		"hazard_state": hazard_state.duplicate(true),
		"trap_state": trap_state.duplicate(true),
		"occupant_ids": occupant_ids.duplicate(),
		"ground_item_instance_ids": ground_item_instance_ids.duplicate(),
		"body_entity_ids": body_entity_ids.duplicate(),
		"incapacitated_entity_ids": incapacitated_entity_ids.duplicate(),
		"surrendered_entity_ids": surrendered_entity_ids.duplicate(),
	}


static func from_dict(data: Dictionary) -> TacticalSectorRecord:
	var record := TacticalSectorRecord.new()
	record.index = int(data.get("index", -1))
	record.coords = data.get("coords", Vector2i.ZERO)
	record.surface_id = str(data.get("surface_id", "plains"))
	record.surface_label = str(data.get("surface_label", "PLAINS"))
	record.ground_asset_path = str(data.get("ground_asset_path", ""))
	record.overlay_asset_path = str(data.get("overlay_asset_path", ""))
	record.movement_modifier = int(data.get("movement_modifier", 0))
	record.elevation = int(data.get("elevation", 0))
	record.visibility_penalty = clampf(float(data.get("visibility_penalty", 0.0)), 0.0, 1.0)
	record.concealment = clampf(float(data.get("concealment", 0.0)), 0.0, 1.0)
	record.opaque = bool(data.get("opaque", false))
	record.blocked = bool(data.get("blocked", false))
	record.spawnable = bool(data.get("spawnable", true))
	record.escape_side = str(data.get("escape_side", ""))
	record.territory_side = str(data.get("territory_side", "neutral"))
	record.cover_edges = data.get("cover_edges", {}).duplicate(true)
	record.object_state = data.get("object_state", {}).duplicate(true)
	record.hazard_state = data.get("hazard_state", {}).duplicate(true)
	record.trap_state = data.get("trap_state", {}).duplicate(true)
	var authored_occupants: Array = data.get("occupant_ids", [])
	# Schema v1 stored one occupant_id. Migrate it into the canonical ordered
	# two-slot list without disturbing items, bodies, or terrain state.
	if authored_occupants.is_empty() and data.has("occupant_id"):
		authored_occupants = [data.get("occupant_id", "")]
	for value in authored_occupants:
		record.occupant_ids.append(str(value))
	for value in data.get("ground_item_instance_ids", []):
		record.ground_item_instance_ids.append(str(value))
	for value in data.get("body_entity_ids", []):
		record.body_entity_ids.append(str(value))
	for value in data.get("incapacitated_entity_ids", []):
		record.incapacitated_entity_ids.append(str(value))
	for value in data.get("surrendered_entity_ids", []):
		record.surrendered_entity_ids.append(str(value))
	return record
