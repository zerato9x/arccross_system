extends SceneTree

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var target := WorldObjectRecord.new()
	target.object_id = "shed-door"
	target.components["door"] = {"open": false, "locked": true}
	target.components["repairable"] = {"task_profile_id": "repair_manual"}

	var affordances := WorldActionResolver.query_affordances(
		{"capabilities": ["force_tool"]},
		target
	)
	if affordances.size() < 3:
		_fail("Physical components did not expose shared affordances.")
		return
	var force := _find_affordance(affordances, WorldActionResolver.VERB_FORCE)
	if force == null or force.task_profile_id != "force_manual":
		_fail("Locked door did not expose the force work profile.")
		return

	var profile := WorldWorkTaskProfile.new()
	profile.profile_id = "force_manual"
	profile.work_units = 2
	profile.miss_resets_stage = true
	profile.base_noise = 2.0
	var request := WorldActionRequest.new()
	request.actor_id = "player"
	request.target_id = target.object_id
	request.target_coords = Vector2i(2, 0)
	request.verb_id = WorldActionResolver.VERB_FORCE
	var first := WorldActionResolver.resolve_work_attempt(
		request,
		profile,
		{"action_id": "work-1", "completed_units": 0, "world_time_minutes": 480},
		true
	)
	if not first.committed or first.work_progress <= 0.0 or first.signals.size() != 0:
		_fail("Successful work did not commit cleanly.")
		return
	var miss := WorldActionResolver.resolve_work_attempt(
		request,
		profile,
		{"action_id": "work-1", "completed_units": 1, "world_time_minutes": 495},
		false,
		true
	)
	if miss.signals.size() != 1 or miss.work_progress != 0.0 or not miss.interrupted:
		_fail("A severe miss did not emit noise and reset the work stage.")
		return

	var player_request := WorldActionRequest.new()
	player_request.actor_id = "player"
	player_request.target_id = target.object_id
	player_request.target_coords = Vector2i(2, 0)
	player_request.verb_id = WorldActionResolver.VERB_FORCE
	var ai_request := WorldActionRequest.new()
	ai_request.actor_id = "npc-equivalent"
	ai_request.target_id = target.object_id
	ai_request.target_coords = Vector2i(2, 0)
	ai_request.verb_id = WorldActionResolver.VERB_FORCE
	var player_receipt := WorldActionResolver.resolve_work_attempt(
		player_request, profile, {"action_id": "parity", "completed_units": 0, "elapsed_minutes": 15}, true
	)
	var ai_receipt := WorldActionResolver.resolve_work_attempt(
		ai_request, profile, {"action_id": "parity", "completed_units": 0, "elapsed_minutes": 15}, true
	)
	var player_dict := player_receipt.to_dict()
	var ai_dict := ai_receipt.to_dict()
	player_dict["actor_id"] = ""
	ai_dict["actor_id"] = ""
	if player_dict != ai_dict:
		_fail("Equivalent player and AI work requests produced different semantic receipts.")
		return
	var kernel := WorldActionKernel.new()
	var committed := kernel.commit(
		player_request,
		profile,
		{"action_id": "kernel-commit", "completed_units": 0, "elapsed_minutes": 15},
		true
	)
	var applied := kernel.apply_receipt(committed, {"revision": 4})
	if not committed.committed or int(applied.get("completed_units", 0)) != 1 or int(applied.get("revision", 0)) != 5:
		_fail("Kernel commit/apply_receipt did not preserve the neutral receipt contract.")
		return
	var custom_catalog := WorldInteractionCatalog.new()
	var custom_action := WorldActionDefinition.new()
	custom_action.action_id = "custom_search"
	custom_action.verb_id = "search"
	custom_action.label = "Scavenge"
	custom_action.task_profile_id = "search_manual"
	custom_catalog.actions = [custom_action]
	var custom_object := WorldObjectDefinition.new()
	custom_object.definition_id = "custom_container"
	custom_object.affordance_ids = ["search"]
	custom_catalog.object_definitions = [custom_object]
	var injected_kernel := WorldActionKernel.new(null, custom_catalog)
	var custom_target := WorldObjectRecord.new()
	custom_target.object_id = "custom-target"
	custom_target.definition_id = "custom_container"
	custom_target.components["container"] = {"finite": false}
	var custom_affordances := injected_kernel.query_affordances({}, custom_target)
	if custom_affordances.is_empty() or custom_affordances[0].label != "Scavenge":
		_fail("Injected interaction catalog did not control the affordance label.")
		return
	var base_profile := WorldActionResolver.profile_for_id("repair_manual")
	var crowbar_profile := WorldActionResolver.profile_for_id("repair_manual")
	WorldActionResolver.apply_method_profile(crowbar_profile, "crowbar")
	var multitool_profile := WorldActionResolver.profile_for_id("repair_manual")
	WorldActionResolver.apply_method_profile(multitool_profile, "multitool")
	if crowbar_profile.success_window() <= base_profile.success_window() or crowbar_profile.base_noise <= base_profile.base_noise:
		_fail("Crowbar method did not widen the window while increasing noise.")
		return
	if multitool_profile.normalized_units() >= base_profile.normalized_units() or multitool_profile.base_tool_wear <= base_profile.base_tool_wear:
		_fail("Multitool method did not reduce cycles while consuming durability.")
		return
	var ownership := RuntimeStateStore.new()
	ownership.begin_new_world("WORLD_ACTION_OWNERSHIP")
	var item_state := {"instance_id": "ownership-item", "definition_id": "scrap"}
	ownership.add_ground_items(Vector2i.ZERO, [item_state])
	ownership.add_ground_items(Vector2i.ONE, [item_state])
	if ownership.get_ground_items(Vector2i.ZERO).size() != 0 or ownership.get_ground_items(Vector2i.ONE).size() != 1:
		_fail("Ownership ledger allowed an item to exist in two ground locations.")
		return
	if str(ownership.find_item_ownership("ownership-item").get("location", "")) != "ground":
		_fail("Ownership ledger did not report the canonical item location.")
		return
	var contained_item := {"instance_id": "contained-item", "definition_id": "scrap"}
	var container := WorldObjectRecord.new()
	container.object_id = "ownership-rubble"
	container.components["container"] = {"items": [contained_item]}
	var container_hex := HexRecord.new()
	container_hex.world_objects = [container.to_dict()]
	ownership.set_hex_record(Vector2i(2, 0), container_hex)
	if str(ownership.find_item_ownership("contained-item").get("location", "")) != "world_object":
		_fail("Ownership ledger did not see an item held by a world object.")
		return
	ownership.add_ground_items(Vector2i(3, 0), [contained_item])
	if str(ownership.find_item_ownership("contained-item").get("location", "")) != "ground":
		_fail("Ground transfer did not remove the item from its world object.")
		return
	print("[TEST PASS] Actor-neutral affordances, work receipts, and signal consequences.")
	quit(0)


func _find_affordance(affordances: Array, verb_id: String) -> WorldAffordance:
	for affordance_value in affordances:
		var affordance := affordance_value as WorldAffordance
		if affordance != null and affordance.verb_id == verb_id:
			return affordance
	return null


func _fail(message: String) -> void:
	push_error("[TEST FAIL] " + message)
	quit(1)
