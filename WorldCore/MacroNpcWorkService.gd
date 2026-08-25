extends RefCounted
class_name MacroNpcWorkService

## NPC work policy and neutral carried-item handling.
##
## This service owns the decision to work, the neutral item state used to
## evaluate that decision, and the resulting tool/material mutations. The
## manager supplies only the authoritative receipt application callback.

var world_state: RuntimeStateStore
var world_generator: HexWorldGenerator
var action_coordinator: MacroWorldActionCoordinator
var loot_catalog: Node


func configure(
	state: RuntimeStateStore,
	generator: HexWorldGenerator,
	coordinator: MacroWorldActionCoordinator,
	loot: Node
) -> void:
	world_state = state
	world_generator = generator
	action_coordinator = coordinator
	loot_catalog = loot


func actor_context(record: EntityRecord) -> Dictionary:
	var capabilities: Array[String] = ["hands"]
	for item_state in carried_item_states(record):
		if not item_state is Dictionary:
			continue
		var definition: Dictionary = item_state.get("definition", {})
		var tags: Array = definition.get("tags", [])
		var roles: Array = definition.get("functional_roles", [])
		var interaction_roles: Array = definition.get("interaction_roles", [])
		if roles.has("light_source") or tags.has("light"):
			if not capabilities.has("light_source"):
				capabilities.append("light_source")
		if interaction_roles.has(GameEnums.InteractionItemRole.SEARCH_TOOL):
			if not capabilities.has("search_tool"):
				capabilities.append("search_tool")
	var method_id := method_for_record(record)
	if method_id == "multitool" and not capabilities.has("repair_tool"):
		capabilities.append("repair_tool")
	if method_id == "crowbar" and not capabilities.has("force_tool"):
		capabilities.append("force_tool")
	if has_material(record) and not capabilities.has("material"):
		capabilities.append("material")
	return {
		"actor_id": record.entity_id if record != null else "",
		"revision": record.revision if record != null else 0,
		"capabilities": capabilities,
		"work_skill": float(record.definition.get("finesse", 4)) / 12.0
			if record != null
			else 0.0,
		"tool_bonus": 0.0,
	}


func has_material(record: EntityRecord) -> bool:
	if record == null:
		return false
	for item_value in carried_item_states(record):
		if not item_value is Dictionary:
			continue
		var definition: Dictionary = item_value.get("definition", {})
		var roles: Array = definition.get("functional_roles", [])
		var tags: Array = definition.get("tags", [])
		if roles.has("repair_material") or tags.has("materials"):
			return true
	return false


func carried_item_states(record: EntityRecord) -> Array:
	## Macro NPCs use the same neutral item state that combat and ownership use.
	## Authored loadout definitions are planning states until tactical handoff.
	var states: Array = []
	if record == null:
		return states
	var has_authoritative_macro_inventory := false
	for item_value in record.runtime.get("inventory_items", []):
		if item_value is Dictionary:
			states.append(item_value)
			has_authoritative_macro_inventory = true
	var runtime_inventory: Dictionary = record.runtime.get("inventory", {})
	for item_value in runtime_inventory.get("equipment", {}).values():
		if item_value is Dictionary:
			states.append(item_value)
			has_authoritative_macro_inventory = true
	for item_value in runtime_inventory.get("backpack", []):
		if item_value is Dictionary:
			states.append(item_value)
			has_authoritative_macro_inventory = true
	if has_authoritative_macro_inventory:
		return states
	if loot_catalog == null or not loot_catalog.has_method(
		"create_runtime_item_from_template_path"
	):
		return states
	var loadout: Dictionary = record.definition.get("loadout", {})
	var template_paths: Array = _loadout_template_paths(loadout)
	for path in template_paths:
		var state: Dictionary = loot_catalog.call(
			"create_runtime_item_from_template_path", path
		) as Dictionary
		if not state.is_empty():
			state["_authored_planning_state"] = true
			states.append(state)
	return states


func materialize_loadout(record: EntityRecord) -> void:
	## Starting gear becomes ordinary carried state at the actor's current
	## world minute. The authored marker prevents tactical handoff duplication.
	if record == null or loot_catalog == null:
		return
	if not loot_catalog.has_method("create_runtime_item_from_template_path"):
		return
	if record.runtime.has("inventory_items"):
		return
	var loadout: Dictionary = record.definition.get("loadout", {})
	var states: Array = []
	for path in _loadout_template_paths(loadout):
		var state: Dictionary = loot_catalog.call(
			"create_runtime_item_from_template_path", path
		) as Dictionary
		if state.is_empty():
			continue
		state["owner_id"] = record.entity_id
		state["physical_location"] = "inventory"
		state["_authored_loadout"] = true
		states.append(state)
	record.runtime["inventory_items"] = states


func method_for_record(record: EntityRecord) -> String:
	if record == null:
		return "hands"
	for item_value in carried_item_states(record):
		if not item_value is Dictionary:
			continue
		var condition := float(
			item_value.get("current_condition", GameEnums.SCALE_MAX)
		)
		if condition <= 0.0:
			continue
		var definition: Dictionary = item_value.get("definition", {})
		var item_id := str(definition.get("id", item_value.get("item_id", "")))
		if item_id in ["multitool", "lockpick"]:
			return "multitool"
		if item_id in ["crowbar", "bent_pry_bar"]:
			return "crowbar"
	return "hands"


func try_work(
	record: EntityRecord,
	macro_turn_index: int,
	callbacks: Dictionary
) -> Dictionary:
	if (
		record == null
		or record.life_state != GameEnums.EntityLifeState.ALIVE
		or world_state == null
		or world_generator == null
		or action_coordinator == null
	):
		return {}
	var hex := world_generator.get_hex_at(record.coords)
	var target: WorldObjectRecord = null
	var affordance: WorldAffordance = null
	var context := actor_context(record)
	for object_value in hex.world_objects:
		if not object_value is Dictionary:
			continue
		var candidate := WorldObjectRecord.from_dict(object_value)
		for value in action_coordinator.query_affordances(context, candidate):
			if value != null and value.verb_id in [
				WorldActionResolver.VERB_SEARCH,
				WorldActionResolver.VERB_DISMANTLE,
				WorldActionResolver.VERB_REPAIR,
			]:
				target = candidate
				affordance = value
				break
		if affordance != null:
			break
	if target == null or affordance == null:
		return {}
	var request := WorldActionRequest.new()
	request.actor_id = record.entity_id
	request.target_id = target.object_id
	request.target_coords = record.coords
	request.verb_id = affordance.verb_id
	request.method_id = method_for_record(record)
	request.expected_actor_revision = record.revision
	request.expected_target_revision = target.revision
	request.payload["expected_hex_revision"] = (
		world_state.get_hex_record(record.coords).revision
		if world_state.get_hex_record(record.coords) != null
		else -1
	)
	request.payload["node_id"] = world_state.active_node_id
	var profile := action_coordinator.profile_for_id(affordance.task_profile_id)
	profile.base_noise = 1.0 if affordance.verb_id == WorldActionResolver.VERB_SEARCH else 1.5
	action_coordinator.apply_method_profile(profile, request.method_id)
	var work_state: Dictionary = record.runtime.get("world_work", {})
	var action_id := str(work_state.get("action_id", ""))
	if not action_id.is_empty():
		request.payload["action_id"] = action_id
	work_state["completed_units"] = int(work_state.get("completed_units", 0))
	work_state["world_time_minutes"] = world_state.world_time_minutes
	work_state["emit_success_signal"] = true
	var preview := action_coordinator.build_preview(
		request,
		affordance,
		context,
		target.to_dict(),
		profile
	)
	if not preview.allowed:
		return {}
	var reservation := (
		world_state.get_world_action_reservation(action_id)
		if not action_id.is_empty()
		else null
	)
	if reservation != null:
		if reservation.actor_id != record.entity_id:
			return {}
	else:
		reservation = world_state.begin_world_action(request)
	if reservation == null:
		return {}
	action_id = reservation.action_id
	request.payload["action_id"] = action_id
	work_state["action_id"] = action_id
	work_state["receipt_id"] = reservation.next_receipt_id()
	work_state["attempt_index"] = reservation.attempt_index
	var receipt := action_coordinator.resolve_ai_work(
		request,
		profile,
		context,
		work_state,
		(world_state.world_seed + request.target_id + str(macro_turn_index)).hash()
	)
	if affordance.verb_id == WorldActionResolver.VERB_REPAIR:
		var material_item := select_repair_material(record)
		if material_item.is_empty():
			world_state.cancel_world_action(action_id)
			return {}
		receipt.mutations.append({
			"type": "consume_material",
			"instance_id": material_item.get("instance_id", ""),
			"item_id": material_item.get("item_id", ""),
		})
	work_state["completed_units"] = int(receipt.work_progress * profile.normalized_units())
	work_state["misses"] = int(work_state.get("misses", 0)) + (
		0 if receipt.work_completed else 1
	)
	var npc_work_mutation := {
		"type": WorldActionNpcWorkTransactionService.MUTATION_TYPE,
		"clear_world_work": receipt.work_completed,
		"world_work_state": {} if receipt.work_completed else work_state.duplicate(true),
	}
	if receipt.work_completed and affordance.verb_id == WorldActionResolver.VERB_SEARCH:
		var search_completion := _build_search_completion(record, target, receipt)
		if search_completion.is_empty():
			world_state.cancel_world_action(action_id)
			return {}
		npc_work_mutation["search_completion"] = search_completion
	receipt.mutations.append(npc_work_mutation)
	action_coordinator.apply_work_consequences(target, affordance.verb_id, receipt)
	var commit_receipt: Callable = callbacks.get("commit_receipt", Callable())
	var application: WorldActionApplicationReceipt = null
	if commit_receipt.is_valid():
		application = commit_receipt.call(
			receipt, record.coords, target, record.entity_id
		) as WorldActionApplicationReceipt
	if application == null or not application.applied:
		world_state.cancel_world_action(action_id)
		return {}
	return {
		"receipt": receipt,
		"target_id": target.object_id,
		"verb_id": affordance.verb_id,
	}


func select_repair_material(record: EntityRecord) -> Dictionary:
	if record == null:
		return {}
	for item_value in carried_item_states(record):
		if not item_value is Dictionary:
			continue
		var definition: Dictionary = item_value.get("definition", {})
		var roles: Array = definition.get("functional_roles", [])
		var tags: Array = definition.get("tags", [])
		if roles.has("repair_material") or tags.has("materials"):
			return {
				"instance_id": item_value.get("instance_id", ""),
				"item_id": definition.get("id", item_value.get("item_id", "")),
			}
	return {}


func _build_search_completion(
	record: EntityRecord,
	target: WorldObjectRecord,
	receipt: WorldActionReceipt
) -> Dictionary:
	if record == null or target == null or receipt == null or loot_catalog == null:
		return {}
	var hex := world_state.get_hex_record(record.coords)
	if hex == null:
		return {}
	var site_catalog := SearchSiteCatalog.data()
	var site := site_catalog.get_site(hex.search_site_id) if site_catalog != null else null
	if site == null:
		return {}
	var profile: Dictionary = loot_catalog.call(
		"get_profile_descriptor", site.loot_profile_id
	) as Dictionary
	var entries: Array = profile.get("guaranteed_entries", [])
	if entries.is_empty():
		entries = profile.get("entries", [])
	if entries.is_empty():
		return {}
	var identity := "%s|%s|%s|%s|%s" % [
		world_state.world_seed,
		world_state.active_node_id,
		receipt.receipt_id,
		record.entity_id,
		target.object_id,
	]
	var index := absi(identity.hash()) % entries.size()
	var item_id := str(entries[index].get("item_id", ""))
	if item_id.is_empty():
		return {}
	var item_state: Dictionary = loot_catalog.call(
		"create_runtime_item_state", item_id
	) as Dictionary
	if item_state.is_empty():
		return {}
	item_state["instance_id"] = "item_npc_search_" + (
		identity + "|" + item_id
	).sha256_text().substr(0, 24)
	item_state["owner_id"] = record.entity_id
	item_state["physical_location"] = "inventory"
	var resource_component := ""
	var expected_remaining := 0
	for candidate in ["rubble", "debris", "container"]:
		if not target.has_component(candidate):
			continue
		var resource := target.component(candidate)
		if candidate == "container" and not bool(resource.get("finite", false)):
			continue
		resource_component = candidate
		expected_remaining = int(resource.get(
			"remaining_searches" if candidate == "container" else "material_units",
			0
		))
		break
	if resource_component.is_empty() or expected_remaining <= 0:
		return {}
	return {
		"resource_component": resource_component,
		"expected_remaining": expected_remaining,
		"item_state": item_state,
	}


func _loadout_template_paths(loadout: Dictionary) -> Array:
	var paths: Array = []
	for key in [
		"weapon", "offhand", "inner_torso", "outer_torso", "legs", "feet", "vest",
		"backpack_gear", "head", "eyes", "face", "neck", "arms", "belt", "sling",
	]:
		var path := str(loadout.get(key, ""))
		if not path.is_empty():
			paths.append(path)
	for path_value in loadout.get("starting_items", []):
		var path := str(path_value)
		if not path.is_empty():
			paths.append(path)
	return paths
