extends Resource
class_name TacticalSectorRuntime

const ENTRY_ORDINARY := "ordinary"
const ENTRY_HOSTILE_ENGAGEMENT := "hostile_engagement"
const ENTRY_FORCED_DISPLACEMENT := "forced_displacement"

var index: int = -1
var coords: Vector2i = Vector2i.ZERO
var record: TacticalSectorRecord
## Ordered runtime occupants. `occupant` remains a compatibility projection for
## legacy callers and returns the first occupant only.
var occupants: Array[HumanoidCore] = []
var occupant: HumanoidCore:
	get:
		return occupants[0] if not occupants.is_empty() else null
	set(value):
		occupants.clear()
		if value != null:
			occupants.append(value)
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
	return not blocked and (actor in occupants or occupants.size() < 2)


func occupancy_kind() -> String:
	## Spatial occupancy only. Relationship-aware Engagement/Crowding is
	## resolved by CombatBoard, which owns the encounter ledger.
	if occupants.is_empty():
		return "empty"
	if occupants.size() == 1:
		return "single"
	return "full"


func can_enter(actor: HumanoidCore, forced: bool = false) -> bool:
	return can_enter_with_policy(
		actor,
		ENTRY_FORCED_DISPLACEMENT if forced else ENTRY_ORDINARY
	)


func can_enter_with_policy(
	actor: HumanoidCore,
	entry_policy: String = ENTRY_ORDINARY,
	target_actor: HumanoidCore = null
) -> bool:
	if actor == null or blocked:
		return false
	if actor in occupants:
		return true
	if occupants.size() >= 2:
		return false
	if occupants.is_empty():
		return true
	if entry_policy == ENTRY_FORCED_DISPLACEMENT:
		return true
	if entry_policy == ENTRY_HOSTILE_ENGAGEMENT:
		return occupants.size() == 1 and (target_actor == null or occupants[0] == target_actor)
	return false


func add_occupant(actor: HumanoidCore, forced: bool = false) -> bool:
	return add_occupant_with_policy(
		actor,
		ENTRY_FORCED_DISPLACEMENT if forced else ENTRY_ORDINARY
	)


func add_occupant_with_policy(
	actor: HumanoidCore,
	entry_policy: String = ENTRY_ORDINARY,
	target_actor: HumanoidCore = null
) -> bool:
	if actor == null or actor in occupants or occupants.size() >= 2:
		return actor in occupants
	if not can_enter_with_policy(actor, entry_policy, target_actor):
		return false
	occupants.append(actor)
	return true


func remove_occupant(actor: HumanoidCore) -> bool:
	var offset := occupants.find(actor)
	if offset < 0:
		return false
	occupants.remove_at(offset)
	return true


func clear_occupants() -> void:
	occupants.clear()


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
		"occupant_ids": occupants.map(func(value: HumanoidCore) -> String: return _actor_id(value)),
		"ground_item_instance_ids": record.ground_item_instance_ids.duplicate() if record != null else [],
		"body_entity_ids": record.body_entity_ids.duplicate() if record != null else [],
		"incapacitated_entity_ids": record.incapacitated_entity_ids.duplicate() if record != null else [],
		"surrendered_entity_ids": record.surrendered_entity_ids.duplicate() if record != null else [],
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
