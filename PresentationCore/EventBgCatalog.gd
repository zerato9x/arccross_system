extends RefCounted
class_name EventBgCatalog

## HexTiles ground plates for exploration / event / collision scenes.
## Parallax Event_bg packs are main-menu only (see MenuParallaxCatalog).

const PLAINS_BG := "res://Asset/HexTiles/_BIOMES/biome_plains/bg_plains.png"
const MUD_BG := "res://Asset/HexTiles/_BIOMES/biome_plains/mud.png"
const NORTH_ROUTE_1_SETTLEMENT_BG := (
	"res://Asset/EventBackgrounds/North/north_route_1_fringe_settlement.png"
)

static func resolve_background(hex_data: MacroHexData) -> String:
	if (
		hex_data.poi_id == "starter_settlement"
		and hex_data.arm_direction == GameEnums.MacroArmDirection.NORTH
		and ResourceLoader.exists(NORTH_ROUTE_1_SETTLEMENT_BG)
	):
		return NORTH_ROUTE_1_SETTLEMENT_BG
	if hex_data.terrain_tile == GameEnums.MacroTerrainTile.MUD_YELLOW:
		if ResourceLoader.exists(MUD_BG):
			return MUD_BG
	if ResourceLoader.exists(PLAINS_BG):
		return PLAINS_BG
	if ResourceLoader.exists(MUD_BG):
		return MUD_BG
	return ""


static func resolve_dialogue_background(
	dialogue_id: String,
	hex_data: MacroHexData
) -> String:
	if (
		dialogue_id == "starter_wayfinder:north"
		and ResourceLoader.exists(NORTH_ROUTE_1_SETTLEMENT_BG)
	):
		return NORTH_ROUTE_1_SETTLEMENT_BG
	return resolve_background(hex_data)

static func build_scene_descriptor(
	hex_data: MacroHexData,
	world_seed: String,
	coords: Vector2i
) -> Dictionary:
	return {
		"background_path": resolve_background(hex_data),
		"props": PoiVisualCatalog.build_prop_descriptors(hex_data, world_seed, coords),
		"title": hex_data.poi_name if not hex_data.poi_name.is_empty() else "Location",
		"zone_name": WorldSectorCatalog.wedge_display_name(hex_data.zone_id),
	}
