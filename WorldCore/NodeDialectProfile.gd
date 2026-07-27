extends RefCounted
class_name NodeDialectProfile

## Resolves Node Map ids → alpha dialect mix (Hex World Asset Overhaul).
## Adjacent ring (*_random_1): homestead / plains dominant.
## North spine: snow theme_weight ramps toward north_core.

const PROFILE_VERSION := 1


static func profile_for_node(node_id: String) -> Dictionary:
	var id := node_id.strip_edges()
	if id.is_empty() or id == MacroGraphGenerator.CENTRAL_ID:
		return _profile(
			"central",
			"urban",
			GameEnums.BIOME_PACK_CENTRALCORE,
			GameEnums.BIOME_PACK_CENTRALCORE,
			1.0,
			0.0
		)

	var arm := _arm_from_id(id)
	var depth := _depth_from_id(id)
	var theme_weight := _theme_weight_for_depth(depth)
	var theme_pack := _theme_pack_for_arm(arm)
	var ecology := _ecology_for_arm(arm)

	# Four nodes adjacent to Central: homestead starters (plains + Golbanc).
	if depth == 1:
		theme_weight = 0.12 if arm == "north" else 0.0
		return _profile(
			arm,
			ecology if arm == "north" else "homestead",
			theme_pack if arm == "north" else GameEnums.BIOME_PACK_PLAINS,
			GameEnums.BIOME_PACK_DEFAULT_ERA8,
			theme_weight,
			0.02,
			theme_pack if arm != "north" else ""
		)

	# Non-north arms stay plains/homestead until those packs ship.
	if arm != "north":
		return _profile(
			arm,
			"homestead",
			GameEnums.BIOME_PACK_PLAINS,
			GameEnums.BIOME_PACK_DEFAULT_ERA8,
			0.0,
			0.02,
			theme_pack
		)

	return _profile(
		"north",
		"ice",
		GameEnums.BIOME_PACK_NORTH,
		GameEnums.BIOME_PACK_DEFAULT_ERA8,
		theme_weight,
		0.04 if depth >= 3 else 0.02
	)


static func pick_terrain_pack(profile: Dictionary, roll: float) -> String:
	var theme_weight := float(profile.get("theme_weight", 0.0))
	var theme_pack := str(profile.get("theme_pool", GameEnums.BIOME_PACK_PLAINS))
	if roll < theme_weight:
		return theme_pack
	# Homestead / plains under snow: use plains terrain until snow wins the roll.
	if theme_pack == GameEnums.BIOME_PACK_NORTH:
		return GameEnums.BIOME_PACK_PLAINS
	return theme_pack if theme_weight >= 1.0 else GameEnums.BIOME_PACK_PLAINS


static func pick_structure_pack(profile: Dictionary, roll: float) -> String:
	## Structures stay Golbanc/default longer than terrain (sheds in snow).
	var theme_weight := float(profile.get("theme_weight", 0.0)) * 0.45
	var theme_pack := str(profile.get("theme_pool", GameEnums.BIOME_PACK_PLAINS))
	var default_pack := str(
		profile.get("default_pool", GameEnums.BIOME_PACK_DEFAULT_ERA8)
	)
	if roll < theme_weight and theme_pack == GameEnums.BIOME_PACK_NORTH:
		return GameEnums.BIOME_PACK_NORTH
	return default_pack


static func _profile(
	arm: String,
	ecology: String,
	theme_pool: String,
	default_pool: String,
	theme_weight: float,
	glitch_rate: float,
	future_theme_pool: String = ""
) -> Dictionary:
	var profile := {
		"arm": arm,
		"ecology": ecology,
		"theme_pool": theme_pool,
		"default_pool": default_pool,
		"theme_weight": clampf(theme_weight, 0.0, 1.0),
		"glitch_rate": clampf(glitch_rate, 0.0, 1.0),
		"version": PROFILE_VERSION,
	}
	if not future_theme_pool.is_empty():
		profile["future_theme_pool"] = future_theme_pool
	return profile


static func _arm_from_id(node_id: String) -> String:
	for prefix in MacroGraphGenerator.ARM_PREFIXES:
		if node_id.begins_with(prefix + "_"):
			return prefix
	return "central"


static func _depth_from_id(node_id: String) -> int:
	if node_id.ends_with("_core") and not node_id.begins_with("central"):
		return 5
	if node_id.ends_with("_gateway"):
		return 4
	if "_random_1" in node_id:
		return 1
	if "_random_2" in node_id:
		return 2
	if "_random_3" in node_id:
		return 3
	return 0


static func _theme_weight_for_depth(depth: int) -> float:
	match depth:
		1:
			return 0.12
		2:
			return 0.40
		3:
			return 0.58
		4:
			return 0.78
		5:
			return 0.92
		_:
			return 0.0


static func _theme_pack_for_arm(arm: String) -> String:
	match arm:
		"north":
			return GameEnums.BIOME_PACK_NORTH
		"central":
			return GameEnums.BIOME_PACK_CENTRALCORE
		"east":
			return GameEnums.BIOME_PACK_EAST
		"south":
			return GameEnums.BIOME_PACK_SOUTH
		"west":
			return GameEnums.BIOME_PACK_WEST_BASIN
		_:
			return GameEnums.BIOME_PACK_PLAINS


static func _ecology_for_arm(arm: String) -> String:
	match arm:
		"north":
			return "ice"
		"central":
			return "urban"
		"east":
			return "wet_lowland"
		"south":
			return "coastal"
		"west":
			return "desert"
		_:
			return "homestead"
