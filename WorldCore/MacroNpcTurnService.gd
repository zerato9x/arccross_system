extends RefCounted
class_name MacroNpcTurnService

## Neutral NPC macro-turn application. Planning operates on copied records and
## commits through RuntimeStateStore snapshots/callbacks; token presentation
## and collision UI remain outside this service.

const _NpcSimulator := preload("res://WorldCore/MacroNpcSimulator.gd")

var world_state: RuntimeStateStore


func configure(state: RuntimeStateStore) -> void:
	world_state = state


func advance_turn(
	player_coords: Vector2i,
	world_seed: String,
	turn_index: int,
	evaluation_radius: int,
	wander_chance: float,
	pursuit_radius: int,
	craven_pursuit_radius: int,
	callbacks: Dictionary
) -> Dictionary:
	if world_state == null:
		return {}

	var planning_records: Array[EntityRecord] = []
	for snapshot_value in world_state.get_all_entity_snapshots():
		if snapshot_value is Dictionary:
			planning_records.append(EntityRecord.from_dict(snapshot_value))

	var get_hex_at: Callable = callbacks.get("get_hex_at", Callable())
	var has_ground_items: Callable = callbacks.get(
		"has_ground_items",
		Callable()
	)
	var get_occupying_entity_id: Callable = callbacks.get(
		"get_occupying_entity_id",
		Callable()
	)
	var plan := _NpcSimulator.plan_macro_turn(
		planning_records,
		player_coords,
		world_seed,
		turn_index,
		evaluation_radius,
		wander_chance,
		pursuit_radius,
		craven_pursuit_radius,
		get_hex_at,
		has_ground_items,
		get_occupying_entity_id,
	)

	for planned_record in planning_records:
		var current_snapshot := world_state.get_entity_snapshot(
			planned_record.entity_id
		)
		if current_snapshot.is_empty():
			continue
		world_state.patch_entity_record(planned_record.entity_id, {
			"runtime": planned_record.runtime.duplicate(true),
			"revision": int(current_snapshot.get("revision", 0)) + 1,
		})

	var move_record: Callable = callbacks.get("move_record", Callable())
	var collect_ground: Callable = callbacks.get("collect_ground", Callable())
	var moved_count := 0
	for move in plan.get("moves", []):
		var record_snapshot := world_state.get_entity_snapshot(
			str(move.get("entity_id", ""))
		)
		if record_snapshot.is_empty():
			continue
		var record := EntityRecord.from_dict(record_snapshot)
		var target_coords: Vector2i = move.get("to", record.coords)
		if not move_record.is_valid() or not bool(move_record.call(record, target_coords)):
			continue
		moved_count += 1
		record.coords = target_coords
		if collect_ground.is_valid():
			collect_ground.call(record)

	var try_work: Callable = callbacks.get("try_work", Callable())
	if try_work.is_valid():
		for worker_snapshot in world_state.get_all_entity_snapshots():
			if worker_snapshot is Dictionary:
				try_work.call(EntityRecord.from_dict(worker_snapshot))

	var refresh_proximity: Callable = callbacks.get(
		"refresh_proximity",
		Callable()
	)
	if refresh_proximity.is_valid():
		refresh_proximity.call(player_coords)

	return {
		"planning_record_count": planning_records.size(),
		"moved_count": moved_count,
		"collision": plan.get("collision", {}),
	}
