extends RefCounted
class_name MacroZoneCompositionPlanner

const _StarterZonePlanner := preload("res://WorldCore/GenerationV2/StarterZonePlanner.gd")
const _ZoneGenerationProfile := preload("res://WorldCore/GenerationV2/ZoneGenerationProfile.gd")
const DEFAULT_PROFILE_CATALOG: ZoneGenerationProfileCatalog = preload(
	"res://WorldCore/GenerationV2/starter_zone_profiles.tres"
)

## Application-facing planner. Route and depth selection chooses a profile ID;
## StarterZonePlanner remains the algorithmic kernel for road/stamp placement.

func build_starter_plan(
	zone_seed: String,
	radius: int,
	start_coords: Vector2i,
	outward_coords: Vector2i,
	hexes: Dictionary,
	arm_key: String,
	include_settlement: bool
) -> GeneratedZonePlan:
	var profile := starter_profile_for_arm(arm_key, include_settlement)
	return _StarterZonePlanner.build_plan(
		zone_seed,
		radius,
		start_coords,
		outward_coords,
		hexes,
		profile,
		include_settlement
	)


func starter_profile_for_arm(
	arm_key: String,
	include_settlement: bool = false
) -> ZoneGenerationProfile:
	if DEFAULT_PROFILE_CATALOG != null:
		return DEFAULT_PROFILE_CATALOG.profile_for_arm(arm_key, include_settlement)
	return _ZoneGenerationProfile.starter_node(arm_key, include_settlement)


func build_starter_terrain_assignments(
	zone_seed: String,
	hexes: Dictionary,
	profile: ZoneGenerationProfile
) -> Dictionary:
	var palette: PackedStringArray = (
		profile.terrain_asset_ids
		if profile != null and not profile.terrain_asset_ids.is_empty()
		else _ZoneGenerationProfile._default_starter_terrain_asset_ids()
	)
	if palette.is_empty():
		palette = PackedStringArray(["terrain.plains.green.5"])
	var ordered_cells: Array[Vector2i] = []
	for coords in hexes.keys():
		ordered_cells.append(coords)
	ordered_cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		if a.y == b.y:
			return a.x < b.x
		return a.y < b.y
	)
	var rng := RandomNumberGenerator.new()
	rng.seed = (zone_seed + ":terrain_palette_v2").hash()
	for index in range(ordered_cells.size() - 1, 0, -1):
		var swap_index := rng.randi_range(0, index)
		var held := ordered_cells[index]
		ordered_cells[index] = ordered_cells[swap_index]
		ordered_cells[swap_index] = held
	var assignments: Dictionary = {}
	var palette_offset := rng.randi_range(0, palette.size() - 1)
	for index in range(ordered_cells.size()):
		assignments[ordered_cells[index]] = palette[(index + palette_offset) % palette.size()]
	return assignments
