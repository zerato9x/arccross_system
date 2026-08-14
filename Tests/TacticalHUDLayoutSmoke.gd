extends SceneTree

const HUD_SCENE := preload("res://CombatCore/Tactical/TacticalCombatHUD.tscn")

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	for viewport_size in [
		Vector2i(1152, 648),
		Vector2i(1280, 720),
		Vector2i(1600, 900),
		Vector2i(1920, 1080),
		Vector2i(2560, 1080),
		Vector2i(2560, 1440),
	]:
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
	for pair in [
		[hud.get_node("TopStrip"), "top strip"],
		[hud.get_node("PlayerCard"), "player status"],
		[hud.get_node("CommandDock"), "command dock"],
		[hud.right_panel, "entity card"],
		[hud.hex_panel, "sector context"],
	]:
		_assert_inside(hud.get_global_rect(), (pair[0] as Control).get_global_rect(), str(pair[1]), viewport_size)
	if hud.has_node("Bottom") or hud.has_node("CommandWheel"):
		_fail("Legacy bottom rail or command wheel still exists at %s." % viewport_size)
	if hud.get_node("TopStrip/TopMargin/TopRow/EndTurnButton").visible:
		_fail("Duplicate top-strip End Turn control remained visible at %s." % viewport_size)
	if hud.dock_end_turn_button == null:
		_fail("Command dock did not expose its local End Turn control at %s." % viewport_size)
	if hud.ap_pips.get_child_count() != 12 or hud.cp_pips.get_child_count() != 12:
		_fail("AP/CP did not render exact twelve-pip counters at %s." % viewport_size)
	if hud.actor_intent == null or hud.player_paper_doll == null:
		_fail("Persistent player status card did not expose intent and paper-doll presenters at %s." % viewport_size)

	var player_projection: Dictionary = hud.snapshot.get("presentation", {}).get("actors_by_id", {}).get("player", {})
	var enemy_projection: Dictionary = hud.snapshot.get("presentation", {}).get("actors_by_id", {}).get("enemy", {})
	if not player_projection.has("blood") or not player_projection.has("limbs"):
		_fail("Player projection omitted exact self body/vitals at %s." % viewport_size)
	if enemy_projection.has("blood") or enemy_projection.has("pain") or enemy_projection.has("items") and not enemy_projection.get("items", []).is_empty():
		_fail("Observable hostile projection leaked exact private state at %s." % viewport_size)

	hud._toggle_pack()
	await process_frame
	var pack_item_buttons := 0
	for child in hud.items.get_children():
		if child is Button:
			pack_item_buttons += 1
	if pack_item_buttons != 1:
		_fail("Hands/Quick drawer did not show exactly one accessible item at %s." % viewport_size)
	elif (hud.items.get_child(0) as Button).icon == null:
		_fail("Hands/Quick item did not render its projected icon path at %s." % viewport_size)
	hud._toggle_pack()

	hud.arena_view.inspect_requested.emit(Vector2i(11, 0), "enemy")
	await process_frame
	if not hud.right_panel.visible or hud.hex_panel.visible:
		_fail("Selecting an entity did not switch to the relationship-neutral card at %s." % viewport_size)
	if hud.target_vitals.visible:
		_fail("Observable hostile selection exposed exact secondary vitals at %s." % viewport_size)
	if not bool(hud.target_body.actor_snapshot.get("qualitative_only", false)):
		_fail("Observable hostile body map did not use qualitative bands at %s." % viewport_size)
	if hud.target_items.get_child_count() != 0:
		_fail("Relationship-neutral entity card exposed carried inventory at %s." % viewport_size)

	hud.arena_view.context_requested.emit(Vector2i(11, 0), "enemy", hud.global_position + Vector2(viewport_size) * 0.75)
	await process_frame
	var phase_before_refresh: int = hud.interaction.phase
	var menu_before_refresh: bool = hud.context_menu.visible
	hud.show_snapshot(hud.snapshot)
	hud.show_quotes(hud.quotes)
	if hud.interaction.phase != phase_before_refresh or hud.context_menu.visible != menu_before_refresh:
		_fail("Passive snapshot refresh changed staged interaction state at %s." % viewport_size)
	if hud.context_menu.visible:
		_assert_inside(hud.get_global_rect(), hud.context_menu.get_global_rect(), "context menu", viewport_size)

	hud.arena_view.inspect_requested.emit(Vector2i(2, 0), "player")
	await process_frame
	if hud.right_panel.visible or not hud.player_card.visible:
		_fail("Selecting the player did not focus the persistent top-left status card at %s." % viewport_size)
	var wound_button: Button
	for child in hud.player_wounds.get_children():
		if child is Button:
			wound_button = child
			break
	if wound_button == null:
		_fail("Player urgent wound remained non-selectable at %s." % viewport_size)

	for topology in [Vector2i(6, 3), Vector2i(7, 5)]:
		hud.show_snapshot(_sample_snapshot(topology.x, topology.y))
		await process_frame
		if hud.arena_view.snapshot.get("width", 0) != topology.x or hud.arena_view.snapshot.get("height", 0) != topology.y:
			_fail("HUD did not accept topology %s." % topology)

	var corner_positions: Array[Vector2] = []
	var corners := [Vector2i(0, 0), Vector2i(6, 0), Vector2i(0, 4), Vector2i(6, 4)]
	var anchors := [
		hud.global_position + Vector2(1.0, 1.0),
		hud.global_position + Vector2(viewport_size.x - 1.0, 1.0),
		hud.global_position + Vector2(1.0, viewport_size.y - 1.0),
		hud.global_position + Vector2(viewport_size.x - 1.0, viewport_size.y - 1.0),
	]
	for index in corners.size():
		var corner: Vector2i = corners[index]
		hud.selected_sector = corner
		hud._context_pointer_anchor = anchors[index]
		hud.context_menu.visible = true
		hud._position_context_menu()
		await process_frame
		_assert_inside(hud.get_global_rect(), hud.context_menu.get_global_rect(), "context menu at %s" % corner, viewport_size)
		corner_positions.append(hud.context_menu.global_position)
	if corner_positions[0].x >= corner_positions[1].x or corner_positions[2].x >= corner_positions[3].x:
		_fail("Context menu did not remain anchored to left/right edge selections at %s." % viewport_size)

	hud._on_arena_context_requested(Vector2i(3, 2), "")
	hud.context_menu.visible = true
	hud._position_context_menu()
	if hud._context_pointer_anchor != Vector2(-1.0, -1.0):
		_fail("Pointerless root-menu request did not retain the dock fallback at %s." % viewport_size)

	var icon_descriptor := {
		"instance_id": "icon_contract",
		"name": "Field Bandage",
		"access": "ground",
		"presentation": {"icon_path": "res://Asset/Innawoods_Asset/Items/Medicines/bandage.png"},
	}
	hud._render_target_items([icon_descriptor], "ally")
	if hud.target_items.get_child_count() != 1 or (hud.target_items.get_child(0) as Button).icon == null:
		_fail("Observable target item did not render its projected icon path at %s." % viewport_size)
	hud._render_ground_items([icon_descriptor])
	if hud.ground_items.get_child_count() != 1 or (hud.ground_items.get_child(0) as Button).icon == null:
		_fail("Ground item did not render its projected icon path at %s." % viewport_size)

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
				"ground_item_instance_ids": [],
				"ground_items": [],
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
	var limbs: Array = []
	for region in GameEnums.LimbRegion.values():
		var region_id := str(GameEnums.LimbRegion.keys()[int(region)]).to_lower()
		limbs.append({
			"region": int(region),
			"region_id": region_id,
			"current": 12.0,
			"maximum": 12.0,
			"function": 12.0,
			"bleeding_rate": 0.0,
			"trauma": "NONE",
			"damage_type": -1,
		})
	var player_item := {
		"instance_id": "bandage",
		"name": "Field Bandage",
		"access": "hands",
		"access_tier": "hands",
		"condition": 12.0,
		"quantity": 1,
		"equipment_slot": GameEnums.EquipmentSlot.NONE,
		"presentation": {"icon_path": "res://Asset/Innawoods_Asset/Items/Medicines/bandage.png", "label": "Field Bandage"},
	}
	return {
		"revision": 1,
		"round": 1,
		"ap": 9,
		"max_ap": 12,
		"active_actor_id": "player",
		"initiative_order": ["enemy", "player"],
		"actors": [
			{
				"actor_id": "player",
				"direct_player": true,
				"team_id": "player",
				"name": "Player",
				"sector": Vector2i(mini(2, width - 1), center_y),
				"blood": 12.0,
				"pain": 0.0,
				"shock": 0.0,
				"consciousness": 12.0,
				"stance": 8.0,
				"max_stance": 12.0,
				"burden": 2,
				"burden_tier": "fluid",
				"region_function": function,
				"limbs": limbs,
				"wounds": [{"wound_id": "player_wound", "body_region": GameEnums.LimbRegion.LEFT_ARM, "wound_type": "laceration", "severity": 4.0, "bleeding_rate": 1.5, "stabilized": false}],
				"items": [player_item],
				"equipment": [],
				"ranged_weapon": {},
				"melee_weapon": {},
				"public_intent": {"intent_id": "holding", "label": "Holding", "readable_label": "HOLDING"},
			},
			{
				"actor_id": "enemy",
				"team_id": "enemy",
				"name": "Scavenger",
				"sector": Vector2i(width - 1, center_y),
				"blood": 10.0,
				"pain": 2.0,
				"shock": 1.0,
				"consciousness": 11.0,
				"stance": 9.0,
				"max_stance": 12.0,
				"burden": 6,
				"burden_tier": "labored",
				"region_function": function,
				"limbs": limbs,
				"wounds": [],
				"items": [{"instance_id": "enemy_weapon", "name": "Enemy Knife", "access": "carried", "condition": 12.0}],
				"equipment": [],
				"ranged_weapon": {},
				"melee_weapon": {"name": "Enemy Knife", "display_name": "Enemy Knife", "condition": 12.0, "readiness": {"reason": "ready"}},
				"public_intent": {"intent_id": "holding", "label": "Holding", "readable_label": "HOLDING"},
			},
		],
		"arena": {
			"width": width,
			"height": height,
			"presentation_style": "tactical_grid",
			"sectors": sectors,
			"tactics": {},
			"communication_points": {"current": 4, "initial": 4, "spent": 0},
			"relationships": {"relation_by_pair": {"enemy|player": CombatRelationshipLedger.Relation.HOSTILE}},
		},
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
