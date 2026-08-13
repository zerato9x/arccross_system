extends SceneTree

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var main_scene := load("res://SystemCore/game_director.tscn") as PackedScene
	if main_scene == null:
		_fail("GameDirector scene did not load.")
		return
	var director := main_scene.instantiate()
	root.add_child(director)
	await process_frame
	await process_frame
	var macro_map := director.get_node("MainWorld") as MacroGameManager
	var world_state := root.get_node("WorldState") as RuntimeStateStore
	if macro_map == null or world_state == null or macro_map.world_generator == null:
		_fail("Macro world services did not initialize.")
		return

	var source := _find_open_source(macro_map, world_state)
	if source == Vector2i(2147483647, 2147483647):
		_fail("Could not find an open assembly source hex.")
		return
	var definition := preload("res://BiologicalCore/scavenger_def.tres") as EntityDefinition
	_register_actor(world_state, "assembly_smoke_primary", source, definition, "assembly_squad", {
		"awareness_strength": 1.0,
		"target_id": "player",
	})
	_register_actor(world_state, "assembly_smoke_same_01", source + Vector2i(1, 0), definition, "assembly_squad", {
		"awareness_strength": 1.0,
	})
	_register_actor(world_state, "assembly_smoke_same_02", source + Vector2i(0, -1), definition, "assembly_squad", {
		"awareness_strength": 1.0,
	})
	_register_actor(world_state, "assembly_smoke_same_03", source + Vector2i(-1, 1), definition, "assembly_squad", {
		"awareness_strength": 1.0,
	})
	_register_actor(world_state, "assembly_smoke_committed", source + Vector2i(1, -1), definition, "other_squad", {
		"awareness_strength": 0.0,
		"committed_to_contact": true,
		"commitment_subject_id": "assembly_smoke_primary",
	})
	_register_actor(world_state, "assembly_smoke_observer", source + Vector2i(1, 1), definition, "observer_squad", {
		"awareness_strength": 0.0,
	})
	_register_actor(world_state, "assembly_smoke_far", source + Vector2i(3, 0), definition, "assembly_squad", {
		"awareness_strength": 1.0,
	})
	world_state.get_entity("assembly_smoke_observer").world_status = GameEnums.EntityWorldStatus.CEASEFIRE

	var request := {
		"enemy_id": "assembly_smoke_primary",
		"coords": source,
		"approach_from": source + Vector2i(-1, 0),
		"initiator_id": "player",
		"context": GameEnums.EncounterContext.NEUTRAL_MEET,
	}
	var first := macro_map._build_combat_encounter_record(request)
	var second := macro_map._build_combat_encounter_record(request)
	if first == null or second == null:
		_fail("Macro encounter service did not produce an encounter record.")
		return
	if first.assembly_radius != 2 or first.participant_cap != 6:
		_fail("Encounter assembly profile did not hydrate radius two and cap six.")
	if first.late_reinforcements_enabled:
		_fail("Encounter assembly enabled late reinforcements.")
	if first.actors.size() != 6:
		_fail("Expected six assembled actors, got %d." % first.actors.size())
	var included_ids: Array[String] = []
	for actor in first.actors:
		included_ids.append(str(actor.get("actor_id", "")))
		var context: Dictionary = actor.get("participant_context", {})
		if context.get("macro_origin_coords", null) == null or not context.has("relative_entry_direction") or not context.has("return_policy"):
			_fail("Participant %s is missing macro context." % str(actor.get("actor_id", "")))
	if "player" not in included_ids or "assembly_smoke_primary" not in included_ids:
		_fail("The player or primary contact was dropped from the assembled roster.")
	if "assembly_smoke_observer" in included_ids or "assembly_smoke_far" in included_ids:
		_fail("A neutral observer or outside-radius actor entered the encounter.")
	if first.assembly_receipt.get("included_actor_ids", []) != second.assembly_receipt.get("included_actor_ids", []):
		_fail("Repeated assembly did not produce the same included actor order.")
	var first_receipt := JSON.stringify(first.assembly_receipt.get("candidates", []))
	var second_receipt := JSON.stringify(second.assembly_receipt.get("candidates", []))
	if first_receipt != second_receipt:
		_fail("Repeated assembly did not produce the same candidate receipt.")

	var ledger := CombatRelationshipLedger.from_dict(first.relationship_state)
	if ledger.relation("player", "assembly_smoke_primary", CombatRelationshipLedger.Relation.NEUTRAL) != CombatRelationshipLedger.Relation.HOSTILE:
		_fail("Primary contact did not receive an explicit hostile player relation.")
	var expected_pairs := first.actors.size() * (first.actors.size() - 1) / 2
	if ledger.relation_by_pair.size() != expected_pairs:
		_fail("Assembly did not write every participant pair into the relation ledger.")

	if failures.is_empty():
		print("COMBAT_ENCOUNTER_ASSEMBLY_SMOKE: PASS // actors=", first.actors.size())
		quit(0)
		return
	for failure in failures:
		push_error("[COMBAT_ASSEMBLY] " + failure)
	quit(1)


func _find_open_source(macro_map: MacroGameManager, world_state: RuntimeStateStore) -> Vector2i:
	var center := macro_map.player_token.current_hex_coords
	var offsets: Array[Vector2i] = [Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(2, 0)]
	for offset: Vector2i in offsets:
		var coords: Vector2i = center + offset
		if not macro_map.world_generator.is_in_zone_bounds(coords):
			continue
		var hex := macro_map.world_generator.get_hex_at(coords)
		if hex != null and hex.is_passable() and not world_state.has_entity_at(coords):
			return coords
	return Vector2i(2147483647, 2147483647)


func _register_actor(
	world_state: RuntimeStateStore,
	actor_id: String,
	coords: Vector2i,
	definition: EntityDefinition,
	squad_id: String,
	extra_runtime: Dictionary
) -> void:
	var record := EntityRecord.new()
	record.entity_id = actor_id
	record.kind = GameEnums.RuntimeEntityKind.NPC
	record.life_state = GameEnums.EntityLifeState.ALIVE
	record.world_status = GameEnums.EntityWorldStatus.HOSTILE
	record.coords = coords
	record.definition = definition.to_state()
	record.runtime = {"squad_id": squad_id}
	for key in extra_runtime.keys():
		record.runtime[key] = extra_runtime[key]
	world_state.register_entity(record)


func _fail(message: String) -> void:
	failures.append(message)
