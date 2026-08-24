extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var packed := load("res://SystemCore/game_director.tscn") as PackedScene
	var director := packed.instantiate()
	root.add_child(director)
	await process_frame
	await process_frame
	var macro_map := director.get_node("MainWorld") as MacroGameManager
	if macro_map == null or macro_map.macro_hud == null:
		_fail("Macro world or HUD did not initialize.")
		return

	var here := macro_map.player_token.current_hex_coords
	var here_hex := macro_map.world_generator.get_hex_at(here)
	here_hex.region = GameEnums.MacroRegion.CENTRAL_HUB
	macro_map.world_generator.world_hex_cache[here] = here_hex
	var world_state := root.get_node("WorldState") as RuntimeStateStore
	world_state.set_hex_record(here, here_hex.to_state())
	macro_map._refresh_world_hud()
	var snapshot: Dictionary = macro_map.macro_hud.get("_snapshot")
	var location: Dictionary = snapshot.get("current_location", {})
	if location.get("coords", Vector2i.ZERO) != here:
		_fail("HERE snapshot is not bound to the player coordinates.")
		return
	if location.get("session", {}).get("site", {}).get("fixtures", []).is_empty():
		_fail("A quiet current hex did not expose explorable fixtures.")
		return
	var presentation: Dictionary = location.get("presentation", {})
	if not presentation.has("layers") or not presentation.has("scene"):
		_fail("HERE presentation is missing literal or scene composition data.")
		return
	var merged_target_panel := macro_map.macro_hud.get_node_or_null("%MacroHexTargetPanel") as MacroHexTargetPanel
	if merged_target_panel == null or not merged_target_panel.visible:
		_fail("Merged HERE/target panel did not render the current location.")
		return
	var current_explore_button := merged_target_panel.get("_explore_button") as Button
	if current_explore_button == null or current_explore_button.disabled:
		_fail("Current merged panel did not enable Explore Here while idle.")
		return
	var composition_root := merged_target_panel.find_child(
		"BorderlessCompositionRoot", true, false
	) as Control
	if composition_root == null or composition_root.custom_minimum_size.y < 120.0:
		_fail("Merged panel lost the enlarged borderless hex composition.")
		return
	for decoration in presentation.get("decorations", []):
		if decoration is Dictionary:
			var path := str(decoration.get("path", ""))
			if not path.is_empty() and not _scene_has_prop_path(presentation.get("scene", {}), path):
				_fail("Expanded scene dropped a generator decoration used by compact HERE.")
				return

	var target := _adjacent_passable(macro_map, here)
	if target == here:
		_fail("Could not find an adjacent travel target.")
		return
	macro_map._select_hex_for_hud(target)
	await process_frame
	snapshot = macro_map.macro_hud.get("_snapshot")
	if snapshot.get("current_location", {}).get("coords") != here:
		_fail("Selecting a destination replaced HERE.")
		return
	if snapshot.get("target_location", {}).get("coords") != target:
		_fail("Selected destination did not reach the target tooltip contract.")
		return
	var target_panel := macro_map.macro_hud.get_node("%MacroHexTargetPanel") as MacroHexTargetPanel
	var hex_preview_root := macro_map.macro_hud.get_hex_panel().get_node("%PreviewRoot")
	if target_panel.get_parent() != hex_preview_root:
		_fail("Target presentation was not merged into the HERE preview surface.")
		return
	var remote_explore_button := target_panel.get("_explore_button") as Button
	if remote_explore_button == null or not remote_explore_button.disabled:
		_fail("Remote Explore Here was not locked in the merged panel.")
		return
	if remote_explore_button.text != "TRAVEL HERE FIRST":
		_fail("Remote Explore lock reason was not visible in the merged panel.")
		return
	if not macro_map.macro_hud.get_hex_panel().get_global_rect().encloses(
		target_panel.get_global_rect()
	):
		_fail("Merged target presentation escaped the HERE preview bounds.")
		return

	macro_map._expand_hex_at(here)
	await process_frame
	if not macro_map.macro_hud.is_location_open():
		_fail("Exploring HERE did not expand the location board.")
		return
	if macro_map.exploration_window != null and macro_map.exploration_window.is_open():
		_fail("Routine exploration still opened MacroExplorationWindow.")
		return
	if macro_map.macro_hud.is_event_open():
		_fail("Routine exploration incorrectly opened the major-event stage.")
		return
	var here_rect := macro_map.macro_hud.get_hex_panel().get_global_rect()
	if not Rect2(Vector2.ZERO, Vector2(1280, 720)).encloses(here_rect):
		_fail("Expanded HERE escaped the supported 1280x720 viewport: %s" % here_rect)
		return
	if target_panel.visible:
		_fail("Target tooltip remained over the expanded HERE board.")
		return
	var board_composition := macro_map.macro_hud.get_hex_panel().get(
		"_board_composition"
	) as MacroHexCompositionView
	if board_composition == null or not is_equal_approx(board_composition.modulate.a, 1.0):
		_fail("Expanded Explore composition is still being rendered as a transparent overlay.")
		return
	var prop_layer := macro_map.macro_hud.get_hex_panel().get("_prop_layer") as Control
	if prop_layer != null:
		for prop in prop_layer.get_children():
			if prop is TextureRect and bool(prop.get_meta("descriptor", {}).get("decorative", false)):
				_fail("Expanded Explore rendered a decorative prop twice.")
				return
	macro_map.macro_hud.get_hex_panel().set_hud_scale(1.25)
	await process_frame
	here_rect = macro_map.macro_hud.get_hex_panel().get_global_rect()
	if not Rect2(Vector2.ZERO, Vector2(1280, 720)).encloses(here_rect):
		_fail("Scaled HERE escaped the supported viewport: %s" % here_rect)
		return
	macro_map.macro_hud.get_hex_panel().set_hud_scale(1.0)
	await process_frame

	location = macro_map.macro_hud.get("_snapshot").get("current_location", {})
	macro_map.resolve_location_action({
		"coords": here,
		"location_revision": int(location.get("revision", 0)) - 1,
		"fixture_id": "stale_probe",
		"verb": SiteCatalog.VERB_SEARCH,
		"selected_item_ids": [],
		"search_option_id": "surface_sweep",
	})
	await process_frame
	var panel := macro_map.macro_hud.get_hex_panel()
	if panel.get("_location_state") != MacroHexCornerPanel.LocationState.OUTCOME:
		_fail("A stale location command was not rejected with in-place feedback.")
		return

	location = macro_map.macro_hud.get("_snapshot").get("current_location", {})
	var search_fixture := _fixture_with_verb(location, SiteCatalog.VERB_SEARCH)
	if search_fixture.is_empty():
		_fail("Quiet HERE has no searchable fixture.")
		return
	var search_actor_revision := macro_map._world_state.player_record.revision
	var search_hex_before := macro_map._world_state.get_hex_record(here)
	var search_hex_revision := search_hex_before.revision
	var search_count_before := search_hex_before.search_count
	var search_time_before := macro_map._world_state.world_time_minutes
	var search_camp_items_before := search_hex_before.camp_item_states.duplicate(true)
	macro_map.resolve_location_action({
		"coords": here,
		"location_revision": int(location.get("revision", 0)),
		"fixture_id": str(search_fixture.get("id", "")),
		"verb": SiteCatalog.VERB_SEARCH,
		"selected_item_ids": [],
		"search_option_id": "forged_option_must_be_ignored",
	})
	await process_frame
	var searched_id := str(search_fixture.get("search_option_id", ""))
	var canonical_search_hex := macro_map._world_state.get_hex_record(here)
	if not canonical_search_hex.searched_targets.has(searched_id):
		_fail("Valid fixture search did not mutate canonical search state.")
		return
	if canonical_search_hex.search_count != search_count_before + 1:
		_fail("Shipping search did not increment canonical search count exactly once.")
		return
	if canonical_search_hex.revision != search_hex_revision + 1:
		_fail("Shipping search did not advance the hex revision exactly once.")
		return
	if macro_map._world_state.player_record.revision != search_actor_revision + 1:
		_fail("Shipping search did not advance the actor revision exactly once.")
		return
	if macro_map._world_state.world_time_minutes != search_time_before + macro_map._time_rules_service.search_minutes():
		_fail("Shipping search did not advance canonical time exactly once.")
		return
	if canonical_search_hex.camp_item_states != search_camp_items_before:
		_fail("Shipping search overwrote unrelated canonical camp gear.")
		return
	var live_search_hex := macro_map.world_generator.get_hex_at(here)
	if (
		live_search_hex.search_count != canonical_search_hex.search_count
		or live_search_hex.searched_targets != canonical_search_hex.searched_targets
	):
		_fail("Shipping search did not reproject canonical search state.")
		return
	if not (panel.get("_confirm_button") as Button).disabled:
		_fail("Resolved search remained repeatable without selecting a new action.")
		return

	location = macro_map.macro_hud.get("_snapshot").get("current_location", {})
	var trap_fixture := _fixture_with_verb(location, SiteCatalog.VERB_TRAP)
	var trap_item := _item_with_role(location, GameEnums.InteractionItemRole.TRAP_GEAR)
	if not trap_fixture.is_empty() and not trap_item.is_empty():
		var trap_instance_id := str(trap_item.get("instance_id", ""))
		var actor_revision_before := macro_map._world_state.player_record.revision
		var hex_revision_before := macro_map._world_state.get_hex_record(here).revision
		var world_time_before := macro_map._world_state.world_time_minutes
		var camp_items_before := macro_map._world_state.get_hex_record(
			here
		).camp_item_states.duplicate(true)
		macro_map.resolve_location_action({
			"coords": here,
			"location_revision": int(location.get("revision", 0)),
			"fixture_id": str(trap_fixture.get("id", "")),
			"verb": SiteCatalog.VERB_TRAP,
			"selected_item_ids": [trap_instance_id],
		})
		await process_frame
		if macro_map.world_generator.get_hex_at(here).camp_traps.is_empty():
			_fail("Trap action did not persist the selected device on HERE.")
			return
		if macro_map.player_token.get_humanoid_core().inventory.find_item_by_instance_id(
			trap_instance_id
		) != null:
			_fail("Trap action left the installed device in the live inventory.")
			return
		var stored_core := EntityFactory.record_to_humanoid_core(
			macro_map._world_state.player_record.to_dict(),
			null,
			"HereTrapCanonicalProbe"
		)
		if stored_core.inventory.find_item_by_instance_id(trap_instance_id) != null:
			stored_core.free()
			_fail("Trap action left the installed device in canonical inventory.")
			return
		var live_runtime := macro_map.player_token.get_humanoid_core().capture_runtime_state().to_dict()
		var stored_runtime := stored_core.capture_runtime_state().to_dict()
		stored_core.free()
		if live_runtime != stored_runtime:
			_fail("Trap receipt did not reproject canonical inventory to the live player.")
			return
		if macro_map._world_state.player_record.revision != actor_revision_before + 1:
			_fail("Trap action advanced actor revision more than once.")
			return
		if macro_map._world_state.get_hex_record(here).revision != hex_revision_before + 1:
			_fail("Trap action advanced hex revision more than once.")
			return
		if macro_map._world_state.world_time_minutes != world_time_before + macro_map._time_rules_service.action_minutes("action"):
			_fail("Trap action did not advance canonical world time exactly once.")
			return
		if macro_map._world_state.get_hex_record(here).camp_item_states != camp_items_before:
			_fail("Installing a fixture trap dismantled unrelated camp gear.")
			return

		var unchanged := macro_map._world_state.capture_reconciliation_snapshot()
		location = macro_map.macro_hud.get("_snapshot").get("current_location", {})
		macro_map.resolve_location_action({
			"coords": here,
			"location_revision": int(location.get("revision", 0)),
			"fixture_id": str(trap_fixture.get("id", "")),
			"verb": SiteCatalog.VERB_TRAP,
			"selected_item_ids": [trap_instance_id],
		})
		await process_frame
		if macro_map._world_state.capture_reconciliation_snapshot() != unchanged:
			_fail("Invalid repeated trap selection changed canonical state.")
			return

	location = macro_map.macro_hud.get("_snapshot").get("current_location", {})
	if bool(location.get("session", {}).get("camp_allowed", false)):
		var camp_actor_revision := macro_map._world_state.player_record.revision
		var camp_time_before := macro_map._world_state.world_time_minutes
		var camp_count_before := macro_map._world_state.get_hex_record(
			here
		).camp_rest_count
		macro_map.resolve_poi_action(GameEnums.PoiAction.REST, [])
		await process_frame
		if macro_map._world_state.player_record.revision != camp_actor_revision + 1:
			_fail("Shipping camp cycle advanced actor revision more than once.")
			return
		if macro_map._world_state.world_time_minutes != camp_time_before + macro_map._time_rules_service.camp_minutes():
			_fail("Shipping camp cycle did not advance canonical time exactly once.")
			return
		if macro_map._world_state.get_hex_record(here).camp_rest_count != camp_count_before + 2:
			_fail("Shipping camp cycle did not commit its canonical rest count.")
			return
		var camp_store_probe := EntityFactory.record_to_humanoid_core(
			macro_map._world_state.player_record.to_dict(),
			null,
			"HereCampCanonicalProbe"
		)
		var camp_live_runtime := macro_map.player_token.get_humanoid_core().capture_runtime_state().to_dict()
		var camp_store_runtime := camp_store_probe.capture_runtime_state().to_dict()
		camp_store_probe.free()
		if camp_live_runtime != camp_store_runtime:
			_fail("Camp receipt did not reproject canonical biology to the live player.")
			return

	macro_map._debug_drop_sample_loot(here)
	await process_frame
	location = macro_map.macro_hud.get("_snapshot").get("current_location", {})
	var ground_items: Array = location.get("session", {}).get("ground_items", [])
	if not ground_items.is_empty():
		var ground_item: Dictionary = ground_items[0]
		macro_map.resolve_location_action({
			"coords": here,
			"location_revision": int(location.get("revision", 0)),
			"fixture_id": "ground:" + str(ground_item.get("instance_id", "")),
			"verb": "take" if bool(ground_item.get("can_pick_up", true)) else "inspect",
			"selected_item_ids": [str(ground_item.get("instance_id", ""))],
		})
		await process_frame
		if panel.get("_location_state") != MacroHexCornerPanel.LocationState.OUTCOME:
			_fail("Ground interaction did not resolve in place on HERE.")
			return

	macro_map.close_macro_interaction()
	await process_frame
	if macro_map.macro_hud.is_location_open():
		_fail("Closing exploration did not return HERE to compact mode.")
		return
	if not target_panel.visible:
		_fail("Target tooltip did not return after HERE collapsed.")
		return
	print("[TEST PASS] HERE ownership, target separation, location board, and stale command guard.")
	quit(0)


func _adjacent_passable(macro_map: MacroGameManager, origin: Vector2i) -> Vector2i:
	for delta in [
		Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1),
		Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1),
	]:
		var coords: Vector2i = origin + Vector2i(delta)
		if macro_map.world_generator.is_in_zone_bounds(coords):
			if macro_map.world_generator.get_hex_at(coords).is_passable():
				return coords
	return origin


func _fixture_with_verb(location: Dictionary, verb: String) -> Dictionary:
	for fixture in location.get("session", {}).get("site", {}).get("fixtures", []):
		if fixture is Dictionary and fixture.get("verbs", []).has(verb):
			return fixture
	return {}


func _item_with_role(location: Dictionary, role: int) -> Dictionary:
	for item in location.get("session", {}).get("available_items", []):
		if item is Dictionary and item.get("interaction_roles", []).has(role):
			return item
	return {}


func _scene_has_prop_path(scene: Dictionary, path: String) -> bool:
	for prop in scene.get("props", []):
		if prop is Dictionary and str(prop.get("sprite_path", "")) == path:
			return true
	return false


func _fail(message: String) -> void:
	push_error("[TEST FAIL] " + message)
	quit(1)
