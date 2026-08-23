extends SceneTree

const _SENTINEL := Vector2i(999999, 999999)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var packed := load("res://SystemCore/game_director.tscn") as PackedScene
	var director := packed.instantiate()
	root.add_child(director)
	await process_frame
	await process_frame
	await process_frame

	var macro := director.get_node_or_null("MainWorld") as MacroGameManager
	var state := root.get_node_or_null("WorldState") as RuntimeStateStore
	if macro == null or state == null or macro.player_token == null:
		_fail("Macro collision movement scene did not initialize.")
		return

	var origin: Vector2i = macro.player_token.current_hex_coords
	var live_coords := _find_adjacent_free_hex(macro, state, origin)
	if live_coords == _SENTINEL:
		_fail("No adjacent free hex was available for the live collision fixture.")
		return
	macro.spawn_procedural_enemy(
		live_coords,
		GameEnums.Faction.SCAVENGER_CELL,
		0
	)
	var live_id := state.get_entity_id_at(live_coords)
	if live_id.is_empty() or not state.is_entity_active(live_id):
		_fail("Live collision fixture did not enter the active occupancy index.")
		return

	macro.call("_select_hex_for_hud", live_coords)
	macro.call("_try_travel_to_selected_hex")
	await create_timer(MacroPlayer.WALK_DURATION_SECONDS + 0.35).timeout
	await process_frame
	if state.player_record.coords != live_coords:
		_fail("Player movement still rolled back on live entity contact.")
		return
	if macro.player_token.current_hex_coords != live_coords:
		_fail("Player token did not remain on the contacted live entity hex.")
		return
	if macro.get_pending_interaction_type() != GameEnums.MacroInteractionType.ENTITY_COLLISION:
		_fail("Live entity contact did not open an entity collision interaction.")
		return

	macro.close_macro_interaction()
	if not state.set_entity_life_state(live_id, GameEnums.EntityLifeState.DEAD):
		_fail("Live collision fixture could not be converted into a corpse.")
		return
	macro.debug_teleport_player(origin)
	macro.npc_evaluation_radius = 0

	var corpse_coords := _find_adjacent_free_hex(macro, state, origin)
	if corpse_coords == _SENTINEL:
		_fail("No adjacent free hex was available for the corpse fixture.")
		return
	var corpse := EntityRecord.new()
	corpse.entity_id = "movement_corpse"
	corpse.kind = GameEnums.RuntimeEntityKind.NPC
	corpse.life_state = GameEnums.EntityLifeState.DEAD
	corpse.world_status = GameEnums.EntityWorldStatus.HOSTILE
	corpse.coords = corpse_coords
	corpse.runtime = {"is_dead": true, "inventory_items": []}
	if state.register_entity(corpse) != corpse.entity_id:
		_fail("Dead corpse fixture could not be registered.")
		return
	if state.has_entity_at(corpse_coords):
		_fail("Dead corpse fixture incorrectly occupied the active index.")
		return

	macro.call("_select_hex_for_hud", corpse_coords)
	macro.call("_try_travel_to_selected_hex")
	await create_timer(MacroPlayer.WALK_DURATION_SECONDS + 0.35).timeout
	await process_frame
	if state.player_record.coords != corpse_coords:
		_fail("Player could not move onto a corpse hex.")
		return
	if macro.player_token.current_hex_coords != corpse_coords:
		_fail("Player token did not arrive on the corpse hex.")
		return
	if macro.get_pending_interaction_type() != GameEnums.MacroInteractionType.NONE:
		_fail("Corpse hex incorrectly opened an entity interaction.")
		return
	if not state.get_entity_snapshot_at(corpse_coords).is_empty():
		_fail("Corpse leaked through the active coordinate snapshot query.")
		return

	print("MACRO_ENTITY_COLLISION_MOVEMENT_SMOKE: PASS")
	director.queue_free()
	await process_frame
	quit(0)


func _find_adjacent_free_hex(
	macro: MacroGameManager,
	state: RuntimeStateStore,
	origin: Vector2i
) -> Vector2i:
	for delta in MacroGameManager.HEX_NEIGHBORS:
		var coords: Vector2i = origin + (delta as Vector2i)
		var hex_data := macro.world_generator.get_hex_at(coords)
		if hex_data == null or not hex_data.is_passable():
			continue
		if state.has_entity_at(coords) or state.has_ground_items(coords):
			continue
		return coords
	return _SENTINEL


func _fail(message: String) -> void:
	push_error("[MACRO_ENTITY_COLLISION_MOVEMENT] " + message)
	quit(1)
