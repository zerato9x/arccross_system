extends RefCounted
class_name MacroNpcWorkService

## NPC work policy and neutral carried-item handling.
##
## This service owns the decision to work, the neutral item state used to
## evaluate that decision, and the resulting tool/material mutations. The
## manager supplies only the authoritative receipt application callback and
## the shared search-resource depletion callback.

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
	var profile := action_coordinator.profile_for_id(affordance.task_profile_id)
	profile.base_noise = 1.0 if affordance.verb_id == WorldActionResolver.VERB_SEARCH else 1.5
	action_coordinator.apply_method_profile(profile, request.method_id)
	var work_state: Dictionary = record.runtime.get("world_work", {})
	work_state["action_id"] = "%s:%s" % [record.entity_id, target.object_id]
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
	var action_id := str(work_state["action_id"])
	var reservation := world_state.get_world_action(action_id)
	var reservation_owned := false
	if not reservation.is_empty():
		if str(reservation.get("actor_id", "")) != record.entity_id:
			return {}
		reservation_owned = true
	else:
		reservation_owned = world_state.reserve_world_action(action_id, {
			"actor_id": record.entity_id,
			"target_id": target.object_id,
			"verb_id": affordance.verb_id,
			"started_minute": world_state.world_time_minutes,
		})
	if not reservation_owned:
		return {}
	var receipt := action_coordinator.resolve_ai_work(
		request,
		profile,
		context,
		work_state,
		(world_state.world_seed + request.target_id + str(macro_turn_index)).hash()
	)
	if affordance.verb_id == WorldActionResolver.VERB_REPAIR:
		var material_item := consume_repair_material(record)
		if material_item.is_empty():
			world_state.release_world_action(action_id)
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
	if receipt.work_completed:
		record.runtime.erase("world_work")
	else:
		record.runtime["world_work"] = work_state
	var commit_receipt: Callable = callbacks.get("commit_receipt", Callable())
	if commit_receipt.is_valid():
		commit_receipt.call(receipt, record.coords, target, record.entity_id)
	apply_tool_wear(record, receipt)
	var latest_snapshot := world_state.get_entity_snapshot(record.entity_id)
	world_state.patch_entity_record(record.entity_id, {
		"runtime": record.runtime.duplicate(true),
		"definition": record.definition.duplicate(true),
		"revision": maxi(
			int(latest_snapshot.get("revision", 0)),
			int(record.revision)
		),
	})
	if receipt.work_completed or receipt.interrupted:
		world_state.release_world_action(action_id)
	else:
		world_state.update_world_action(action_id, {
			"actor_id": record.entity_id,
			"target_id": target.object_id,
			"verb_id": affordance.verb_id,
			"started_minute": int(
				reservation.get("started_minute", world_state.world_time_minutes)
			),
			"progress": receipt.work_progress,
			"last_receipt": receipt.to_dict(),
		})
	if receipt.work_completed and affordance.verb_id == WorldActionResolver.VERB_SEARCH:
		var deplete_after_search: Callable = callbacks.get(
			"deplete_after_search",
			Callable()
		)
		if deplete_after_search.is_valid():
			deplete_after_search.call(
				record.coords,
				target.object_id,
				record.entity_id
			)
		generate_salvage(record, target, macro_turn_index)
	return {
		"receipt": receipt,
		"target_id": target.object_id,
		"verb_id": affordance.verb_id,
	}


func apply_tool_wear(record: EntityRecord, receipt: WorldActionReceipt) -> void:
	if record == null or receipt == null or receipt.method_id.is_empty():
		return
	var wear := receipt.tool_wear
	if receipt.method_id == "crowbar":
		wear = maxf(wear, 0.10)
	elif receipt.method_id == "multitool":
		wear = maxf(wear, 0.16)
	if wear <= 0.0:
		return
	var carried: Array = record.runtime.get("inventory_items", [])
	for index in range(carried.size()):
		var item_value = carried[index]
		if not item_value is Dictionary:
			continue
		var state: Dictionary = item_value
		var definition: Dictionary = state.get("definition", {})
		var item_id := str(definition.get("id", state.get("item_id", "")))
		if (
			(receipt.method_id == "crowbar" and item_id not in ["crowbar", "bent_pry_bar"])
			or (receipt.method_id == "multitool" and item_id not in ["multitool", "lockpick"])
		):
			continue
		state = state.duplicate(true)
		state["current_condition"] = maxf(
			0.0,
			float(state.get("current_condition", GameEnums.SCALE_MAX)) - wear
		)
		carried[index] = state
		record.runtime["inventory_items"] = carried
		record.revision += 1
		world_state.patch_entity_record(record.entity_id, {
			"runtime": record.runtime,
			"revision": record.revision,
		})
		return


func consume_repair_material(record: EntityRecord) -> Dictionary:
	if record == null:
		return {}
	var carried: Array = record.runtime.get("inventory_items", [])
	for index in range(carried.size()):
		var item_value = carried[index]
		if not item_value is Dictionary:
			continue
		var definition: Dictionary = item_value.get("definition", {})
		var roles: Array = definition.get("functional_roles", [])
		var tags: Array = definition.get("tags", [])
		if not (roles.has("repair_material") or tags.has("materials")):
			continue
		var state: Dictionary = item_value.duplicate(true)
		var stack_count := int(state.get("stack_count", 1))
		if stack_count > 1:
			state["stack_count"] = stack_count - 1
			carried[index] = state
		else:
			carried.remove_at(index)
		record.runtime["inventory_items"] = carried
		if bool(state.get("_authored_loadout", false)):
			remove_loadout_template(record, str(state.get("template_path", "")))
		return {
			"instance_id": state.get("instance_id", ""),
			"item_id": definition.get("id", ""),
		}
	# Tactical handoff may have moved neutral states into the
	# InventorySystem-shaped equipment/backpack payload.
	var inventory: Dictionary = record.runtime.get("inventory", {}).duplicate(true)
	var equipment: Dictionary = inventory.get("equipment", {}).duplicate(true)
	for slot in equipment.keys():
		var equipped = equipment[slot]
		if not equipped is Dictionary:
			continue
		var definition: Dictionary = equipped.get("definition", {})
		var roles: Array = definition.get("functional_roles", [])
		var tags: Array = definition.get("tags", [])
		if not (roles.has("repair_material") or tags.has("materials")):
			continue
		var state: Dictionary = equipped.duplicate(true)
		equipment.erase(slot)
		inventory["equipment"] = equipment
		record.runtime["inventory"] = inventory
		if bool(state.get("_authored_loadout", false)):
			remove_loadout_template(record, str(state.get("template_path", "")))
		return {
			"instance_id": state.get("instance_id", ""),
			"item_id": definition.get("id", ""),
		}
	var backpack: Array = inventory.get("backpack", []).duplicate(true)
	for index in range(backpack.size()):
		var carried_value = backpack[index]
		if not carried_value is Dictionary:
			continue
		var definition: Dictionary = carried_value.get("definition", {})
		var roles: Array = definition.get("functional_roles", [])
		var tags: Array = definition.get("tags", [])
		if not (roles.has("repair_material") or tags.has("materials")):
			continue
		var state: Dictionary = carried_value.duplicate(true)
		var stack_count := int(state.get("stack_count", 1))
		if stack_count > 1:
			state["stack_count"] = stack_count - 1
			backpack[index] = state
		else:
			backpack.remove_at(index)
		inventory["backpack"] = backpack
		record.runtime["inventory"] = inventory
		if bool(state.get("_authored_loadout", false)):
			remove_loadout_template(record, str(state.get("template_path", "")))
		return {
			"instance_id": state.get("instance_id", ""),
			"item_id": definition.get("id", ""),
		}
	return {}


func remove_loadout_template(record: EntityRecord, template_path: String) -> void:
	if record == null or template_path.is_empty():
		return
	var loadout: Dictionary = record.definition.get("loadout", {}).duplicate(true)
	for key in [
		"weapon", "offhand", "inner_torso", "outer_torso", "legs", "feet", "vest",
		"backpack_gear", "head", "eyes", "face", "neck", "arms", "belt", "sling",
	]:
		if str(loadout.get(key, "")) == template_path:
			loadout[key] = ""
			record.definition["loadout"] = loadout
			return
	var starting_items: Array = loadout.get("starting_items", []).duplicate()
	for index in range(starting_items.size()):
		if str(starting_items[index]) == template_path:
			starting_items.remove_at(index)
			loadout["starting_items"] = starting_items
			record.definition["loadout"] = loadout
			return


func generate_salvage(
	record: EntityRecord,
	_target: WorldObjectRecord,
	macro_turn_index: int
) -> void:
	if record == null or loot_catalog == null or world_generator == null:
		return
	var hex := world_generator.get_hex_at(record.coords)
	var site_catalog := SearchSiteCatalog.data()
	var site := site_catalog.get_site(hex.search_site_id) if site_catalog != null else null
	if site == null:
		return
	var profile: Dictionary = loot_catalog.call(
		"get_profile_descriptor", site.loot_profile_id
	) as Dictionary
	var entries: Array = profile.get("guaranteed_entries", [])
	if entries.is_empty():
		entries = profile.get("entries", [])
	if entries.is_empty():
		return
	var index := absi((record.entity_id + str(macro_turn_index)).hash()) % entries.size()
	var item_id := str(entries[index].get("item_id", ""))
	if item_id.is_empty():
		return
	var item_state: Dictionary = loot_catalog.call(
		"create_runtime_item_state", item_id
	) as Dictionary
	if item_state.is_empty():
		return
	item_state["owner_id"] = record.entity_id
	item_state["physical_location"] = "inventory"
	var carried: Array = record.runtime.get("inventory_items", [])
	for carried_value in carried:
		if (
			carried_value is Dictionary
			and str(carried_value.get("instance_id", ""))
			== str(item_state.get("instance_id", ""))
		):
			return
	carried.append(item_state)
	record.runtime["inventory_items"] = carried
	record.knowledge["northward_evidence"] = {
		"source": record.entity_id,
		"coords": record.coords,
		"age_minutes": 0,
		"confidence": 0.5,
		"evidence": "disturbed_rubble",
	}
	record.runtime["macro_purpose_label"] = "Carrying salvage"
	record.revision += 1
	record.last_simulated_minute = world_state.world_time_minutes
	world_state.patch_entity_record(record.entity_id, {
		"runtime": record.runtime,
		"knowledge": record.knowledge,
		"revision": record.revision,
		"last_simulated_minute": record.last_simulated_minute,
	})


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
