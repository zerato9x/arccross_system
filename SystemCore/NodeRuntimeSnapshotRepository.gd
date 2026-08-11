extends RefCounted
class_name NodeRuntimeSnapshotRepository

## Node-scoped run snapshots.  This repository only copies neutral records;
## RuntimeStateStore remains responsible for submitting restored records to its
## authoritative indexes and for deciding when a snapshot is captured.


static func capture(
	entity_records: Dictionary,
	hex_records: Dictionary,
	ground_item_records: Dictionary,
	active_world_actions: Dictionary,
	world_signal_records: Dictionary,
	last_simulated_minute: int,
	player_revision: int
) -> Dictionary:
	var signals: Array = []
	for value in world_signal_records.values():
		if value is WorldSignalRecord:
			signals.append(value.to_dict())
	return {
		"entities": RuntimeRecordRepository.capture_entities(entity_records),
		"hexes": RuntimeRecordRepository.capture_hexes(hex_records),
		"ground_items": RuntimeRecordRepository.capture_ground_items(ground_item_records),
		"active_world_actions": active_world_actions.duplicate(true),
		"world_signals": signals,
		"last_simulated_minute": maxi(0, last_simulated_minute),
		"player_revision": maxi(0, player_revision),
	}


static func restore_records(snapshot: Dictionary) -> Dictionary:
	var signals: Array = []
	for signal_data in snapshot.get("world_signals", []):
		if signal_data is Dictionary:
			signals.append(WorldSignalRecord.from_dict(signal_data))
	return {
		"entities": snapshot.get("entities", []).duplicate(true),
		"hexes": RuntimeRecordRepository.restore_hexes(snapshot.get("hexes", [])),
		"ground_items": RuntimeRecordRepository.restore_ground_items(
			snapshot.get("ground_items", [])
		),
		"active_world_actions": snapshot.get("active_world_actions", {}).duplicate(true),
		"world_signals": signals,
		"last_simulated_minute": maxi(0, int(snapshot.get("last_simulated_minute", 0))),
		"player_revision": maxi(0, int(snapshot.get("player_revision", 0))),
	}
