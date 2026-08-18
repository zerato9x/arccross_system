extends RefCounted
class_name MacroPersistenceBridge

## Macro application adapter. Persistence authorities remain RuntimeStateStore
## and MetaProgressionStore; this bridge only assembles their neutral inputs.

func synchronize(
	world_state: RuntimeStateStore,
	_player_record: Dictionary,
	_player_coords: Vector2i,
	_world_hex_cache: Dictionary,
	campaign: MacroProgressController,
	meta_progress: Node
) -> void:
	if world_state == null:
		return
	if campaign == null or campaign.graph == null:
		return
	if not world_state.set_campaign_state(
		campaign.graph.to_dict(),
		campaign.active_node_id,
		int(campaign.last_arrival_direction)
	):
		return
	world_state.capture_node_runtime(campaign.active_node_id)
	var active_node := campaign.get_active_node()
	if (
		active_node != null
		and active_node.persistence == GameEnums.MacroNodePersistence.PERMANENT_META
		and meta_progress != null
		and meta_progress.has_method("capture_node_mutations")
	):
		var hex_snapshot_records: Dictionary = {}
		for coords_value in world_state.get_hex_coordinates():
			if not coords_value is Vector2i:
				continue
			var coords: Vector2i = coords_value
			var hex_snapshot := world_state.get_hex_snapshot(coords)
			if not hex_snapshot.is_empty():
				hex_snapshot_records[coords] = HexRecord.from_dict(hex_snapshot)
		meta_progress.capture_node_mutations(
			active_node.id,
			campaign.zone_generator.permanent_baseline_records,
			hex_snapshot_records
		)


func flush_world_mutations(
	mutation_store: Node,
	world_state: RuntimeStateStore,
	campaign: MacroProgressController,
	world_generator: HexWorldGenerator
) -> void:
	if campaign != null and not campaign.active_node_id.is_empty():
		# Directional node worlds use node-scoped Meta patches. The legacy
		# coordinate-only store must never receive these overlapping coordinates.
		return
	if mutation_store == null or world_generator == null:
		return
	if world_generator.authored_map == null:
		return
	if not mutation_store.has_method("capture_run_mutations"):
		return
	mutation_store.capture_run_mutations(
		world_generator.authored_map.map_id,
		_build_mutation_baseline_records(world_state, world_generator),
		world_state.get_hex_records_snapshot()
	)


func _build_mutation_baseline_records(
	world_state: RuntimeStateStore,
	world_generator: HexWorldGenerator
) -> Dictionary:
	var baseline_records: Dictionary = {}
	for coords in world_state.get_hex_coordinates():
		if not coords is Vector2i:
			continue
		var baseline_hex: MacroHexData
		if world_generator.authored_map.has_hex(coords):
			baseline_hex = world_generator.authored_map.build_hex_data(
				coords,
				world_state.world_seed
			)
		else:
			baseline_hex = HexWorldGenerator.build_void_hex(coords)
		baseline_records[coords] = baseline_hex.to_state()
	return baseline_records
