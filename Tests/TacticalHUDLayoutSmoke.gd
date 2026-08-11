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
	if hud.target_heading.visible:
		_fail("Enemy condition was exposed before an actor was selected.")
	if hud.context_menu.visible:
		_fail("Passive snapshot/quote refresh opened an action menu at %s." % viewport_size)

	if not hud.size.is_equal_approx(Vector2(viewport_size)):
		_fail("HUD did not fill %s; got %s." % [viewport_size, hud.size])
	var arena: Control = hud.get_node("Arena")
	var player_card: Control = hud.get_node("PlayerCard")
	var actor_intent: Label = hud.actor_intent
	if actor_intent == null:
		_fail("Player card did not expose the production AI intent label at %s." % viewport_size)
	var inventory_panel: Control = hud.get_node("InventoryPanel")
	var hex_panel: Control = hud.get_node("HexPanel")
	_assert_inside(hud.get_global_rect(), hud.right_panel.get_global_rect(), "inspector", viewport_size)
	for pair in [[player_card, "player health"], [inventory_panel, "inventory"], [hex_panel, "hex inspector"]]:
		_assert_inside(hud.get_global_rect(), (pair[0] as Control).get_global_rect(), str(pair[1]), viewport_size)
	if hud.has_node("Bottom") or hud.has_node("CommandWheel"):
		_fail("Legacy bottom rail or command wheel still exists at %s." % viewport_size)
	var expected_preview_width := clampf(float(viewport_size.x) * 0.16, 240.0, 300.0)
	if not is_equal_approx(hud.right_panel.size.x, expected_preview_width) or not is_equal_approx(hud.right_panel.size.y, 76.0):
		_fail("Enemy panel did not begin as a compact preview at %s: %s." % [viewport_size, hud.right_panel.size])
	if not hud.expanded_corner_id().is_empty():
		_fail("A corner panel began expanded at %s." % viewport_size)
	if hud.find_child("PlayerVerbBar", true, false) != null:
		_fail("Persistent Move/Attack/Aim/Weapon command bar survived at %s." % viewport_size)
	if hud.end_turn_button == null or not hud.end_turn_button.visible:
		_fail("End Turn was not retained in the global turn strip at %s." % viewport_size)
	var weapon_snapshot := _sample_snapshot(12, 1)
	var weapon_actor: Dictionary = weapon_snapshot.actors[0]
	weapon_actor.ranged_weapon = {
		"instance_id": "smoke_revolver",
		"definition_id": "revolver",
		"name": "Smoke Revolver",
		"current_magazine": 0,
		"max_magazine": 6,
		"cycle_loads_one_round": true,
		"needs_cycling": false,
		"condition": 12.0,
		"readiness": {"reason": "jammed"},
	}
	var jam_quotes := _sample_quotes()
	var jam_reload := _quote_for(jam_quotes, "reload")
	jam_reload.deny("weapon_not_ready", "Clear the malfunction before reloading.")
	hud.show_snapshot(weapon_snapshot)
	hud.show_quotes(jam_quotes)
	await process_frame
	var weapon_button := hud._weapon_action_buttons.get("clear_malfunction") as Button
	var reload_button := hud._weapon_action_buttons.get("reload") as Button
	if reload_button == null:
		_fail("Reload was not kept discoverable for an equipped firearm at %s." % viewport_size)
	elif not reload_button.disabled or not reload_button.text.contains("CLEAR JAM FIRST"):
		_fail("Jammed firearm did not keep Reload gray with an inline reason at %s." % viewport_size)
	if weapon_button == null or not weapon_button.text.begins_with("CLEAR MALFUNCTION") or weapon_button.disabled:
		_fail("Loadout did not expose the authored jam-clearing action at %s." % viewport_size)
	else:
		var routed_weapon := {"id": ""}
		hud.action_selected.connect(func(action_id: String) -> void: routed_weapon.id = action_id, CONNECT_ONE_SHOT)
		weapon_button.pressed.emit()
		if routed_weapon.id != "clear_malfunction":
			_fail("Weapon verb did not route to clear_malfunction at %s." % viewport_size)
	weapon_actor.current_magazine = 6
	weapon_actor.readiness = {"reason": "ready"}
	var full_quotes := _sample_quotes()
	_quote_for(full_quotes, "reload").deny("reload_not_needed", "The magazine is full.")
	_quote_for(full_quotes, "cycle").deny("cycle_not_needed", "The weapon does not need cycling.")
	hud.show_snapshot(weapon_snapshot)
	hud.show_quotes(full_quotes)
	var full_reload := hud._weapon_action_buttons.get("reload") as Button
	if full_reload == null or not full_reload.disabled or not full_reload.text.contains("MAGAZINE FULL"):
		_fail("Loaded firearm did not show gray Reload — Magazine Full at %s." % viewport_size)
	var full_cycle := hud._weapon_action_buttons.get("cycle") as Button
	if full_cycle == null or not full_cycle.disabled or not full_cycle.text.contains("WEAPON ALREADY READY"):
		_fail("Ready cycle-capable firearm did not show gray Cycle with its inline reason at %s." % viewport_size)
	hud.show_snapshot(_sample_snapshot(12, 1))
	hud.show_quotes(_sample_quotes())
	await process_frame
	for panel_id in ["health", "loadout", "site", "hostile"]:
		if (hud._corner_contents[panel_id] as Control).visible:
			_fail("Compact panel %s exposed its full contents at %s." % [panel_id, viewport_size])
	var compact_safe_width: float = hud.arena_view._camera_safe_rect.size.x
	hud._toggle_corner_panel("hostile")
	await process_frame
	var expected_expanded_width := clampf(float(viewport_size.x) * 0.30, 340.0, 460.0)
	if hud.expanded_corner_id() != "hostile" or not is_equal_approx(hud.right_panel.size.x, expected_expanded_width):
		_fail("Hostile preview did not expand into the right work area at %s." % viewport_size)
	if not (hud._corner_buttons["hostile"] as Button).text.contains("[CLOSE]"):
		_fail("Expanded corner preview did not advertise its collapse affordance at %s." % viewport_size)
	for panel_id in ["health", "loadout", "site"]:
		if (hud._corner_contents[panel_id] as Control).visible:
			_fail("Expanding hostile left %s expanded at %s." % [panel_id, viewport_size])
	if hud.arena_view._camera_safe_rect.size.x >= compact_safe_width:
		_fail("Expanded hostile panel did not reserve a camera-safe right inset at %s." % viewport_size)
	hud._toggle_corner_panel("site")
	await process_frame
	if hud.expanded_corner_id() != "site" or (hud._corner_contents["hostile"] as Control).visible:
		_fail("Corner expansion was not exclusive at %s." % viewport_size)
	hud._unhandled_input(_key_event(KEY_ESCAPE))
	await process_frame
	if not hud.expanded_corner_id().is_empty() or hud.arena_view._camera_safe_rect.size.x < compact_safe_width:
		_fail("Escape did not restore the compact camera-safe layout at %s." % viewport_size)
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
	var context_phase: int = hud.interaction.phase
	var context_was_visible := hud.context_menu.visible
	hud.show_snapshot(hud.snapshot)
	hud.show_quotes(hud.quotes)
	if hud.interaction.phase != context_phase or hud.context_menu.visible != context_was_visible:
		_fail("Passive refresh changed the active target interaction at %s." % viewport_size)
	for button in hud.context_actions.get_children():
		var action_id := str(button.get_meta("action_id", ""))
		if action_id in ["fire", "aimed_fire", "reload", "cycle", "clear_malfunction", "brace"]:
			_fail("Capability-inapplicable action %s leaked into an unarmed enemy menu." % action_id)
	if not hud.context_menu.is_ancestor_of(hud.confirm_button) or not hud.context_menu.is_ancestor_of(hud.cancel_button):
		_fail("Confirm/Cancel are not local to the contextual menu.")
	if hud.context_menu.visible:
		_assert_inside(arena.get_global_rect(), hud.context_menu.get_global_rect(), "context menu", viewport_size)
	var target_item_button: Button
	for child in hud.target_items.get_children():
		if child is Button:
			target_item_button = child
			break
	if target_item_button == null:
		_fail("Selected enemy did not expose its carried item list.")
	else:
		target_item_button.pressed.emit()
		var strip_visible := false
		for child in hud.context_actions.get_children():
			if child is Button and str(child.get_meta("action_id", "")) == "strip":
				strip_visible = true
		if not strip_visible:
			_fail("Selecting a carried enemy item did not expose Strip Body.")
	var aimed_button: Button
	for child in hud.context_actions.get_children():
		if child is Button and (child as Button).text.contains("AIM..."):
			aimed_button = child
			break
	if aimed_button != null and not aimed_button.disabled:
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
		# Manual body-region aiming is retired in the unified combat contract;
		# Attack resolves the region authoritatively and no persistent aim panel
		# should be opened from a passive target refresh.
		if hud.aim_target_panel.visible:
			_fail("Retired manual aiming panel opened without an authored action.")
	hud.arena_view.sector_selected.emit(Vector2i(2, 0))
	await process_frame
	if not hud.target_heading.visible or hud.target_heading.text != "FIELD CONDITION":
		_fail("Selecting the player did not expose the player's condition inspector.")
	var wound_button: Button
	for child in hud.wounds.get_children():
		if child is Button:
			wound_button = child
			break
	if wound_button == null:
		_fail("Player wounds were not selectable from the condition inspector.")
	else:
		wound_button.pressed.emit()
		_toggle_items_for_test(hud)
		var treat_visible := false
		for child in hud.context_actions.get_children():
			if child is Button and str(child.get_meta("action_id", "")) == "treat":
				treat_visible = true
		if not treat_visible:
			_fail("Selecting a player wound and treatment item did not expose Treat Wound.")
	var ground_button: Button
	hud.arena_view.sector_selected.emit(Vector2i(5, 0))
	await process_frame
	for child in hud.ground_items.get_children():
		if child is Button:
			ground_button = child
			break
	if ground_button == null:
		_fail("Selected sector did not expose its ground item.")
	else:
		ground_button.pressed.emit()
		var pickup_visible := false
		for child in hud.context_actions.get_children():
			if child is Button and str(child.get_meta("action_id", "")) == "pick_up":
				pickup_visible = true
		if not pickup_visible:
			_fail("Selecting a ground item did not expose Pick Up.")
	hud.arena_view.sector_selected.emit(Vector2i(4, 0))
	await process_frame
	var interact_visible := false
	for child in hud.context_actions.get_children():
		if child is Button and str(child.get_meta("action_id", "")) == "interact":
			interact_visible = true
	if not interact_visible:
		_fail("Selecting an object sector did not expose Interact.")
	var movement_confirmation := {"value": false}
	hud.action_confirmed.connect(func() -> void: movement_confirmation.value = true)
	hud.current_quote = null
	hud.arena_view.sector_selected.emit(Vector2i(3, 0))
	var move_quote := CombatActionQuote.new()
	move_quote.action_id = "move"
	move_quote.actor_id = "player"
	move_quote.target_sector = Vector2i(3, 0)
	move_quote.ap_cost = 2
	move_quote.legal = true
	hud.show_route_quote(move_quote)
	if hud.context_actions.visible or hud.context_title.text != "ROUTE PREVIEW":
		_fail("A staged move reused stale contextual verbs instead of the route-preview surface.")
	hud.arena_view.sector_selected.emit(Vector2i(3, 0))
	if not bool(movement_confirmation.value):
		_fail("A second click on a staged move did not confirm it.")
	hud.show_reaction({"actions": ["block", "dodge"], "title": "TEST ATTACK"})
	await process_frame
	if hud.reaction_actions.get_child_count() != 3 or not hud.reaction_actions.get_child(0).has_focus():
		_fail("Reaction prompt did not expose actions with initial focus.")
	hud.hide_reaction()
	hud.items.visible = false
	hud._unhandled_input(_key_event(KEY_I))
	if not hud.items.visible:
		_fail("Inventory shortcut did not open the pack.")
	hud._unhandled_input(_key_event(KEY_I))
	if hud.items.visible:
		_fail("Inventory shortcut did not close the pack.")
	var end_turn_button := hud.end_turn_button
	if end_turn_button == null or end_turn_button.disabled:
		_fail("End Turn was not available from the selected player context.")
	else:
		end_turn_button.pressed.emit()
		if not hud.local_confirmation.visible or not hud.context_menu.visible:
			_fail("End Turn did not request deliberate confirmation from the top strip.")
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
	# At very wide viewports the complete logical lane fits inside the safe
	# camera rect even after zooming, so a bounded pan correctly remains zero.
	if viewport_size.x <= 1280 and hud.arena_view.camera_pan().is_zero_approx():
		_fail("Arena middle-drag input did not pan the bounded camera after zooming at %s." % viewport_size)
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
			"object": {"id": "crate", "label": "Supply Crate"} if x == 4 and y == center_y else {},
			"ground_item_instance_ids": ["ground_item"] if x == 5 and y == center_y else [],
			"ground_items": [{"instance_id": "ground_item", "name": "Loose Bandage", "access": "ground", "condition": 12.0}] if x == 5 and y == center_y else [],
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
		"initiative_order": ["enemy", "player"],
		"reserved_ap": {"player": 0},
		"actors": [
			{"actor_id": "player", "team_id": "player", "name": "Player", "sector": Vector2i(mini(2, width - 1), center_y), "posture": "standing", "facing": "east", "blood": 12.0, "pain": 0.0, "shock": 0.0, "consciousness": 12.0, "region_function": function, "wounds": [{"wound_id": "player_wound", "body_region": GameEnums.LimbRegion.LEFT_ARM, "wound_type": "laceration", "severity": 4.0, "bleeding_rate": 1.5, "stabilized": false}], "items": [{"instance_id": "bandage", "name": "Field Bandage", "access": "accessible", "condition": 12.0}], "ranged_weapon": {}, "melee_weapon": {}},
			{"actor_id": "enemy", "team_id": "enemy", "name": "Scavenger", "sector": Vector2i(width - 1, center_y), "posture": "standing", "facing": "west", "blood": 10.0, "pain": 2.0, "shock": 1.0, "consciousness": 11.0, "dead": true, "incapacitated": true, "region_function": function, "wounds": [], "items": [{"instance_id": "enemy_weapon", "name": "Enemy Knife", "access": "carried", "condition": 12.0}], "ranged_weapon": {}, "melee_weapon": {}},
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


func _quote_for(source: Array[CombatActionQuote], action_id: String) -> CombatActionQuote:
	for action_quote in source:
		if action_quote.action_id == action_id:
			return action_quote
	return null


func _toggle_items_for_test(hud: TacticalCombatHUD) -> void:
	if not hud.items.visible:
		hud._toggle_pack()
	for child in hud.items.get_children():
		if child is Button:
			child.pressed.emit()
			return


func _key_event(keycode: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	event.keycode = keycode
	event.pressed = true
	return event


func _assert_inside(parent_rect: Rect2, child_rect: Rect2, label: String, viewport_size: Vector2i) -> void:
	if child_rect.position.x < parent_rect.position.x - 0.5 or child_rect.end.x > parent_rect.end.x + 0.5:
		_fail("%s overflowed horizontally at %s: %s outside %s." % [label, viewport_size, child_rect, parent_rect])
	if child_rect.position.y < parent_rect.position.y - 0.5 or child_rect.end.y > parent_rect.end.y + 0.5:
		_fail("%s overflowed vertically at %s: %s outside %s." % [label, viewport_size, child_rect, parent_rect])


func _fail(message: String) -> void:
	_failures.append(message)
