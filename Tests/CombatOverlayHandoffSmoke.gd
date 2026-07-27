extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load("res://SystemCore/game_director.tscn") as PackedScene
	if packed == null:
		_fail("Could not load GameDirector.")
		return
	var director := packed.instantiate() as GameDirector
	root.add_child(director)
	await process_frame
	await process_frame

	var macro := director.macro_map
	if macro == null or not macro.debug_spawn_enemy_near_player():
		_fail("Could not create the collision probe.")
		return
	var enemy_coords: Vector2i = macro.active_enemies.keys()[-1]
	var enemy := macro.active_enemies[enemy_coords] as MacroEnemy
	macro.begin_entity_collision(
		enemy.entity_id,
		enemy_coords,
		macro.player_token.current_hex_coords
	)
	await process_frame

	var stage := macro.macro_hud.get_exploration_stage()
	if (
		not stage.is_open()
		or not stage._dim.visible
		or stage._root.mouse_filter != Control.MOUSE_FILTER_STOP
	):
		_fail("Collision modal did not open as a blocking presentation.")
		return
	var ambush_index: int = stage._choice_ids.find(
		MacroEntityCollisionResolver.CHOICE_AMBUSH
	)
	if ambush_index < 0:
		_fail("Collision modal did not expose AMBUSH.")
		return
	stage._choice_buttons[ambush_index].pressed.emit()
	await process_frame
	var standard_index: int = stage._choice_ids.find(
		MacroEntityCollisionResolver.CHOICE_AMBUSH_STANDARD
	)
	if standard_index < 0:
		_fail("Ambush modal did not expose STANDARD.")
		return
	stage._choice_buttons[standard_index].pressed.emit()
	await process_frame
	await process_frame

	if director.get_active_arena() == null:
		_fail("Collision selection did not create combat.")
		return
	if (
		stage.is_open()
		or stage._dim.visible
		or stage._root.mouse_filter != Control.MOUSE_FILTER_IGNORE
	):
		_fail("Collision dimmer or input blocker survived combat handoff.")
		return
	for child in macro.get_children():
		if child is CanvasLayer and (child as CanvasLayer).visible:
			_fail("Macro CanvasLayer survived combat: %s" % child.name)
			return

	director._restore_macro_canvas_layers()
	var vignette := macro.get_node("VisionVignette") as CanvasLayer
	var node_map := macro.get_node("NodeMapSystem") as CanvasLayer
	if not vignette.visible or node_map.visible:
		_fail("Macro CanvasLayer visibility was not restored exactly.")
		return

	director.get_active_arena().turn_manager.halt_loop()
	director.queue_free()
	await process_frame
	print(
		"[COMBAT_OVERLAY_HANDOFF_SMOKE] PASS // "
		+ "collision clicks route to combat without leaked macro layers"
	)
	quit(0)


func _fail(message: String) -> void:
	push_error("[COMBAT_OVERLAY_HANDOFF_SMOKE] FAIL // " + message)
	quit(1)
