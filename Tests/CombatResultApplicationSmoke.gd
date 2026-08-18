extends SceneTree


func _init() -> void:
	var store := RuntimeStateStore.new()
	store.begin_new_world("COMBAT_APPLICATION_SMOKE")
	var player_runtime := _runtime_for_definition(
		preload("res://BiologicalCore/player_def.tres") as EntityDefinition,
		"player"
	)
	store.set_player_record({
		"entity_id": "player",
		"kind": GameEnums.RuntimeEntityKind.PLAYER,
		"coords": Vector2i.ZERO,
		"definition": (preload("res://BiologicalCore/player_def.tres") as EntityDefinition).to_state(),
		"runtime": player_runtime,
	}, Vector2i.ZERO)
	var enemy := _enemy("application-enemy", Vector2i(1, 0))
	store.register_entity(enemy)
	store.set_hex_record(Vector2i(1, 0), HexRecord.new())
	var initial_ground := _item("initial-ground")
	store.add_ground_items(Vector2i(1, 0), [initial_ground])

	var encounter := _encounter(store, enemy, "application-encounter", initial_ground)
	var handoff := store.begin_combat_handoff(encounter)
	if handoff == null:
		_fail("Could not begin the controlled combat handoff.")
		return
	var dead_runtime := enemy.runtime.duplicate(true)
	dead_runtime["is_dead"] = true
	dead_runtime["inventory_items"] = [_item("corpse-item")]
	var result := CombatResultRecord.new()
	result.encounter_id = encounter.encounter_id
	result.source_coords = encounter.source_coords
	result.outcome = GameEnums.CombatOutcome.PLAYER_VICTORY
	result.reason = "test_resolution"
	result.elapsed_minutes = 7
	result.actor_runtime_updates = [
		{"actor_id": "player", "runtime": player_runtime.duplicate(true)},
		{"actor_id": enemy.entity_id, "runtime": dead_runtime},
	]
	result.participant_results = [
		{"actor_id": "player", "status": "active"},
		{"actor_id": enemy.entity_id, "status": "dead"},
	]
	result.body_locations = [{"actor_id": enemy.entity_id, "sector_index": 4}]
	result.ground_items = [initial_ground]
	var ledger := CombatRelationshipLedger.new()
	ledger.set_relation("player", enemy.entity_id, CombatRelationshipLedger.Relation.HOSTILE)
	result.relationship_state = ledger.to_dict()

	var service := CombatResultApplicationService.new()
	service.configure(store)
	var applied := service.apply(result, handoff)
	if not applied.applied or applied.idempotent:
		_fail("Valid combat result was not applied exactly once: " + applied.error)
		return
	if store.world_time_minutes != GameTimeRules.STARTING_WORLD_MINUTES + 7:
		_fail("Combat elapsed time was not committed exactly once.")
		return
	if store.is_entity_alive(enemy.entity_id) or store.has_entity_at(enemy.coords):
		_fail("Dead combat actor remained alive or occupied its macro coordinate.")
		return
	if not _ground_has(store, enemy.coords, "corpse-item"):
		_fail("Dead actor inventory did not transfer to the combat site.")
		return
	var site := store.get_hex_record(enemy.coords).combat_site_state
	if site.get("bodies", []).size() != 1:
		_fail("Body location was not persisted in the combat-site state.")
		return
	if store.get_hex_record(enemy.coords).revision != 1:
		_fail("Combat-site mutation did not advance the canonical hex revision.")
		return
	if store.relationship_between("player", enemy.entity_id) != CombatRelationshipLedger.Relation.HOSTILE:
		_fail("Combat relationship state did not persist.")
		return
	var time_after_first := store.world_time_minutes
	var repeated := service.apply(result, null)
	if not repeated.applied or not repeated.idempotent or store.world_time_minutes != time_after_first:
		_fail("Repeated combat result was not idempotent.")
		return
	var malformed_repeat := CombatResultRecord.from_dict(result.to_dict())
	var malformed_player_runtime: Dictionary = malformed_repeat.actor_runtime_updates[0].get(
		"runtime", {}
	).duplicate(true)
	malformed_player_runtime["inventory_items"] = [_item("corpse-item")]
	malformed_repeat.actor_runtime_updates[0]["runtime"] = malformed_player_runtime
	var rejected_repeat := service.apply(malformed_repeat, null)
	if rejected_repeat.idempotent or rejected_repeat.error.is_empty():
		_fail("Malformed repeated result bypassed payload validation.")
		return
	var malformed_ground_repeat := CombatResultRecord.from_dict(result.to_dict())
	malformed_ground_repeat.ground_items.append(_item("corpse-item"))
	var rejected_ground_repeat := service.apply(malformed_ground_repeat, null)
	if rejected_ground_repeat.idempotent or rejected_ground_repeat.error.is_empty():
		_fail("Malformed repeated ground payload bypassed payload validation.")
		return

	var second_enemy := _enemy("application-enemy-2", Vector2i(2, 0))
	store.register_entity(second_enemy)
	var malformed_encounter := _encounter(store, second_enemy, "malformed-encounter", {})
	var malformed_handoff := store.begin_combat_handoff(malformed_encounter)
	var malformed := CombatResultRecord.new()
	malformed.encounter_id = malformed_encounter.encounter_id
	malformed.source_coords = malformed_encounter.source_coords
	malformed.actor_runtime_updates = [
		{"actor_id": "player", "runtime": store.player_record.runtime.duplicate(true)},
	]
	var before_malformed := store.capture_reconciliation_snapshot()
	var rejected := service.apply(malformed, malformed_handoff)
	if rejected.applied or store.world_time_minutes != int(before_malformed["world_time_minutes"]):
		_fail("Malformed combat result partially mutated authoritative state.")
		return
	var invalid_relationship := CombatResultRecord.from_dict(malformed.to_dict())
	invalid_relationship.actor_runtime_updates.append({
		"actor_id": second_enemy.entity_id,
		"runtime": second_enemy.runtime.duplicate(true),
	})
	invalid_relationship.participant_results = [
		{"actor_id": "player", "status": "active"},
		{"actor_id": second_enemy.entity_id, "status": "active"},
	]
	invalid_relationship.relationship_state = {
		"schema_version": 1,
		"relation_by_pair": {"malformed": 99},
		"trust_by_pair": {},
		"accepted_orders": {},
	}
	var before_relationship_rejection := store.capture_reconciliation_snapshot()
	var relationship_rejected := service.apply(invalid_relationship, malformed_handoff)
	if relationship_rejected.applied or relationship_rejected.error.is_empty():
		_fail("Malformed relationship payload was accepted.")
		return
	if store.capture_reconciliation_snapshot() != before_relationship_rejection:
		_fail("Malformed relationship result partially mutated authoritative state.")
		return
	store.cancel_combat_handoff(malformed.encounter_id)
	print("COMBAT_RESULT_APPLICATION_SMOKE: PASS")
	quit(0)


func _enemy(entity_id: String, coords: Vector2i) -> EntityRecord:
	var definition := preload("res://BiologicalCore/scavenger_def.tres") as EntityDefinition
	var record := EntityRecord.new()
	record.entity_id = entity_id
	record.kind = GameEnums.RuntimeEntityKind.NPC
	record.life_state = GameEnums.EntityLifeState.ALIVE
	record.world_status = GameEnums.EntityWorldStatus.HOSTILE
	record.coords = coords
	record.definition = definition.to_state()
	record.runtime = _runtime_for_definition(definition, entity_id)
	return record


func _runtime_for_definition(definition: EntityDefinition, actor_id: String) -> Dictionary:
	var core := EntityFactory.record_to_humanoid_core({
		"entity_id": actor_id,
		"definition": definition.to_state(),
		"runtime": {},
	}, null, actor_id)
	var runtime := core.capture_runtime_state().to_dict()
	core.free()
	return runtime


func _encounter(
	store: RuntimeStateStore,
	enemy: EntityRecord,
	encounter_id: String,
	ground_item: Dictionary
) -> CombatEncounterRecord:
	var encounter := CombatEncounterRecord.new()
	encounter.encounter_id = encounter_id
	encounter.source_coords = enemy.coords
	encounter.topology_id = "squad_7x5"
	encounter.actors = [
		{
			"actor_id": "player",
			"direct_player": true,
			"runtime_record": store.player_record.to_dict(),
			"participant_context": {"macro_origin_coords": store.player_record.coords},
		},
		{
			"actor_id": enemy.entity_id,
			"runtime_record": enemy.to_dict(),
			"participant_context": {"macro_origin_coords": enemy.coords},
		},
	]
	if not ground_item.is_empty():
		encounter.ground_items = [ground_item.duplicate(true)]
	return encounter


func _item(instance_id: String) -> Dictionary:
	return {
		"instance_id": instance_id,
		"id": "water_bottle",
		"template_path": "res://ItemCore/Items/water_bottle.tres",
		"owner_id": "",
		"physical_location": "ground",
		"equipped_slot": GameEnums.EquipmentSlot.NONE,
	}


func _ground_has(store: RuntimeStateStore, coords: Vector2i, instance_id: String) -> bool:
	for value in store.get_ground_items(coords):
		if str(value.get("instance_id", "")) == instance_id:
			return true
	return false


func _fail(message: String) -> void:
	push_error("[COMBAT_RESULT_APPLICATION] " + message)
	quit(1)
