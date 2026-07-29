extends SceneTree

## Smoke: Phase C dialect mix — North snow ramp + homestead structure packs.

const SEED := "HEX_ZONE_DIALECT_SMOKE"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var zone_r1 := _generate_zone("north_random_1")
	var zone_core := _generate_zone("north_core")
	var snow_r1 := _count_snow(zone_r1)
	var snow_core := _count_snow(zone_core)
	if snow_r1 != 0:
		_fail(
			"north_random_1 is Central's cold fringe and must have zero snow terrain (got %d)."
			% snow_r1
		)
		return

	if snow_core <= snow_r1:
		_fail(
			"north_core must have more SNOW_TRANSITION hexes than north_random_1 (core=%d, r1=%d)."
			% [snow_core, snow_r1]
		)
		return

	var zone_r1_b := _generate_zone("north_random_1")
	var snow_r1_b := _count_snow(zone_r1_b)
	if snow_r1_b != snow_r1:
		_fail(
			"Same seed must yield same snow count (got %d then %d)."
			% [snow_r1, snow_r1_b]
		)
		return

	if not _assert_homestead_structure_packs(zone_r1):
		return
	if not _assert_homestead_structure_packs(zone_core):
		return

	var east := NodeDialectProfile.profile_for_node("east_random_2")
	if str(east.get("future_theme_pool", "")) != GameEnums.BIOME_PACK_EAST:
		_fail("east stub profile must expose future_theme_pool=east.")
		return
	if str(east.get("theme_pool", "")) != GameEnums.BIOME_PACK_PLAINS:
		_fail("east stub terrain must remain plains until pack ships.")
		return

	print(
		"[MacroZoneDialectSmoke] OK snow_r1=%d snow_core=%d"
		% [snow_r1, snow_core]
	)
	quit(0)


func _generate_zone(node_id: String) -> MacroZoneGenerator:
	var zone := MacroZoneGenerator.new()
	zone.configure_seed(SEED)
	zone.generate_zone(
		node_id,
		GameEnums.MacroZoneKind.BIOME_RNG,
		GameEnums.GridBiome.PLAINS
	)
	return zone


func _count_snow(zone: MacroZoneGenerator) -> int:
	var count := 0
	for coords in zone.world_hex_cache.keys():
		var hex: MacroHexData = zone.world_hex_cache[coords]
		if hex.terrain_tile == GameEnums.MacroTerrainTile.SNOW_TRANSITION:
			count += 1
	return count


func _assert_homestead_structure_packs(zone: MacroZoneGenerator) -> bool:
	var checked := 0
	for coords in zone.world_hex_cache.keys():
		var hex: MacroHexData = zone.world_hex_cache[coords]
		if hex.structure_layer == GameEnums.MacroStructureLayer.NONE:
			continue
		var path := hex.structure_sprite_path
		if path.is_empty():
			continue
		if "default_era8" in path or "Homestead" in path:
			checked += 1
			if hex.structure_pack != GameEnums.BIOME_PACK_DEFAULT_ERA8:
				return _fail(
					"Homestead structure at %s must use structure_pack=default_era8 (got %s, path=%s)."
					% [str(coords), hex.structure_pack, path]
				)
		elif "biome_plains/remnants" in path:
			checked += 1
			if hex.structure_pack != GameEnums.BIOME_PACK_DEFAULT_ERA8:
				return _fail(
					"Remnant at %s must use structure_pack=default_era8 (got %s)."
					% [str(coords), hex.structure_pack]
				)
	if checked == 0:
		return _fail("Expected at least one homestead/remnant structure path to validate.")
	return true


func _fail(message: String) -> bool:
	push_error("[MacroZoneDialectSmoke] " + message)
	quit(1)
	return false
