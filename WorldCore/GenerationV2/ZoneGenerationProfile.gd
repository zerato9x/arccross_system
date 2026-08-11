extends Resource
class_name ZoneGenerationProfile

@export var profile_id: String = "starter_node_v3"
@export var world_generation_version: int = 3
@export var climate_id: String = "central_fringe"
@export var terrain_family_ids: PackedStringArray = ["plains_green"]
## Exact stable terrain IDs used by this profile's materialization pass. The
## profile owns the palette; the generator only performs deterministic shuffling.
@export var terrain_asset_ids: PackedStringArray = PackedStringArray()
@export var required_stamp_ids: PackedStringArray = []
@export var road_required: bool = true
@export_range(0, 32) var rubble_search_min: int = 6
@export_range(0, 32) var rubble_search_max: int = 10
@export_range(0, 64) var visual_rubble_min: int = 12
@export_range(0, 64) var visual_rubble_max: int = 20
@export_range(0.0, 1.0) var quiet_ratio_min: float = 0.60
@export var loot_tier_id: String = "starter_poor"
@export var allowed_faction_ids: PackedStringArray = []
@export var simulated_resident_count: int = 1


static func starter_node(arm_key: String, include_settlement: bool = false) -> ZoneGenerationProfile:
	var profile := ZoneGenerationProfile.new()
	profile.profile_id = "starter_node_%s_v3" % arm_key
	profile.world_generation_version = 3
	profile.climate_id = "north_cold_fringe" if arm_key == "north" else "central_fringe"
	profile.terrain_asset_ids = _default_starter_terrain_asset_ids()
	profile.rubble_search_min = 7
	profile.rubble_search_max = 7
	if not include_settlement:
		profile.required_stamp_ids = PackedStringArray()
		profile.simulated_resident_count = 0
	return profile


static func _default_starter_terrain_asset_ids() -> PackedStringArray:
	return PackedStringArray([
		"terrain.plains.green.5", "terrain.plains.green.6", "terrain.plains.green.7",
		"terrain.plains.green.8", "terrain.plains.green.9", "terrain.plains.green.13",
		"terrain.plains.green.14", "terrain.plains.green.15", "terrain.plains.green.16",
		"terrain.plains.green.17", "terrain.plains.green.18", "terrain.plains.green.19",
		"terrain.plains.green.20", "terrain.plains.green.21", "terrain.plains.green.22",
		"terrain.plains.green.23", "terrain.plains.green.26", "terrain.plains.green.27",
		"terrain.plains.green.28", "terrain.plains.green.29", "terrain.plains.green.30",
		"terrain.plains.green.31", "terrain.plains.green.32", "terrain.plains.green.33",
		"terrain.plains.green.34", "terrain.plains.green.35", "terrain.plains.green.36",
		"terrain.plains.green.37", "terrain.plains.green.38", "terrain.plains.green.39",
		"terrain.plains.green.40", "terrain.plains.green.44", "terrain.plains.green.45",
		"terrain.plains.green.46", "terrain.plains.green.47", "terrain.plains.green.48",
		"terrain.plains.green.49", "terrain.plains.green.50", "terrain.plains.green.51",
		"terrain.plains.green.52", "terrain.plains.green.53", "terrain.plains.green.54",
		"terrain.plains.green.55", "terrain.plains.green.56", "terrain.plains.green.59",
		"terrain.plains.green.60", "terrain.plains.green.61", "terrain.plains.green.62",
		"terrain.plains.green.63", "terrain.plains.green.64", "terrain.plains.green.65",
		"terrain.plains.green.69", "terrain.plains.green.70", "terrain.plains.green.71",
	])
