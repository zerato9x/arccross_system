extends SceneTree

const FORBIDDEN_DOMAIN_IMPORTS := {
	"SystemCore": ["WorldCore/", "CombatCore/", "res://UI/"],
	"WorldCore": ["CombatCore/", "res://UI/"],
	"CombatCore": ["WorldCore/", "res://UI/"],
	"UI": ["res://SystemCore/"],
	"ItemCore": [
		"WorldCore/",
		"CombatCore/",
		"BiologicalCore/",
		"SystemCore/",
		"SoundCore/",
		"PresentationCore/",
	],
}


func _init() -> void:
	var violations: Array[String] = []
	for domain in FORBIDDEN_DOMAIN_IMPORTS.keys():
		for file_path in _list_gd_files("res://%s" % domain):
			var source := FileAccess.get_file_as_string(file_path)
			for pattern in FORBIDDEN_DOMAIN_IMPORTS[domain]:
				if source.find(pattern) != -1:
					violations.append("%s imports %s" % [file_path, pattern])
	violations.append_array(_snapshot_contract_violations())
	violations.append_array(_extraction_contract_violations())
	if not violations.is_empty():
		for violation in violations:
			push_error(violation)
		_fail("Architecture contract violations detected.")
		return
	print("[PASS] Architecture domain contracts are clean.")
	quit()


func _snapshot_contract_violations() -> Array[String]:
	var violations: Array[String] = []
	var inventory_path := "res://UI/Inventory/InventoryUI.gd"
	var inventory_source := FileAccess.get_file_as_string(inventory_path)
	if inventory_source.find("func open_inventory(snapshot: Dictionary") == -1:
		violations.append("%s does not accept a neutral inventory snapshot" % inventory_path)
	if inventory_source.find("signal inventory_action_requested") == -1:
		violations.append("%s does not emit inventory intent IDs" % inventory_path)
	for forbidden in ["InventorySystem", "HumanoidCore", "HumanoidBody"]:
		if inventory_source.find(forbidden) != -1:
			violations.append("%s imports live domain object %s" % [inventory_path, forbidden])
	var macro_hud_path := "res://UI/HUD/Macro/MacroHudController.gd"
	if FileAccess.get_file_as_string(macro_hud_path).find("func refresh(snapshot: Dictionary") == -1:
		violations.append("%s does not accept a neutral macro snapshot" % macro_hud_path)
	var combat_hud_path := "res://CombatCore/Tactical/TacticalCombatHUD.gd"
	if FileAccess.get_file_as_string(combat_hud_path).find("func show_snapshot(value: Dictionary") == -1:
		violations.append("%s does not accept a neutral combat snapshot" % combat_hud_path)
	for macro_ui_path in [
		"res://UI/Macro/MacroExplorationWindow.gd",
		"res://UI/HUD/Macro/MacroHexCornerPanel.gd",
	]:
		if FileAccess.get_file_as_string(macro_ui_path).find("res://WorldCore/") != -1:
			violations.append("%s imports WorldCore instead of consuming a location snapshot" % macro_ui_path)
	return violations


func _extraction_contract_violations() -> Array[String]:
	var violations: Array[String] = []
	var manager_path := "res://WorldCore/MacroGameManager.gd"
	var manager_source := FileAccess.get_file_as_string(manager_path)
	if manager_source.find("WorldActionResolver.resolve_") != -1:
		violations.append("%s still resolves direct actions outside the world-action coordinator" % manager_path)
	if manager_source.find("func _apply_world_work_consequence_to_target") != -1:
		violations.append("%s still owns world-action target consequences" % manager_path)
	if manager_source.find("MacroCampaignPopulationService.gd") == -1:
		violations.append("%s does not delegate authored NPC population policy" % manager_path)
	for required_service in [
		"MacroActiveZoneService.gd",
		"MacroCampaignContentService.gd",
		"MacroCombatEncounterService.gd",
		"MacroSearchResourceService.gd",
		"MacroSearchActionService.gd",
		"MacroCampActionService.gd",
		"MacroWorldActionExecutionService.gd",
		"MacroShelterRuntimeService.gd",
		"MacroMovementService",
		"MacroLocationSnapshotService.gd",
		"MacroNpcTurnService.gd",
		"MacroNpcWorkService.gd",
		"MacroReceiptApplicationService.gd",
	]:
		if manager_source.find(required_service) == -1:
			violations.append("%s is missing the %s application seam" % [manager_path, required_service])
	for legacy_content_function in [
		"func _run_has_meta_component",
		"func _runtime_item_state_id",
	]:
		if manager_source.find(legacy_content_function) != -1:
			violations.append("%s still owns extracted campaign-content policy %s" % [manager_path, legacy_content_function])
	var active_zone_start := manager_source.find("func _apply_active_zone_to_world")
	if active_zone_start >= 0:
		var next_function := manager_source.find("\nfunc ", active_zone_start + 1)
		var active_zone_body := manager_source.substr(
			active_zone_start,
			manager_source.length() - active_zone_start
			if next_function < 0
			else next_function - active_zone_start
		)
		if active_zone_body.find("inject_zone_hexes") != -1:
			violations.append("%s still owns active-zone world injection" % manager_path)
		if active_zone_body.find("update_player_runtime") != -1:
			violations.append("%s still owns active-zone player persistence" % manager_path)
	for legacy_population_function in [
		"func _pick_route_population_coords",
		"func _is_route_one_node",
		"func _central_facing_direction_for_route_one",
		"func _has_central_guard_pair",
		"func _pick_central_rim_pair_coords",
		"func _is_guard_spawn_hex",
	]:
		if manager_source.find(legacy_population_function) != -1:
			violations.append("%s still owns extracted population policy %s" % [manager_path, legacy_population_function])
	var trace_start := manager_source.find("func _emit_movement_trace")
	if trace_start >= 0:
		var next_function := manager_source.find("\nfunc ", trace_start + 1)
		var trace_body := manager_source.substr(
			trace_start,
			manager_source.length() - trace_start if next_function < 0 else next_function - trace_start
		)
		if trace_body.find("_world_state.register_world_signal") != -1:
			violations.append("%s still owns movement-trace signal persistence" % manager_path)
	var state_store_path := "res://SystemCore/RuntimeStateStore.gd"
	if FileAccess.get_file_as_string(state_store_path).find("NodeRuntimeSnapshotRepository.gd") == -1:
		violations.append("%s does not delegate node snapshots to their repository" % state_store_path)
	var persistence_path := "res://WorldCore/MacroPersistenceBridge.gd"
	if FileAccess.get_file_as_string(persistence_path).find("func flush_world_mutations") == -1:
		violations.append("%s does not own run mutation flushing" % persistence_path)
	if manager_source.find("func _build_mutation_baseline_records") != -1:
		violations.append("%s still owns extracted persistence policy" % manager_path)
	for legacy_world_action_policy in [
		"reserve_world_action",
		"release_world_action",
		"update_world_action",
		"build_preview(",
		"resolve_work_attempt(",
	]:
		if manager_source.find(legacy_world_action_policy) != -1:
			violations.append(
				"%s still owns player world-action execution policy %s"
				% [manager_path, legacy_world_action_policy]
			)
	for legacy_camp_policy in [
		"MacroInteractionResolver.calculate_camp_metrics",
		"MacroInteractionResolver.resolve_camp",
	]:
		if manager_source.find(legacy_camp_policy) != -1:
			violations.append(
				"%s still owns camp resolution policy %s"
				% [manager_path, legacy_camp_policy]
			)
	for legacy_search_policy in [
		"resolve_search_outcome",
		"MacroInteractionResolver.resolve_search",
	]:
		if manager_source.find(legacy_search_policy) != -1:
			violations.append(
				"%s still owns search resolution policy %s"
				% [manager_path, legacy_search_policy]
			)
	if manager_source.find("func _shelter_hostile_present") != -1:
		violations.append("%s still owns extracted shelter runtime policy" % manager_path)
	if manager_source.find('record.runtime["biology"]') != -1:
		violations.append("%s still owns NPC runtime initialization policy" % manager_path)
	var generator_path := "res://WorldCore/MacroZoneGenerator.gd"
	var generator_source := FileAccess.get_file_as_string(generator_path)
	if generator_source.find("MacroWorldObjectSeeder.gd") == -1:
		violations.append("%s does not delegate world-object seeding to its generation service" % generator_path)
	if generator_source.find("MacroZoneCompositionPlanner.gd") == -1:
		violations.append("%s does not delegate starter composition planning to its generation service" % generator_path)
	if generator_source.find("MacroHexMaterializer.gd") == -1:
		violations.append("%s does not delegate starter hex mutation to its materializer" % generator_path)
	if generator_source.find("MacroZoneDecorationService.gd") == -1:
		violations.append("%s does not delegate visual dressing to its decoration service" % generator_path)
	for legacy_seed_function in ["func _shelter_components", "func _apply_shelter_state", "func _world_object("]:
		if generator_source.find(legacy_seed_function) != -1:
			violations.append("%s still owns extracted object-seeding function %s" % [generator_path, legacy_seed_function])
	for legacy_palette_function in ["STARTER_TERRAIN_VARIANT_NUMBERS", "func _build_starter_terrain_assignments"]:
		if generator_source.find(legacy_palette_function) != -1:
			violations.append("%s still owns extracted terrain palette policy %s" % [generator_path, legacy_palette_function])
	for legacy_composition_function in ["func _apply_route_1_signature_landmark", "func _seed_starter_truth_grove", "func _is_quiet_grove_cell"]:
		if generator_source.find(legacy_composition_function) != -1:
			violations.append("%s still owns extracted composition mutation %s" % [generator_path, legacy_composition_function])
	for legacy_decoration_function in ["func _scatter_zone_decorations", "func _append_authored_decoration", "func _pick_cluster_decor_path", "func _decor_target_box"]:
		if generator_source.find(legacy_decoration_function) != -1:
			violations.append("%s still owns extracted decoration policy %s" % [generator_path, legacy_decoration_function])
	var inventory_path := "res://UI/Inventory/InventoryUI.gd"
	var inventory_source := FileAccess.get_file_as_string(inventory_path)
	for required in [
		"InventoryCommandRouter.gd",
		"InventorySlotRenderer.gd",
		"InventoryContextMenuPresenter.gd",
	]:
		if inventory_source.find(required) == -1:
			violations.append("%s is missing the %s presentation seam" % [inventory_path, required])
	var inventory_system_path := "res://ItemCore/InventorySystem.gd"
	var inventory_system_source := FileAccess.get_file_as_string(inventory_system_path)
	if inventory_system_source.find("InventoryFirearmService.gd") == -1:
		violations.append(
			"%s does not delegate firearm mutations to their inventory service"
			% inventory_system_path
		)
	if inventory_system_source.find("weapon_equip_error") == -1:
		violations.append(
			"%s does not delegate weapon readiness legality to EquipmentRules"
			% inventory_system_path
		)
	if inventory_system_source.find("func _validate_weapon_equip") != -1:
		violations.append(
			"%s still owns weapon readiness legality"
			% inventory_system_path
		)
	var combat_path := "res://CombatCore/Tactical/TacticalCombatHUD.gd"
	if FileAccess.get_file_as_string(combat_path).find("TacticalCombatSnapshotPresenter.gd") == -1:
		violations.append("%s does not compose neutral combat snapshot presenters" % combat_path)
	return violations


func _list_gd_files(root_path: String) -> Array[String]:
	var results: Array[String] = []
	var stack: Array[String] = [root_path]
	while not stack.is_empty():
		var current: String = stack.pop_back()
		var directory := DirAccess.open(current)
		if directory == null:
			continue
		directory.list_dir_begin()
		var entry := directory.get_next()
		while entry != "":
			if entry == "." or entry == "..":
				entry = directory.get_next()
				continue
			var full_path := current.path_join(entry)
			if directory.current_is_dir():
				stack.append(full_path)
			elif entry.ends_with(".gd"):
				results.append(full_path)
			entry = directory.get_next()
		directory.list_dir_end()
	return results


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
