extends RefCounted
class_name MacroMovementService

## Purely world-facing movement policy. Scene input and animation remain in
## MacroGameManager; route selection lives here and can be tested without UI.

const HEX_NEIGHBORS := [
	Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1),
	Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1),
]

var world_generator: HexWorldGenerator


func configure(generator: HexWorldGenerator) -> void:
	world_generator = generator


func build_known_route(
	from_coords: Vector2i,
	to_coords: Vector2i,
	max_steps: int = 144
) -> Array[Vector2i]:
	var empty_route: Array[Vector2i] = []
	if world_generator == null or from_coords == to_coords:
		return empty_route
	if not _is_known_passable(from_coords) or not _is_known_passable(to_coords):
		return empty_route

	var frontier: Array[Vector2i] = [from_coords]
	var came_from: Dictionary = {from_coords: from_coords}
	var distances: Dictionary = {from_coords: 0}
	var frontier_index := 0
	while frontier_index < frontier.size():
		var cursor: Vector2i = frontier[frontier_index]
		frontier_index += 1
		var cursor_distance := int(distances.get(cursor, 0))
		if cursor_distance >= max_steps:
			continue
		for direction in HEX_NEIGHBORS:
			var candidate: Vector2i = cursor + direction
			if came_from.has(candidate) or not _is_known_passable(candidate):
				continue
			came_from[candidate] = cursor
			distances[candidate] = cursor_distance + 1
			if candidate == to_coords:
				return _reconstruct_route(came_from, from_coords, to_coords)
			frontier.append(candidate)
	return empty_route


func _is_known_passable(coords: Vector2i) -> bool:
	if world_generator == null or not world_generator.is_in_zone_bounds(coords):
		return false
	var hex_data := world_generator.get_hex_at(coords)
	return hex_data != null and hex_data.is_explored and hex_data.is_passable()


func _reconstruct_route(
	came_from: Dictionary,
	from_coords: Vector2i,
	to_coords: Vector2i
) -> Array[Vector2i]:
	var reversed_route: Array[Vector2i] = []
	var cursor := to_coords
	while cursor != from_coords:
		if not came_from.has(cursor):
			return []
		reversed_route.append(cursor)
		cursor = came_from[cursor]
	reversed_route.reverse()
	return reversed_route


func emit_trace(
	world_state: RuntimeStateStore,
	actor_id: String,
	from_coords: Vector2i,
	to_coords: Vector2i,
	node_id: String = ""
) -> void:
	## Movement is a physical action, so it leaves the same inspectable evidence
	## whether the actor is the player or an AI record. The renderer may draw a
	## subtle trail; perception reads this persisted trace/signal instead.
	if world_state == null or world_generator == null or from_coords == to_coords:
		return
	var now := world_state.world_time_minutes
	var hex := world_generator.get_hex_at(to_coords)
	hex.trace_records.append({
		"kind": "tracks",
		"source_id": actor_id,
		"coords": to_coords,
		"created_minute": now,
		"expires_minute": now + 180,
		"age_minutes": 0,
		"direction": str(to_coords - from_coords),
		"surface": "road" if hex.road_mask != 0 else str(hex.terrain_tile),
	})
	var signal_record := WorldSignalRecord.new()
	signal_record.signal_id = "tracks:%s:%s:%d" % [actor_id, str(to_coords), now]
	signal_record.signal_type = "tracks"
	signal_record.source_id = actor_id
	signal_record.node_id = node_id
	signal_record.coords = to_coords
	signal_record.created_minute = now
	signal_record.expires_minute = now + 180
	signal_record.intensity = 0.35 if hex.road_mask != 0 else 0.65
	signal_record.direction = to_coords - from_coords
	signal_record.payload = {"from": from_coords, "to": to_coords}
	world_state.register_world_signal(signal_record)
	hex.world_signals.append(signal_record.to_dict())
	hex.last_simulated_minute = now
	world_generator.commit_hex_projection(to_coords, hex)


func append_trace_to_receipt(
	receipt: WorldActionReceipt,
	actor_id: String,
	from_coords: Vector2i,
	to_coords: Vector2i,
	node_id: String,
	now: int,
	hex_data: MacroHexData
) -> void:
	if receipt == null or hex_data == null or from_coords == to_coords:
		return
	var trace := {
		"kind": "tracks",
		"source_id": actor_id,
		"coords": to_coords,
		"created_minute": now,
		"expires_minute": now + 180,
		"age_minutes": 0,
		"direction": str(to_coords - from_coords),
		"surface": "road" if hex_data.road_mask != 0 else str(hex_data.terrain_tile),
	}
	receipt.mutations.append({"type": "movement_trace", "trace": trace})
	var signal_record := WorldSignalRecord.new()
	signal_record.signal_id = "%s:tracks:%d" % [receipt.action_id, now]
	signal_record.signal_type = "tracks"
	signal_record.source_id = actor_id
	signal_record.node_id = node_id
	signal_record.coords = to_coords
	signal_record.created_minute = now
	signal_record.expires_minute = now + 180
	signal_record.intensity = 0.35 if hex_data.road_mask != 0 else 0.65
	signal_record.direction = to_coords - from_coords
	signal_record.payload = {"from": from_coords, "to": to_coords}
	receipt.add_signal(signal_record)
