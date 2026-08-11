extends RefCounted
class_name MacroNpcRuntimeService

## World-time NPC/evidence simulation. It mutates only through the neutral
## RuntimeStateStore patch APIs; token projection stays in MacroGameManager.

const _NpcSimulator := preload("res://WorldCore/MacroNpcSimulator.gd")
const _NpcBehaviorState := preload("res://SystemCore/NpcBehaviorState.gd")

func advance(
	world_state: RuntimeStateStore,
	current_minutes: int,
	elapsed_minutes: int
) -> void:
	if world_state == null or elapsed_minutes <= 0:
		return
	for snapshot_value in world_state.get_all_entity_snapshots():
		if not snapshot_value is Dictionary:
			continue
		var snapshot: Dictionary = snapshot_value
		if int(snapshot.get("life_state", GameEnums.EntityLifeState.DEAD)) != GameEnums.EntityLifeState.ALIVE:
			continue
		_advance_snapshot(world_state, snapshot, current_minutes, elapsed_minutes)
	_decay_hex_evidence(world_state, current_minutes)


func reconcile_dormant(world_state: RuntimeStateStore, current_minutes: int) -> void:
	if world_state == null:
		return
	for snapshot_value in world_state.get_all_entity_snapshots():
		if not snapshot_value is Dictionary:
			continue
		var snapshot: Dictionary = snapshot_value
		if int(snapshot.get("life_state", GameEnums.EntityLifeState.DEAD)) != GameEnums.EntityLifeState.ALIVE:
			continue
		var elapsed := maxi(
			0,
			current_minutes - int(snapshot.get("last_simulated_minute", 0))
		)
		if elapsed > 0:
			_advance_snapshot(world_state, snapshot, current_minutes, elapsed)


func refresh_encounters(
	world_state: RuntimeStateStore,
	world_generator: HexWorldGenerator,
	mob_spawner: MobSpawner,
	center_coords: Vector2i,
	generation_radius: int,
	max_new_encounters: int,
	safe_start_radius: int,
	base_spawn_chance: float,
	fog_gated_spawning: bool,
	is_hex_visible: Callable,
	get_hex_at: Callable,
	initialize_npc_runtime: Callable,
	log_spawn: Callable = Callable()
) -> void:
	if world_state == null or world_generator == null or mob_spawner == null:
		return
	for outcome in _NpcSimulator.plan_encounter_refresh(
		center_coords,
		world_state.world_seed,
		generation_radius,
		max_new_encounters,
		safe_start_radius,
		base_spawn_chance,
		fog_gated_spawning,
		is_hex_visible,
		get_hex_at,
	):
		var coords: Vector2i = outcome.get("coords", Vector2i.ZERO)
		var hex_data := world_generator.get_hex_at(coords)
		if bool(outcome.get("mark_evaluated", false)):
			hex_data.encounter_evaluated = true
		var spawn: Variant = outcome.get("spawn")
		if spawn is Dictionary and not spawn.is_empty():
			var spawn_info: Dictionary = spawn
			var faction: GameEnums.Faction = spawn_info.get(
				"faction",
				GameEnums.Faction.SCAVENGER_CELL
			)
			var record := mob_spawner.generate_mob_record(
				coords,
				faction,
				int(spawn_info.get("difficulty", 0)),
				str(spawn_info.get("deterministic_key", "")),
			)
			if initialize_npc_runtime.is_valid():
				initialize_npc_runtime.call(record)
			var entity_id := world_state.register_entity(record)
			hex_data.encounter_entity_id = entity_id
			if log_spawn.is_valid():
				log_spawn.call(
					entity_id,
					faction,
					coords,
					float(spawn_info.get("spawn_chance", 0.0)),
				)
		world_state.set_hex_record(coords, hex_data.to_state())


func collect_ground_items(
	world_state: RuntimeStateStore,
	record: EntityRecord,
	build_pickup_receipt: Callable,
	commit_receipt: Callable
) -> void:
	if world_state == null or record == null:
		return
	if record.life_state != GameEnums.EntityLifeState.ALIVE:
		return
	for item_state_value in world_state.get_ground_items(record.coords):
		if not item_state_value is Dictionary:
			continue
		var item_state: Dictionary = item_state_value
		# Ground items are ordinary world resources. Ownership and knowledge
		# determine who can take them; quest identity is not hard-coded here.
		var instance_id := str(item_state.get("instance_id", ""))
		var taken := world_state.take_ground_item(record.coords, instance_id)
		if taken.is_empty():
			continue
		if not world_state.transfer_item_to_entity(record.entity_id, taken):
			world_state.add_ground_items(record.coords, [taken])
			continue
		var latest_snapshot := world_state.get_entity_snapshot(record.entity_id)
		if latest_snapshot.is_empty():
			continue
		record = EntityRecord.from_dict(latest_snapshot)
		var pickup_receipt: WorldActionReceipt = (
			build_pickup_receipt.call(record, instance_id)
			if build_pickup_receipt.is_valid()
			else null
		)
		if commit_receipt.is_valid():
			commit_receipt.call(
				pickup_receipt,
				record.coords,
				null,
				record.entity_id,
			)
		latest_snapshot = world_state.get_entity_snapshot(record.entity_id)
		if not latest_snapshot.is_empty():
			record = EntityRecord.from_dict(latest_snapshot)
		record.runtime["macro_purpose_label"] = "Carrying salvage"
		world_state.patch_entity_record(record.entity_id, {
			"runtime": record.runtime,
			"revision": int(latest_snapshot.get("revision", record.revision)) + 1,
			"last_simulated_minute": record.last_simulated_minute,
		})
		break


func initialize_runtime(
	world_state: RuntimeStateStore,
	record: EntityRecord,
	macro_turn_index: int,
	player_coords: Vector2i,
	materialize_loadout: Callable,
	get_hex_at: Callable,
	has_ground_items: Callable
) -> void:
	if world_state == null or record == null:
		return
	if materialize_loadout.is_valid():
		materialize_loadout.call(record)
	record.runtime = _NpcBehaviorState.ensure_runtime(record.runtime, record.definition)
	if not record.runtime.has("biology"):
		record.runtime["biology"] = {
			"hunger": 12.0,
			"thirst": 12.0,
			"fatigue": 0.0,
			"temperature": 15.0,
			"wounds": 0.0,
		}
	if record.last_simulated_minute <= 0:
		record.last_simulated_minute = world_state.world_time_minutes
	if not record.runtime.has("trade"):
		var role_id := str(record.runtime.get(
			"npc_role_id",
			record.definition.get("npc_role_id", "")
		))
		var wants: Array = ["consumable", "material"]
		if role_id in ["raider", "patrol"]:
			wants = ["ammunition", "consumable", "tool"]
		elif role_id == "stalker":
			wants = ["consumable", "ammunition"]
		elif role_id in ["technician", "resident"]:
			wants = ["material", "tool", "consumable"]
		record.runtime["trade"] = {
			"wants": wants,
			"value_tolerance": 1.35,
			"disposition": 0.0,
		}
	_NpcSimulator.initialize_npc_runtime(
		record,
		world_state.world_seed,
		macro_turn_index,
		player_coords,
		get_hex_at,
		has_ground_items,
		world_state.world_time_minutes,
	)


func _advance_snapshot(
	world_state: RuntimeStateStore,
	snapshot: Dictionary,
	current_minutes: int,
	elapsed_minutes: int
) -> void:
	var snapshot_runtime: Dictionary = snapshot.get("runtime", {}).duplicate(true)
	var biology: Dictionary = snapshot_runtime.get("biology", {
		"hunger": 12.0,
		"thirst": 12.0,
		"fatigue": 0.0,
		"temperature": 15.0,
		"wounds": 0.0,
	}).duplicate(true)
	biology["hunger"] = maxf(
		0.0,
		float(biology.get("hunger", 12.0)) - elapsed_minutes * 0.018
	)
	biology["thirst"] = maxf(
		0.0,
		float(biology.get("thirst", 12.0)) - elapsed_minutes * 0.028
	)
	biology["fatigue"] = minf(
		12.0,
		float(biology.get("fatigue", 0.0)) + elapsed_minutes * 0.012
	)
	snapshot_runtime["biology"] = biology
	var behavior_state: Resource = _NpcBehaviorState.from_runtime(
		snapshot_runtime,
		snapshot.get("definition", {})
	)
	# Survival pressure is the cross-mode AI meter. The legacy biology payload
	# remains available for old saves and non-AI presentation, but is not a
	# second decision authority.
	behavior_state.survival_pressure = clampf(
		behavior_state.survival_pressure + float(elapsed_minutes) * 0.02,
		0.0,
		GameEnums.SCALE_MAX
	)
	snapshot_runtime[_NpcBehaviorState.RUNTIME_KEY] = behavior_state.to_dict()
	var revision := int(snapshot.get("revision", 0)) + 1
	world_state.patch_entity_record(str(snapshot.get("entity_id", "")), {
		"runtime": snapshot_runtime,
		"revision": revision,
		"last_simulated_minute": current_minutes,
	})


func _decay_hex_evidence(
	world_state: RuntimeStateStore,
	current_minutes: int
) -> void:
	for coords_value in world_state.get_hex_coordinates():
		if not coords_value is Vector2i:
			continue
		var coords: Vector2i = coords_value
		var hex_snapshot := world_state.get_hex_snapshot(coords)
		if hex_snapshot.is_empty():
			continue
		var active_signals: Array[Dictionary] = []
		for signal_value in hex_snapshot.get("world_signals", []):
			if not signal_value is Dictionary:
				continue
			var expires := int(signal_value.get("expires_minute", -1))
			if expires < 0 or expires > current_minutes:
				active_signals.append(signal_value.duplicate(true))
		var active_traces: Array[Dictionary] = []
		for trace_value in hex_snapshot.get("trace_records", []):
			if not trace_value is Dictionary:
				continue
			var trace_expires := int(trace_value.get("expires_minute", -1))
			if trace_expires < 0 or trace_expires > current_minutes:
				var trace: Dictionary = (trace_value as Dictionary).duplicate(true)
				trace["age_minutes"] = maxi(
					0,
					current_minutes - int(trace.get("created_minute", current_minutes))
				)
				active_traces.append(trace)
		hex_snapshot["trace_records"] = active_traces
		hex_snapshot["world_signals"] = active_signals
		hex_snapshot["last_simulated_minute"] = current_minutes
		world_state.set_hex_record(coords, hex_snapshot)
