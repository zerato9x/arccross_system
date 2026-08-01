extends SceneTree

const DIRECTIONS := [
	Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1),
	Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1),
]


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var generator := CombatArenaGenerator.new()
	var encounter := _make_encounter()
	var first := generator.generate(encounter)
	var second := generator.generate(
		CombatEncounterRecord.from_dict(encounter.to_dict())
	)
	if not first.is_valid() or first.sectors.size() != 35:
		return _fail("Arena is not a valid fixed 7x5 sector set.")
	if first.to_dict() != second.to_dict():
		return _fail("Identical encounter records produced different baselines.")
	if first.sector_at(Vector2i(3, 2)) == null:
		return _fail("The unique center sector is missing.")
	if not _verify_all_approach_rotations(generator):
		return
	if not _verify_persistent_mutation(generator, encounter):
		return
	if not await _verify_base_twelve_movement(encounter):
		return
	print("[COMBAT_ARENA_OVERHAUL] PASS")
	quit(0)


func _make_encounter() -> CombatEncounterRecord:
	var encounter := CombatEncounterRecord.new()
	encounter.topology_id = "squad_7x5"
	encounter.encounter_id = "combat_overhaul_smoke"
	encounter.source_coords = Vector2i(4, -2)
	encounter.approach_from = encounter.source_coords - DIRECTIONS[0]
	encounter.world_seed = "COMBAT_OVERHAUL_SMOKE"
	encounter.world_time = {"hour": 21}
	encounter.center_hex = HexRecord.new()
	encounter.center_hex.zone_id = "smoke_zone"
	encounter.center_hex.world_generation_version = 12
	encounter.center_hex.visual_variant_hash = 1207
	encounter.center_hex.terrain_tile = GameEnums.MacroTerrainTile.PLAINS_GRASS
	encounter.center_hex.road_mask = (1 << 0) | (1 << 3)
	for _direction in DIRECTIONS:
		var neighbor := HexRecord.new()
		neighbor.zone_id = "smoke_neighbor"
		encounter.neighbor_hexes.append(neighbor)
	return encounter


func _verify_all_approach_rotations(generator: CombatArenaGenerator) -> bool:
	for direction_index in range(DIRECTIONS.size()):
		var encounter := _make_encounter()
		encounter.approach_from = encounter.source_coords - DIRECTIONS[direction_index]
		var arena := generator.generate(encounter)
		if arena.orientation_step != direction_index:
			return _fail("Approach rotation %d was not preserved." % direction_index)
		var road_edges: Dictionary = {}
		for sector in arena.sectors:
			if sector.surface_id != "road":
				continue
			if sector.coords.x == 0:
				road_edges["left"] = true
			elif sector.coords.x == 6:
				road_edges["right"] = true
			elif sector.coords.y == 0:
				road_edges["top"] = true
			elif sector.coords.y == 4:
				road_edges["bottom"] = true
		if road_edges.size() != 2:
			return _fail(
				"Rotation %d exposed %d road boundaries: %s."
				% [direction_index, road_edges.size(), str(road_edges)]
			)
	return true


func _verify_persistent_mutation(
	generator: CombatArenaGenerator,
	encounter: CombatEncounterRecord
) -> bool:
	encounter.center_hex.combat_site_state = {
		"schema_version": CombatArenaState.SCHEMA_VERSION,
		"sector_patches": {
			"17": {
				"surface_id": "burned_ground",
				"blocked": true,
				"hazard_state": {"fire": 4, "expires_at": 144},
			}
		},
	}
	var arena := generator.generate(encounter)
	var center := arena.sectors[17]
	if center.surface_id != "burned_ground" or not center.blocked:
		return _fail("Persistent sector mutation was not reapplied.")
	if int(center.hazard_state.get("fire", 0)) != 4:
		return _fail("Persistent hazard state was lost.")
	return true


func _verify_base_twelve_movement(
	encounter: CombatEncounterRecord
) -> bool:
	encounter.center_hex.combat_site_state.clear()
	encounter.center_hex.road_mask = 0
	var board := CombatBoard.new()
	root.add_child(board)
	await process_frame
	board.configure_from_encounter(encounter)
	var actor := HumanoidCore.new()
	actor.kinetic_tier = GameEnums.KineticTier.FLUID
	var path: Array[int] = []
	path.append(board.arena_state.index_for(Vector2i(0, 2)))
	for x in range(1, 7):
		path.append(board.arena_state.index_for(Vector2i(x, 2)))
	if board.path_cost(path, 2) != 12:
		actor.free()
		board.queue_free()
		return _fail("Six clear fluid steps do not cost exactly 12 AP.")
	actor.free()
	board.queue_free()
	await process_frame
	return true


func _fail(message: String) -> bool:
	push_error("[COMBAT_ARENA_OVERHAUL] " + message)
	quit(1)
	return false
