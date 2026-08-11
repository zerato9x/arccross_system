extends RefCounted
class_name MacroCombatEncounterService

## Builds the neutral macro-to-tactical encounter handoff.
## Runtime state remains authoritative in RuntimeStateStore; this service only
## snapshots the source hex, local context, and presentation descriptor.

var world_state: RuntimeStateStore
var world_generator: HexWorldGenerator
var map_visualizer: HexMapVisualizer


func configure(
	state: RuntimeStateStore,
	generator: HexWorldGenerator,
	visualizer: HexMapVisualizer
) -> void:
	world_state = state
	world_generator = generator
	map_visualizer = visualizer


func build(request: Dictionary) -> CombatEncounterRecord:
	if world_state == null or world_generator == null:
		return null
	var coords: Vector2i = request.get("coords", Vector2i.ZERO)
	if not world_generator.is_in_zone_bounds(coords):
		return null
	var center := world_generator.get_hex_at(coords)
	if center == null:
		return null
	var encounter := CombatEncounterRecord.new()
	encounter.encounter_id = "%s:%s:%d" % [
		str(world_state.world_seed),
		str(coords),
		int(world_state.world_time_minutes),
	]
	encounter.source_coords = coords
	encounter.approach_from = request.get("approach_from", coords)
	encounter.initiator_id = str(request.get("initiator_id", "player"))
	encounter.context = int(
		request.get("context", GameEnums.EncounterContext.NEUTRAL_MEET)
	)
	encounter.ambush_position = int(
		request.get("ambush_position", GameEnums.AmbushPosition.STANDARD)
	)
	encounter.world_seed = str(world_state.world_seed)
	encounter.world_time = world_state.get_world_time_snapshot()
	encounter.center_hex = center.to_state()
	for direction in HexCoordUtils.AXIAL_DIRECTIONS:
		var neighbor_coords: Vector2i = coords + direction
		var neighbor_record: HexRecord = null
		if world_generator.is_in_zone_bounds(neighbor_coords):
			neighbor_record = world_generator.get_hex_at(neighbor_coords).to_state()
		encounter.neighbor_hexes.append(neighbor_record)
	for trap in center.camp_traps:
		if not trap is Dictionary:
			continue
		var trap_record: Dictionary = trap.duplicate(true)
		trap_record["id"] = str(trap.get("item_id", "trap_makeshift"))
		trap_record["instance_id"] = str(trap.get("instance_id", ""))
		trap_record["armed"] = true
		trap_record["damage"] = float(trap.get("trap_damage", 2.5))
		trap_record["owner_side"] = "player"
		var combat_topology := CombatTopologyCatalog.load_profile(encounter.topology_id)
		trap_record["sector"] = Vector2i(
			clampi(int(trap.get("sector_x", 1)), 0, combat_topology.columns - 1),
			clampi(int(trap.get("sector_y", 0)), 0, combat_topology.rows - 1)
		)
		encounter.traps.append(trap_record)
	var encounter_ground_items: Array[Dictionary] = []
	for ground_item in world_state.get_ground_items(coords):
		if ground_item is Dictionary:
			encounter_ground_items.append(ground_item.duplicate(true))
	encounter.ground_items = encounter_ground_items
	var decorations: Array = []
	if world_generator.has_method("get_decorations_at"):
		decorations = world_generator.get_decorations_at(coords)
	var catalog: MacroTileCatalog = map_visualizer.tile_catalog if map_visualizer else null
	encounter.presentation = HexPresentationDescriptor.build(
		center,
		catalog,
		decorations,
		encounter.world_seed,
		coords,
		{},
		encounter.ground_items
	)
	return encounter
