extends Node
class_name HexWorldGenerator

# ---------------------------------------------------------
# THE SEED & THE NOISE
# ---------------------------------------------------------
@export var master_seed: String = "THE_NORTH_REMEMBERS"

var noise_engine: FastNoiseLite
var world_hex_cache: Dictionary = {} # Stores Vector2i -> MacroHexData
var manual_poi_overrides: Dictionary = {} # Stores Vector2i -> Dictionary (POI Data)

# --- SECTOR LOGIC ---
@export var sector_size: int = 10
# Registry of hand-crafted sectors. Key: Vector2i (Sector Coord), Value: Dictionary containing hex data
var handcrafted_sectors: Dictionary = {} 

var _world_state: RuntimeStateStore

func _ready() -> void:
	_world_state = get_node("/root/WorldState") as RuntimeStateStore
	_initialize_noise()

func _initialize_noise() -> void:
	noise_engine = FastNoiseLite.new()
	# The hash turns your string phrase into a massive, unique integer
	noise_engine.seed = master_seed.hash() 
	
	# Cellular noise creates chunky, distinct regional biomes (perfect for Hex games)
	noise_engine.noise_type = FastNoiseLite.TYPE_CELLULAR
	noise_engine.frequency = 0.05 # Lower = massive continents. Higher = scattered islands.

func configure_seed(seed_value: String) -> void:
	master_seed = seed_value
	world_hex_cache.clear()
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

	var persistent_state: Dictionary = _world_state.get_hex_record(coords)
	if not persistent_state.is_empty():
		var persistent_hex := MacroHexData.from_state(persistent_state)
		world_hex_cache[coords] = persistent_hex
		return persistent_hex
		
	# 2. It's undiscovered country. We must generate it.
	var new_hex = MacroHexData.new()
	
	# 3. Check the Narrative Override Dict. Did An manually put a camp here?
	if manual_poi_overrides.has(coords):
		var override_data = manual_poi_overrides[coords]
		new_hex.biome = override_data["biome"]
		new_hex.is_poi = true
		new_hex.poi_id = override_data["id"]
		new_hex.poi_name = override_data["name"]
		
	# 4. Check if it's in a Hand-Crafted Sector
	elif _is_in_handcrafted_sector(coords):
		_load_from_handcrafted_sector(coords, new_hex)
		
	# 5. No override or hand-crafted sector found. Roll the procedural noise engine.
	else:
		_generate_procedural_biome(coords, new_hex)
		
	# 6. Save it to the cache so it never changes, and return it.
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
		if data.get("is_poi", false):
			hex.is_poi = true
			hex.poi_id = data.get("poi_id", "")
			hex.poi_name = data.get("poi_name", "Unknown POI")
	else:
		# Fallback if a hex within a hand-crafted sector was left blank
		hex.biome = GameEnums.GridBiome.PLAINS

func _generate_procedural_biome(coords: Vector2i, hex: MacroHexData) -> void:
	# Get a noise value between -1.0 and 1.0 based on the hex coordinates
	var altitude: float = noise_engine.get_noise_2dv(coords)
	
	# Translate the abstract math into physical dirt
	if altitude < -0.4:
		hex.biome = GameEnums.GridBiome.SWAMP
	elif altitude < 0.0:
		hex.biome = GameEnums.GridBiome.MUD
	elif altitude < 0.4:
		hex.biome = GameEnums.GridBiome.PLAINS
	elif altitude < 0.7:
		hex.biome = GameEnums.GridBiome.FOREST
	else:
		hex.biome = GameEnums.GridBiome.HILLS
		
	# Small random chance for a generic, non-unique scavenge location
	var poi_rng := RandomNumberGenerator.new()
	poi_rng.seed = (
		master_seed
		+ ":poi:"
		+ str(coords.x)
		+ ":"
		+ str(coords.y)
	).hash()
	if poi_rng.randf() > 0.99:
		hex.is_poi = true
		hex.poi_id = "generic_ruins"
		hex.poi_name = "Collapsing Scavenger Shack"
