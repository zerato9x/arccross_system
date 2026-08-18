extends Resource
class_name CombatArenaState

const LEGACY_WIDTH: int = 7
const LEGACY_HEIGHT: int = 5
const SCHEMA_VERSION: int = 4

@export var schema_version: int = SCHEMA_VERSION
@export var topology_id: String = "squad_7x5"
@export var width: int = 7
@export var height: int = 5
@export var movement_policy: int = CombatTopologyProfile.MovementPolicy.ORTHOGONAL
@export var baseline_seed: int = 0
@export var source_coords: Vector2i = Vector2i.ZERO
@export var orientation_step: int = 0
@export var backdrop_asset_path: String = ""
@export var map_composition: Dictionary = {}
@export var lighting: Dictionary = {}
@export var sectors: Array[TacticalSectorRecord] = []
@export var actor_positions: Dictionary = {}
@export var mutations: Dictionary = {}


func is_valid() -> bool:
	if sectors.size() != sector_count():
		return false
	for sector in sectors:
		if sector == null or not contains(sector.coords):
			return false
	return true


func sector_at(coords: Vector2i) -> TacticalSectorRecord:
	if not contains(coords):
		return null
	var index := index_for(coords)
	return sectors[index] if index >= 0 and index < sectors.size() else null


func sector_count() -> int:
	return width * height


func contains(coords: Vector2i) -> bool:
	return coords.x >= 0 and coords.x < width and coords.y >= 0 and coords.y < height


func index_for(coords: Vector2i) -> int:
	return coords.y * width + coords.x


func coords_for(index: int) -> Vector2i:
	return Vector2i(index % width, floori(float(index) / float(width)))


func configure_topology(profile: CombatTopologyProfile) -> void:
	if profile == null:
		return
	topology_id = profile.topology_id
	width = profile.columns
	height = profile.rows
	movement_policy = profile.movement_policy


func to_dict() -> Dictionary:
	var sector_states: Array = []
	for sector in sectors:
		sector_states.append(sector.to_dict())
	return {
		"schema_version": schema_version,
		"topology_id": topology_id,
		"width": width,
		"height": height,
		"movement_policy": movement_policy,
		"baseline_seed": baseline_seed,
		"source_coords": source_coords,
		"orientation_step": orientation_step,
		"backdrop_asset_path": backdrop_asset_path,
		"map_composition": map_composition.duplicate(true),
		"lighting": lighting.duplicate(true),
		"sectors": sector_states,
		"actor_positions": actor_positions.duplicate(true),
		"mutations": mutations.duplicate(true),
	}


static func from_dict(data: Dictionary) -> CombatArenaState:
	var error := compatibility_error(data)
	if not error.is_empty():
		push_error(error)
		return null
	var state := CombatArenaState.new()
	state.schema_version = SCHEMA_VERSION
	state.topology_id = str(data.get("topology_id", "squad_7x5"))
	state.width = int(data.get("width", LEGACY_WIDTH))
	state.height = int(data.get("height", LEGACY_HEIGHT))
	state.movement_policy = int(data.get(
		"movement_policy",
		CombatTopologyProfile.MovementPolicy.ORTHOGONAL
	))
	state.baseline_seed = int(data.get("baseline_seed", 0))
	state.source_coords = data.get("source_coords", Vector2i.ZERO)
	state.orientation_step = int(data.get("orientation_step", 0))
	state.backdrop_asset_path = str(data.get("backdrop_asset_path", ""))
	state.map_composition = data.get("map_composition", {}).duplicate(true)
	state.lighting = data.get("lighting", {}).duplicate(true)
	for raw_sector in data.get("sectors", []):
		if raw_sector is Dictionary:
			state.sectors.append(TacticalSectorRecord.from_dict(raw_sector))
	state.actor_positions = data.get("actor_positions", {}).duplicate(true)
	state.mutations = data.get("mutations", {}).duplicate(true)
	return state


static func compatibility_error(data: Dictionary) -> String:
	var found_version := int(data.get("schema_version", -1))
	if found_version != SCHEMA_VERSION:
		return "Combat arena schema %d is incompatible with current schema %d; start a new combat encounter." % [
			found_version,
			SCHEMA_VERSION,
		]
	for retired_field in ["actor_facings", "facings", "posture", "postures", "reserved_ap"]:
		if data.has(retired_field):
			return "Combat arena schema %d contains retired field '%s'; start a new combat encounter." % [
				SCHEMA_VERSION,
				retired_field,
			]
	return ""
