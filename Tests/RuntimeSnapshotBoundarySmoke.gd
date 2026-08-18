extends SceneTree

const _NpcSimulator := preload("res://WorldCore/MacroNpcSimulator.gd")


func _init() -> void:
	var store := RuntimeStateStore.new()
	var entity := EntityRecord.new()
	entity.entity_id = "snapshot-npc"
	entity.coords = Vector2i(1, 0)
	entity.runtime = {"biology": {"hunger": 12.0}}
	store.register_entity(entity)

	var entity_snapshot := store.get_entity_snapshot(entity.entity_id)
	entity_snapshot["runtime"]["biology"]["hunger"] = 0.0
	if float(store.get_entity(entity.entity_id).runtime["biology"]["hunger"]) != 12.0:
		_fail("Entity snapshot mutation leaked into the authoritative record.")
		return

	var hex := HexRecord.new()
	hex.world_signals = [{"signal_id": "signal-1", "expires_minute": 90}]
	store.set_hex_record(Vector2i.ZERO, hex)
	var hex_snapshot := store.get_hex_snapshot(Vector2i.ZERO)
	hex_snapshot["world_signals"].clear()
	if store.get_hex_record(Vector2i.ZERO).world_signals.is_empty():
		_fail("Hex snapshot mutation leaked into the authoritative record.")
		return

	var runtime_service := MacroNpcRuntimeService.new()
	runtime_service.advance(store, 60, 60)
	var updated := store.get_entity(entity.entity_id)
	if updated == null or float(updated.runtime["biology"]["hunger"]) >= 12.0:
		_fail("NPC runtime service did not apply a snapshot-derived patch.")
		return
	var manager := MacroGameManager.new()
	var purpose_record := EntityRecord.new()
	purpose_record.entity_id = "projection-npc"
	purpose_record.definition = {"faction": GameEnums.Faction.SCAVENGER_CELL}
	purpose_record.runtime = {}
	var purpose_before := purpose_record.to_dict()
	manager._ensure_npc_purpose(purpose_record)
	if purpose_record.to_dict() != purpose_before:
		_fail("HUD purpose projection mutated an authoritative record.")
		return
	_NpcSimulator.projection_score(purpose_record, Vector2i.ZERO)
	if purpose_record.to_dict() != purpose_before:
		_fail("NPC proximity scoring mutated an authoritative record.")
		return
	manager.free()
	print("[RUNTIME_SNAPSHOT_BOUNDARY] PASS")
	quit(0)


func _fail(message: String) -> void:
	push_error("[RUNTIME_SNAPSHOT_BOUNDARY] " + message)
	quit(1)
