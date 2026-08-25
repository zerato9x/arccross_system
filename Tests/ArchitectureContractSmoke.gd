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
		"MacroPoiSelectionActionService.gd",
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
	var poi_controller_path := "res://WorldCore/MacroPoiController.gd"
	var poi_controller_source := FileAccess.get_file_as_string(poi_controller_path)
	for legacy_poi_mutator in [
		"apply_camp_gear_selection",
		"apply_sleep_gear_selection",
		"apply_trap_install",
	]:
		if poi_controller_source.find(legacy_poi_mutator) != -1:
			violations.append(
				"%s still owns live POI mutation policy %s"
				% [poi_controller_path, legacy_poi_mutator]
			)
	var application_path := "res://SystemCore/WorldActionApplicationService.gd"
	var application_source := FileAccess.get_file_as_string(application_path)
	if application_source.find(
		"WorldActionPoiSelectionTransactionService"
	) == -1:
		violations.append(
			"%s does not delegate POI selection staging" % application_path
		)
	if application_source.find(
		"WorldActionCampTransactionService"
	) == -1:
		violations.append(
			"%s does not delegate camp-cycle staging" % application_path
		)
	if application_source.find(
		"WorldActionMovementTransactionService"
	) == -1:
		violations.append(
			"%s does not delegate canonical movement" % application_path
		)
	if application_source.find(
		"WorldActionSearchTransactionService"
	) == -1:
		violations.append(
			"%s does not delegate canonical search staging" % application_path
		)
	if application_source.find(
		"WorldActionNpcWorkTransactionService"
	) == -1:
		violations.append(
			"%s does not delegate canonical NPC work staging" % application_path
		)
	if application_source.find(
		"WorldActionNegotiationTransactionService"
	) == -1:
		violations.append(
			"%s does not delegate canonical negotiation staging" % application_path
		)
	for extracted_service in [
		"WorldActionReceiptValidationService",
		"WorldActionActorStagingService",
	]:
		if application_source.find(extracted_service) == -1:
			violations.append(
				"%s does not delegate to %s" % [application_path, extracted_service]
			)
	for atomic_owner_call in [
		"capture_reconciliation_snapshot",
		"restore_reconciliation_snapshot",
		"advance_world_time",
		"mark_world_receipt_applied",
	]:
		if application_source.find(atomic_owner_call) == -1:
			violations.append(
				"%s no longer owns atomic operation %s"
				% [application_path, atomic_owner_call]
			)
	var validation_path := "res://SystemCore/WorldActionReceiptValidationService.gd"
	var validation_source := FileAccess.get_file_as_string(validation_path)
	if validation_source.find("ALLOWED_MUTATION_TYPES") == -1:
		violations.append("%s does not own receipt mutation validation" % validation_path)
	var staging_path := "res://SystemCore/WorldActionActorStagingService.gd"
	var staging_source := FileAccess.get_file_as_string(staging_path)
	for forbidden_staging_commit in [
		"capture_reconciliation_snapshot",
		"restore_reconciliation_snapshot",
		"advance_world_time",
		"mark_world_receipt_applied",
		"replace_hex_record",
	]:
		if staging_source.find(forbidden_staging_commit) != -1:
			violations.append(
				"%s illegally owns canonical commit operation %s"
				% [staging_path, forbidden_staging_commit]
			)
	var receipt_path := "res://SystemCore/WorldActionReceipt.gd"
	var receipt_source := FileAccess.get_file_as_string(receipt_path)
	if receipt_source.find("var actor_state") != -1:
		violations.append("%s still exposes caller-owned actor snapshots" % receipt_path)
	var npc_work_path := "res://WorldCore/MacroNpcWorkService.gd"
	var npc_work_source := FileAccess.get_file_as_string(npc_work_path)
	for forbidden_npc_mutator in [
		"receipt.actor_state",
		"generate_salvage",
		"deplete_after_search",
		"patch_entity_record",
	]:
		if npc_work_source.find(forbidden_npc_mutator) != -1:
			violations.append(
				"%s still owns post-commit NPC mutation %s"
				% [npc_work_path, forbidden_npc_mutator]
			)
	if npc_work_source.find("WorldActionNpcWorkTransactionService.MUTATION_TYPE") == -1:
		violations.append(
			"%s does not submit semantic NPC work progress" % npc_work_path
		)
	var talk_start := manager_source.find("func resolve_talk_action")
	if talk_start >= 0:
		var next_talk_function := manager_source.find("\nfunc ", talk_start + 1)
		var talk_body := manager_source.substr(
			talk_start,
			manager_source.length() - talk_start
			if next_talk_function < 0
			else next_talk_function - talk_start
		)
		if talk_body.find(
			"WorldActionNegotiationTransactionService.MUTATION_TYPE"
		) == -1:
			violations.append(
				"%s does not submit semantic negotiation state" % manager_path
			)
		for forbidden_negotiation_mutator in [
			"_apply_macro_event_effects",
			"patch_entity_record",
			"set_entity_world_status",
			"set_relationship",
			"add_ground_items",
		]:
			if talk_body.find(forbidden_negotiation_mutator) != -1:
				violations.append(
					"%s still owns post-commit negotiation mutation %s"
					% [manager_path, forbidden_negotiation_mutator]
				)
	var search_commit_start := manager_source.find("func _commit_search_transaction")
	if search_commit_start >= 0:
		var next_function := manager_source.find("\nfunc ", search_commit_start + 1)
		var search_commit_body := manager_source.substr(
			search_commit_start,
			manager_source.length() - search_commit_start
			if next_function < 0
			else next_function - search_commit_start
		)
		for forbidden_search_replacement in ["replace_hex_state", "hex_state"]:
			if search_commit_body.find(forbidden_search_replacement) != -1:
				violations.append(
					"%s still performs live-first search replacement %s"
					% [manager_path, forbidden_search_replacement]
				)
	var search_service_path := "res://WorldCore/MacroSearchActionService.gd"
	var search_service_source := FileAccess.get_file_as_string(search_service_path)
	for forbidden_search_callback in [
		"player_body",
		"advance_survival_time",
		"capture_player_runtime",
		"deplete_resource",
	]:
		if search_service_source.find(forbidden_search_callback) != -1:
			violations.append(
				"%s still depends on live-first callback %s"
				% [search_service_path, forbidden_search_callback]
			)
	for movement_commit_name in ["_commit_player_retreat", "_commit_player_step", "_move_npc_record"]:
		var movement_commit_start := manager_source.find("func " + movement_commit_name)
		if movement_commit_start < 0:
			continue
		var next_function := manager_source.find("\nfunc ", movement_commit_start + 1)
		var movement_commit_body := manager_source.substr(
			movement_commit_start,
			manager_source.length() - movement_commit_start
			if next_function < 0
			else next_function - movement_commit_start
		)
		if movement_commit_body.find("actor_state") != -1:
			violations.append(
				"%s still submits live actor state during %s"
				% [manager_path, movement_commit_name]
			)
	var camp_commit_start := manager_source.find("func _commit_camp_cycle")
	if camp_commit_start >= 0:
		var next_function := manager_source.find("\nfunc ", camp_commit_start + 1)
		var camp_commit_body := manager_source.substr(
			camp_commit_start,
			manager_source.length() - camp_commit_start
			if next_function < 0
			else next_function - camp_commit_start
		)
		for forbidden_camp_replacement in [
			"actor_state",
			"replace_actor_runtime",
			"replace_hex_state",
		]:
			if camp_commit_body.find(forbidden_camp_replacement) != -1:
				violations.append(
					"%s still performs live-first camp replacement %s"
					% [manager_path, forbidden_camp_replacement]
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
