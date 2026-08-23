extends SceneTree

const HUD_SCENE := preload("res://CombatCore/Tactical/TacticalCombatHUD.tscn")

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1152, 648)
	get_root().add_child(viewport)
	var hud: TacticalCombatHUD = HUD_SCENE.instantiate()
	viewport.add_child(hud)
	await process_frame
	hud.configure_action_catalog(load("res://CombatCore/Tactical/default_combat_action_catalog.tres"))
	hud.show_snapshot(_snapshot())
	hud.show_quotes(_quotes())
	await process_frame
	await process_frame

	hud._on_arena_context_requested(Vector2i(5, 0), "")
	await process_frame
	if hud._context_shortcuts.is_empty():
		_fail("Building context did not expose an action branch.")
	else:
		hud._context_shortcuts[0].pressed.emit()
		await process_frame
	var move_to_building := _context_button(hud, "move")
	var interact_from_afar := _context_button(hud, "interact")
	if move_to_building == null or move_to_building.disabled:
		_fail("A passable building sector did not expose an enabled Move action.")
	if interact_from_afar == null or not interact_from_afar.disabled:
		_fail("Interact was not disabled while the player was away from the building.")

	hud.show_snapshot(_snapshot(Vector2i(5, 0)))
	hud.show_quotes(_quotes(true))
	await process_frame
	hud._on_arena_context_requested(Vector2i(5, 0), "")
	await process_frame
	if hud._context_shortcuts.is_empty():
		_fail("Occupied building context did not expose an action branch.")
	else:
		hud._context_shortcuts[0].pressed.emit()
		await process_frame
	var interact_on_building := _context_button(hud, "interact")
	if interact_on_building == null or interact_on_building.disabled:
		_fail("Interact did not become enabled on the occupied building sector.")

	hud.show_snapshot(_snapshot())
	hud.show_quotes(_quotes())
	await process_frame

	hud._on_arena_context_requested(Vector2i(2, 0), "")
	hud._unhandled_input(_key(KEY_D))
	hud._unhandled_input(_key(KEY_D))
	hud._unhandled_input(_key(KEY_D))
	if hud.interaction.phase != CombatInteractionState.Phase.ROUTE_PREVIEW:
		_fail("D did not enter route preview.")
	if hud.staged_route().size() != 4 or hud.staged_route().back() != Vector2i(5, 0):
		_fail("D did not extend the route one legal cell at a time.")
	hud._unhandled_input(_key(KEY_A))
	if hud.staged_route().size() != 3 or hud.staged_route().back() != Vector2i(4, 0):
		_fail("Opposite-direction A did not retract one staged route cell.")

	hud.clear_staged_action()
	hud._on_arena_context_requested(Vector2i(2, 0), "")
	hud._unhandled_input(_key(KEY_A))
	hud._unhandled_input(_key(KEY_A))
	if hud.staged_route().back() != Vector2i(0, 0):
		_fail("A did not build a leftward route from the actor.")
	hud._unhandled_input(_key(KEY_D))
	if hud.staged_route().back() != Vector2i(1, 0):
		_fail("D did not retract a leftward route.")

	hud.clear_staged_action()
	hud._on_arena_context_requested(Vector2i(2, 0), "")
	for _step in range(9):
		hud._unhandled_input(_key(KEY_D))
	if hud.interaction.phase != CombatInteractionState.Phase.ACTION_MENU:
		_fail("Entering an occupied cell did not open the bump menu.")
	if hud.interaction.bumped_actor_id != "enemy":
		_fail("Bump menu did not retain the occupied actor identity.")
	if hud.staged_route().back() != Vector2i(10, 0):
		_fail("Bump menu projected origin was not the last empty cell.")

	await process_frame
	var initial_highlight: int = hud.interaction.highlighted_action_index
	hud._unhandled_input(_key(KEY_S))
	if hud.interaction.highlighted_action_index == initial_highlight and hud.context_actions.get_child_count() > 1:
		_fail("S did not advance the contextual highlight.")
	hud._unhandled_input(_key(KEY_A))
	if hud.interaction.phase != CombatInteractionState.Phase.ROUTE_PREVIEW:
		_fail("A did not return from the bump menu to the staged route.")

	# Reopen the bump menu, use the number shortcut, then verify the full chain
	# can still be cancelled without committing a consequential action.
	hud._unhandled_input(_key(KEY_D))
	if hud.interaction.phase != CombatInteractionState.Phase.ACTION_MENU:
		_fail("Bump menu did not reopen after returning to the route.")
	await process_frame
	hud._unhandled_input(_key(KEY_1))
	if hud.interaction.phase not in [CombatInteractionState.Phase.ACTION_PREVIEW, CombatInteractionState.Phase.CONFIRMATION]:
		_fail("Number shortcut did not stage the visible contextual choice.")
	hud._unhandled_input(_key(KEY_ESCAPE))
	if hud.interaction.phase != CombatInteractionState.Phase.ACTION_MENU:
		_fail("First Escape did not cancel only the staged action.")
	hud._unhandled_input(_key(KEY_ESCAPE))
	if hud.interaction.phase != CombatInteractionState.Phase.ROUTE_PREVIEW or hud.staged_route().is_empty():
		_fail("Second Escape did not return to the movement preview.")
	hud._unhandled_input(_key(KEY_ESCAPE))
	if not hud.staged_route().is_empty() or hud.interaction.phase != CombatInteractionState.Phase.IDLE:
		_fail("Third Escape did not clear the remaining movement selection.")

	viewport.queue_free()
	await process_frame
	if _failures.is_empty():
		print("COMBAT_INTERACTION_STATE_SMOKE: PASS")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	quit(1)


func _snapshot(player_sector: Vector2i = Vector2i(2, 0)) -> Dictionary:
	var actors: Array[Dictionary] = [
		{
			"actor_id": "player",
			"team_id": "player",
			"name": "Player",
			"sector": player_sector,
			"blood": 12.0,
			"consciousness": 12.0,
			"pain": 0.0,
			"shock": 0.0,
			"region_function": {},
			"items": [],
			"ranged_weapon": {},
			"melee_weapon": {},
		},
		{
			"actor_id": "enemy",
			"team_id": "enemy",
			"name": "Hostile",
			"sector": Vector2i(11, 0),
			"blood": 10.0,
			"consciousness": 10.0,
			"pain": 0.0,
			"shock": 0.0,
			"region_function": {},
			"items": [],
			"ranged_weapon": {},
			"melee_weapon": {},
		},
	]
	var sectors: Array[Dictionary] = []
	for x in range(12):
		sectors.append({
			"coords": Vector2i(x, 0),
			"surface_id": "plains",
			"surface_label": "Short Grass",
			"movement_modifier": 0,
			"cover_edges": {},
			"hazards": {},
			"object": {"id": "building-1", "label": "BUILDING", "usable": true} if x == 5 else {},
			"occupant_id": "player" if x == player_sector.x else ("enemy" if x == 11 else ""),
		})
	return {
		"round": 1,
		"ap": 12,
		"active_actor_id": "player",
		"initiative_order": ["player", "enemy"],
		"actors": actors,
		"arena": {
			"width": 12,
			"height": 1,
			"presentation_style": "tactical_grid",
			"sectors": sectors,
			"tactics": {},
		},
	}


func _quotes(interact_legal: bool = false) -> Array[CombatActionQuote]:
	var result: Array[CombatActionQuote] = []
	var catalog: CombatActionCatalog = load("res://CombatCore/Tactical/default_combat_action_catalog.tres")
	for definition in catalog.all():
		var quote := CombatActionQuote.new()
		quote.action_id = definition.action_id
		quote.actor_id = "player"
		quote.target_sector = Vector2i(5, 0) if definition.action_id == "interact" else Vector2i(11, 0)
		quote.legal = interact_legal if definition.action_id == "interact" else true
		if definition.action_id == "interact" and not interact_legal:
			quote.denial_code = "target_out_of_range"
			quote.denial_message = "Stand on the selected sector to interact."
		quote.ap_cost = definition.base_ap_cost(GameEnums.KineticTier.FLUID, 12)
		result.append(quote)
	return result


func _context_button(hud: TacticalCombatHUD, action_id: String) -> Button:
	for child in hud.context_actions.get_children():
		var button := child as Button
		if button != null and str(button.get_meta("action_id", "")) == action_id:
			return button
	return null


func _key(keycode: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.pressed = true
	return event


func _fail(message: String) -> void:
	_failures.append(message)
