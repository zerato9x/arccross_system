extends SceneTree

const SAVE_PATH := "res://.godot/test-logs/system_integration_round_trip.json"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load("res://SystemCore/game_director.tscn") as PackedScene
	var director := packed.instantiate() as GameDirector
	root.add_child(director)
	await process_frame
	await process_frame
	var store := root.get_node("WorldState") as RuntimeStateStore
	var macro := director.macro_map
	var player_core := macro.player_token.get_humanoid_core()
	if store == null or player_core == null:
		return _fail(store, "World runtime did not initialize.")
	store.delete_save_file(SAVE_PATH)
	var combat_coords := _find_open_coords(macro, store, macro.player_token.current_hex_coords)
	if combat_coords == Vector2i(2147483647, 2147483647):
		return _fail(store, "Could not find a controlled combat site.")
	var support_coords := _find_open_coords(macro, store, combat_coords)
	if support_coords == Vector2i(2147483647, 2147483647):
		return _fail(store, "Could not find a support-actor coordinate.")
	var surrender_coords := _find_open_coords(macro, store, support_coords)
	if surrender_coords == Vector2i(2147483647, 2147483647):
		return _fail(store, "Could not find a surrender-actor coordinate.")
	var primary := _register_enemy(store, "roundtrip-primary", combat_coords)
	var support := _register_enemy(store, "roundtrip-support", support_coords)
	var surrender := _register_enemy(store, "roundtrip-surrender", surrender_coords)
	if primary.is_empty() or support.is_empty() or surrender.is_empty():
		return _fail(store, "Could not register the controlled roster.")

	player_core.body.apply_targeted_hit(GameEnums.LimbRegion.LEFT_ARM, 0.75, 0.0)
	var firearm := player_core.inventory.get_active_weapon(false)
	if firearm == null:
		return _fail(store, "Player fixture has no active firearm.")
	firearm.current_magazine = 1
	var firearm_id := firearm.instance_id
	var carried := _item("roundtrip-carried")
	var carried_item := ItemData.from_runtime_state(carried)
	if carried_item == null or not player_core.inventory.add_to_backpack(carried_item):
		return _fail(store, "Could not add the stable carried-item fixture.")
	var initial_ground := _item("roundtrip-initial-ground")
	if not store.add_ground_items(combat_coords, [initial_ground]):
		return _fail(store, "Could not seed combat-site ground ownership.")
	var site := macro.world_generator.get_hex_at(combat_coords)
	site.search_count = 2
	store.set_hex_record(combat_coords, site.to_state())
	store.run_flags["integration_progression"] = 3

	macro.begin_entity_collision(primary, combat_coords)
	macro.resolve_entity_ambush(GameEnums.AmbushPosition.FAR)
	await process_frame
	await process_frame
	var arena := director.get_active_arena() as TacticalCombatScene
	var handoff := store.get_active_combat_handoff()
	if arena == null or handoff == null:
		return _fail(store, "World-to-combat handoff did not open an arena.")
	if handoff.actor_ids != ["player", primary, support, surrender]:
		return _fail(store, "Handoff did not preserve the exact assembled actor set: %s" % str(handoff.actor_ids))
	if _runtime_item_state(store.player_record, firearm_id).is_empty():
		return _fail(
			store,
			"Firearm identity was lost while freezing the handoff. expected=%s raw_ids=%s"
			% [firearm_id, str(_collect_instance_ids(store.player_record.runtime))]
		)

	var result := CombatResultRecord.new()
	result.encounter_id = handoff.encounter_id
	result.source_coords = handoff.source_coords
	result.outcome = GameEnums.CombatOutcome.PLAYER_VICTORY
	result.reason = "integration_round_trip"
	result.elapsed_minutes = 9
	for actor_id in handoff.actor_ids:
		var runtime := (
			store.player_record.runtime.duplicate(true)
			if actor_id == "player"
			else store.get_entity(actor_id).runtime.duplicate(true)
		)
		var status := "active"
		if actor_id == primary:
			status = "dead"
			runtime["is_dead"] = true
			runtime["inventory_items"] = [_item("roundtrip-corpse-item")]
		elif actor_id == support:
			status = "incapacitated"
			runtime["is_comatose"] = true
		elif actor_id == surrender:
			status = "surrendered"
		result.actor_runtime_updates.append({"actor_id": actor_id, "runtime": runtime})
		result.participant_results.append({"actor_id": actor_id, "status": status})
	result.body_locations = [{"actor_id": primary, "sector_index": 8}]
	result.incapacitated_locations = [{"actor_id": support, "sector_index": 9}]
	result.surrendered_actor_ids = [surrender]
	result.surrendered_locations = [{"actor_id": surrender, "sector_index": 10}]
	result.ground_items = [initial_ground, _item("roundtrip-combat-drop")]
	result.environment_patch = {"cover_destroyed": true}
	var relations := CombatRelationshipLedger.from_dict(arena.encounter_record.relationship_state)
	relations.adjust_trust("player", surrender, 4.0)
	result.relationship_state = relations.to_dict()
	director._on_combat_finished(result)
	await process_frame
	await process_frame

	if store.get_active_combat_handoff() != null or not store.has_applied_combat_result(result.encounter_id):
		return _fail(store, "Combat result was not closed and recorded exactly once.")
	if store.is_entity_alive(primary) or store.has_entity_at(combat_coords):
		return _fail(store, "Dead actor survived in the macro occupancy index.")
	if not bool(store.get_entity(support).runtime.get("is_comatose", false)):
		return _fail(store, "Incapacitation did not return to macro authority.")
	if store.get_entity(surrender).world_status != GameEnums.EntityWorldStatus.WITHDRAWN:
		return _fail(store, "Surrender did not update macro availability.")
	if not _ground_has(store, combat_coords, "roundtrip-corpse-item"):
		return _fail(store, "Corpse inventory did not transfer to the site.")
	if _runtime_item_state(store.player_record, firearm_id).is_empty():
		return _fail(store, "Firearm identity was lost during result application.")
	var saved_time := store.world_time_minutes
	var encounter_id := result.encounter_id
	var player_coords := store.player_record.coords
	var relation_trust := CombatRelationshipLedger.from_dict(store.get_relationship_state()).trust("player", surrender)
	if not director.save_game(SAVE_PATH):
		return _fail(store, "Round-trip save failed: " + store.get_last_persistence_error())
	if _runtime_item_state(store.player_record, firearm_id).is_empty():
		return _fail(store, "Firearm identity was lost during macro save synchronization.")
	director.queue_free()
	await process_frame
	store.begin_new_world("SCRAMBLED_AFTER_COMBAT")
	if not store.load_from_disk(SAVE_PATH):
		return _fail(store, "Round-trip load failed: " + store.get_last_persistence_error())

	if store.player_record.coords != player_coords:
		return _fail(store, "Canonical player coordinates drifted across save/load.")
	if store.world_time_minutes != saved_time or not store.has_applied_combat_result(encounter_id):
		return _fail(store, "Time or applied-encounter idempotence history was lost.")
	if store.is_entity_alive(primary) or not bool(store.get_entity(support).runtime.get("is_comatose", false)):
		return _fail(store, "Dead/incapacitated lifecycle state was lost.")
	var loaded_site := store.get_hex_record(combat_coords)
	if loaded_site == null or loaded_site.search_count != 2:
		return _fail(store, "World search mutation was lost.")
	if loaded_site.combat_site_state.get("bodies", []).size() != 1:
		return _fail(store, "Body location was lost.")
	if not bool(loaded_site.combat_site_state.get("cover_destroyed", false)):
		return _fail(store, "Combat environment mutation was lost.")
	if not _ground_has(store, combat_coords, "roundtrip-combat-drop"):
		return _fail(store, "Dropped combat item was lost.")
	if not is_equal_approx(
		CombatRelationshipLedger.from_dict(store.get_relationship_state()).trust("player", surrender),
		relation_trust
	):
		return _fail(store, "Pairwise relationship state was lost.")
	if int(store.run_flags.get("integration_progression", 0)) != 3:
		return _fail(store, "Run progression was lost.")
	var loaded_firearm := _runtime_item_state(store.player_record, firearm_id)
	if loaded_firearm.is_empty() or int(loaded_firearm.get("current_magazine", -1)) != 1:
		return _fail(
			store,
			"Firearm identity or magazine state was lost: %s" % str(loaded_firearm)
		)
	if _runtime_item_state(store.player_record, "roundtrip-carried").is_empty():
		return _fail(store, "Carried item identity was lost.")
	if store.player_record.runtime.get("body", {}).get("wounds_by_limb", {}).get(
		str(GameEnums.LimbRegion.LEFT_ARM), []
	).is_empty():
		return _fail(store, "Player wound state was lost.")
	var integrity := store.validate_integrity()
	if not integrity.is_empty():
		return _fail(store, "Loaded integration state failed integrity: " + "; ".join(integrity))
	store.delete_save_file(SAVE_PATH)
	print("SYSTEM_INTEGRATION_ROUND_TRIP_SMOKE: PASS")
	quit(0)


func _register_enemy(store: RuntimeStateStore, actor_id: String, coords: Vector2i) -> String:
	var definition := preload("res://BiologicalCore/scavenger_def.tres") as EntityDefinition
	var record := EntityRecord.new()
	record.entity_id = actor_id
	record.coords = coords
	record.definition = definition.to_state()
	record.runtime = {
		"squad_id": "roundtrip-squad",
		"awareness_strength": 1.0,
		"inventory_items": [],
	}
	return store.register_entity(record)


func _find_open_coords(macro: MacroGameManager, store: RuntimeStateStore, origin: Vector2i) -> Vector2i:
	for radius in range(1, 5):
		for direction in HexCoordUtils.AXIAL_DIRECTIONS:
			var coords: Vector2i = origin + direction * radius
			if (
				coords == store.player_record.coords
				or not macro.world_generator.is_in_zone_bounds(coords)
				or store.has_entity_at(coords)
			):
				continue
			var hex := macro.world_generator.get_hex_at(coords)
			if hex != null and hex.is_passable():
				return coords
	return Vector2i(2147483647, 2147483647)


func _item(instance_id: String) -> Dictionary:
	var definition := load("res://ItemCore/Items/water_bottle.tres") as ItemData
	var state := definition.create_runtime_instance().to_runtime_state()
	state["instance_id"] = instance_id
	state["owner_id"] = ""
	state["physical_location"] = "ground"
	state["equipped_slot"] = GameEnums.EquipmentSlot.NONE
	return state


func _ground_has(store: RuntimeStateStore, coords: Vector2i, instance_id: String) -> bool:
	for item in store.get_ground_items(coords):
		if str(item.get("instance_id", "")) == instance_id:
			return true
	return false


func _runtime_item_state(record: EntityRecord, instance_id: String) -> Dictionary:
	var core := EntityFactory.record_to_humanoid_core(
		record.to_dict(), null, "IntegrationRoundTripVerifier"
	)
	if core == null:
		return {}
	var item := core.inventory.find_item_by_instance_id(instance_id)
	var state := item.to_runtime_state() if item != null else {}
	core.free()
	return state


func _collect_instance_ids(value: Variant) -> Array[String]:
	var ids: Array[String] = []
	_collect_instance_ids_into(value, ids)
	return ids


func _collect_instance_ids_into(value: Variant, ids: Array[String]) -> void:
	if value is Dictionary:
		var state: Dictionary = value
		var instance_id := str(state.get("instance_id", ""))
		if not instance_id.is_empty() and instance_id not in ids:
			ids.append(instance_id)
		for nested in state.values():
			_collect_instance_ids_into(nested, ids)
	elif value is Array:
		for nested in value:
			_collect_instance_ids_into(nested, ids)


func _fail(store: RuntimeStateStore, message: String) -> void:
	if store != null:
		store.delete_save_file(SAVE_PATH)
	push_error("[SYSTEM_INTEGRATION_ROUND_TRIP] " + message)
	quit(1)
