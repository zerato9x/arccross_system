extends Node
class_name HexWorldGenerator

# ---------------------------------------------------------
# THE SEED & THE NOISE
# ---------------------------------------------------------
@export var master_seed: String = "THE_NORTH_REMEMBERS"
@export var snow_transition_distance: int = 48
@export_range(0.0, 1.0) var random_structure_chance: float = 0.015
@export_range(0.0, 1.0) var random_remnant_chance: float = 0.025
@export_range(0.0, 1.0) var shrub_spawn_chance: float = 0.14

@export_group("Macro Regions")
@export_range(0, 6) var central_hub_radius: int = 2
@export_range(0, 12) var hub_border_radius: int = 5
@export var active_arm_directions: Array[int] = [
	GameEnums.MacroArmDirection.EAST,
]
@export_range(1, 3) var active_arm_stages: int = 1
@export_range(1, 48) var arm_stage_1_length: int = 18
@export_range(1, 48) var arm_stage_2_length: int = 20
@export_range(1, 48) var arm_stage_3_length: int = 24
@export_range(0, 12) var arm_initial_half_width: int = 1
@export_range(1, 18) var arm_final_half_width: int = 6

var elevation_noise: FastNoiseLite
var moisture_noise: FastNoiseLite
var world_hex_cache: Dictionary = {} # Stores Vector2i -> MacroHexData
var manual_poi_overrides: Dictionary = {} # Stores Vector2i -> Dictionary (POI Data)

# --- SECTOR LOGIC ---
@export var sector_size: int = 10
# Registry of hand-crafted sectors. Key: Vector2i (Sector Coord), Value: Dictionary containing hex data
var handcrafted_sectors: Dictionary = {} 

var _world_state: RuntimeStateStore

func configure_services(world_state: RuntimeStateStore) -> void:
	_world_state = world_state


func _ready() -> void:
	if _world_state == null:
		_world_state = get_node("/root/WorldState") as RuntimeStateStore
	_initialize_noise()

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

func configure_seed(seed_value: String) -> void:
	master_seed = seed_value
	world_hex_cache.clear()
	manual_poi_overrides.clear()
	_initialize_noise()

# ---------------------------------------------------------
# THE NARRATIVE OVERRIDES
# ---------------------------------------------------------

## Call this from your narrative scripts BEFORE generating the map 
## to force a unique location into existence.
func inject_unique_poi(coords: Vector2i, poi_id: String, poi_name: String, forced_biome: GameEnums.GridBiome) -> void:
	manual_poi_overrides[coords] = {
		"id": poi_id,
		"name": poi_name,
		"biome": forced_biome
	}
	print("[CARTOGRAPHER] Narrative override injected at: ", coords, " -> ", poi_name)

# ---------------------------------------------------------
# PROCEDURAL GENERATION (The "Lazy Load")
# ---------------------------------------------------------

## Ask the map what exists at a coordinate. If it doesn't know, it creates it.
func get_hex_at(coords: Vector2i) -> MacroHexData:
	# 1. Have we been here before? Return the cached memory.
	if world_hex_cache.has(coords):
		return world_hex_cache[coords]

	var persistent_state: HexRecord = _world_state.get_hex_record(coords)
	if persistent_state != null:
		var persistent_hex := MacroHexData.from_state(persistent_state)
		_assign_region_identity(coords, persistent_hex)
		if persistent_hex.region == GameEnums.MacroRegion.CENTRAL_HUB:
			_apply_central_hub(coords, persistent_hex)
		else:
			_apply_region_hazard(coords, persistent_hex)
		if persistent_hex.visual_variant_hash == 0:
			persistent_hex.visual_variant_hash = compute_visual_variant_hash(
				coords,
				master_seed
			)
		_world_state.set_hex_record(coords, persistent_hex.to_state())
		world_hex_cache[coords] = persistent_hex
		return persistent_hex
		
	# 2. It's undiscovered country. We must generate it.
	var new_hex = MacroHexData.new()
	_assign_region_identity(coords, new_hex)
	
	# 3. The central city is a fixed world anchor, not a procedural accident.
	if new_hex.region == GameEnums.MacroRegion.CENTRAL_HUB:
		_apply_central_hub(coords, new_hex)

	# 4. Check the Narrative Override Dict. Did An manually put a camp here?
	elif manual_poi_overrides.has(coords):
		var override_data = manual_poi_overrides[coords]
		new_hex.biome = GameEnums.GridBiome.PLAINS
		new_hex.is_poi = true
		new_hex.poi_id = override_data["id"]
		new_hex.poi_name = override_data["name"]
		new_hex.structure_layer = GameEnums.MacroStructureLayer.STRUCTURES
		
	# 5. Check if it's in a Hand-Crafted Sector
	elif _is_in_handcrafted_sector(coords):
		_load_from_handcrafted_sector(coords, new_hex)
		
	# 6. No override or hand-crafted sector found. Roll the procedural noise engine.
	else:
		_generate_procedural_layers(coords, new_hex)

	if new_hex.region != GameEnums.MacroRegion.CENTRAL_HUB:
		_apply_region_hazard(coords, new_hex)

	new_hex.visual_variant_hash = compute_visual_variant_hash(coords, master_seed)
		
	# 7. Save it to the cache so it never changes, and return it.
	world_hex_cache[coords] = new_hex
	_world_state.set_hex_record(coords, new_hex.to_state())
	return new_hex

# ---------------------------------------------------------
# SECTOR HANDLERS
# ---------------------------------------------------------

func _get_sector_for_coords(coords: Vector2i) -> Vector2i:
	# Integer division correctly chunks coordinates into grid boxes
	var sx = int(floor(float(coords.x) / float(sector_size)))
	var sy = int(floor(float(coords.y) / float(sector_size)))
	return Vector2i(sx, sy)

func _is_in_handcrafted_sector(coords: Vector2i) -> bool:
	var sector = _get_sector_for_coords(coords)
	return handcrafted_sectors.has(sector)

func _load_from_handcrafted_sector(coords: Vector2i, hex: MacroHexData) -> void:
	var sector = _get_sector_for_coords(coords)
	var sector_data = handcrafted_sectors[sector]
	
	# Local coordinates within the sector (0 to sector_size - 1)
	var local_x = posmod(coords.x, sector_size)
	var local_y = posmod(coords.y, sector_size)
	var local_coords = Vector2i(local_x, local_y)
	
	# If the sector data has explicitly defined this hex, use it.
	if sector_data.has(local_coords):
		var data = sector_data[local_coords]
		hex.biome = data.get("biome", GameEnums.GridBiome.PLAINS)
		hex.terrain_tile = data.get(
			"terrain_tile",
			HexRecord._legacy_terrain_for_biome(hex.biome)
		)
		hex.flora_layer = data.get(
			"flora_layer",
			HexRecord._legacy_flora_for_biome(hex.biome)
		)
		hex.rock_layer = data.get(
			"rock_layer",
			HexRecord._legacy_rock_for_biome(hex.biome)
		)
		hex.structure_layer = data.get(
			"structure_layer",
			GameEnums.MacroStructureLayer.NONE
		)
		if data.get("is_poi", false):
			hex.is_poi = true
			hex.poi_id = data.get("poi_id", "")
			hex.poi_name = data.get("poi_name", "Unknown POI")
			if hex.structure_layer == GameEnums.MacroStructureLayer.NONE:
				hex.structure_layer = GameEnums.MacroStructureLayer.STRUCTURES
	else:
		# Fallback if a hex within a hand-crafted sector was left blank
		hex.biome = GameEnums.GridBiome.PLAINS
		hex.terrain_tile = GameEnums.MacroTerrainTile.PLAINS_GRASS
		hex.flora_layer = GameEnums.MacroFloraLayer.NONE

func _assign_region_identity(coords: Vector2i, hex: MacroHexData) -> void:
	var region_data := _resolve_region(coords)
	hex.region = int(region_data.get(
		"region",
		GameEnums.MacroRegion.WASTELAND
	))
	hex.arm_direction = int(region_data.get(
		"arm_direction",
		GameEnums.MacroArmDirection.NONE
	))

func _resolve_region(coords: Vector2i) -> Dictionary:
	var distance := _hex_distance(Vector2i.ZERO, coords)
	if distance <= central_hub_radius:
		return {
			"region": GameEnums.MacroRegion.CENTRAL_HUB,
			"arm_direction": GameEnums.MacroArmDirection.NONE,
		}
	if distance <= maxi(hub_border_radius, central_hub_radius):
		return {
			"region": GameEnums.MacroRegion.HUB_BORDER,
			"arm_direction": GameEnums.MacroArmDirection.NONE,
		}

	for direction in active_arm_directions:
		var arm_region := _resolve_arm_region(coords, direction)
		if arm_region != GameEnums.MacroRegion.WASTELAND:
			return {
				"region": arm_region,
				"arm_direction": direction,
			}
	return {
		"region": GameEnums.MacroRegion.WASTELAND,
		"arm_direction": GameEnums.MacroArmDirection.NONE,
	}

func _resolve_arm_region(
	coords: Vector2i,
	direction: int
) -> GameEnums.MacroRegion:
	var axes := _get_arm_axes(coords, direction)
	var forward: int = axes.x
	var lateral: int = axes.y
	var stage_start := maxi(hub_border_radius, central_hub_radius) + 1
	var stage_lengths := [
		arm_stage_1_length,
		arm_stage_2_length,
		arm_stage_3_length,
	]
	for stage_index in range(mini(active_arm_stages, stage_lengths.size())):
		var stage_length: int = stage_lengths[stage_index]
		if forward >= stage_start and forward < stage_start + stage_length:
			var stage_progress := float(forward - stage_start) / float(
				maxi(1, stage_length - 1)
			)
			var half_width := roundi(lerpf(
				float(arm_initial_half_width),
				float(arm_final_half_width),
				stage_progress
			))
			if abs(lateral) <= half_width:
				return GameEnums.MacroRegion.ARM_STAGE_1 + stage_index
			return GameEnums.MacroRegion.WASTELAND
		stage_start += stage_length
	return GameEnums.MacroRegion.WASTELAND

func _get_arm_axes(coords: Vector2i, direction: int) -> Vector2i:
	match direction:
		GameEnums.MacroArmDirection.NORTH:
			return Vector2i(-coords.y, coords.x)
		GameEnums.MacroArmDirection.EAST:
			return Vector2i(coords.x, coords.y)
		GameEnums.MacroArmDirection.SOUTH:
			return Vector2i(coords.y, coords.x)
		GameEnums.MacroArmDirection.WEST:
			return Vector2i(-coords.x, coords.y)
	return Vector2i(-999999, 0)

func _apply_central_hub(coords: Vector2i, hex: MacroHexData) -> void:
	hex.biome = GameEnums.GridBiome.PLAINS
	hex.terrain_tile = GameEnums.MacroTerrainTile.PLAINS_GRASS
	hex.flora_layer = GameEnums.MacroFloraLayer.NONE
	hex.rock_layer = GameEnums.MacroRockLayer.NONE
	hex.structure_layer = GameEnums.MacroStructureLayer.STRUCTURES
	hex.is_poi = true
	if coords == Vector2i.ZERO:
		hex.poi_id = "alpha_central_hub"
		hex.poi_name = "Alpha Hub"
	else:
		hex.poi_id = "alpha_hub_district"
		hex.poi_name = "Alpha Hub District"
	hex.hazard_level = 0.0

func _generate_procedural_layers(coords: Vector2i, hex: MacroHexData) -> void:
	var elevation: float = elevation_noise.get_noise_2dv(coords)
	var moisture: float = moisture_noise.get_noise_2dv(coords)
	var distance := _hex_distance(Vector2i.ZERO, coords)

	hex.biome = GameEnums.GridBiome.PLAINS
	hex.terrain_tile = GameEnums.MacroTerrainTile.PLAINS_GRASS
	hex.flora_layer = GameEnums.MacroFloraLayer.NONE
	hex.rock_layer = GameEnums.MacroRockLayer.NONE
	hex.structure_layer = GameEnums.MacroStructureLayer.NONE

	if elevation > 0.65:
		hex.rock_layer = GameEnums.MacroRockLayer.ROCKS
		hex.flora_layer = GameEnums.MacroFloraLayer.NONE
	elif elevation > 0.40:
		hex.rock_layer = GameEnums.MacroRockLayer.HILLS

	if hex.rock_layer != GameEnums.MacroRockLayer.ROCKS:
		if elevation < -0.35 or moisture < -0.35:
			hex.terrain_tile = GameEnums.MacroTerrainTile.MUD_YELLOW
			hex.flora_layer = GameEnums.MacroFloraLayer.NONE
		elif moisture > 0.35:
			hex.terrain_tile = GameEnums.MacroTerrainTile.FOREST_SPARSE
			hex.flora_layer = GameEnums.MacroFloraLayer.TREES
		else:
			hex.terrain_tile = GameEnums.MacroTerrainTile.PLAINS_GRASS
			hex.flora_layer = GameEnums.MacroFloraLayer.NONE

	if distance >= snow_transition_distance:
		hex.terrain_tile = GameEnums.MacroTerrainTile.SNOW_TRANSITION
		hex.flora_layer = GameEnums.MacroFloraLayer.NONE

	_apply_shrub_variation(coords, hex)

	_apply_structural_noise(coords, hex)

func _apply_shrub_variation(coords: Vector2i, hex: MacroHexData) -> void:
	if (
		hex.region == GameEnums.MacroRegion.CENTRAL_HUB
		or hex.terrain_tile != GameEnums.MacroTerrainTile.PLAINS_GRASS
		or hex.flora_layer != GameEnums.MacroFloraLayer.NONE
	):
		return
	var chance := shrub_spawn_chance
	if hex.region == GameEnums.MacroRegion.HUB_BORDER:
		chance *= 0.65
	elif hex.region == GameEnums.MacroRegion.ARM_STAGE_1:
		chance *= 1.15
	var rng := RandomNumberGenerator.new()
	rng.seed = (master_seed + ":shrub:" + str(coords)).hash()
	if rng.randf() < chance:
		hex.flora_layer = GameEnums.MacroFloraLayer.SHRUBS

func _apply_region_hazard(coords: Vector2i, hex: MacroHexData) -> void:
	var distance := _hex_distance(Vector2i.ZERO, coords)
	match hex.region:
		GameEnums.MacroRegion.CENTRAL_HUB:
			hex.hazard_level = 0.0
		GameEnums.MacroRegion.HUB_BORDER:
			hex.hazard_level = 1.0
		GameEnums.MacroRegion.ARM_STAGE_1:
			hex.hazard_level = clampf(2.0 + float(distance) * 0.08, 0.0, 12.0)
		GameEnums.MacroRegion.ARM_STAGE_2:
			hex.hazard_level = clampf(3.5 + float(distance) * 0.09, 0.0, 12.0)
		GameEnums.MacroRegion.ARM_STAGE_3:
			hex.hazard_level = clampf(5.0 + float(distance) * 0.10, 0.0, 12.0)
		_:
			hex.hazard_level = clampf(2.0 + float(distance) * 0.12, 0.0, 12.0)

func _apply_structural_noise(coords: Vector2i, hex: MacroHexData) -> void:
	if (
		hex.region == GameEnums.MacroRegion.CENTRAL_HUB
		or not hex.is_passable()
	):
		return
	var structure_chance := random_structure_chance
	var remnant_chance := random_remnant_chance
	if hex.region == GameEnums.MacroRegion.HUB_BORDER:
		structure_chance *= 0.2
		remnant_chance *= 0.2
	elif hex.region == GameEnums.MacroRegion.ARM_STAGE_1:
		structure_chance *= 0.7
		remnant_chance *= 0.7

	var rng := RandomNumberGenerator.new()
	rng.seed = (
		master_seed
		+ ":structure:"
		+ str(coords.x)
		+ ":"
		+ str(coords.y)
	).hash()
	var roll := rng.randf()
	if roll < structure_chance:
		hex.structure_layer = GameEnums.MacroStructureLayer.STRUCTURES
	elif roll < structure_chance + remnant_chance:
		hex.structure_layer = GameEnums.MacroStructureLayer.REMNANTS
	else:
		hex.structure_layer = GameEnums.MacroStructureLayer.NONE

	# Small random chance for a generic, non-unique scavenge location.
	var poi_rng := RandomNumberGenerator.new()
	poi_rng.seed = (
		master_seed
		+ ":poi:"
		+ str(coords.x)
		+ ":"
		+ str(coords.y)
	).hash()
	if (
		hex.region != GameEnums.MacroRegion.HUB_BORDER
		and poi_rng.randf() > 0.99
	):
		hex.is_poi = true
		hex.poi_id = "generic_ruins"
		hex.poi_name = "Collapsing Scavenger Shack"
		hex.structure_layer = GameEnums.MacroStructureLayer.STRUCTURES

func _hex_distance(from_coords: Vector2i, to_coords: Vector2i) -> int:
	var delta := to_coords - from_coords
	return maxi(abs(delta.x), maxi(abs(delta.y), abs(delta.x + delta.y)))
