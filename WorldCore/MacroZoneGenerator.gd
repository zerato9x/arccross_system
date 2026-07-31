extends RefCounted
class_name MacroZoneGenerator

## Generates one true radius-12 axial local map for a campaign node.
## Reuses plains layer rules from HexWorldGenerator (noise + shrub/structure rolls).

const ZONE_RADIUS := GameEnums.MACRO_ZONE_RADIUS
const _PoiVisualCatalog := preload("res://PresentationCore/PoiVisualCatalog.gd")
const _SectorCatalog := preload("res://WorldCore/WorldSectorCatalog.gd")
const _StarterZonePlanner := preload("res://WorldCore/GenerationV2/StarterZonePlanner.gd")
const _ZoneGenerationProfile := preload("res://WorldCore/GenerationV2/ZoneGenerationProfile.gd")
const _WorldAssetManifest := preload("res://WorldCore/GenerationV2/WorldAssetManifest.gd")
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
## Every approved tile in grass_default. A 469-cell starter node distributes
## this entire family, rather than collapsing the terrain to one repeated tile.
const STARTER_TERRAIN_VARIANT_NUMBERS := [
	5, 6, 7, 8, 9,
	13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23,
	26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40,
	44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56,
	59, 60, 61, 62, 63, 64, 65, 69, 70, 71,
]
const RANDOM_STRUCTURE_PATHS := [
	"res://Asset/HexTiles/_BIOMES/default_era8/Structures/Homestead Building Size1 B-i shadow.png",
	"res://Asset/HexTiles/_BIOMES/default_era8/Structures/Homestead Building Size1 A shadow.png",
	"res://Asset/HexTiles/_BIOMES/default_era8/Structures/Homestead Building Size 2 - A.png",
	"res://Asset/HexTiles/_BIOMES/default_era8/Structures/Cylindrical Tank A - Size 1 - Yellow.png",
	"res://Asset/HexTiles/_BIOMES/default_era8/Structures/Homestead Building Size 2 - A.png",
	"res://Asset/HexTiles/_BIOMES/default_era8/Structures/Cylindrical Tank A - Size 1 - Gray.png",
]
const RANDOM_NORTH_STRUCTURE_PATHS := [
	"res://Asset/HexTiles/_BIOMES/biome_north/Structures/snowtrailer_1.png",
	"res://Asset/HexTiles/_BIOMES/biome_north/Structures/snowtrailer_2.png",
	"res://Asset/HexTiles/_BIOMES/biome_north/Structures/Industrial Building - Sz 2 - A.png",
]
const RANDOM_REMNANT_PATHS := [
	"res://Asset/HexTiles/_BIOMES/biome_plains/remnants/Rubble 1x1 A.png",
	"res://Asset/HexTiles/_BIOMES/biome_plains/remnants/Rubble 1x1 B.png",
	"res://Asset/HexTiles/_BIOMES/biome_plains/remnants/Rubble 1x1 C.png",
	"res://Asset/HexTiles/_BIOMES/biome_plains/remnants/Rubble 1x1 D.png",
]
const DECOR_NORTH_ROCK_PATHS := [
	"res://Asset/HexTiles/_BIOMES/biome_north/Rocks/Snowy Rocks - Sz 1 - A.png",
	"res://Asset/HexTiles/_BIOMES/biome_north/Rocks/Snowy Rocks - Sz 1 - B.png",
	"res://Asset/HexTiles/_BIOMES/biome_north/Rocks/Glacial Ice - Sz 1 - A.png",
	"res://Asset/HexTiles/_BIOMES/biome_north/Rocks/Glacial Ice - Sz 2 - A.png",
]
const STARTER_STRUCTURE_PATHS := [
	"res://Asset/HexTiles/_BIOMES/default_era8/Structures/Homestead Building Size1 B-i shadow.png",
	"res://Asset/HexTiles/_BIOMES/default_era8/Structures/Homestead Building Size1 A shadow.png",
	"res://Asset/HexTiles/_BIOMES/default_era8/Structures/Homestead Building Size1 C shadow.png",
	"res://Asset/HexTiles/_BIOMES/default_era8/Structures/Homestead Building Size 2 - B-i.png",
]
const STARTER_TENT_PATHS := [
	"res://Asset/HexTiles/_BIOMES/biome_plains/Infrastructure/Colony Infrastructure/Tent A.a - Gray - closed.png",
	"res://Asset/HexTiles/_BIOMES/biome_plains/Infrastructure/Colony Infrastructure/Tent A.b - Green - closed.png",
	"res://Asset/HexTiles/_BIOMES/biome_plains/Infrastructure/Colony Infrastructure/Tent Quonset - A.a - Gray.png",
]
const STARTER_INFRA_PATHS := [
	"res://Asset/HexTiles/_BIOMES/biome_plains/Infrastructure/MoreInfras/Infrastructural Post A1-i.png",
	"res://Asset/HexTiles/_BIOMES/biome_plains/Infrastructure/MoreInfras/Infrastructural Crate A1-i.png",
	"res://Asset/HexTiles/_BIOMES/biome_plains/Infrastructure/MoreInfras/Infrastructural Barrel A1-i.png",
	"res://Asset/HexTiles/_BIOMES/biome_plains/Infrastructure/MoreInfras/Infrastructural Solar Panel A1-i.png",
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
var _dialect_profile: Dictionary = {}

var elevation_noise: FastNoiseLite
var moisture_noise: FastNoiseLite
var terrain_detail_noise: FastNoiseLite
var vegetation_detail_noise: FastNoiseLite
var world_hex_cache: Dictionary = {} # Vector2i -> MacroHexData
var start_coords: Vector2i = HexCoordUtils.rim_anchor(
	GameEnums.MacroTravelDirection.SOUTH,
	ZONE_RADIUS
)
var objective_coords: Vector2i = Vector2i.ZERO
var starter_settlement_coords: Vector2i = Vector2i.ZERO
var starter_clue_coords: Vector2i = Vector2i.ZERO
var starter_npc_coords: Vector2i = Vector2i.ZERO
@export_range(0.0, 1.0) var random_structure_chance: float = 0.018
@export_range(0.0, 1.0) var random_remnant_chance: float = 0.035
@export_range(0.0, 1.0) var shrub_spawn_chance: float = 0.40
@export_range(0.0, 1.0) var landmark_spawn_chance: float = 0.0
@export_range(0, 24) var guaranteed_landmark_count: int = 12
@export_range(0.0, 1.0) var clutter_spawn_chance: float = 0.34

var zone_decorations: Dictionary = {} # Vector2i -> Array[Dictionary]
var trail_hexes: Dictionary = {} # Vector2i -> true
var permanent_baseline_records: Dictionary = {} # Vector2i -> HexRecord
var generated_plan: GeneratedZonePlan = null
var _runtime_asset_metadata: Dictionary = {}

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
	_dialect_profile = NodeDialectProfile.profile_for_node(node_id)
	world_hex_cache.clear()
	zone_decorations.clear()
	trail_hexes.clear()
	permanent_baseline_records.clear()
	starter_settlement_coords = Vector2i.ZERO
	starter_clue_coords = Vector2i.ZERO
	starter_npc_coords = Vector2i.ZERO
	generated_plan = null
	_initialize_noise()

	var spawn_direction := arrival_direction
	if spawn_direction == GameEnums.MacroTravelDirection.NONE:
		spawn_direction = GameEnums.MacroTravelDirection.SOUTH
	start_coords = HexCoordUtils.rim_anchor(spawn_direction, ZONE_RADIUS)
	objective_coords = Vector2i.ZERO

	for coords in HexCoordUtils.cells_in_radius(ZONE_RADIUS):
		var hex := _build_hex(coords)
		world_hex_cache[coords] = hex

	if _is_starter_route_zone():
		_apply_starter_v2_composition()
		_place_start_and_objective()
		_apply_permanent_profile_patches()
		_sync_hex_records()
		_scatter_zone_decorations()
		_apply_starter_v2_dressing()
	else:
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

	terrain_detail_noise = FastNoiseLite.new()
	terrain_detail_noise.seed = (zone_seed + ":terrain_detail").hash()
	terrain_detail_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	terrain_detail_noise.frequency = 0.085

	vegetation_detail_noise = FastNoiseLite.new()
	vegetation_detail_noise.seed = (zone_seed + ":vegetation_detail").hash()
	vegetation_detail_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	vegetation_detail_noise.frequency = 0.11


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
	hex.biome_pack = GameEnums.BIOME_PACK_CENTRALCORE
	hex.region = GameEnums.MacroRegion.CENTRAL_HUB
	hex.terrain_tile = GameEnums.MacroTerrainTile.HUB_CONCRETE
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
	# Hub concrete does not use plains shrub pass.
	shrub_spawn_chance = saved
	return hex


func _build_plains_rng_hex(coords: Vector2i) -> MacroHexData:
	var hex := MacroHexData.new()
	hex.zone_id = "zone_" + node_id
	if _dialect_profile.is_empty():
		_dialect_profile = NodeDialectProfile.profile_for_node(node_id)
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

	# Large fields keep causal regions coherent; smaller secondary fields stop
	# different seeds from collapsing into the same few oversized blobs.
	var elevation: float = (
		elevation_noise.get_noise_2dv(coords)
		+ terrain_detail_noise.get_noise_2dv(coords) * 0.18
	)
	var moisture: float = (
		moisture_noise.get_noise_2dv(coords)
		+ vegetation_detail_noise.get_noise_2dv(coords) * 0.22
	)

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
	if _is_starter_route_zone():
		# Starter nodes share a coherent green-plains floor. Elevation still
		# drives rocks and vegetation, but never swaps in snow/mud families.
		hex.biome = GameEnums.GridBiome.PLAINS
		hex.biome_pack = GameEnums.BIOME_PACK_PLAINS
		hex.terrain_tile = GameEnums.MacroTerrainTile.PLAINS_GRASS
		# Starter plains are not a lawn. Broaden the damp band into contiguous
		# woodland while keeping roads, settlement cells, and rock masses clear.
		if (
			hex.rock_layer == GameEnums.MacroRockLayer.NONE
			and moisture > 0.08
			and elevation > -0.20
			and elevation < 0.38
		):
			hex.flora_layer = GameEnums.MacroFloraLayer.TREES
		hex.structure_layer = GameEnums.MacroStructureLayer.NONE
		hex.structure_sprite_path = ""
		hex.world_generation_version = 2
		hex.terrain_asset_id = "terrain.plains.green.5"
		hex.composition_role = "quiet_plains"
		hex.visual_variant_hash = HexWorldGenerator.compute_visual_variant_hash(coords, _zone_seed())
		return hex

	var zone_seed := _zone_seed()
	var dialect_rng := RandomNumberGenerator.new()
	dialect_rng.seed = (zone_seed + ":dialect:" + str(coords)).hash()
	var terrain_pack := NodeDialectProfile.pick_terrain_pack(
		_dialect_profile,
		dialect_rng.randf()
	)
	if (
		terrain_pack == GameEnums.BIOME_PACK_NORTH
		and hex.rock_layer != GameEnums.MacroRockLayer.ROCKS
	):
		hex.terrain_tile = GameEnums.MacroTerrainTile.SNOW_TRANSITION
		hex.flora_layer = GameEnums.MacroFloraLayer.NONE
		hex.biome_pack = GameEnums.BIOME_PACK_NORTH
		# Snow suppresses plains forest/mud; keep rock language via north rocks.
	else:
		hex.biome_pack = GameEnums.BIOME_PACK_PLAINS

	# North snow hexes prefer north rock sprites when rock/hill layers are present.
	if (
		hex.biome_pack == GameEnums.BIOME_PACK_NORTH
		and hex.rock_layer != GameEnums.MacroRockLayer.NONE
		and hex.rock_sprite_path.is_empty()
	):
		var rock_rng := RandomNumberGenerator.new()
		rock_rng.seed = (zone_seed + ":north_rock:" + str(coords)).hash()
		hex.rock_sprite_path = _pick_curated_layer_path(DECOR_NORTH_ROCK_PATHS, rock_rng)

	var rng := RandomNumberGenerator.new()
	rng.seed = (zone_seed + ":layers:" + str(coords)).hash()
	if hex.structure_layer == GameEnums.MacroStructureLayer.NONE and hex.landmark_id.is_empty():
		var structure_roll := rng.randf()
		if structure_roll < random_structure_chance:
			hex.structure_layer = GameEnums.MacroStructureLayer.STRUCTURES
			hex.structure_pack = NodeDialectProfile.pick_structure_pack(
				_dialect_profile,
				rng.randf()
			)
			if hex.structure_pack == GameEnums.BIOME_PACK_NORTH:
				hex.structure_sprite_path = _pick_curated_layer_path(
					RANDOM_NORTH_STRUCTURE_PATHS,
					rng
				)
				if hex.structure_sprite_path.is_empty():
					hex.structure_sprite_path = _pick_curated_layer_path(
						RANDOM_STRUCTURE_PATHS,
						rng
					)
					hex.structure_pack = GameEnums.BIOME_PACK_DEFAULT_ERA8
			else:
				hex.structure_pack = GameEnums.BIOME_PACK_DEFAULT_ERA8
				hex.structure_sprite_path = _pick_curated_layer_path(
					RANDOM_STRUCTURE_PATHS,
					rng
				)
		elif structure_roll < random_structure_chance + random_remnant_chance:
			hex.structure_layer = GameEnums.MacroStructureLayer.REMNANTS
			hex.structure_pack = GameEnums.BIOME_PACK_DEFAULT_ERA8
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
	hex.structure_pack = GameEnums.BIOME_PACK_DEFAULT_ERA8
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
		if _is_starter_route_zone():
			hex.hazard_level = minf(hex.hazard_level, 1.25)
			# Route 1 logistics spines are onboarding space. Hazard level does not
			# currently drive encounter rolls, so explicitly consume the roll.
			hex.encounter_evaluated = true
		if _world_state != null:
			_world_state.set_hex_record(coords, hex.to_state())


func _apply_starter_v2_composition() -> void:
	var include_settlement := _has_alpha_starter_settlement()
	var profile: ZoneGenerationProfile = _ZoneGenerationProfile.starter_node(
		_arm_key(), include_settlement
	)
	var inward_direction := HexCoordUtils.opposite_travel_direction(int(node_arm_direction))
	var logistics_entry := HexCoordUtils.rim_anchor(inward_direction, ZONE_RADIUS)
	var outward_coords := HexCoordUtils.rim_anchor(int(node_arm_direction), ZONE_RADIUS)
	generated_plan = _StarterZonePlanner.build_plan(
		_zone_seed(), ZONE_RADIUS, logistics_entry, outward_coords, world_hex_cache,
		profile, include_settlement
	)
	starter_settlement_coords = (
		generated_plan.settlement_coords if include_settlement else Vector2i.ZERO
	)
	objective_coords = generated_plan.gameplay_anchor_coords
	trail_hexes.clear()
	var terrain_assignments := _build_starter_terrain_assignments()
	generated_plan.terrain_asset_usage.clear()

	for coords in world_hex_cache.keys():
		var hex: MacroHexData = world_hex_cache[coords]
		hex.world_generation_version = 2
		hex.terrain_asset_id = str(terrain_assignments.get(coords, "terrain.plains.green.5"))
		generated_plan.terrain_asset_usage[hex.terrain_asset_id] = (
			int(generated_plan.terrain_asset_usage.get(hex.terrain_asset_id, 0)) + 1
		)
		hex.overlay_asset_ids.clear()
		hex.composition_role = generated_plan.role_at(coords)
		hex.stamp_instance_id = ""
		hex.road_mask = generated_plan.road_mask_at(coords)
		hex.loot_tier_id = ""
		hex.search_site_id = ""
		hex.trace_records.clear()
		hex.biome = GameEnums.GridBiome.PLAINS
		hex.biome_pack = GameEnums.BIOME_PACK_PLAINS
		hex.terrain_tile = GameEnums.MacroTerrainTile.PLAINS_GRASS
		hex.structure_layer = GameEnums.MacroStructureLayer.NONE
		hex.structure_sprite_path = ""
		hex.is_poi = false
		hex.poi_id = ""
		hex.poi_name = ""
		hex.landmark_id = ""
		if generated_plan.road_cells.has(coords):
			trail_hexes[coords] = true
			var road_surface := (
				"dirt" if hex.composition_role == "dirt_service_spur" else "paved"
			)
			hex.overlay_asset_ids.append(
				"overlay.road.%s.%02d" % [road_surface, hex.road_mask]
			)
			hex.impassable = false
			hex.rock_layer = GameEnums.MacroRockLayer.NONE
			hex.flora_layer = GameEnums.MacroFloraLayer.NONE
			hex.hazard_level = minf(hex.hazard_level, 1.25)
			hex.encounter_evaluated = true
		if generated_plan.stamp_cells.has(coords):
			var stamp_cell: Dictionary = generated_plan.stamp_cells[coords]
			hex.stamp_instance_id = str(stamp_cell.get("stamp_instance_id", ""))
			hex.impassable = false
			hex.rock_layer = GameEnums.MacroRockLayer.NONE
			hex.flora_layer = GameEnums.MacroFloraLayer.NONE
			hex.hazard_level = minf(hex.hazard_level, 0.75)
			if hex.composition_role in ["settlement_structure", "settlement_tent"]:
				hex.structure_layer = GameEnums.MacroStructureLayer.STRUCTURES
			elif hex.composition_role == "settlement_rubble":
				hex.structure_layer = GameEnums.MacroStructureLayer.REMNANTS

	var ordered_rubble: Array[Vector2i] = generated_plan.rubble_search_cells.duplicate()
	ordered_rubble.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var a_distance := HexCoordUtils.distance(start_coords, a)
		var b_distance := HexCoordUtils.distance(start_coords, b)
		if a_distance == b_distance:
			return str(a) < str(b)
		return a_distance < b_distance
	)
	generated_plan.rubble_search_cells = ordered_rubble
	var search_catalog := SearchSiteCatalog.data()
	var assigned_search_sites: Array[String] = (
		search_catalog.assignment_ids_for_arm(_arm_key())
		if search_catalog != null
		else []
	)
	for rubble_index in range(generated_plan.rubble_search_cells.size()):
		var coords: Vector2i = generated_plan.rubble_search_cells[rubble_index]
		var rubble_hex: MacroHexData = world_hex_cache[coords]
		rubble_hex.structure_layer = GameEnums.MacroStructureLayer.REMNANTS
		rubble_hex.loot_tier_id = profile.loot_tier_id
		if rubble_index < assigned_search_sites.size():
			rubble_hex.search_site_id = assigned_search_sites[rubble_index]
		rubble_hex.impassable = false

	if include_settlement:
		_seed_starter_truth_grove()
		starter_npc_coords = generated_plan.gameplay_anchor_coords
		for coords in generated_plan.stamp_cells.keys():
			if generated_plan.role_at(coords) == "settlement_tent":
				starter_npc_coords = coords
				break
	_apply_route_1_signature_landmark(include_settlement)
	starter_clue_coords = outward_coords
	for trace in generated_plan.trace_records:
		var trace_coords: Vector2i = trace.get("coords", Vector2i.ZERO)
		if world_hex_cache.has(trace_coords):
			world_hex_cache[trace_coords].trace_records.append(trace.duplicate(true))
	if not generated_plan.is_valid():
		push_error("Starter V2 plan failed validation: %s" % "; ".join(generated_plan.validation_errors))


func _has_alpha_starter_settlement() -> bool:
	# Alpha lock. Production can seed-select one arm later, but the inner ring
	# must still contain exactly one inhabited starter settlement.
	return node_id == "north_random_1"


func _apply_route_1_signature_landmark(include_settlement: bool) -> void:
	var catalog := Route1LandmarkCatalog.data()
	var definition := catalog.for_arm(_arm_key()) if catalog != null else null
	if definition == null:
		return
	var signature_coords := generated_plan.gameplay_anchor_coords
	if not include_settlement:
		var spur_cells: Array[Vector2i] = []
		for coords in generated_plan.road_cells.keys():
			if generated_plan.role_at(coords) == "dirt_service_spur":
				spur_cells.append(coords)
		spur_cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			var a_distance := HexCoordUtils.distance(a, Vector2i.ZERO)
			var b_distance := HexCoordUtils.distance(b, Vector2i.ZERO)
			if a_distance == b_distance:
				return str(a) < str(b)
			return a_distance < b_distance
		)
		if not spur_cells.is_empty():
			signature_coords = spur_cells[0]
	objective_coords = signature_coords
	var anchor: MacroHexData = world_hex_cache[signature_coords]
	anchor.is_poi = true
	anchor.poi_id = definition.poi_id
	anchor.poi_name = definition.display_name
	anchor.landmark_id = definition.landmark_id
	anchor.sleep_anchor = definition.sleep_anchor
	anchor.structure_layer = GameEnums.MacroStructureLayer.STRUCTURES
	anchor.structure_pack = GameEnums.BIOME_PACK_DEFAULT_ERA8
	anchor.impassable = false
	anchor.encounter_evaluated = true


func _build_starter_terrain_assignments() -> Dictionary:
	var ordered_cells: Array[Vector2i] = []
	for coords in world_hex_cache.keys():
		ordered_cells.append(coords)
	ordered_cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		if a.y == b.y:
			return a.x < b.x
		return a.y < b.y
	)
	# Fisher-Yates gives each seed a different spatial composition. Cycling the
	# complete palette after the shuffle guarantees all 54 variants appear.
	var rng := RandomNumberGenerator.new()
	rng.seed = (_zone_seed() + ":terrain_palette_v2").hash()
	for index in range(ordered_cells.size() - 1, 0, -1):
		var swap_index := rng.randi_range(0, index)
		var held := ordered_cells[index]
		ordered_cells[index] = ordered_cells[swap_index]
		ordered_cells[swap_index] = held
	var assignments: Dictionary = {}
	var variant_offset := rng.randi_range(0, STARTER_TERRAIN_VARIANT_NUMBERS.size() - 1)
	for index in range(ordered_cells.size()):
		var palette_index := (index + variant_offset) % STARTER_TERRAIN_VARIANT_NUMBERS.size()
		assignments[ordered_cells[index]] = "terrain.plains.green.%d" % (
			STARTER_TERRAIN_VARIANT_NUMBERS[palette_index]
		)
	return assignments


func _seed_starter_truth_grove() -> void:
	# Guarantee one readable woodland mass near the reference settlement view.
	# The first cell is seed-ranked, then adjacent eligible cells grow from it.
	var candidates: Array[Vector2i] = []
	for coords in world_hex_cache.keys():
		var distance := HexCoordUtils.distance(coords, starter_settlement_coords)
		if distance < 2 or distance > 3:
			continue
		if not _is_quiet_grove_cell(coords):
			continue
		candidates.append(coords)
	candidates.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return (
			(_zone_seed() + ":truth_grove:" + str(a)).hash()
			< (_zone_seed() + ":truth_grove:" + str(b)).hash()
		)
	)
	if candidates.is_empty():
		return
	var selected: Array[Vector2i] = [candidates[0]]
	var frontier: Array[Vector2i] = [candidates[0]]
	while not frontier.is_empty() and selected.size() < 5:
		var current: Vector2i = frontier.pop_front()
		for direction in HexCoordUtils.AXIAL_DIRECTIONS:
			var neighbor: Vector2i = current + Vector2i(direction)
			if HexCoordUtils.distance(neighbor, starter_settlement_coords) > 3:
				continue
			if selected.has(neighbor) or not _is_quiet_grove_cell(neighbor):
				continue
			selected.append(neighbor)
			frontier.append(neighbor)
			if selected.size() >= 5:
				break
	for coords in selected:
		var hex: MacroHexData = world_hex_cache[coords]
		hex.flora_layer = GameEnums.MacroFloraLayer.TREES
		hex.rock_layer = GameEnums.MacroRockLayer.NONE
		hex.impassable = false


func _is_quiet_grove_cell(coords: Vector2i) -> bool:
	if not world_hex_cache.has(coords):
		return false
	if generated_plan == null or generated_plan.role_at(coords) != "quiet_plains":
		return false
	if generated_plan.road_cells.has(coords) or generated_plan.stamp_cells.has(coords):
		return false
	if generated_plan.rubble_search_cells.has(coords) or generated_plan.visual_rubble_cells.has(coords):
		return false
	var hex: MacroHexData = world_hex_cache[coords]
	return hex.rock_layer == GameEnums.MacroRockLayer.NONE


func _apply_starter_v2_dressing() -> void:
	if generated_plan == null:
		return
	var structure_index := 0
	var tent_index := 0
	var rubble_index := 0
	for coords in generated_plan.stamp_cells.keys():
		var role := generated_plan.role_at(coords)
		match role:
			"settlement_structure":
				_append_authored_decoration(coords, STARTER_STRUCTURE_PATHS[structure_index % STARTER_STRUCTURE_PATHS.size()], "structure", 1.0)
				structure_index += 1
			"settlement_tent":
				_append_tent_cluster(coords, tent_index)
				tent_index += 1
			"settlement_rubble":
				_append_rubble_cluster(coords, rubble_index, 1.0, 3)
				rubble_index += 1
			"settlement_anchor":
				_append_authored_decoration(coords, STARTER_INFRA_PATHS[0], "prop", 1.0)
	for coords in generated_plan.rubble_search_cells:
		_append_rubble_cluster(coords, rubble_index, 0.95, 3)
		rubble_index += 1
	for coords in generated_plan.visual_rubble_cells:
		_append_rubble_cluster(coords, rubble_index, 0.84, 2)
		rubble_index += 1
	var infra_index := 1
	for coords in generated_plan.stamp_cells.keys():
		if infra_index >= STARTER_INFRA_PATHS.size():
			break
		if generated_plan.role_at(coords) == "settlement_structure":
			_append_authored_decoration(coords, STARTER_INFRA_PATHS[infra_index], "prop", 0.88)
			infra_index += 1


func _append_tent_cluster(coords: Vector2i, cluster_index: int) -> void:
	var phase := posmod(cluster_index + absi((_zone_seed() + str(coords)).hash()), 3)
	var tent_offset_recipes: Array = [
		[Vector2(-82.0, 28.0), Vector2(76.0, -36.0), Vector2(26.0, 104.0)],
		[Vector2(-72.0, -34.0), Vector2(88.0, 32.0), Vector2(-18.0, 108.0)],
		[Vector2(-92.0, 12.0), Vector2(62.0, 48.0), Vector2(44.0, -104.0)],
	]
	var tent_offsets: Array = tent_offset_recipes[phase]
	_append_authored_decoration(
		coords,
		STARTER_TENT_PATHS[cluster_index % STARTER_TENT_PATHS.size()],
		"tent",
		0.82,
		tent_offsets[0]
	)
	_append_authored_decoration(
		coords,
		STARTER_TENT_PATHS[(cluster_index + 1) % STARTER_TENT_PATHS.size()],
		"tent",
		0.72,
		tent_offsets[1],
		cluster_index % 2 == 0
	)
	# Every other camp gets a smaller third shelter, so the settlement reads as
	# several lived-in camps rather than six identical two-object stamps.
	if cluster_index % 2 == 0:
		_append_authored_decoration(
			coords,
			STARTER_TENT_PATHS[(cluster_index + 2) % STARTER_TENT_PATHS.size()],
			"tent",
			0.60,
			tent_offsets[2],
			true
		)
	var detail_offsets := [Vector2(-12.0, 112.0), Vector2(132.0, 74.0)]
	for detail_index in range(2):
		var path: String = STARTER_INFRA_PATHS[
			1 + posmod(cluster_index * 2 + detail_index, STARTER_INFRA_PATHS.size() - 1)
		]
		_append_authored_decoration(
			coords,
			path,
			"prop",
			0.72 if detail_index == 0 else 0.62,
			detail_offsets[detail_index]
		)


func _append_rubble_cluster(
	coords: Vector2i,
	cluster_index: int,
	scale_multiplier: float,
	shrub_count: int
) -> void:
	var phase := posmod(cluster_index + absi((_zone_seed() + ":rubble:" + str(coords)).hash()), 4)
	var rubble_offsets := [
		Vector2(-18.0, 12.0), Vector2(20.0, -8.0),
		Vector2(-8.0, -18.0), Vector2(14.0, 18.0),
	]
	_append_authored_decoration(
		coords,
		RANDOM_REMNANT_PATHS[cluster_index % RANDOM_REMNANT_PATHS.size()],
		"rock",
		scale_multiplier,
		rubble_offsets[phase]
	)
	var shrub_offsets := [
		Vector2(-144.0, 66.0), Vector2(136.0, 54.0),
		Vector2(-112.0, -86.0), Vector2(104.0, -96.0),
	]
	for shrub_index in range(shrub_count):
		var slot := posmod(phase + shrub_index, shrub_offsets.size())
		var shrub_path: String = DECOR_SHRUB_PATHS[
			posmod(cluster_index * 3 + shrub_index, DECOR_SHRUB_PATHS.size())
		]
		_append_authored_decoration(
			coords,
			shrub_path,
			"shrub",
			0.86 + float((cluster_index + shrub_index) % 3) * 0.06,
			shrub_offsets[slot],
			(cluster_index + shrub_index) % 2 == 0
		)


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
		if _is_starter_route_zone() and hex.composition_role != "quiet_plains":
			continue
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
		if (
			hex.rock_layer != GameEnums.MacroRockLayer.NONE
			or hex.flora_layer == GameEnums.MacroFloraLayer.TREES
		):
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
			var kind := _decor_kind(path)
			var offset := _sample_cluster_offset(rng, used_offsets, kind, path)
			used_offsets.append(offset)
			var asset_meta := _asset_metadata_for_path(path)
			props.append({
				"coords": coords,
				"asset_id": str(asset_meta.get("asset_id", "")),
				"sprite_path": path,
				"kind": kind,
				"footprint_class": str(asset_meta.get("footprint_class", "fitted_prop")),
				"target_box": _decor_target_box(kind, path),
				"scale_multiplier": rng.randf_range(0.88, 1.08),
				"offset": offset,
				"rotation": 0.0,
				"flip_h": kind == "shrub" and rng.randf() < 0.35,
				"layer": _decor_layer(path),
			})
		if not props.is_empty():
			zone_decorations[coords] = props


func _append_authored_decoration(
	coords: Vector2i,
	path: String,
	kind: String,
	scale_multiplier: float,
	offset: Vector2 = Vector2.ZERO,
	flip_h: bool = false
) -> void:
	if not world_hex_cache.has(coords) or not ResourceLoader.exists(path):
		return
	var asset_meta := _asset_metadata_for_path(path)
	var footprint_class := str(asset_meta.get("footprint_class", "fitted_prop"))
	var props: Array = zone_decorations.get(coords, [])
	props.append({
		"coords": coords,
		"asset_id": str(asset_meta.get("asset_id", "")),
		"sprite_path": path,
		"kind": kind,
		"footprint_class": footprint_class,
		"reserved_cells": _reserved_cells_for_decoration(coords, footprint_class),
		"target_box": _decor_target_box(kind, path),
		"scale_multiplier": scale_multiplier,
		"offset": offset,
		"rotation": 0.0,
		"flip_h": flip_h,
		"layer": _decor_layer(path),
	})
	zone_decorations[coords] = props


func _asset_metadata_for_path(path: String) -> Dictionary:
	if _runtime_asset_metadata.is_empty():
		for entry in _WorldAssetManifest.approved_assets():
			if not entry is Dictionary:
				continue
			_runtime_asset_metadata[str(entry.get("destination", ""))] = entry
	return _runtime_asset_metadata.get(path, {})


func _reserved_cells_for_decoration(coords: Vector2i, footprint_class: String) -> Array[Vector2i]:
	var reserved: Array[Vector2i] = [coords]
	if footprint_class != "reserved_two_hex":
		return reserved
	if generated_plan != null:
		for direction in HexCoordUtils.AXIAL_DIRECTIONS:
			var neighbor: Vector2i = coords + Vector2i(direction)
			if generated_plan.stamp_cells.has(neighbor):
				reserved.append(neighbor)
				return reserved
		generated_plan.overflow_violations.append({
			"coords": coords,
			"footprint_class": footprint_class,
			"reason": "No reserved neighboring stamp cell.",
		})
		generated_plan.validation_errors.append("Large dressing has no reserved neighboring cell.")
	return reserved


func _cluster_size_for_hex(hex: MacroHexData, rng: RandomNumberGenerator) -> int:
	if hex.flora_layer == GameEnums.MacroFloraLayer.TREES:
		return rng.randi_range(3, 5)
	if hex.rock_layer == GameEnums.MacroRockLayer.ROCKS:
		return rng.randi_range(3, 4)
	if hex.rock_layer == GameEnums.MacroRockLayer.HILLS:
		return rng.randi_range(2, 3)
	if hex.structure_layer != GameEnums.MacroStructureLayer.NONE:
		return rng.randi_range(2, 4)
	return rng.randi_range(1, 3)


func _pick_cluster_decor_path(
	hex: MacroHexData,
	rng: RandomNumberGenerator,
	index: int
) -> String:
	if hex.flora_layer == GameEnums.MacroFloraLayer.TREES:
		if index == 0:
			return DECOR_TREE_PATHS[rng.randi_range(0, DECOR_TREE_PATHS.size() - 1)]
		return DECOR_SHRUB_PATHS[rng.randi_range(0, DECOR_SHRUB_PATHS.size() - 1)]
	if hex.rock_layer != GameEnums.MacroRockLayer.NONE:
		var prefer_north_rocks := hex.biome_pack == GameEnums.BIOME_PACK_NORTH
		if prefer_north_rocks and index < 2:
			var north_rock := _pick_curated_layer_path(DECOR_NORTH_ROCK_PATHS, rng)
			if not north_rock.is_empty():
				return north_rock
		if index == 0:
			# Sz2 establishes the rock mass; smaller stones and restrained scrub
			# frame it instead of forming a tiny central pebble pile.
			return DECOR_ROCK_PATHS[rng.randi_range(3, 4)]
		if index == 1 or rng.randf() < 0.72:
			return DECOR_ROCK_PATHS[rng.randi_range(0, 2)]
		return DECOR_SHRUB_PATHS[rng.randi_range(0, DECOR_SHRUB_PATHS.size() - 1)]
	if rng.randf() < 0.12:
		if hex.biome_pack == GameEnums.BIOME_PACK_NORTH:
			var north_rock := _pick_curated_layer_path(DECOR_NORTH_ROCK_PATHS, rng)
			if not north_rock.is_empty():
				return north_rock
		return DECOR_ROCK_PATHS[rng.randi_range(0, DECOR_ROCK_PATHS.size() - 1)]
	if hex.structure_layer != GameEnums.MacroStructureLayer.NONE and rng.randf() < 0.65:
		return DECOR_PROP_PATHS[rng.randi_range(0, DECOR_PROP_PATHS.size() - 1)]
	return DECOR_SHRUB_PATHS[rng.randi_range(0, DECOR_SHRUB_PATHS.size() - 1)]


func _sample_cluster_offset(
	rng: RandomNumberGenerator,
	used_offsets: Array[Vector2],
	kind: String,
	path: String
) -> Vector2:
	var large_visual := kind == "tree" or (kind == "rock" and "sz2" in path.to_lower())
	var inset := 72.0 if large_visual else 38.0
	var max_y := 154.0 if large_visual else 188.0
	var min_separation := 92.0 if large_visual else (62.0 if kind == "rock" else 48.0)
	for _attempt in range(28):
		var y := rng.randf_range(-max_y, max_y)
		# Exact pointy-hex interior: vertical sides through |y| <= 128,
		# then the diagonal caps pull toward the top/bottom point.
		var polygon_limit := 256.0 if absf(y) <= 128.0 else 512.0 - 2.0 * absf(y)
		var x_limit := maxf(36.0, polygon_limit - inset)
		var candidate := Vector2(rng.randf_range(-x_limit, x_limit), y)
		var separated := true
		for used in used_offsets:
			if candidate.distance_to(used) < min_separation:
				separated = false
				break
		if separated:
			return candidate
	# Deterministic frame slots prevent a failed dense recipe from collapsing
	# every remaining object back into the middle of the tile.
	var frame_slots := [
		Vector2(-152.0, -58.0), Vector2(152.0, -58.0),
		Vector2(-138.0, 72.0), Vector2(138.0, 72.0),
		Vector2(-68.0, -146.0), Vector2(70.0, 146.0),
	]
	return frame_slots[rng.randi_range(0, frame_slots.size() - 1)]


func _decor_kind(path: String) -> String:
	var lowered := path.to_lower()
	if "tree" in lowered:
		return "tree"
	if "rocks" in lowered:
		return "rock"
	if "shrub" in lowered:
		return "shrub"
	return "prop"


func _decor_target_box(kind: String, path: String = "") -> Vector2:
	var lowered := path.to_lower()
	match kind:
		"structure":
			return Vector2(300.0, 240.0)
		"tent":
			return Vector2(176.0, 126.0)
		"tree":
			return Vector2(310.0, 270.0)
		"rock":
			if "sz2" in lowered:
				return Vector2(270.0, 220.0)
			if "rubble" in lowered:
				return Vector2(270.0, 205.0)
			return Vector2(164.0, 132.0)
		"shrub":
			return Vector2(54.0, 62.0)
		"prop":
			if "post" in lowered:
				return Vector2(78.0, 126.0)
			if "crate" in lowered:
				return Vector2(92.0, 72.0)
			if "barrel" in lowered:
				return Vector2(74.0, 82.0)
			if "solar panel" in lowered:
				return Vector2(150.0, 112.0)
			return Vector2(96.0, 80.0)
		_:
			return Vector2(62.0, 68.0)


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
	if _is_starter_route_zone():
		if _world_state != null:
			_world_state.set_hex_record(start_coords, start_hex.to_state())
		return

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


func _is_starter_route_zone() -> bool:
	return (
		zone_profile_id == "starter_route_1"
		or (
			node_arm_tier == 1
			and node_arm_direction != GameEnums.MacroArmDirection.NONE
		)
	)


func _arm_key() -> String:
	match node_arm_direction:
		GameEnums.MacroArmDirection.NORTH:
			return "north"
		GameEnums.MacroArmDirection.EAST:
			return "east"
		GameEnums.MacroArmDirection.SOUTH:
			return "south"
		GameEnums.MacroArmDirection.WEST:
			return "west"
		_:
			return "unknown"


func _arm_label() -> String:
	return _arm_key().capitalize()


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
