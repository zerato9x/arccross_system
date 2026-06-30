extends RefCounted

## POI session snapshots, preview metrics, and neutral search/camp outcomes.
## MacroGameManager applies returned mutations to RuntimeStateStore and UI.


static func build_session_snapshot(
	coords: Vector2i,
	hex_data: MacroHexData,
	world_seed: String,
	world_time: Dictionary,
	hex_label: String,
	camp_access: Dictionary,
	available_items: Array,
	inventory_has_item_id: Callable,
	inventory_has_tag: Callable,
	inventory_has_role: Callable
) -> Dictionary:
	var camp_items := camp_item_descriptors(hex_data.camp_item_states)
	var camp_item_ids: Array = []
	for descriptor in camp_items:
		camp_item_ids.append(descriptor.get("instance_id", ""))
	var search_options := evaluated_search_options(
		world_seed,
		coords,
		hex_data,
		inventory_has_item_id,
		inventory_has_tag,
		inventory_has_role
	)
	var camp_interactions := evaluated_camp_interactions(
		MacroInteractionResolver.build_camp_interactions(
			hex_data,
			camp_access
		)
	)
	return {
		"poi_name": hex_data.poi_name,
		"hex_label": hex_label,
		"search_metric_keys": MacroInteractionResolver.SEARCH_KEYS,
		"camp_metric_keys": MacroInteractionResolver.CAMP_KEYS,
		"search_options": search_options,
		"camp_interactions": camp_interactions,
		"available_items": available_items,
		"camp_items": camp_item_options(hex_data.camp_item_states),
		"camp_item_ids": camp_item_ids,
		"camp_allowed": camp_access.get("allowed", false),
		"camp_block_reason": camp_access.get("reason", ""),
		"world_time": world_time,
	}


static func preview_metrics(
	action: GameEnums.PoiAction,
	world_seed: String,
	coords: Vector2i,
	hex_data: MacroHexData,
	selected_item_ids: Array,
	selected_search_option_id: String,
	tool_descriptors: Array,
	camp_preview_states: Array,
	loot_profile: Dictionary,
	inventory_has_item_id: Callable,
	inventory_has_tag: Callable,
	inventory_has_role: Callable
) -> Dictionary:
	var profile := MacroInteractionResolver.build_poi_profile(
		world_seed,
		coords,
		hex_data.biome,
		hex_data.poi_id
	)
	if action == GameEnums.PoiAction.SEARCH:
		var search_options := evaluated_search_options(
			world_seed,
			coords,
			hex_data,
			inventory_has_item_id,
			inventory_has_tag,
			inventory_has_role
		)
		var search_option := available_search_option(
			search_options,
			selected_search_option_id
		)
		var base_metrics: Dictionary = profile["search"]
		if not selected_search_option_id.is_empty():
			base_metrics = MacroInteractionResolver.apply_search_option_metrics(
				profile["search"],
				search_option
			)
		return MacroInteractionResolver.calculate_search_metrics(
			base_metrics,
			tool_descriptors,
			hex_data.search_count,
			loot_profile.get("max_searches", 4)
		)
	return MacroInteractionResolver.calculate_camp_metrics(
		profile["camp"],
		camp_item_descriptors(camp_preview_states)
	)


static func resolve_search_outcome(
	world_seed: String,
	coords: Vector2i,
	hex_data: MacroHexData,
	base_metrics: Dictionary,
	selected_item_ids: Array,
	selected_search_option_id: String,
	tool_descriptors: Array,
	loot_profile: Dictionary,
	inventory_has_item_id: Callable,
	inventory_has_tag: Callable,
	inventory_has_role: Callable
) -> Dictionary:
	var search_options := evaluated_search_options(
		world_seed,
		coords,
		hex_data,
		inventory_has_item_id,
		inventory_has_tag,
		inventory_has_role
	)
	var search_option := available_search_option(
		search_options,
		selected_search_option_id
	)
	if search_option.is_empty():
		return {
			"blocked": true,
			"title": "SEARCH BLOCKED",
			"message": "No unlocked search target is available at this hex.",
		}
	if bool(search_option.get("locked", false)):
		return {
			"blocked": true,
			"title": "SEARCH LOCKED",
			"message": str(
				search_option.get("lock_reason", "That target is locked.")
			),
		}

	var option_metrics: Dictionary = base_metrics
	if not selected_search_option_id.is_empty():
		option_metrics = MacroInteractionResolver.apply_search_option_metrics(
			base_metrics,
			search_option
		)
	var metrics := MacroInteractionResolver.calculate_search_metrics(
		option_metrics,
		tool_descriptors,
		hex_data.search_count,
		loot_profile.get("max_searches", 4)
	)
	var result := MacroInteractionResolver.resolve_search(
		world_seed,
		coords,
		hex_data.search_count,
		metrics,
		loot_profile,
		selected_search_option_id
	)
	if hex_data.region == GameEnums.MacroRegion.CENTRAL_HUB:
		result["injured"] = false
		result["attracted_enemy"] = false
	hex_data.search_count += 1

	return {
		"blocked": false,
		"coords": coords,
		"hex_state": hex_data.to_state(),
		"search_result": result,
		"loot_ids": result.get("loot_ids", []),
		"search_label": str(search_option.get("label", "Search")),
		"injured": bool(result.get("injured", false)),
		"injury_limb": result.get("injury_limb", GameEnums.LimbRegion.LEFT_ARM),
		"injury_damage": float(result.get("injury_damage", 0.0)),
		"attracted_enemy": bool(result.get("attracted_enemy", false)),
	}


static func apply_camp_gear_selection(
	hex_data: MacroHexData,
	coords: Vector2i,
	selected_item_ids: Array,
	find_item_callback: Callable,
	remove_item_callback: Callable,
	add_to_backpack_callback: Callable
) -> Dictionary:
	var selected: Array[String] = []
	for instance_id in selected_item_ids:
		if not selected.has(instance_id) and selected.size() < 3:
			selected.append(instance_id)

	var existing_states: Dictionary = {}
	for item_state in hex_data.camp_item_states:
		existing_states[item_state.get("instance_id", "")] = item_state

	var new_states: Array = []
	for instance_id in selected:
		if existing_states.has(instance_id):
			new_states.append(existing_states[instance_id])
			continue
		var item: ItemData = find_item_callback.call(instance_id)
		if (
			item == null
			or not item.has_interaction_role(
				GameEnums.InteractionItemRole.CAMP_GEAR
			)
		):
			continue
		var removed: ItemData = remove_item_callback.call(instance_id)
		if removed:
			new_states.append(removed.to_runtime_state())

	var ground_restore: Array = []
	for instance_id in existing_states.keys():
		if selected.has(instance_id):
			continue
		var returned_item := ItemData.from_runtime_state(
			existing_states[instance_id]
		)
		if not add_to_backpack_callback.call(returned_item):
			ground_restore.append(returned_item.to_runtime_state())

	hex_data.camp_item_states = new_states
	return {
		"hex_state": hex_data.to_state(),
		"camp_item_states": new_states,
		"ground_restore": ground_restore,
		"camp_descriptors": camp_item_descriptors(new_states),
	}


static func get_camp_access(
	hex_data: MacroHexData,
	has_hostile_entity: bool
) -> Dictionary:
	return WorldRules.get_camp_access(
		hex_data.is_poi,
		hex_data.hazard_level,
		has_hostile_entity
	)


static func available_interaction_options(inventory_items: Array) -> Array:
	var descriptors: Array = []
	for item in inventory_items:
		if item is ItemData and not item.interaction_roles.is_empty():
			descriptors.append({
				"instance_id": item.instance_id,
				"item_id": item.id,
				"name": item.display_name,
				"tags": item.tags.duplicate(),
				"roles": item.interaction_roles.duplicate(),
			})
	return descriptors


static func inventory_descriptors_for_ids(
	instance_ids: Array,
	role: GameEnums.InteractionItemRole,
	find_item_callback: Callable
) -> Array:
	var descriptors: Array = []
	for instance_id in instance_ids:
		var item: ItemData = find_item_callback.call(instance_id)
		if item != null and item.has_interaction_role(role):
			descriptors.append(item.to_interaction_descriptor())
	return descriptors


static func camp_states_for_preview(
	existing_states: Array,
	selected_item_ids: Array,
	find_item_callback: Callable
) -> Array:
	var states_by_id: Dictionary = {}
	for item_state in existing_states:
		states_by_id[item_state.get("instance_id", "")] = item_state
	for instance_id in selected_item_ids:
		if states_by_id.has(instance_id):
			continue
		var item: ItemData = find_item_callback.call(instance_id)
		if item and item.has_interaction_role(
			GameEnums.InteractionItemRole.CAMP_GEAR
		):
			states_by_id[instance_id] = item.to_runtime_state()
	var selected_states: Array = []
	for instance_id in selected_item_ids:
		if states_by_id.has(instance_id):
			selected_states.append(states_by_id[instance_id])
	return selected_states


static func evaluated_search_options(
	world_seed: String,
	coords: Vector2i,
	hex_data: MacroHexData,
	inventory_has_item_id: Callable,
	inventory_has_tag: Callable,
	inventory_has_role: Callable
) -> Array:
	var evaluated_options: Array = []
	for option in MacroInteractionResolver.build_search_options(
		world_seed,
		coords,
		hex_data
	):
		var evaluated: Dictionary = option.duplicate(true)
		var requirements: Dictionary = evaluated.get("requirements", {})
		var unlocked := requirements_met(
			requirements,
			inventory_has_item_id,
			inventory_has_tag,
			inventory_has_role
		)
		evaluated["locked"] = not unlocked
		evaluated["lock_reason"] = (
			"" if unlocked else requirement_text(requirements)
		)
		evaluated_options.append(evaluated)
	return evaluated_options


static func evaluated_camp_interactions(interactions: Array) -> Array:
	var evaluated_interactions: Array = []
	for interaction in interactions:
		var evaluated: Dictionary = interaction.duplicate(true)
		if bool(evaluated.get("available", false)):
			evaluated["lock_reason"] = ""
		else:
			var requirements: Dictionary = evaluated.get("requirements", {})
			evaluated["lock_reason"] = str(
				requirements.get("reason", "This camp interaction is unavailable.")
			)
		evaluated_interactions.append(evaluated)
	return evaluated_interactions


static func available_search_option(
	options: Array,
	selected_search_option_id: String
) -> Dictionary:
	var selected := MacroInteractionResolver.find_option(
		options,
		selected_search_option_id
	)
	if not selected.is_empty():
		return selected
	for option in options:
		if not bool(option.get("locked", false)):
			return option
	return {}


static func camp_item_descriptors(item_states: Array) -> Array:
	var descriptors: Array = []
	for item_state in item_states:
		var item := ItemData.from_runtime_state(item_state)
		var descriptor := item.to_interaction_descriptor()
		descriptor["installed"] = true
		descriptors.append(descriptor)
	return descriptors


static func camp_item_options(item_states: Array) -> Array:
	var options: Array = []
	for item_state in item_states:
		var definition: Dictionary = item_state.get("definition", {})
		options.append({
			"instance_id": item_state.get("instance_id", ""),
			"name": definition.get("display_name", "Unknown Camp Gear"),
			"roles": definition.get("interaction_roles", []).duplicate(),
			"installed": true,
		})
	return options


static func requirements_met(
	requirements: Dictionary,
	inventory_has_item_id: Callable,
	inventory_has_tag: Callable,
	inventory_has_role: Callable
) -> bool:
	if requirements.is_empty():
		return true

	var has_requirement := false
	var satisfied := false
	var item_ids: Array = requirements.get("any_item_ids", [])
	if not item_ids.is_empty():
		has_requirement = true
		satisfied = satisfied or inventory_has_item_id.call(item_ids)

	var tags: Array = requirements.get("any_tags", [])
	if not tags.is_empty():
		has_requirement = true
		satisfied = satisfied or inventory_has_tag.call(tags)

	var roles: Array = requirements.get("any_roles", [])
	if not roles.is_empty():
		has_requirement = true
		satisfied = satisfied or inventory_has_role.call(roles)

	var traits: Array = requirements.get("any_traits", [])
	if not traits.is_empty():
		has_requirement = true

	return not has_requirement or satisfied


static func requirement_text(requirements: Dictionary) -> String:
	var parts: Array[String] = []
	var item_ids: Array = requirements.get("any_item_ids", [])
	if not item_ids.is_empty():
		parts.append("item: " + "/".join(PackedStringArray(item_ids)))
	var tags: Array = requirements.get("any_tags", [])
	if not tags.is_empty():
		parts.append("tag: " + "/".join(PackedStringArray(tags)))
	var roles: Array = requirements.get("any_roles", [])
	if not roles.is_empty():
		var role_names := PackedStringArray()
		for role in roles:
			role_names.append(_interaction_role_name(int(role)))
		parts.append("role: " + "/".join(role_names))
	var traits: Array = requirements.get("any_traits", [])
	if not traits.is_empty():
		parts.append("trait: " + "/".join(PackedStringArray(traits)))
	if parts.is_empty():
		return str(requirements.get("reason", "Requirement not met."))
	return "Requires " + " or ".join(parts) + "."


static func _interaction_role_name(role: int) -> String:
	if role >= 0 and role < GameEnums.InteractionItemRole.keys().size():
		return GameEnums.InteractionItemRole.keys()[role]
	return str(role)
