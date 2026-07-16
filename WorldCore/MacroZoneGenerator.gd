extends RefCounted
class_name MacroZoneGenerator

## Generates one true radius-12 axial local map for a campaign node.
## Reuses plains layer rules from HexWorldGenerator (noise + shrub/structure rolls).

const ZONE_RADIUS := GameEnums.MACRO_ZONE_RADIUS
const _PoiVisualCatalog := preload("res://PresentationCore/PoiVisualCatalog.gd")
const _SectorCatalog := preload("res://WorldCore/WorldSectorCatalog.gd")
const DECOR_SHRUB_PATHS := [
	"res://Asset/HexTiles/_BIOMES/biome_plains/flora/Shrub A.png",
	"res://Asset/HexTiles/_BIOMES/biome_plains/flora/Shrub B.png",
	"res://Asset/HexTiles/_BIOMES/biome_plains/flora/Shrub C.png",
	"res://Asset/HexTiles/_BIOMES/biome_plains/flora/Shrub D.png",
	"res://Asset/HexTiles/_BIOMES/biome_plains/flora/Shrub E.png",
	"res://Asset/HexTiles/_BIOMES/biome_plains/flora/Shrub F.png",
	"res://Asset/HexTiles/_BIOMES/biome_plains/flora/Shrub G.png",
	"res://Asset/HexTiles/_BIOMES/biome_plains/flora/Shrub H.png",
]
const DECOR_TREE_PATHS := [
	"res://Asset/HexTiles/_BIOMES/biome_plains/flora/Trees Green - 2x2A.png",
	"res://Asset/HexTiles/_BIOMES/biome_plains/flora/Trees Green - 2x2B.png",
	"res://Asset/HexTiles/_BIOMES/biome_plains/flora/Temperate Trees v2 size-2 A green.png",
]
const DECOR_PROP_PATHS := [
	"res://Asset/HexTiles/_BIOMES/biome_plains/Infrastructure/Homestead Crates Size1.png",
	"res://Asset/HexTiles/_BIOMES/biome_plains/Infrastructure/Colony Infrastructure/Small Crates 1A.png",
	"res://Asset/HexTiles/_BIOMES/biome_plains/Infrastructure/Colony Infrastructure/Small Crates 1B.png",
	"res://Asset/HexTiles/_BIOMES/biome_plains/Infrastructure/Colony Infrastructure/Tent A.a - Gray - closed.png",
]
const DECOR_ROCK_PATHS := [
	"res://Asset/HexTiles/_BIOMES/biome_plains/Rocks/Rocks Sz1 A.png",
	"res://Asset/HexTiles/_BIOMES/biome_plains/Rocks/Rocks Sz1 B.png",
	"res://Asset/HexTiles/_BIOMES/biome_plains/Rocks/Rocks Sz1 C shadow.png",
	"res://Asset/HexTiles/_BIOMES/biome_plains/Rocks/Rocks Sz2 A.png",
	"res://Asset/HexTiles/_BIOMES/biome_plains/Rocks/Rocks Sz2 B.png",
]
const RANDOM_STRUCTURE_PATHS := [
	"res://Asset/HexTiles/_BIOMES/biome_plains/Structures/Homestead Building Size1 B-i shadow.png",
	"res://Asset/HexTiles/_BIOMES/biome_plains/Structures/Cylindrical Tank A - Size 1 - Yellow.png",
]
const RANDOM_REMNANT_PATHS := [
	"res://Asset/HexTiles/_BIOMES/biome_plains/remnants/Rubble 1x1 A.png",
	"res://Asset/HexTiles/_BIOMES/biome_plains/remnants/Rubble 1x1 B.png",
	"res://Asset/HexTiles/_BIOMES/biome_plains/remnants/Rubble 1x1 C.png",
	"res://Asset/HexTiles/_BIOMES/biome_plains/remnants/Rubble 1x1 D.png",
]

var master_seed: String = ""
var node_id: String = ""
var zone_kind: GameEnums.MacroZoneKind = GameEnums.MacroZoneKind.BIOME_RNG
var biome: GameEnums.GridBiome = GameEnums.GridBiome.PLAINS
var event_id: String = ""
var node_persistence: GameEnums.MacroNodePersistence = GameEnums.MacroNodePersistence.SEEDED_RANDOM
var node_role: GameEnums.MacroNodeRole = GameEnums.MacroNodeRole.RANDOM_ZONE
var zone_profile_id: String = "plains_default"
var node_arm_direction: GameEnums.MacroArmDirection = GameEnums.MacroArmDirection.NONE
var node_arm_tier: int = 0
var arrival_direction: GameEnums.MacroTravelDirection = GameEnums.MacroTravelDirection.SOUTH
var connected_directions: Array[int] = []

var elevation_noise: FastNoiseLite
var moisture_noise: FastNoiseLite
var world_hex_cache: Dictionary = {} # Vector2i -> MacroHexData
var start_coords: Vector2i = HexCoordUtils.rim_anchor(
	GameEnums.MacroTravelDirection.SOUTH,
	ZONE_RADIUS
)
var objective_coords: Vector2i = Vector2i.ZERO
var authored_map: Resource = null # unused; kept for MacroGameManager compatibility
var require_authored_map: bool = false

@export_range(0.0, 1.0) var random_structure_chance: float = 0.018
@export_range(0.0, 1.0) var random_remnant_chance: float = 0.035
@export_range(0.0, 1.0) var shrub_spawn_chance: float = 0.40
@export_range(0.0, 1.0) var landmark_spawn_chance: float = 0.0
@export_range(0, 24) var guaranteed_landmark_count: int = 12
@export_range(0.0, 1.0) var clutter_spawn_chance: float = 0.34

var zone_decorations: Dictionary = {} # Vector2i -> Array[Dictionary]
var trail_hexes: Dictionary = {} # Vector2i -> true
var permanent_baseline_records: Dictionary = {} # Vector2i -> HexRecord

var _world_state: RuntimeStateStore
var _meta_progress: Node


func configure_services(world_state: RuntimeStateStore) -> void:
	_world_state = world_state
	_meta_progress = Engine.get_main_loop().root.get_node_or_null("MetaProgression")


func configure_seed(seed_value: String) -> void:
	master_seed = seed_value
	_initialize_noise()


func is_in_bounds(coords: Vector2i) -> bool:
	return HexCoordUtils.is_in_radius(coords, ZONE_RADIUS)


func generate_node_zone(
	node: MacroNodeData,
	p_arrival_direction: int,
	p_connected_directions: Array[int]
) -> void:
	node_persistence = node.persistence
	node_role = node.role
	zone_profile_id = node.zone_profile_id
	node_arm_direction = node.arm_direction
	node_arm_tier = node.arm_tier
	arrival_direction = p_arrival_direction as GameEnums.MacroTravelDirection
	connected_directions = p_connected_directions.duplicate()
	generate_zone(node.id, node.zone_kind, node.biome, node.event_id)


func generate_zone(
	p_node_id: String,
	p_zone_kind: GameEnums.MacroZoneKind,
	p_biome: GameEnums.GridBiome = GameEnums.GridBiome.PLAINS,
	p_event_id: String = ""
) -> void:
	node_id = p_node_id
	zone_kind = p_zone_kind
	biome = p_biome
	event_id = p_event_id
	world_hex_cache.clear()
	zone_decorations.clear()
	trail_hexes.clear()
	permanent_baseline_records.clear()
	_initialize_noise()

	var spawn_direction := arrival_direction
	if spawn_direction == GameEnums.MacroTravelDirection.NONE:
		spawn_direction = GameEnums.MacroTravelDirection.SOUTH
	start_coords = HexCoordUtils.rim_anchor(spawn_direction, ZONE_RADIUS)
	objective_coords = Vector2i.ZERO

	for coords in HexCoordUtils.cells_in_radius(ZONE_RADIUS):
		var hex := _build_hex(coords)
		world_hex_cache[coords] = hex

	_apply_trail_network()
	_place_start_and_objective()
	_place_guaranteed_landmarks()
	_apply_permanent_profile_patches()
	_sync_hex_records()
	_scatter_zone_decorations()


func get_decorations_at(coords: Vector2i) -> Array:
	return zone_decorations.get(coords, [])


func get_hex_at(coords: Vector2i) -> MacroHexData:
	if world_hex_cache.has(coords):
		return world_hex_cache[coords]
	if not is_in_bounds(coords):
		return HexWorldGenerator.build_void_hex(coords)

	if _world_state != null:
		var persistent: HexRecord = _world_state.get_hex_record(coords)
		if persistent != null:
			var restored := MacroHexData.from_state(persistent)
			world_hex_cache[coords] = restored
			return restored

	var hex := _build_hex(coords)
	world_hex_cache[coords] = hex
	if _world_state != null:
		_world_state.set_hex_record(coords, hex.to_state())
	return hex


func _initialize_noise() -> void:
	var zone_seed := _zone_seed()
	elevation_noise = FastNoiseLite.new()
	elevation_noise.seed = (zone_seed + ":elevation").hash()
	elevation_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	# Lower frequency → contiguous hills / mud / forest patches.
	elevation_noise.frequency = 0.025

	moisture_noise = FastNoiseLite.new()
	moisture_noise.seed = (zone_seed + ":moisture").hash()
	moisture_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	moisture_noise.frequency = 0.03


func _zone_seed() -> String:
	if node_persistence == GameEnums.MacroNodePersistence.PERMANENT_META:
		return "ARCCROSS_PERMANENT_NODE:" + node_id
	return master_seed + ":zone:" + node_id


func _apply_permanent_profile_patches() -> void:
	if node_persistence != GameEnums.MacroNodePersistence.PERMANENT_META:
		return
	for coords in world_hex_cache.keys():
		var hex: MacroHexData = world_hex_cache[coords]
		var baseline := hex.to_state()
		permanent_baseline_records[coords] = HexRecord.from_dict(baseline.to_dict())
		if _meta_progress == null or not _meta_progress.has_method("apply_patch_to_record"):
			continue
		var patched := HexRecord.from_dict(baseline.to_dict())
		_meta_progress.apply_patch_to_record(node_id, coords, patched)
		world_hex_cache[coords] = MacroHexData.from_state(patched)


func _sync_hex_records() -> void:
	if _world_state == null:
		return
	for coords in world_hex_cache.keys():
		var hex: MacroHexData = world_hex_cache[coords]
		_world_state.set_hex_record(coords, hex.to_state())


func _build_hex(coords: Vector2i) -> MacroHexData:
	if node_id == MacroGraphGenerator.HUB_ID:
		return _build_hub_hex(coords)
	if zone_kind == GameEnums.MacroZoneKind.UNIQUE_EVENT:
		return _build_unique_event_hex(coords)
	return _build_plains_rng_hex(coords)


func _build_hub_hex(coords: Vector2i) -> MacroHexData:
	var hex := MacroHexData.new()
	hex.zone_id = "zone_hub"
	hex.biome = GameEnums.GridBiome.PLAINS
	hex.biome_pack = GameEnums.BIOME_PACK_PLAINS
	hex.region = GameEnums.MacroRegion.CENTRAL_HUB
	hex.terrain_tile = GameEnums.MacroTerrainTile.PLAINS_GRASS
	hex.flora_layer = GameEnums.MacroFloraLayer.NONE
	hex.rock_layer = GameEnums.MacroRockLayer.NONE
	hex.structure_layer = GameEnums.MacroStructureLayer.NONE
	hex.hazard_level = 0.0
	hex.impassable = false
	hex.visual_variant_hash = HexWorldGenerator.compute_visual_variant_hash(
		coords,
		_zone_seed()
	)
	# Hub stays readable: light shrub scatter, no random landmarks.
	var hub_shrub := shrub_spawn_chance * 0.35
	var saved := shrub_spawn_chance
	shrub_spawn_chance = hub_shrub
	_apply_shrub_variation(coords, hex)
	shrub_spawn_chance = saved
	return hex


func _build_plains_rng_hex(coords: Vector2i) -> MacroHexData:
	var hex := MacroHexData.new()
	hex.zone_id = "zone_" + node_id
	hex.biome_pack = GameEnums.BIOME_PACK_PLAINS
	match node_arm_tier:
		1:
			hex.region = GameEnums.MacroRegion.ARM_STAGE_1
		2:
			hex.region = GameEnums.MacroRegion.ARM_STAGE_2
		3, 4, 5:
			hex.region = GameEnums.MacroRegion.ARM_STAGE_3
		_:
			hex.region = GameEnums.MacroRegion.WASTELAND
	hex.arm_direction = node_arm_direction
	hex.biome = biome
	hex.terrain_tile = GameEnums.MacroTerrainTile.PLAINS_GRASS
	hex.flora_layer = GameEnums.MacroFloraLayer.NONE
	hex.rock_layer = GameEnums.MacroRockLayer.NONE
	hex.structure_layer = GameEnums.MacroStructureLayer.NONE
	hex.is_poi = false
	hex.landmark_id = ""
	hex.hazard_level = (
		1.2
		+ float(node_arm_tier) * 0.8
		+ float(HexCoordUtils.distance_from_origin(coords)) * 0.08
	)

	var elevation: float = elevation_noise.get_noise_2dv(coords)
	var moisture: float = moisture_noise.get_noise_2dv(coords)

	# Contiguous rock / hill clusters (flood-style thresholds, not speckles).
	if elevation > 0.52:
		hex.rock_layer = GameEnums.MacroRockLayer.ROCKS
		hex.impassable = true
	elif elevation > 0.22:
		hex.rock_layer = GameEnums.MacroRockLayer.HILLS

	if hex.rock_layer != GameEnums.MacroRockLayer.ROCKS:
		# Mud follows moisture corridors; sparse forest on damp mid-elevation.
		if moisture < -0.18 or elevation < -0.28:
			hex.terrain_tile = GameEnums.MacroTerrainTile.MUD_YELLOW
		elif moisture > 0.20 and elevation > -0.12 and elevation < 0.40:
			hex.terrain_tile = GameEnums.MacroTerrainTile.FOREST_SPARSE
			hex.flora_layer = GameEnums.MacroFloraLayer.TREES

	_apply_shrub_variation(coords, hex)

	var zone_seed := _zone_seed()
	var rng := RandomNumberGenerator.new()
	rng.seed = (zone_seed + ":layers:" + str(coords)).hash()
	if hex.structure_layer == GameEnums.MacroStructureLayer.NONE and hex.landmark_id.is_empty():
		var structure_roll := rng.randf()
		if structure_roll < random_structure_chance:
			hex.structure_layer = GameEnums.MacroStructureLayer.STRUCTURES
			hex.structure_sprite_path = _pick_curated_layer_path(
				RANDOM_STRUCTURE_PATHS,
				rng
			)
		elif structure_roll < random_structure_chance + random_remnant_chance:
			hex.structure_layer = GameEnums.MacroStructureLayer.REMNANTS
			hex.structure_sprite_path = _pick_curated_layer_path(
				RANDOM_REMNANT_PATHS,
				rng
			)

	var landmark_rng := RandomNumberGenerator.new()
	landmark_rng.seed = (zone_seed + ":landmark:" + str(coords)).hash()
	if (
		not hex.impassable
		and hex.landmark_id.is_empty()
		and landmark_rng.randf() < landmark_spawn_chance
	):
		_apply_landmark_to_hex(hex, coords, zone_seed)

	hex.visual_variant_hash = HexWorldGenerator.compute_visual_variant_hash(
		coords,
		zone_seed
	)
	return hex


func _pick_curated_layer_path(
	paths: Array,
	rng: RandomNumberGenerator
) -> String:
	var valid: Array[String] = []
	for path in paths:
		if ResourceLoader.exists(str(path)):
			valid.append(str(path))
	if valid.is_empty():
		return ""
	return valid[rng.randi_range(0, valid.size() - 1)]


func _build_unique_event_hex(coords: Vector2i) -> MacroHexData:
	var hex := _build_plains_rng_hex(coords)
	hex.zone_id = "zone_event_" + node_id
	hex.region = GameEnums.MacroRegion.ARM_STAGE_3
	hex.hazard_level = maxf(hex.hazard_level, 4.0)
	return hex


func _apply_shrub_variation(coords: Vector2i, hex: MacroHexData) -> void:
	if (
		hex.terrain_tile != GameEnums.MacroTerrainTile.PLAINS_GRASS
		or hex.flora_layer != GameEnums.MacroFloraLayer.NONE
		or hex.impassable
	):
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = (_zone_seed() + ":shrub:" + str(coords)).hash()
	if rng.randf() < shrub_spawn_chance:
		hex.flora_layer = GameEnums.MacroFloraLayer.SHRUBS


func _apply_landmark_to_hex(
	hex: MacroHexData,
	coords: Vector2i,
	zone_seed: String
) -> void:
	var landmark := _SectorCatalog.pick_landmark(
		zone_seed,
		coords,
		_node_landmark_wedge(coords)
	)
	hex.landmark_id = str(landmark.get("landmark_id", ""))
	hex.is_poi = true
	hex.poi_id = str(landmark.get("poi_id", "plains_landmark"))
	hex.poi_name = str(landmark.get("poi_name", "Landmark"))
	hex.sleep_anchor = str(landmark.get("sleep_anchor", "ground"))
	hex.structure_layer = GameEnums.MacroStructureLayer.STRUCTURES
	hex.structure_sprite_path = _PoiVisualCatalog.pick_structure_path(
		hex.landmark_id,
		zone_seed,
		coords
	)


func _node_landmark_wedge(coords: Vector2i) -> String:
	match node_arm_direction:
		GameEnums.MacroArmDirection.NORTH:
			return "wedge_n"
		GameEnums.MacroArmDirection.EAST:
			return "wedge_e"
		GameEnums.MacroArmDirection.SOUTH:
			return "wedge_s"
		GameEnums.MacroArmDirection.WEST:
			return "wedge_w"
		_:
			return _SectorCatalog.wedge_id_for_coords(coords)


func _apply_trail_network() -> void:
	trail_hexes.clear()
	var main_path := _axial_line(start_coords, Vector2i.ZERO)
	for coords in main_path:
		trail_hexes[coords] = true

	var exits := connected_directions.duplicate()
	if not exits.has(int(arrival_direction)):
		exits.append(int(arrival_direction))
	for direction in exits:
		if int(direction) == GameEnums.MacroTravelDirection.NONE:
			continue
		var rim := HexCoordUtils.rim_anchor(int(direction), ZONE_RADIUS)
		for coords in _axial_line(Vector2i.ZERO, rim):
			trail_hexes[coords] = true

	var zone_seed := _zone_seed()
	var rng := RandomNumberGenerator.new()
	rng.seed = (zone_seed + ":trails").hash()
	# 1–2 spurs off the main path into the zone interior.
	var all_cells := HexCoordUtils.cells_in_radius(ZONE_RADIUS - 2)
	var spur_count := rng.randi_range(2, 4)
	for _i in range(spur_count):
		if main_path.is_empty() or all_cells.is_empty():
			break
		var junction: Vector2i = main_path[rng.randi_range(0, main_path.size() - 1)]
		var spur_end: Vector2i = all_cells[rng.randi_range(0, all_cells.size() - 1)]
		for coords in _axial_line(junction, spur_end):
			if is_in_bounds(coords):
				trail_hexes[coords] = true

	for coords in trail_hexes.keys():
		if not world_hex_cache.has(coords):
			continue
		var hex: MacroHexData = world_hex_cache[coords]
		hex.impassable = false
		hex.rock_layer = GameEnums.MacroRockLayer.NONE
		if hex.terrain_tile == GameEnums.MacroTerrainTile.MUD_YELLOW:
			hex.terrain_tile = GameEnums.MacroTerrainTile.PLAINS_GRASS
		if hex.flora_layer == GameEnums.MacroFloraLayer.TREES:
			hex.flora_layer = GameEnums.MacroFloraLayer.NONE
			hex.terrain_tile = GameEnums.MacroTerrainTile.PLAINS_GRASS
		if _world_state != null:
			_world_state.set_hex_record(coords, hex.to_state())


func _axial_line(from_coords: Vector2i, to_coords: Vector2i) -> Array[Vector2i]:
	var results: Array[Vector2i] = []
	var n := _hex_distance(from_coords, to_coords)
	if n == 0:
		results.append(from_coords)
		return results
	for i in range(n + 1):
		var t := float(i) / float(n)
		var q := int(round(lerpf(float(from_coords.x), float(to_coords.x), t)))
		var r := int(round(lerpf(float(from_coords.y), float(to_coords.y), t)))
		var cell := Vector2i(q, r)
		if results.is_empty() or results[results.size() - 1] != cell:
			results.append(cell)
	return results


func _hex_distance(a: Vector2i, b: Vector2i) -> int:
	var delta := b - a
	return maxi(abs(delta.x), maxi(abs(delta.y), abs(delta.x + delta.y)))


func _scatter_zone_decorations() -> void:
	zone_decorations.clear()
	var zone_seed := _zone_seed()
	for coords in world_hex_cache.keys():
		var hex: MacroHexData = world_hex_cache[coords]
		if (
			(hex.impassable and hex.rock_layer == GameEnums.MacroRockLayer.NONE)
			or hex.is_poi
			or not hex.landmark_id.is_empty()
		):
			continue
		if HexCoordUtils.distance(coords, start_coords) <= 1:
			continue
		var rng := RandomNumberGenerator.new()
		rng.seed = (zone_seed + ":decor:" + str(coords)).hash()
		var chance := clutter_spawn_chance
		if node_role == GameEnums.MacroNodeRole.CENTRAL_CORE:
			chance *= 0.45
		if hex.rock_layer != GameEnums.MacroRockLayer.NONE:
			chance = 1.0
		if trail_hexes.has(coords):
			chance *= 0.16
		if hex.structure_layer != GameEnums.MacroStructureLayer.NONE:
			chance *= 0.85
		if rng.randf() > chance:
			continue
		var props: Array = []
		var count := _cluster_size_for_hex(hex, rng)
		var used_offsets: Array[Vector2] = []
		for i in range(count):
			var path := _pick_cluster_decor_path(hex, rng, i)
			if path.is_empty() or not ResourceLoader.exists(path):
				continue
			var offset := _sample_cluster_offset(rng, used_offsets)
			used_offsets.append(offset)
			var kind := _decor_kind(path)
			props.append({
				"coords": coords,
				"sprite_path": path,
				"kind": kind,
				"target_box": _decor_target_box(kind),
				"scale_multiplier": rng.randf_range(0.88, 1.08),
				"offset": offset,
				"rotation": 0.0,
				"flip_h": kind == "shrub" and rng.randf() < 0.35,
				"layer": _decor_layer(path),
			})
		if not props.is_empty():
			zone_decorations[coords] = props


func _cluster_size_for_hex(hex: MacroHexData, rng: RandomNumberGenerator) -> int:
	if hex.flora_layer == GameEnums.MacroFloraLayer.TREES:
		return rng.randi_range(2, 3)
	if hex.rock_layer == GameEnums.MacroRockLayer.ROCKS:
		return rng.randi_range(5, 7)
	if hex.rock_layer == GameEnums.MacroRockLayer.HILLS:
		return rng.randi_range(3, 5)
	if hex.structure_layer != GameEnums.MacroStructureLayer.NONE:
		return rng.randi_range(2, 4)
	return rng.randi_range(2, 5)


func _pick_cluster_decor_path(
	hex: MacroHexData,
	rng: RandomNumberGenerator,
	index: int
) -> String:
	# Large trees and formations already come from authoritative TileMap layers.
	# Cluster recipes add understory and small ground clutter without duplicating
	# an entire grove or rock field on top of itself.
	if hex.flora_layer == GameEnums.MacroFloraLayer.TREES:
		return DECOR_SHRUB_PATHS[rng.randi_range(0, DECOR_SHRUB_PATHS.size() - 1)]
	if hex.rock_layer != GameEnums.MacroRockLayer.NONE:
		return (
			DECOR_ROCK_PATHS[rng.randi_range(0, DECOR_ROCK_PATHS.size() - 1)]
			if index < maxi(2, _cluster_size_for_rock_layer(hex.rock_layer) - 1)
			else DECOR_SHRUB_PATHS[rng.randi_range(0, DECOR_SHRUB_PATHS.size() - 1)]
		)
	if rng.randf() < 0.14:
		return DECOR_ROCK_PATHS[rng.randi_range(0, DECOR_ROCK_PATHS.size() - 1)]
	if hex.structure_layer != GameEnums.MacroStructureLayer.NONE and rng.randf() < 0.65:
		return DECOR_PROP_PATHS[rng.randi_range(0, DECOR_PROP_PATHS.size() - 1)]
	return DECOR_SHRUB_PATHS[rng.randi_range(0, DECOR_SHRUB_PATHS.size() - 1)]


func _cluster_size_for_rock_layer(rock_layer: int) -> int:
	return 5 if rock_layer == GameEnums.MacroRockLayer.ROCKS else 3


func _sample_cluster_offset(
	rng: RandomNumberGenerator,
	used_offsets: Array[Vector2]
) -> Vector2:
	for _attempt in range(16):
		var candidate := Vector2(
			rng.randf_range(-132.0, 132.0),
			rng.randf_range(-72.0, 72.0)
		)
		# Pull the corners inward so ground anchors remain inside the hex.
		var x_limit := 132.0 * (1.0 - absf(candidate.y) / 150.0)
		if absf(candidate.x) > x_limit:
			continue
		var separated := true
		for used in used_offsets:
			if candidate.distance_to(used) < 42.0:
				separated = false
				break
		if separated:
			return candidate
	return Vector2(rng.randf_range(-44.0, 44.0), rng.randf_range(-28.0, 28.0))


func _decor_kind(path: String) -> String:
	var lowered := path.to_lower()
	if "tree" in lowered:
		return "tree"
	if "rocks" in lowered:
		return "rock"
	if "shrub" in lowered:
		return "shrub"
	return "prop"


func _decor_target_box(kind: String) -> Vector2:
	match kind:
		"tree":
			return Vector2(180.0, 170.0)
		"rock":
			return Vector2(88.0, 70.0)
		"prop":
			return Vector2(96.0, 80.0)
		_:
			return Vector2(76.0, 88.0)


func _decor_layer(path: String) -> int:
	var lowered := path.to_lower()
	if "flora" in lowered:
		return 0
	if "rocks" in lowered:
		return 1
	return 3


func _place_guaranteed_landmarks() -> void:
	var target_count := guaranteed_landmark_count
	if node_persistence == GameEnums.MacroNodePersistence.PERMANENT_META:
		target_count = 4
	if node_role == GameEnums.MacroNodeRole.CENTRAL_CORE:
		target_count = 1
	elif node_role == GameEnums.MacroNodeRole.META_BRANCH:
		target_count = 3
	var zone_seed := _zone_seed()
	var existing := 0
	var occupied: Array[Vector2i] = []
	var candidates: Array[Vector2i] = []
	for coords in world_hex_cache.keys():
		var hex: MacroHexData = world_hex_cache[coords]
		if hex.is_poi or not hex.landmark_id.is_empty():
			existing += 1
			occupied.append(coords)
			continue
		if (
			HexCoordUtils.distance(coords, start_coords) <= 2
			or HexCoordUtils.distance_from_origin(coords) <= 1
			or hex.impassable
		):
			continue
		candidates.append(coords)

	var needed := maxi(0, target_count - existing)
	if needed <= 0 or candidates.is_empty():
		return

	var rng := RandomNumberGenerator.new()
	rng.seed = (zone_seed + ":guaranteed_landmarks").hash()
	# Deterministic shuffle.
	for i in range(candidates.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := candidates[i]
		candidates[i] = candidates[j]
		candidates[j] = tmp

	var placed := 0
	for coords in candidates:
		if placed >= needed:
			break
		var spaced := true
		for other in occupied:
			if HexCoordUtils.distance(coords, other) < 3:
				spaced = false
				break
		if not spaced:
			continue
		var hex: MacroHexData = world_hex_cache[coords]
		_apply_landmark_to_hex(hex, coords, zone_seed)
		occupied.append(coords)
		if _world_state != null:
			_world_state.set_hex_record(coords, hex.to_state())
		placed += 1


func _place_start_and_objective() -> void:
	var start_hex: MacroHexData = world_hex_cache[start_coords]
	start_hex.impassable = false
	start_hex.rock_layer = GameEnums.MacroRockLayer.NONE
	start_hex.flora_layer = GameEnums.MacroFloraLayer.NONE
	start_hex.terrain_tile = GameEnums.MacroTerrainTile.PLAINS_GRASS
	start_hex.is_explored = true

	var center_hex: MacroHexData = world_hex_cache[Vector2i.ZERO]
	center_hex.impassable = false
	center_hex.rock_layer = GameEnums.MacroRockLayer.NONE
	center_hex.flora_layer = GameEnums.MacroFloraLayer.NONE
	center_hex.is_poi = true
	center_hex.structure_layer = GameEnums.MacroStructureLayer.STRUCTURES
	if node_role == GameEnums.MacroNodeRole.CENTRAL_CORE:
		center_hex.poi_id = "central_core"
		center_hex.poi_name = "Central Core"
		center_hex.landmark_id = "central_core"
		center_hex.sleep_anchor = "bed"
		center_hex.terrain_tile = GameEnums.MacroTerrainTile.HUB_CONCRETE
		center_hex.biome_pack = GameEnums.BIOME_PACK_CENTRALCORE
		center_hex.region = GameEnums.MacroRegion.CENTRAL_HUB
		center_hex.hazard_level = 0.0
		center_hex.structure_sprite_path = _PoiVisualCatalog.pick_structure_path(
			"centralcore_city", _zone_seed(), Vector2i.ZERO
		)
	elif node_role == GameEnums.MacroNodeRole.META_BRANCH:
		center_hex.poi_id = "meta_component_source"
		center_hex.poi_name = "Component Vault"
		center_hex.landmark_id = "warehouse_b"
		center_hex.structure_sprite_path = _PoiVisualCatalog.pick_structure_path(
			"warehouse_b", _zone_seed(), Vector2i.ZERO
		)
	elif node_role == GameEnums.MacroNodeRole.GATEWAY:
		center_hex.poi_id = "arm_gateway"
		center_hex.poi_name = "Sealed Arm Gateway"
		center_hex.landmark_id = "arm_gateway"
		center_hex.structure_sprite_path = _PoiVisualCatalog.pick_structure_path(
			"centralcore_city", _zone_seed(), Vector2i.ZERO
		)
	elif node_role == GameEnums.MacroNodeRole.ARM_CORE:
		center_hex.poi_id = "arm_core"
		center_hex.poi_name = "Arm Core"
		center_hex.landmark_id = "arm_core"
		center_hex.structure_sprite_path = _PoiVisualCatalog.pick_structure_path(
			"centralcore_city", _zone_seed(), Vector2i.ZERO
		)
	elif zone_kind == GameEnums.MacroZoneKind.UNIQUE_EVENT:
		center_hex.poi_id = "macro_event_" + (event_id if not event_id.is_empty() else "event")
		center_hex.poi_name = "Anomalous Site"
		center_hex.landmark_id = "event_site"
		center_hex.structure_sprite_path = _PoiVisualCatalog.pick_structure_path(
			"warehouse_b", _zone_seed(), Vector2i.ZERO
		)
	else:
		# Ordinary random zones get a central landmark, but travel is performed
		# through directional rim exits rather than this POI.
		_apply_landmark_to_hex(center_hex, Vector2i.ZERO, _zone_seed())

	if _world_state != null:
		_world_state.set_hex_record(start_coords, start_hex.to_state())
		_world_state.set_hex_record(Vector2i.ZERO, center_hex.to_state())


func hex_count() -> int:
	return world_hex_cache.size()


func debug_ascii() -> String:
	var lines: PackedStringArray = PackedStringArray()
	lines.append(
		"=== Zone %s kind=%s radius=%d cells=%d ==="
		% [node_id, str(zone_kind), ZONE_RADIUS, world_hex_cache.size()]
	)
	for y in range(-ZONE_RADIUS, ZONE_RADIUS + 1):
		var row := ""
		for x in range(-ZONE_RADIUS, ZONE_RADIUS + 1):
			var coords := Vector2i(x, y)
			var ch := " " if not is_in_bounds(coords) else "."
			if coords == start_coords:
				ch = "S"
			elif coords == objective_coords:
				ch = "X"
			elif world_hex_cache.has(coords):
				var hex: MacroHexData = world_hex_cache[coords]
				if hex.impassable:
					ch = "#"
				elif hex.is_poi:
					ch = "P"
				elif hex.flora_layer == GameEnums.MacroFloraLayer.TREES:
					ch = "T"
				elif hex.rock_layer == GameEnums.MacroRockLayer.HILLS:
					ch = "^"
				elif hex.terrain_tile == GameEnums.MacroTerrainTile.MUD_YELLOW:
					ch = "~"
			row += ch
		lines.append(row)
	return "\n".join(lines)
