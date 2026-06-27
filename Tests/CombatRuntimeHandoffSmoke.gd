extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var main_scene := load(
		"res://SystemCore/game_director.tscn"
	) as PackedScene
	var game_director := main_scene.instantiate()
	root.add_child(game_director)
	await process_frame
	await process_frame

	var macro_map := game_director.get_node("MainWorld") as MacroGameManager
	var world_state := root.get_node("WorldState") as RuntimeStateStore
	if macro_map == null or world_state == null:
		_fail("World systems did not initialize.")
		return

	var enemy_id := _ensure_enemy(macro_map, world_state)
	if enemy_id.is_empty():
		_fail("Could not create a controlled enemy record.")
		return
	var enemy_record := world_state.get_entity(enemy_id)
	enemy_record.runtime["macro_test_marker"] = "preserve-me"

	var token := macro_map.load_enemy_token(enemy_id)
	if token == null:
		_fail("Could not project the controlled enemy token.")
		return
	var token_signature := token.humanoid_token.get_appearance_signature()
	var record_signature := str(
		HumanoidVisualCatalog.appearance_from_record(
			enemy_record.to_dict()
		).get("signature", "")
	)
	if token_signature != record_signature:
		_fail("Macro token appearance does not match its record.")
		return

	macro_map._begin_entity_collision(enemy_id, enemy_record.coords)
	macro_map.resolve_entity_ambush(GameEnums.AmbushPosition.FAR)
	await process_frame
	await process_frame

	var arena = game_director.get("_active_arena")
	if arena == null:
		_fail("Combat handoff did not create a duel arena.")
		return
	var duel_signature := str(
		HumanoidVisualCatalog.appearance_from_inventory(
			arena.enemy_core.inventory
		).get("signature", "")
	)
	if duel_signature != token_signature:
		_fail("Duel enemy appearance drifted from the macro token.")
		return

	arena.enemy_core.body.apply_targeted_hit(
		GameEnums.LimbRegion.LEFT_ARM,
		0.75,
		0.0
	)
	var injured_hp: float = arena.enemy_core.body.limb_hp[
		GameEnums.LimbRegion.LEFT_ARM
	]
	arena.turn_manager.escape_combat(arena.enemy_core)
	await process_frame
	await process_frame
	await process_frame

	var escaped_record := world_state.get_entity(enemy_id)
	var stored_hp: float = escaped_record.runtime.get(
		"body",
		{}
	).get("limb_hp", {}).get(
		str(GameEnums.LimbRegion.LEFT_ARM),
		-1.0
	)
	if not is_equal_approx(stored_hp, injured_hp):
		_fail("Enemy escape did not persist duel body runtime.")
		return
	if escaped_record.runtime.get("macro_test_marker", "") != "preserve-me":
		_fail("Combat write-back erased macro runtime metadata.")
		return
	if not world_state.is_entity_alive(enemy_id):
		_fail("Enemy escape incorrectly killed the persistent record.")
		return

	print("[TEST PASS] Combat handoff preserves macro identity, appearance, and escape runtime.")
	quit(0)

func _ensure_enemy(
	macro_map: MacroGameManager,
	world_state: RuntimeStateStore
) -> String:
	if not macro_map.active_enemies.is_empty():
		var coords: Vector2i = macro_map.active_enemies.keys()[0]
		return (macro_map.active_enemies[coords] as MacroEnemy).entity_id

	for coords in [
		Vector2i(3, 0),
		Vector2i(3, -1),
		Vector2i(3, 1),
		Vector2i(2, -3),
	]:
		if world_state.has_entity_at(coords):
			var existing := world_state.get_entity_at(coords)
			if existing != null and world_state.is_entity_alive(existing.entity_id):
				macro_map.load_enemy_token(existing.entity_id)
				return existing.entity_id
		var hex := macro_map.world_generator.get_hex_at(coords)
		if not hex.is_passable():
			continue
		macro_map.spawn_procedural_enemy(
			coords,
			GameEnums.Faction.SCAVENGER_CELL,
			0
		)
		var record := world_state.get_entity_at(coords)
		if record != null:
			return record.entity_id
	return ""

func _fail(message: String) -> void:
	push_error("[TEST FAIL] " + message)
	quit(1)
