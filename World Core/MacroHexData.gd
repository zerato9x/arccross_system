extends Resource
class_name MacroHexData

# Pulled straight from our GameEnums[cite: 1]
@export var biome: GameEnums.GridBiome = GameEnums.GridBiome.PLAINS

# POI Variables
@export var is_poi: bool = false
@export var poi_id: String = ""
@export var poi_name: String = ""

# Fog of War / Exploration
@export var is_explored: bool = false
@export var hazard_level: float = 0.0 # High values equal intense Red Mist zones
