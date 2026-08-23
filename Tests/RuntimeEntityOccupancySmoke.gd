extends SceneTree


func _init() -> void:
	var store := RuntimeStateStore.new()
	store.begin_new_world("ENTITY_OCCUPANCY_SMOKE")
	store.set_player_record({
		"entity_id": "player",
		"kind": GameEnums.RuntimeEntityKind.PLAYER,
		"coords": Vector2i.ZERO,
		"runtime": {"inventory": {"equipment": {}, "backpack": []}},
	}, Vector2i.ZERO)

	var live := _entity("live", Vector2i(1, 0))
	if store.register_entity(live) != live.entity_id:
		_fail("Could not register the live entity.")
		return
	if not store.update_player_runtime(
		{"inventory": {"equipment": {}, "backpack": []}},
		live.coords
	):
		_fail("Player co-location with a live entity was rejected.")
		return
	if store.get_entity_id_at(live.coords) != live.entity_id:
		_fail("Live entity occupancy disappeared when the player co-located.")
		return

	var corpse := _entity("corpse", Vector2i(2, 0))
	if store.register_entity(corpse) != corpse.entity_id:
		_fail("Could not register the corpse fixture.")
		return
	if not store.set_entity_life_state(corpse.entity_id, GameEnums.EntityLifeState.DEAD):
		_fail("Corpse lifecycle transition failed.")
		return
	# Simulate the stale mapping reported by the movement bug, then exercise the
	# idempotent death path that should repair it.
	store.entity_ids_by_coords[corpse.coords] = corpse.entity_id
	if not store.set_entity_life_state(corpse.entity_id, GameEnums.EntityLifeState.DEAD):
		_fail("Repeated corpse lifecycle normalization failed.")
		return
	if store.has_entity_at(corpse.coords) or not store.get_entity_snapshot_at(corpse.coords).is_empty():
		_fail("Dead corpse still occupied its coordinate after normalization.")
		return

	var withdrawn := _entity("withdrawn", Vector2i(3, 0))
	if store.register_entity(withdrawn) != withdrawn.entity_id:
		_fail("Could not register the withdrawn fixture.")
		return
	if not store.set_entity_world_status(
		withdrawn.entity_id,
		GameEnums.EntityWorldStatus.WITHDRAWN
	):
		_fail("Withdrawn status transition failed.")
		return
	if store.has_entity_at(withdrawn.coords) or store.is_entity_active(withdrawn.entity_id):
		_fail("Withdrawn entity remained an active occupant.")
		return

	var legacy_dead_payload := _entity("legacy_dead", Vector2i(4, 0)).to_dict()
	legacy_dead_payload["life_state"] = GameEnums.EntityLifeState.ALIVE
	legacy_dead_payload["runtime"]["is_dead"] = true
	if store.register_entity(legacy_dead_payload) != "legacy_dead":
		_fail("Legacy runtime-dead entity could not be registered.")
		return
	if store.is_entity_alive("legacy_dead") or store.has_entity_at(Vector2i(4, 0)):
		_fail("Runtime death flag was not normalized before indexing.")
		return

	var errors := store.validate_integrity()
	if not errors.is_empty():
		_fail("Valid occupancy state failed integrity: " + "; ".join(errors))
		return
	print("RUNTIME_ENTITY_OCCUPANCY_SMOKE: PASS")
	quit(0)


func _entity(entity_id: String, coords: Vector2i) -> EntityRecord:
	var record := EntityRecord.new()
	record.entity_id = entity_id
	record.kind = GameEnums.RuntimeEntityKind.NPC
	record.life_state = GameEnums.EntityLifeState.ALIVE
	record.world_status = GameEnums.EntityWorldStatus.HOSTILE
	record.coords = coords
	record.runtime = {"inventory_items": []}
	return record


func _fail(message: String) -> void:
	push_error("[RUNTIME_ENTITY_OCCUPANCY] " + message)
	quit(1)
