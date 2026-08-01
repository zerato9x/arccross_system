extends SceneTree

const HUD_SCENE := preload("res://CombatCore/Tactical/TacticalCombatHUD.tscn")

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	for viewport_size in [Vector2i(1152, 648), Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(2560, 1080)]:
		await _verify_size(viewport_size)
	if _failures.is_empty():
		print("TACTICAL_HUD_LAYOUT_SMOKE: PASS")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	quit(1)


func _verify_size(viewport_size: Vector2i) -> void:
	var viewport := SubViewport.new()
	viewport.size = viewport_size
	get_root().add_child(viewport)
	var hud: TacticalCombatHUD = HUD_SCENE.instantiate()
	viewport.add_child(hud)
	await process_frame
	hud.configure_action_catalog(load("res://CombatCore/Tactical/default_combat_action_catalog.tres"))
	hud.show_snapshot(_sample_snapshot(12, 1))
	hud.show_quotes(_sample_quotes())
	await process_frame
	await process_frame

	if not hud.size.is_equal_approx(Vector2(viewport_size)):
		_fail("HUD did not fill %s; got %s." % [viewport_size, hud.size])
	var arena: Control = hud.get_node("Arena")
	var player_card: Control = hud.get_node("PlayerCard")
	var inventory_panel: Control = hud.get_node("InventoryPanel")
	var hex_panel: Control = hud.get_node("HexPanel")
	_assert_inside(hud.get_global_rect(), hud.right_panel.get_global_rect(), "inspector", viewport_size)
	for pair in [[player_card, "player health"], [inventory_panel, "inventory"], [hex_panel, "hex inspector"]]:
		_assert_inside(hud.get_global_rect(), (pair[0] as Control).get_global_rect(), str(pair[1]), viewport_size)
	if hud.has_node("Bottom") or hud.has_node("CommandWheel"):
		_fail("Legacy bottom rail or command wheel still exists at %s." % viewport_size)
	if hud.right_panel.size.x < 340.0 or hud.right_panel.size.x > 360.0:
		_fail("Enemy panel width escaped its corner target at %s: %.1f." % [viewport_size, hud.right_panel.size.x])
	if arena.size.x < 640.0:
		_fail("Arena lost its minimum usable width at %s: %.1f." % [viewport_size, arena.size.x])
	if not is_equal_approx(player_card.position.x, inventory_panel.position.x) or inventory_panel.position.y <= player_card.position.y:
		_fail("Player health and inventory no longer form the left corner stack at %s." % viewport_size)
	if not is_equal_approx(hex_panel.position.x, hud.right_panel.position.x) or hud.right_panel.position.y <= hex_panel.position.y:
		_fail("Hex and enemy panels no longer form the right corner stack at %s." % viewport_size)
	for topology in [Vector2i(6, 3), Vector2i(7, 5)]:
		hud.show_snapshot(_sample_snapshot(topology.x, topology.y))
		await process_frame
		if hud.arena_view.snapshot.get("width", 0) != topology.x or hud.arena_view.snapshot.get("height", 0) != topology.y:
			_fail("HUD did not accept topology %s." % topology)
	hud.show_snapshot(_sample_snapshot(12, 1))

	hud.arena_view.sector_selected.emit(Vector2i(11, 0))
	await process_frame
	await process_frame
	for button in hud.context_actions.get_children():
		var action_id := str(button.get_meta("action_id", ""))
		if action_id in ["fire", "aimed_fire", "reload", "cycle", "clear_malfunction", "brace"]:
			_fail("Capability-inapplicable action %s leaked into an unarmed enemy menu." % action_id)
	if not hud.context_menu.is_ancestor_of(hud.confirm_button) or not hud.context_menu.is_ancestor_of(hud.cancel_button):
		_fail("Confirm/Cancel are not local to the contextual menu.")
	if hud.context_menu.visible:
		_assert_inside(arena.get_global_rect(), hud.context_menu.get_global_rect(), "context menu", viewport_size)
	var aimed_button: Button
	for child in hud.context_actions.get_children():
		if child is Button and str(child.get_meta("action_id", "")) == "aimed_strike":
			aimed_button = child
			break
	if aimed_button != null:
		aimed_button.pressed.emit()
		if not hud.aim_target_panel.visible or hud.context_menu.visible:
			_fail("Aimed attack did not replace the remote context trip with its target panel.")
		hud.aim_target_body.region_selected.emit(GameEnums.LimbRegion.HEAD)
		var aimed_quote := CombatActionQuote.new()
		aimed_quote.action_id = "aimed_strike"
		aimed_quote.actor_id = "player"
		aimed_quote.target_sector = Vector2i(11, 0)
		aimed_quote.ap_cost = 4
		aimed_quote.legal = true
		hud.show_quote(aimed_quote)
		if hud.aim_confirm_button.disabled or not hud.aim_target_panel.is_ancestor_of(hud.aim_confirm_button):
			_fail("Aimed targeting did not keep region selection and confirmation together.")
		_assert_inside(hud.aim_target_panel.get_global_rect(), hud.aim_confirm_button.get_global_rect(), "aim confirm", viewport_size)
		_assert_inside(hud.aim_target_panel.get_global_rect(), hud.aim_cancel_button.get_global_rect(), "aim cancel", viewport_size)
		hud.aim_cancel_button.pressed.emit()
	else:
		_fail("Aimed Strike was unavailable for targeting-panel verification.")
	hud.arena_view.sector_selected.emit(Vector2i(2, 0))
	await process_frame
	var end_turn_button: Button
	for child in hud.context_actions.get_children():
		if child is Button and str(child.get_meta("action_id", "")) == "end_turn":
			end_turn_button = child
			break
	if end_turn_button == null:
		_fail("End Turn was not available from the selected player context.")
	else:
		end_turn_button.pressed.emit()
		if not hud.local_confirmation.visible or hud.confirm_button.disabled:
			_fail("End Turn did not stage with local confirmation.")
		hud.cancel_button.pressed.emit()
		if hud.current_quote != null:
			_fail("Cancel left a staged request behind.")
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	wheel.position = arena.size * 0.5
	hud.arena_view.gui_input.emit(wheel)
	if hud.arena_view.camera_zoom() <= 1.0:
		_fail("Arena wheel input did not zoom the bounded camera.")
	var pan_start := InputEventMouseButton.new()
	pan_start.button_index = MOUSE_BUTTON_MIDDLE
	pan_start.pressed = true
	pan_start.position = arena.size * 0.5
	hud.arena_view.gui_input.emit(pan_start)
	var pan_motion := InputEventMouseMotion.new()
	pan_motion.position = pan_start.position + Vector2(36.0, 20.0)
	hud.arena_view.gui_input.emit(pan_motion)
	var pan_end := InputEventMouseButton.new()
	pan_end.button_index = MOUSE_BUTTON_MIDDLE
	pan_end.pressed = false
	pan_end.position = pan_motion.position
	hud.arena_view.gui_input.emit(pan_end)
	if hud.arena_view.camera_pan().is_zero_approx():
		_fail("Arena middle-drag input did not pan the bounded camera after zooming.")
	viewport.queue_free()
	await process_frame


func _sample_snapshot(width: int, height: int) -> Dictionary:
	var sectors: Array[Dictionary] = []
	var center_y := floori(float(height) * 0.5)
	for y in range(height):
		for x in range(width):
			sectors.append({
			"coords": Vector2i(x, y),
			"surface_id": "plains",
			"surface_label": "Short Grass",
			"movement_modifier": 0,
			"concealment": 0.0,
			"cover_edges": {},
			"hazards": {},
			"object": {},
			"occupant_id": "player" if x == mini(2, width - 1) and y == center_y else ("enemy" if x == width - 1 and y == center_y else ""),
			})
	var function := {
		"head": 12.0,
		"upper_torso": 12.0,
		"lower_torso": 12.0,
		"left_arm": 12.0,
		"right_arm": 12.0,
		"left_leg": 12.0,
		"right_leg": 12.0,
	}
	return {
		"round": 1,
		"ap": 12,
		"active_actor_id": "player",
		"reserved_ap": {"player": 0},
		"actors": [
			{"actor_id": "player", "team_id": "player", "name": "Player", "sector": Vector2i(mini(2, width - 1), center_y), "posture": "standing", "facing": "east", "blood": 12.0, "pain": 0.0, "shock": 0.0, "consciousness": 12.0, "region_function": function, "wounds": [], "items": [], "ranged_weapon": {}, "melee_weapon": {}},
			{"actor_id": "enemy", "team_id": "enemy", "name": "Scavenger", "sector": Vector2i(width - 1, center_y), "posture": "standing", "facing": "west", "blood": 10.0, "pain": 2.0, "shock": 1.0, "consciousness": 11.0, "region_function": function, "wounds": [], "items": [], "ranged_weapon": {}, "melee_weapon": {}},
		],
		"arena": {"width": width, "height": height, "presentation_style": "duel_lane" if height == 1 else "tactical_grid", "sectors": sectors, "facings": {"player": "east", "enemy": "west"}, "tactics": {}},
	}


func _sample_quotes() -> Array[CombatActionQuote]:
	var result: Array[CombatActionQuote] = []
	var catalog: CombatActionCatalog = load("res://CombatCore/Tactical/default_combat_action_catalog.tres")
	for definition in catalog.all():
		var quote := CombatActionQuote.new()
		quote.action_id = definition.action_id
		quote.actor_id = "player"
		quote.target_sector = Vector2i(6, 0)
		quote.ap_cost = 3
		quote.legal = true
		quote.has_line_of_sight = true
		result.append(quote)
	return result


func _assert_inside(parent_rect: Rect2, child_rect: Rect2, label: String, viewport_size: Vector2i) -> void:
	if child_rect.position.x < parent_rect.position.x - 0.5 or child_rect.end.x > parent_rect.end.x + 0.5:
		_fail("%s overflowed horizontally at %s: %s outside %s." % [label, viewport_size, child_rect, parent_rect])
	if child_rect.position.y < parent_rect.position.y - 0.5 or child_rect.end.y > parent_rect.end.y + 0.5:
		_fail("%s overflowed vertically at %s: %s outside %s." % [label, viewport_size, child_rect, parent_rect])


func _fail(message: String) -> void:
	_failures.append(message)
