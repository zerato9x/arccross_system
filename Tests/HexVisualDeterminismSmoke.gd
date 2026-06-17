extends SceneTree

const SAMPLE_COORDS := [
	Vector2i(0, 0),
	Vector2i(12, -4),
	Vector2i(-8, 15),
	Vector2i(33, 21),
]

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var world_state := RuntimeStateStore.new()
	world_state.name = "WorldState"
	root.add_child(world_state)

	var generator := HexWorldGenerator.new()
	generator.master_seed = "DETERMINISM_SMOKE"
	generator.configure_seed(generator.master_seed)
	root.add_child(generator)
	await process_frame

	for coords in SAMPLE_COORDS:
		var first := generator.get_hex_at(coords)
		var second := generator.get_hex_at(coords)
		if first.visual_variant_hash != second.visual_variant_hash:
			_fail(
				"visual_variant_hash changed for "
				+ str(coords)
				+ " on repeated get_hex_at calls."
			)
			return
		if first.biome != second.biome:
			_fail("Biome changed for " + str(coords) + " on repeated calls.")
			return
		if first.visual_variant_hash == 0:
			_fail("visual_variant_hash was not assigned for " + str(coords) + ".")
			return

	generator.world_hex_cache.clear()
	generator.configure_seed("DETERMINISM_SMOKE")
	for coords in SAMPLE_COORDS:
		var expected_hash := HexWorldGenerator.compute_visual_variant_hash(
			coords,
			"DETERMINISM_SMOKE"
		)
		var regenerated := generator.get_hex_at(coords)
		if regenerated.visual_variant_hash != expected_hash:
			_fail(
				"visual_variant_hash drifted after cache clear for "
				+ str(coords)
				+ "."
			)
			return

	print("[TEST PASS] Hex visual variant generation is deterministic.")
	quit(0)

func _fail(message: String) -> void:
	push_error("[TEST FAIL] " + message)
	quit(1)
