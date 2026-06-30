extends RefCounted
class_name WorldRules

const DEFAULT_LOOT_PROFILE_BY_BIOME := {
	GameEnums.GridBiome.PLAINS: "loot_plains",
	GameEnums.GridBiome.FOREST: "loot_forest",
	GameEnums.GridBiome.HILLS: "loot_hills",
	GameEnums.GridBiome.MUD: "loot_mud",
	GameEnums.GridBiome.SWAMP: "loot_swamp",
}

const LOOT_PROFILE_BY_POI_ID := {
	"alpha_central_hub": "loot_alpha_hub",
	"alpha_hub_district": "loot_alpha_hub",
}

const CAMP_HAZARD_LIMIT: float = 8.0

static func get_loot_profile_id(
	biome: GameEnums.GridBiome,
	poi_id: String,
	region: GameEnums.MacroRegion = GameEnums.MacroRegion.WASTELAND
) -> String:
	if LOOT_PROFILE_BY_POI_ID.has(poi_id):
		return LOOT_PROFILE_BY_POI_ID[poi_id]
	if region == GameEnums.MacroRegion.HUB_BORDER:
		return "loot_hub_border"
	return DEFAULT_LOOT_PROFILE_BY_BIOME.get(biome, "loot_plains")

static func get_camp_access(
	has_landmark: bool,
	hazard_level: float,
	has_hostile_entity: bool
) -> Dictionary:
	if not has_landmark:
		return {
			"allowed": false,
			"reason": "A landmark location is required to establish camp.",
		}
	if has_hostile_entity:
		return {
			"allowed": false,
			"reason": "A hostile entity still controls this location.",
		}
	if hazard_level > CAMP_HAZARD_LIMIT:
		return {
			"allowed": false,
			"reason": "The location is too hazardous for sustained rest.",
		}
	return {"allowed": true, "reason": ""}
