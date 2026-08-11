extends RefCounted
class_name MacroNpcPerceptionService

## NPC sensory consequences for neutral world signals. This service owns role
## weighting, hearing checks, and memory patches; UI and token projection stay
## outside the perception boundary.

const _NpcSimulator := preload("res://WorldCore/MacroNpcSimulator.gd")
const _Perception := preload("res://WorldCore/WorldPerceptionQuery.gd")


func emit_noise(
	world_state: RuntimeStateStore,
	world_generator: HexWorldGenerator,
	coords: Vector2i,
	event_id: String,
	macro_turn_index: int
) -> void:
	if world_state == null or world_generator == null:
		return
	var signal_record := WorldSignalRecord.new()
	signal_record.signal_id = "%s:%s:%d" % [
		event_id,
		str(coords),
		world_state.world_time_minutes,
	]
	signal_record.signal_type = "noise"
	signal_record.source_id = "player"
	signal_record.coords = coords
	signal_record.created_minute = world_state.world_time_minutes
	signal_record.expires_minute = world_state.world_time_minutes + 45
	signal_record.intensity = 2.0 if event_id.find("search") >= 0 else 1.0
	world_state.register_world_signal(signal_record)
	var signal_hex := world_generator.get_hex_at(coords)
	signal_hex.world_signals.append(signal_record.to_dict())
	world_state.set_hex_record(coords, signal_hex.to_state())
	notify_signal(
		world_state,
		world_generator,
		signal_record,
		macro_turn_index
	)


func notify_signal(
	world_state: RuntimeStateStore,
	world_generator: HexWorldGenerator,
	signal_record: WorldSignalRecord,
	macro_turn_index: int
) -> void:
	if world_state == null or world_generator == null or signal_record == null:
		return
	for snapshot_value in world_state.get_all_entity_snapshots():
		if not snapshot_value is Dictionary:
			continue
		var snapshot: Dictionary = snapshot_value
		if int(snapshot.get("life_state", GameEnums.EntityLifeState.DEAD)) != GameEnums.EntityLifeState.ALIVE:
			continue
		var record := EntityRecord.from_dict(snapshot)
		var role := _NpcSimulator.role_descriptor(record)
		if not bool(role.get("investigates_noise", false)):
			continue
		var observer_hex := world_generator.get_hex_at(record.coords)
		var source_hex := world_generator.get_hex_at(signal_record.coords)
		if not _Perception.can_hear(
			signal_record,
			record.coords,
			observer_hex,
			source_hex,
			float(role.get("hearing_acuity", 1.0))
		):
			continue
		if _NpcSimulator.hex_distance(record.coords, signal_record.coords) > int(role.get("detection_radius", 5)) + 2:
			continue
		_NpcSimulator.remember_player_event(
			record,
			signal_record.signal_type,
			macro_turn_index,
			signal_record.coords,
			0.0,
			1.0 if record.world_status == GameEnums.EntityWorldStatus.HOSTILE else 0.25
		)
		record.runtime["macro_target_coords"] = signal_record.coords
		if record.world_status == GameEnums.EntityWorldStatus.HOSTILE:
			record.runtime["macro_purpose"] = GameEnums.NPC_PURPOSE_HUNT
			record.runtime["macro_purpose_label"] = "Investigate noise"
		else:
			record.runtime["macro_purpose"] = GameEnums.NPC_PURPOSE_PATROL
			record.runtime["macro_purpose_label"] = "Check noise"
		world_state.patch_entity_record(record.entity_id, {
			"runtime": record.runtime.duplicate(true),
			"revision": int(snapshot.get("revision", 0)) + 1,
		})
