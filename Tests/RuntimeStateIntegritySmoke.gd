extends SceneTree


func _init() -> void:
	var store := RuntimeStateStore.new()
	store.begin_new_world("INTEGRITY_SMOKE")
	store.set_player_record({
		"entity_id": "player",
		"kind": GameEnums.RuntimeEntityKind.PLAYER,
		"coords": Vector2i.ZERO,
		"runtime": {"inventory": {"equipment": {}, "backpack": []}},
	}, Vector2i.ZERO)

	var alpha := _entity("alpha", Vector2i(1, 0))
	if store.register_entity(alpha) != "alpha":
		_fail("Could not register the primary entity.")
		return
	if not store.register_entity(_entity("collision", Vector2i(1, 0))).is_empty():
		_fail("Coordinate collision silently overwrote the alive index.")
		return
	if store.get_entity("collision") != null:
		_fail("Rejected coordinate collision still entered entity_records.")
		return

	var item := _item("integrity-item")
	if not store.add_ground_items(Vector2i(1, 0), [item]):
		_fail("Could not add the controlled ground item.")
		return
	if not store.transfer_ground_item_to_entity(
		Vector2i(1, 0), "integrity-item", "alpha"
	):
		_fail("Atomic ground-to-entity transfer failed.")
		return
	var owner := store.find_item_ownership("integrity-item")
	if owner.get("owner_id", "") != "alpha":
		_fail("Transferred item does not have exactly one entity owner.")
		return
	if store.transfer_item_to_entity("missing", item):
		_fail("Transfer to a missing destination committed.")
		return
	if store.find_item_ownership("integrity-item").get("owner_id", "") != "alpha":
		_fail("Failed transfer disturbed the valid source owner.")
		return

	store.set_relationship(
		"player", "alpha", CombatRelationshipLedger.Relation.HOSTILE
	)
	store.adjust_relationship_trust("player", "alpha", 2.5)
	if store.relationship_between("player", "alpha") != CombatRelationshipLedger.Relation.HOSTILE:
		_fail("Run-global relationship state did not commit.")
		return

	if not store.set_entity_life_state("alpha", GameEnums.EntityLifeState.DEAD):
		_fail("Entity death did not commit.")
		return
	if store.has_entity_at(Vector2i(1, 0)):
		_fail("Dead entity remained in the alive coordinate index.")
		return
	var errors := store.validate_integrity()
	if not errors.is_empty():
		_fail("Valid store failed integrity: " + "; ".join(errors))
		return
	for index in range(70):
		store.mark_combat_result_applied("bounded-encounter-%02d" % index)
	if store.applied_combat_encounters.size() != 64:
		_fail("Applied encounter history did not remain bounded at 64 entries.")
		return
	var save_path := "res://.godot/test-logs/runtime_integrity_atomic.json"
	if not store.save_to_disk(save_path):
		_fail("Could not create the valid atomic-save fixture.")
		return
	var valid_contents := FileAccess.get_file_as_string(save_path)

	store.player_record.runtime["inventory"]["backpack"].append(item.duplicate(true))
	if store.validate_integrity().is_empty():
		_fail("Duplicate item ownership was not detected.")
		return
	if store.save_to_disk(save_path):
		_fail("Integrity-invalid state overwrote the last valid save.")
		return
	if FileAccess.get_file_as_string(save_path) != valid_contents:
		_fail("Rejected save changed the last valid file contents.")
		return
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	print("RUNTIME_STATE_INTEGRITY_SMOKE: PASS")
	quit(0)


func _entity(entity_id: String, coords: Vector2i) -> EntityRecord:
	var record := EntityRecord.new()
	record.entity_id = entity_id
	record.kind = GameEnums.RuntimeEntityKind.NPC
	record.life_state = GameEnums.EntityLifeState.ALIVE
	record.coords = coords
	record.runtime = {"inventory_items": []}
	return record


func _item(instance_id: String) -> Dictionary:
	return {
		"instance_id": instance_id,
		"id": "water_bottle",
		"template_path": "res://ItemCore/Items/water_bottle.tres",
		"owner_id": "",
		"physical_location": "ground",
		"equipped_slot": GameEnums.EquipmentSlot.NONE,
	}


func _fail(message: String) -> void:
	push_error("[RUNTIME_STATE_INTEGRITY] " + message)
	quit(1)
