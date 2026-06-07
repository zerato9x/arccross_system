extends Node
class_name HexWorldGenerator

# ---------------------------------------------------------
# THE SEED & THE NOISE
# ---------------------------------------------------------
@export var master_seed: String = "THE_NORTH_REMEMBERS"

var noise_engine: FastNoiseLite
var world_hex_cache: Dictionary = {} # Stores Vector2i -> MacroHexData
var manual_poi_overrides: Dictionary = {} # Stores Vector2i -> Dictionary (POI Data)

func _ready() -> void:
	_initialize_noise()

func _initialize_noise() -> void:
	noise_engine = FastNoiseLite.new()
	# The hash turns your string phrase into a massive, unique integer
	noise_engine.seed = master_seed.hash() 
	
	# Cellular noise creates chunky, distinct regional biomes (perfect for Hex games)
	noise_engine.noise_type = FastNoiseLite.TYPE_CELLULAR
	noise_engine.frequency = 0.05 # Lower = massive continents. Higher = scattered islands.

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
		
	# 2. It's undiscovered country. We must generate it.
	var new_hex = MacroHexData.new()
	
	# 3. Check the Narrative Override Dict. Did An manually put a camp here?
	if manual_poi_overrides.has(coords):
		var override_data = manual_poi_overrides[coords]
		new_hex.biome = override_data["biome"]
		new_hex.is_poi = true
		new_hex.poi_id = override_data["id"]
		new_hex.poi_name = override_data["name"]
		
	# 4. No override found. Roll the procedural noise engine.
	else:
		_generate_procedural_biome(coords, new_hex)
		
	# 5. Save it to the cache so it never changes, and return it.
	world_hex_cache[coords] = new_hex
	return new_hex

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
	if randf() > 0.99:
		hex.is_poi = true
		hex.poi_id = "generic_ruins"
		hex.poi_name = "Collapsing Scavenger Shack"
