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

	hud._on_sector_selected(Vector2i(2, 0))
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
	hud._on_sector_selected(Vector2i(2, 0))
	hud._unhandled_input(_key(KEY_A))
	hud._unhandled_input(_key(KEY_A))
	if hud.staged_route().back() != Vector2i(0, 0):
		_fail("A did not build a leftward route from the actor.")
	hud._unhandled_input(_key(KEY_D))
	if hud.staged_route().back() != Vector2i(1, 0):
		_fail("D did not retract a leftward route.")

	hud.clear_staged_action()
	hud._on_sector_selected(Vector2i(2, 0))
	for _step in range(9):
		hud._unhandled_input(_key(KEY_D))
	if hud.interaction.phase != CombatInteractionState.Phase.BUMP_MENU:
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
	if hud.interaction.phase != CombatInteractionState.Phase.BUMP_MENU:
		_fail("Bump menu did not reopen after returning to the route.")
	await process_frame
	hud._unhandled_input(_key(KEY_1))
	if hud.interaction.phase not in [CombatInteractionState.Phase.ACTION_PREVIEW, CombatInteractionState.Phase.CONFIRMATION]:
		_fail("Number shortcut did not stage the visible contextual choice.")
	hud._unhandled_input(_key(KEY_ESCAPE))
	if hud.interaction.phase != CombatInteractionState.Phase.BUMP_MENU:
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


func _snapshot() -> Dictionary:
	var actors: Array[Dictionary] = [
		{
			"actor_id": "player",
			"team_id": "player",
			"name": "Player",
			"sector": Vector2i(2, 0),
			"posture": "standing",
			"facing": "east",
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
			"posture": "standing",
			"facing": "west",
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
			"object": {},
			"occupant_id": "player" if x == 2 else ("enemy" if x == 11 else ""),
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
			"presentation_style": "duel_lane",
			"sectors": sectors,
			"facings": {"player": "east", "enemy": "west"},
			"tactics": {},
		},
	}


func _quotes() -> Array[CombatActionQuote]:
	var result: Array[CombatActionQuote] = []
	var catalog: CombatActionCatalog = load("res://CombatCore/Tactical/default_combat_action_catalog.tres")
	for definition in catalog.all():
		var quote := CombatActionQuote.new()
		quote.action_id = definition.action_id
		quote.actor_id = "player"
		quote.target_sector = Vector2i(11, 0)
		quote.legal = true
		quote.ap_cost = definition.base_ap_cost(GameEnums.KineticTier.FLUID, 12)
		result.append(quote)
	return result


func _key(keycode: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.pressed = true
	return event


func _fail(message: String) -> void:
	_failures.append(message)
