extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if not _verify_item_instance_isolation():
		return

	var main_scene := load("res://SystemCore/game_director.tscn") as PackedScene
	if not main_scene:
		_fail("Could not load the game director scene.")
		return

	var game_director := main_scene.instantiate()
	root.add_child(game_director)
	await process_frame
	await process_frame

	var macro_map := game_director.get_node("MainWorld") as MacroGameManager
	var world_state := root.get_node("WorldState") as RuntimeStateStore
	if not macro_map or not world_state:
		_fail("World systems did not initialize.")
		return

	if macro_map.active_enemies.is_empty():
		_fail("Deterministic proximity generation created no nearby enemies.")
		return

	var enemy_coords: Vector2i = macro_map.active_enemies.keys()[0]
	var enemy_token := macro_map.active_enemies.get(enemy_coords) as MacroEnemy
	if not enemy_token:
		_fail("Expected an active enemy token at the demo coordinate.")
		return

	var enemy_id := enemy_token.entity_id
	var original_record := world_state.get_entity(enemy_id)
	macro_map.unload_enemy_token(enemy_coords)
	await process_frame

	if world_state.get_entity(enemy_id).is_empty():
		_fail("Unloading a token deleted its persistent entity record.")
		return

	var reloaded_token := macro_map.load_enemy_token(enemy_id)
	if not reloaded_token or reloaded_token.entity_id != enemy_id:
		_fail("Reloading did not project the same persistent enemy.")
		return

	var first_hex := macro_map.world_generator.get_hex_at(Vector2i(4, -2))
	var first_hex_state := first_hex.to_state()
	macro_map.world_generator.world_hex_cache.clear()
	var restored_hex := macro_map.world_generator.get_hex_at(Vector2i(4, -2))
	if restored_hex.to_state() != first_hex_state:
		_fail("Hex state changed after the visual generator cache was cleared.")
		return

	var duel_scene := load("res://CombatCore/MainDuelScene.tscn") as PackedScene
	var first_arena = duel_scene.instantiate()
	game_director.add_child(first_arena)
	first_arena.setup_duel(
		macro_map.player_token.get_humanoid_core(),
		original_record
	)
	await process_frame

	var damaged_hp: float = first_arena.enemy_core.body.limb_hp[
		GameEnums.LimbRegion.LEFT_ARM
	] - 4.0
	first_arena.enemy_core.body.apply_targeted_hit(
		GameEnums.LimbRegion.LEFT_ARM,
		4.0,
		0.0
	)

	var first_weapon: ItemData = first_arena.enemy_core.inventory.paper_doll.get(
		GameEnums.EquipmentSlot.HANDS
	)
	var weapon_instance_id := first_weapon.instance_id if first_weapon else ""
	if first_weapon and first_weapon.is_ranged():
		first_weapon.current_magazine = 1

	world_state.update_entity_runtime(
		enemy_id,
		first_arena.capture_enemy_runtime_state()
	)
	first_arena.turn_manager.halt_loop()
	first_arena.queue_free()
	await process_frame

	var second_arena = duel_scene.instantiate()
	game_director.add_child(second_arena)
	second_arena.setup_duel(
		macro_map.player_token.get_humanoid_core(),
		world_state.get_entity(enemy_id)
	)
	await process_frame

	var restored_hp: float = second_arena.enemy_core.body.limb_hp[
		GameEnums.LimbRegion.LEFT_ARM
	]
	if not is_equal_approx(restored_hp, damaged_hp):
		_fail("Enemy injury did not survive runtime reconstruction.")
		return

	var restored_weapon: ItemData = second_arena.enemy_core.inventory.paper_doll.get(
		GameEnums.EquipmentSlot.HANDS
	)
	if restored_weapon and restored_weapon.instance_id != weapon_instance_id:
		_fail("Enemy item identity changed during runtime reconstruction.")
		return

	if restored_weapon and restored_weapon.is_ranged():
		if restored_weapon.current_magazine != 1:
			_fail("Firearm runtime state did not survive reconstruction.")
			return

	print("[TEST PASS] Neutral world records and item instances preserve runtime state.")
	quit(0)

func _verify_item_instance_isolation() -> bool:
	var pistol_definition := load(
		"res://ItemCore/Items/makeshift_sidearm.tres"
	) as ItemData
	var first := pistol_definition.create_runtime_instance()
	var second := pistol_definition.create_runtime_instance()

	if first.instance_id == second.instance_id:
		_fail("Two runtime items received the same identity.")
		return false

	first.current_magazine = 0
	if second.current_magazine != second.max_magazine:
		_fail("Mutating one firearm changed another firearm instance.")
		return false

	var restored := ItemData.from_runtime_state(first.to_runtime_state())
	if restored.instance_id != first.instance_id or restored.current_magazine != 0:
		_fail("Item runtime state failed its round trip.")
		return false

	return true

func _fail(message: String) -> void:
	push_error("[TEST FAIL] " + message)
	quit(1)
