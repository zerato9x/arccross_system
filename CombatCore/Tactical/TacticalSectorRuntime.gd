extends Resource
class_name TacticalSectorRuntime

var index: int = -1
var coords: Vector2i = Vector2i.ZERO
var record: TacticalSectorRecord
var occupant: HumanoidCore
var object_durability: float = 0.0
var blocked: bool = false
var opaque: bool = false
var spawnable: bool = true
var movement_modifier: int = 0
var elevation: int = 0
var concealment: float = 0.0
var cover_edges: Dictionary = {}
var hazard_state: Dictionary = {}
var trap_state: Dictionary = {}


func configure(source: TacticalSectorRecord) -> void:
	record = source
	index = source.index
	coords = source.coords
	blocked = source.blocked
	opaque = source.opaque
	spawnable = source.spawnable
	movement_modifier = source.movement_modifier
	elevation = source.elevation
	concealment = source.concealment
	cover_edges = source.cover_edges.duplicate(true)
	hazard_state = source.hazard_state.duplicate(true)
	trap_state = source.trap_state.duplicate(true)
	object_durability = float(source.object_state.get("durability", 0.0))


func movement_cost(base_cost: int) -> int:
	return maxi(1, base_cost + movement_modifier)


func is_open_for(actor: HumanoidCore = null) -> bool:
	return not blocked and (occupant == null or occupant == actor)


func damage_object(amount: float) -> Dictionary:
	if record == null or record.object_state.is_empty() or object_durability <= 0.0:
		return {}
	var before := object_durability
	object_durability = maxf(0.0, object_durability - maxf(0.0, amount))
	record.object_state["durability"] = object_durability
	if object_durability <= 0.0:
		blocked = false
		opaque = false
		cover_edges.clear()
		record.blocked = false
		record.opaque = false
		record.cover_edges.clear()
		record.object_state["type"] = "rubble"
		record.object_state["label"] = "Shattered debris"
	return {
		"sector": coords,
		"object_id": str(record.object_state.get("id", "")),
		"durability_before": before,
		"durability_after": object_durability,
		"destroyed": object_durability <= 0.0,
	}


func presentation_descriptor() -> Dictionary:
	return {
		"index": index,
		"coords": coords,
		"surface_id": record.surface_id if record != null else "unresolved",
		"surface_label": record.surface_label if record != null else "UNRESOLVED",
		"ground_asset": record.ground_asset_path if record != null else "",
		"overlay_asset": record.overlay_asset_path if record != null else "",
		"movement_modifier": movement_modifier,
		"elevation": elevation,
		"concealment": concealment,
		"opaque": opaque,
		"blocked": blocked,
		"cover_edges": cover_edges.duplicate(true),
		"object": record.object_state.duplicate(true) if record != null else {},
		"hazards": hazard_state.duplicate(true),
		"trap": trap_state.duplicate(true),
		"escape_side": record.escape_side if record != null else "",
		"occupant_id": _actor_id(occupant),
	}


func capture_mutation_patch() -> Dictionary:
	if record == null:
		return {}
	return {
		"object_state": record.object_state.duplicate(true),
		"hazard_state": hazard_state.duplicate(true),
		"trap_state": trap_state.duplicate(true),
		"surface_id": record.surface_id,
		"blocked": blocked,
		"cover_edges": cover_edges.duplicate(true),
	}


func _actor_id(actor: HumanoidCore) -> String:
	return "" if actor == null else str(actor.get_meta("actor_id", actor.name))
