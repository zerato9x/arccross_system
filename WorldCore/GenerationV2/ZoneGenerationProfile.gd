extends Resource
class_name ZoneGenerationProfile

@export var profile_id: String = "starter_node_v2"
@export var world_generation_version: int = 2
@export var climate_id: String = "central_fringe"
@export var terrain_family_ids: PackedStringArray = ["plains_green"]
@export var required_stamp_ids: PackedStringArray = ["starter_settlement_v2"]
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
	profile.profile_id = "starter_node_%s_v2" % arm_key
	profile.climate_id = "north_cold_fringe" if arm_key == "north" else "central_fringe"
	if not include_settlement:
		profile.required_stamp_ids = PackedStringArray()
		profile.simulated_resident_count = 0
	return profile
