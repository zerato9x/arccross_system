extends RefCounted
class_name RuntimeSaveMigrationService

## Pure migration boundary for legacy disposable-run snapshots.


static func migrate(
	snapshot: Dictionary,
	from_version: int,
	target_version: int
) -> Dictionary:
	var migrated := snapshot.duplicate(true)
	if from_version == 12:
		migrated["relationship_state"] = migrated.get(
			"relationship_state", CombatRelationshipLedger.new().to_dict()
		)
		migrated["applied_combat_encounters"] = migrated.get(
			"applied_combat_encounters", {}
		)
		var player_data: Dictionary = migrated.get("player_record", {}).duplicate(true)
		if not player_data.is_empty():
			player_data["coords"] = player_data.get(
				"coords", migrated.get("player_coords", Vector2i.ZERO)
			)
			migrated["player_record"] = player_data
		migrated["version"] = 13
	if from_version in [12, 13]:
		migrated["applied_world_receipts"] = migrated.get(
			"applied_world_receipts", {}
		)
		var active_node := str(migrated.get("active_node_id", ""))
		migrated["active_world_actions"] = _migrate_world_action_reservations(
			migrated.get("active_world_actions", {}), active_node
		)
		for hex_entry in migrated.get("hexes", []):
			if not hex_entry is Dictionary:
				continue
			var record_data: Dictionary = hex_entry.get("record", {}).duplicate(true)
			record_data["revision"] = maxi(0, int(record_data.get("revision", 0)))
			hex_entry["record"] = record_data
		for node_id in migrated.get("node_runtime_snapshots", {}).keys():
			var node_snapshot: Dictionary = migrated["node_runtime_snapshots"][node_id]
			node_snapshot["active_world_actions"] = _migrate_world_action_reservations(
				node_snapshot.get("active_world_actions", {}), str(node_id)
			)
			migrated["node_runtime_snapshots"][node_id] = node_snapshot
	if from_version in [12, 13, 14]:
		migrated = _retire_legacy_world_receipts(migrated)
		migrated["version"] = target_version
	return migrated


static func _retire_legacy_world_receipts(value: Variant) -> Variant:
	if value is Array:
		var migrated_array: Array = []
		for entry in value:
			migrated_array.append(_retire_legacy_world_receipts(entry))
		return migrated_array
	if not value is Dictionary:
		return value
	var migrated: Dictionary = {}
	for key in value.keys():
		migrated[key] = _retire_legacy_world_receipts(value[key])
	if (
		migrated.has("receipt_id")
		and migrated.has("action_id")
		and migrated.get("mutations", []) is Array
	):
		migrated.erase("actor_state")
		var mutations: Array = []
		for mutation_value in migrated.get("mutations", []):
			if (
				mutation_value is Dictionary
				and str(mutation_value.get("type", "")) == "replace_actor_runtime"
			):
				continue
			mutations.append(mutation_value)
		migrated["mutations"] = mutations
	return migrated


static func _migrate_world_action_reservations(
	value: Variant,
	node_id: String
) -> Dictionary:
	if not value is Dictionary:
		return {}
	var migrated: Dictionary = {}
	for action_id_value in value.keys():
		var action_id := str(action_id_value)
		var state: Variant = value[action_id_value]
		if action_id.is_empty() or not state is Dictionary:
			continue
		var reservation := WorldActionReservationRecord.from_dict(state)
		reservation.action_id = action_id
		if reservation.node_id.is_empty():
			reservation.node_id = node_id
		reservation.actor_id = str(state.get("actor_id", reservation.actor_id))
		reservation.target_id = str(state.get("target_id", reservation.target_id))
		reservation.verb_id = str(state.get("verb_id", reservation.verb_id))
		reservation.started_minute = maxi(0, int(state.get("started_minute", 0)))
		reservation.progress = clampf(float(state.get("progress", 0.0)), 0.0, 1.0)
		reservation.state = state.duplicate(true)
		if reservation.validation_error().is_empty():
			migrated[action_id] = reservation.to_dict()
	return migrated
