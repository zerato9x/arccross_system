extends RefCounted
class_name WorldMutationRules

## Defines which hex fields persist across runs (world mutations) versus
## which reset each run (exploration fog, encounter seeds, rest state).

const PERSISTENT_FIELDS := [
	"biome",
	"terrain_tile",
	"flora_layer",
	"rock_layer",
	"structure_layer",
	"region",
	"arm_direction",
	"zone_id",
	"biome_pack",
	"landmark_id",
	"impassable",
	"terrain_sprite_path",
	"flora_sprite_path",
	"rock_sprite_path",
	"structure_sprite_path",
	"sleep_anchor",
	"sleep_gear_instance_id",
	"is_poi",
	"poi_id",
	"poi_name",
	"hazard_level",
	"search_count",
	"camp_item_states",
	"camp_traps",
	"camp_rest_count",
]


static func apply_patch(hex: MacroHexData, patch: Dictionary) -> void:
	if patch.is_empty():
		return
	for field_name in PERSISTENT_FIELDS:
		if not patch.has(field_name):
			continue
		hex.set(field_name, patch[field_name])


static func diff_from_baseline(
	baseline: MacroHexData,
	current: HexRecord
) -> Dictionary:
	var patch: Dictionary = {}
	for field_name in PERSISTENT_FIELDS:
		var baseline_value: Variant = baseline.get(field_name)
		var current_value: Variant = current.get(field_name)
		if _values_equal(baseline_value, current_value):
			continue
		patch[field_name] = current_value
	return patch


static func merge_patches(
	existing: Dictionary,
	incoming: Dictionary
) -> Dictionary:
	var merged := existing.duplicate(true)
	for key in incoming.keys():
		merged[key] = incoming[key]
	return merged


static func _values_equal(left: Variant, right: Variant) -> bool:
	if left is Array and right is Array:
		return left.duplicate(true) == right.duplicate(true)
	return left == right
