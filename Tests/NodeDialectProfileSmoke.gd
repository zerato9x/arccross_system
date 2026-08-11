extends SceneTree

## Smoke: NodeDialectProfile alpha mixes for adjacent ring + North spine.


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures: PackedStringArray = PackedStringArray()

	var e1 := NodeDialectProfile.profile_for_node("east_random_1")
	if float(e1.get("theme_weight", 1.0)) > 0.0:
		failures.append("east_random_1 must be homestead (theme_weight 0).")
	if str(e1.get("default_pool", "")) != GameEnums.BIOME_PACK_DEFAULT_ERA8:
		failures.append("east_random_1 default_pool must be default_era8.")

	var n1 := NodeDialectProfile.profile_for_node("north_random_1")
	if str(n1.get("theme_pool", "")) != GameEnums.BIOME_PACK_NORTH:
		failures.append("north_random_1 theme_pool must be north.")
	if float(n1.get("theme_weight", 0.0)) > 0.2:
		failures.append("north_random_1 theme_weight must stay light.")

	var n3 := NodeDialectProfile.profile_for_node("north_random_3")
	var ng := NodeDialectProfile.profile_for_node("north_gateway")
	var nc := NodeDialectProfile.profile_for_node("north_core")
	if float(n3.get("theme_weight", 0.0)) <= float(n1.get("theme_weight", 0.0)):
		failures.append("north_random_3 must be snowier than north_random_1.")
	if float(ng.get("theme_weight", 0.0)) <= float(n3.get("theme_weight", 0.0)):
		failures.append("north_gateway must be snowier than north_random_3.")
	if float(nc.get("theme_weight", 0.0)) <= float(ng.get("theme_weight", 0.0)):
		failures.append("north_core must be snowiest.")

	var snow_pack := NodeDialectProfile.pick_terrain_pack(nc, 0.0)
	var plains_pack := NodeDialectProfile.pick_terrain_pack(nc, 0.99)
	if snow_pack != GameEnums.BIOME_PACK_NORTH:
		failures.append("north_core low roll must pick north terrain.")
	if plains_pack != GameEnums.BIOME_PACK_PLAINS:
		failures.append("north_core high roll should still allow plains under snow.")

	var north_root := "res://Asset/HexTiles/_BIOMES/biome_north/HEX/snow_tiles"
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(north_root)):
		# DirAccess.dir_exists_absolute needs OS path; also try open.
		var dir := DirAccess.open(north_root)
		if dir == null:
			failures.append("biome_north/HEX/snow_tiles missing.")

	var era8 := DirAccess.open("res://Asset/HexTiles/_BIOMES/default_era8/Structures")
	if era8 == null:
		failures.append("default_era8/Structures missing.")

	if failures.is_empty():
		print("[NodeDialectProfileSmoke] OK")
		quit(0)
		return
	for failure in failures:
		push_error("[NodeDialectProfileSmoke] " + failure)
	quit(1)
