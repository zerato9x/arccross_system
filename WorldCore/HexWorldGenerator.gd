extends Node
class_name HexWorldGenerator

@export var master_seed: String = "THE_NORTH_REMEMBERS"
@export_range(0.0, 1.0) var random_structure_chance: float = 0.012
@export_range(0.0, 1.0) var random_remnant_chance: float = 0.022
@export_range(0.0, 1.0) var shrub_spawn_chance: float = 0.14

@export_group("Authored Map")
@export var authored_map: Resource
@export var require_authored_map: bool = false

@export_group("Macro Regions")
## Legacy hub+wedge procedural world. Campaign play must inject MacroZoneGenerator
## zones instead; keep this false except for old smokes/tools that still exercise
## the pre-Node-Web layout.
@export var enable_legacy_hub_wedge: bool = false
@export_range(1, 6) var central_hub_radius: int = 2
@export_range(3, 12) var hub_border_radius: int = 4

## When enabled, only axial cells within zone_radius of the origin are playable.
@export var zone_bounds_enabled: bool = false
@export_range(1, 32) var zone_radius: int = GameEnums.MACRO_ZONE_RADIUS

var elevation_noise: FastNoiseLite
var moisture_noise: FastNoiseLite
var world_hex_cache: Dictionary = {}
var manual_poi_overrides: Dictionary = {}
## Zone-generated prop clutter (Vector2i -> Array[Dictionary]). Used when no authored map.
var zone_decorations: Dictionary = {}

var _world_state: RuntimeStateStore
var _mutation_store: Node
const _SectorCatalog := preload("res://WorldCore/WorldSectorCatalog.gd")
const _PoiVisualCatalog := preload("res://PresentationCore/PoiVisualCatalog.gd")

func configure_services(world_state: RuntimeStateStore) -> void:
	_world_state = world_state

func _ready() -> void:
	if _world_state == null:
		_world_state = get_node("/root/WorldState") as RuntimeStateStore
	_mutation_store = get_node_or_null("/root/WorldMutationStore")
	_initialize_noise()
	if authored_map != null:
		authored_map.rebuild_index()

func _initialize_noise() -> void:
	elevation_noise = FastNoiseLite.new()
	elevation_noise.seed = (master_seed + ":elevation").hash()
	elevation_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	elevation_noise.frequency = 0.04

	moisture_noise = FastNoiseLite.new()
	moisture_noise.seed = (master_seed + ":moisture").hash()
	moisture_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	moisture_noise.frequency = 0.06

static func compute_visual_variant_hash(coords: Vector2i, seed_value: String) -> int:
	return absi((seed_value + ":variant:" + str(coords.x) + ":" + str(coords.y)).hash())

static func build_void_hex(coords: Vector2i) -> MacroHexData:
	var hex := MacroHexData.new()
	hex.zone_id = "void"
	hex.region = GameEnums.MacroRegion.WASTELAND
	hex.impassable = true
	hex.terrain_tile = GameEnums.MacroTerrainTile.PLAINS_GRASS
	return hex

func configure_seed(seed_value: String) -> void:
	master_seed = seed_value
	world_hex_cache.clear()
	manual_poi_overrides.clear()
	_initialize_noise()


func enable_zone_bounds(radius: int = GameEnums.MACRO_ZONE_RADIUS) -> void:
	zone_bounds_enabled = true
	zone_radius = radius


func disable_zone_bounds() -> void:
	zone_bounds_enabled = false


func is_in_zone_bounds(coords: Vector2i) -> bool:
	if not zone_bounds_enabled:
		return true
	return HexCoordUtils.is_in_radius(coords, zone_radius)


func inject_zone_hexes(hexes: Dictionary) -> void:
	## Replace cache with a pre-generated local zone (Vector2i -> MacroHexData).
	world_hex_cache.clear()
	zone_decorations.clear()
	for coords in hexes.keys():
		if coords is Vector2i:
			world_hex_cache[coords] = hexes[coords]


func inject_zone_decorations(decorations: Dictionary) -> void:
	zone_decorations = decorations.duplicate(true)


func get_decorations_at(coords: Vector2i) -> Array:
	if authored_map != null and authored_map.has_method("get_decorations_at"):
		var authored_props: Array = authored_map.get_decorations_at(coords)
		if not authored_props.is_empty():
			return authored_props
	return zone_decorations.get(coords, [])


func inject_unique_poi(
	coords: Vector2i,
	poi_id: String,
	poi_name: String,
	forced_biome: GameEnums.GridBiome
) -> void:
	manual_poi_overrides[coords] = {
		"id": poi_id,
		"name": poi_name,
		"biome": forced_biome,
	}


func get_hex_at(coords: Vector2i) -> MacroHexData:
	if world_hex_cache.has(coords):
		return world_hex_cache[coords]

	if zone_bounds_enabled and not is_in_zone_bounds(coords):
		# Boundary probes are not part of the local zone. Caching them quietly
		# bloats a 469-cell map and leaks fake cells into node snapshots.
		return build_void_hex(coords)

	var persistent_state: HexRecord = _world_state.get_hex_record(coords)
	if persistent_state != null:
		var persistent_hex := MacroHexData.from_state(persistent_state)
		if persistent_hex.zone_id.is_empty():
			_assign_zone_identity(coords, persistent_hex)
		if persistent_hex.visual_variant_hash == 0:
			persistent_hex.visual_variant_hash = compute_visual_variant_hash(
				coords,
				master_seed
			)
		# Persisted records are authoritative. Reapplying regional defaults here
		# changes injected campaign-zone values after a cache clear/save reload.
		_world_state.set_hex_record(coords, persistent_hex.to_state())
		world_hex_cache[coords] = persistent_hex
		return persistent_hex

	var new_hex := _build_fresh_hex(coords)
	_apply_region_hazard(coords, new_hex)
	if new_hex.visual_variant_hash == 0:
		new_hex.visual_variant_hash = compute_visual_variant_hash(coords, master_seed)
	world_hex_cache[coords] = new_hex
	_world_state.set_hex_record(coords, new_hex.to_state())
	return new_hex

func _build_fresh_hex(coords: Vector2i) -> MacroHexData:
	if manual_poi_overrides.has(coords):
		var hex := MacroHexData.new()
		_assign_zone_identity(coords, hex)
		_apply_manual_override(coords, hex)
		_apply_world_mutations(coords, hex)
		return hex

	if authored_map != null:
		if _authored_map_has_hex(coords):
			var authored_hex: MacroHexData = authored_map.build_hex_data(
				coords,
				master_seed
			)
			_finalize_authored_hex(coords, authored_hex)
			_apply_world_mutations(coords, authored_hex)
			return authored_hex
		if require_authored_map:
			return build_void_hex(coords)

	# Campaign contract: inject MacroZoneGenerator output. Without inject (and
	# without authored_map), fall back to unscoped plains — never invent a fake
	# hub/wedge world unless explicitly opted in for legacy tools.
	if enable_legacy_hub_wedge:
		var procedural_hex := MacroHexData.new()
		_assign_zone_identity(coords, procedural_hex)
		if procedural_hex.zone_id == "hub_core":
			_apply_hub_core(coords, procedural_hex)
		elif procedural_hex.zone_id == "hub_border":
			_apply_hub_border(coords, procedural_hex)
		else:
			_generate_wedge_hex(coords, procedural_hex)
		_apply_world_mutations(coords, procedural_hex)
		return procedural_hex

	var unscoped := _build_unscoped_plains_hex(coords)
	_apply_world_mutations(coords, unscoped)
	return unscoped

func _finalize_authored_hex(coords: Vector2i, hex: MacroHexData) -> void:
	if hex.zone_id.is_empty():
		_assign_zone_identity(coords, hex)
	if hex.structure_sprite_path.is_empty() and not hex.landmark_id.is_empty():
		hex.structure_sprite_path = _PoiVisualCatalog.pick_structure_path(
			hex.landmark_id,
			master_seed,
			coords
		)

func _apply_world_mutations(coords: Vector2i, hex: MacroHexData) -> void:
	if _mutation_store == null:
		return
	if not _mutation_store.has_method("apply_patch_to_record"):
		return
	var record := hex.to_state()
	_mutation_store.apply_patch_to_record(coords, record)
	hex.apply_state(record)

func _build_unscoped_plains_hex(coords: Vector2i) -> MacroHexData:
	## Deterministic plains filler for debug get_hex_at without zone inject.
	## No hub_core / hub_border / wedge_* ids and no wedge landmarks.
	var hex := MacroHexData.new()
	hex.zone_id = "unscoped"
	hex.biome_pack = GameEnums.BIOME_PACK_PLAINS
	hex.region = GameEnums.MacroRegion.WASTELAND
	hex.biome = GameEnums.GridBiome.PLAINS
	hex.terrain_tile = GameEnums.MacroTerrainTile.PLAINS_GRASS
	hex.flora_layer = GameEnums.MacroFloraLayer.NONE
	hex.rock_layer = GameEnums.MacroRockLayer.NONE
	hex.structure_layer = GameEnums.MacroStructureLayer.NONE
	hex.is_poi = false
	hex.landmark_id = ""

	var elevation: float = elevation_noise.get_noise_2dv(coords)
	var moisture: float = moisture_noise.get_noise_2dv(coords)
	if elevation > 0.62:
		hex.rock_layer = GameEnums.MacroRockLayer.ROCKS
	elif elevation > 0.38:
		hex.rock_layer = GameEnums.MacroRockLayer.HILLS
	if hex.rock_layer != GameEnums.MacroRockLayer.ROCKS:
		if elevation < -0.30 or moisture < -0.30:
			hex.terrain_tile = GameEnums.MacroTerrainTile.MUD_YELLOW
		elif moisture > 0.32:
			hex.terrain_tile = GameEnums.MacroTerrainTile.FOREST_SPARSE
			hex.flora_layer = GameEnums.MacroFloraLayer.TREES

	_apply_shrub_variation(coords, hex, 1.0)

	var rng := RandomNumberGenerator.new()
	rng.seed = (master_seed + ":unscoped:layers:" + str(coords)).hash()
	if hex.structure_layer == GameEnums.MacroStructureLayer.NONE:
		var structure_roll := rng.randf()
		if structure_roll < random_structure_chance:
			hex.structure_layer = GameEnums.MacroStructureLayer.STRUCTURES
		elif structure_roll < random_structure_chance + random_remnant_chance:
			hex.structure_layer = GameEnums.MacroStructureLayer.REMNANTS
	return hex


func _assign_zone_identity(coords: Vector2i, hex: MacroHexData) -> void:
	var distance := _hex_distance(Vector2i.ZERO, coords)
	if distance <= central_hub_radius:
		hex.zone_id = "hub_core"
		hex.biome_pack = GameEnums.BIOME_PACK_CENTRALCORE
		hex.region = GameEnums.MacroRegion.CENTRAL_HUB
	elif distance <= hub_border_radius:
		hex.zone_id = "hub_border"
		hex.biome_pack = GameEnums.BIOME_PACK_PLAINS
		hex.region = GameEnums.MacroRegion.HUB_BORDER
	else:
		hex.zone_id = _SectorCatalog.wedge_id_for_coords(coords)
		hex.biome_pack = GameEnums.BIOME_PACK_PLAINS
		hex.region = GameEnums.MacroRegion.WASTELAND

func _apply_hub_core(coords: Vector2i, hex: MacroHexData) -> void:
	hex.biome = GameEnums.GridBiome.PLAINS
	hex.terrain_tile = GameEnums.MacroTerrainTile.HUB_CONCRETE
	hex.flora_layer = GameEnums.MacroFloraLayer.NONE
	hex.rock_layer = GameEnums.MacroRockLayer.NONE
	hex.structure_layer = GameEnums.MacroStructureLayer.STRUCTURES
	hex.hazard_level = 0.0
	hex.structure_sprite_path = _PoiVisualCatalog.pick_structure_path(
		"centralcore_city",
		master_seed,
		coords
	)
	if coords == Vector2i.ZERO:
		hex.impassable = false
		hex.is_poi = true
		hex.poi_id = "alpha_central_hub"
		hex.poi_name = "Alpha Hub"
		hex.landmark_id = "alpha_hub"
		hex.sleep_anchor = "bed"
	else:
		hex.impassable = true
		hex.is_poi = false
		hex.landmark_id = ""

func _apply_hub_border(coords: Vector2i, hex: MacroHexData) -> void:
	hex.biome = GameEnums.GridBiome.PLAINS
	hex.terrain_tile = GameEnums.MacroTerrainTile.PLAINS_GRASS
	hex.flora_layer = GameEnums.MacroFloraLayer.NONE
	hex.rock_layer = GameEnums.MacroRockLayer.NONE
	hex.structure_layer = GameEnums.MacroStructureLayer.NONE
	hex.is_poi = false
	hex.landmark_id = ""
	_apply_shrub_variation(coords, hex, 0.5)

func _generate_wedge_hex(coords: Vector2i, hex: MacroHexData) -> void:
	var wedge_def := _SectorCatalog.wedge_definition(hex.zone_id)
	var wedge_seed := master_seed + ":" + hex.zone_id
	var elevation: float = elevation_noise.get_noise_2dv(coords)
	var moisture: float = moisture_noise.get_noise_2dv(coords)

	hex.biome = GameEnums.GridBiome.PLAINS
	hex.terrain_tile = GameEnums.MacroTerrainTile.PLAINS_GRASS
	hex.flora_layer = GameEnums.MacroFloraLayer.NONE
	hex.rock_layer = GameEnums.MacroRockLayer.NONE
	hex.structure_layer = GameEnums.MacroStructureLayer.NONE
	hex.is_poi = false
	hex.landmark_id = ""

	if elevation > 0.62:
		hex.rock_layer = GameEnums.MacroRockLayer.ROCKS
	elif elevation > 0.38:
		hex.rock_layer = GameEnums.MacroRockLayer.HILLS

	if hex.rock_layer != GameEnums.MacroRockLayer.ROCKS:
		if elevation < -0.30 or moisture < -0.30:
			hex.terrain_tile = GameEnums.MacroTerrainTile.MUD_YELLOW
		elif moisture > 0.32:
			hex.terrain_tile = GameEnums.MacroTerrainTile.FOREST_SPARSE
			hex.flora_layer = GameEnums.MacroFloraLayer.TREES

	_apply_shrub_variation(coords, hex, 1.0)

	var rng := RandomNumberGenerator.new()
	rng.seed = (wedge_seed + ":layers:" + str(coords)).hash()
	if hex.structure_layer == GameEnums.MacroStructureLayer.NONE and hex.landmark_id.is_empty():
		var structure_roll := rng.randf()
		if structure_roll < random_structure_chance:
			hex.structure_layer = GameEnums.MacroStructureLayer.STRUCTURES
		elif structure_roll < random_structure_chance + random_remnant_chance:
			hex.structure_layer = GameEnums.MacroStructureLayer.REMNANTS

	var landmark_rng := RandomNumberGenerator.new()
	landmark_rng.seed = (wedge_seed + ":landmark:" + str(coords)).hash()
	if landmark_rng.randf() < float(wedge_def.get("poi_density", 0.06)):
		var landmark := _SectorCatalog.pick_landmark(wedge_seed, coords, hex.zone_id)
		hex.landmark_id = str(landmark.get("landmark_id", ""))
		hex.is_poi = true
		hex.poi_id = str(landmark.get("poi_id", "plains_landmark"))
		hex.poi_name = str(landmark.get("poi_name", "Landmark"))
		hex.sleep_anchor = str(landmark.get("sleep_anchor", "ground"))
		hex.structure_layer = GameEnums.MacroStructureLayer.STRUCTURES
		hex.structure_sprite_path = _PoiVisualCatalog.pick_structure_path(
			hex.landmark_id,
			wedge_seed,
			coords
		)

func _apply_manual_override(coords: Vector2i, hex: MacroHexData) -> void:
	var override_data: Dictionary = manual_poi_overrides[coords]
	hex.biome = override_data.get("biome", GameEnums.GridBiome.PLAINS)
	hex.is_poi = true
	hex.poi_id = str(override_data.get("id", ""))
	hex.poi_name = str(override_data.get("name", "Unknown"))
	hex.landmark_id = str(override_data.get("landmark_id", hex.poi_id))
	hex.structure_layer = GameEnums.MacroStructureLayer.STRUCTURES
	hex.sleep_anchor = str(override_data.get("sleep_anchor", "ground"))
	hex.structure_sprite_path = _PoiVisualCatalog.pick_structure_path(
		hex.landmark_id,
		master_seed,
		coords
	)

func _apply_shrub_variation(
	coords: Vector2i,
	hex: MacroHexData,
	chance_scale: float
) -> void:
	if (
		hex.zone_id == "hub_core"
		or hex.terrain_tile != GameEnums.MacroTerrainTile.PLAINS_GRASS
		or hex.flora_layer != GameEnums.MacroFloraLayer.NONE
	):
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = (master_seed + ":shrub:" + str(coords)).hash()
	if rng.randf() < shrub_spawn_chance * chance_scale:
		hex.flora_layer = GameEnums.MacroFloraLayer.SHRUBS

func _apply_region_hazard(coords: Vector2i, hex: MacroHexData) -> void:
	if hex.zone_id == "void":
		hex.hazard_level = GameEnums.SCALE_MAX
		return
	if hex.hazard_level > 0.0 and authored_map != null and _authored_map_has_hex(coords):
		return
	var distance := _hex_distance(Vector2i.ZERO, coords)
	match hex.zone_id:
		"hub_core":
			hex.hazard_level = 0.0
		"hub_border":
			hex.hazard_level = 1.0
		"unscoped":
			hex.hazard_level = clampf(2.0 + float(distance) * 0.08, 0.0, GameEnums.SCALE_MAX)
		_:
			var wedge_def := _SectorCatalog.wedge_definition(hex.zone_id)
			hex.hazard_level = clampf(
				float(wedge_def.get("hazard_bias", 3.0)) + float(distance) * 0.08,
				0.0,
				GameEnums.SCALE_MAX
			)

func _hex_distance(from_coords: Vector2i, to_coords: Vector2i) -> int:
	var delta := to_coords - from_coords
	return maxi(abs(delta.x), maxi(abs(delta.y), abs(delta.x + delta.y)))


func _authored_map_has_hex(coords: Vector2i) -> bool:
	return authored_map != null and authored_map.has_method("has_hex") and authored_map.has_hex(coords)
