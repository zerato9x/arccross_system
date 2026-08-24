extends RefCounted

const SiteCatalog := preload("res://WorldCore/SiteCatalog.gd")

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
	if hex_data.searched_targets.has(selected_search_option_id):
		return {
			"blocked": true,
			"title": "ALREADY SEARCHED",
			"message": "This structure has already been looted.",
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
	if hex_data.region in [
		GameEnums.MacroRegion.CENTRAL_HUB,
		GameEnums.MacroRegion.HUB_BORDER,
	]:
		result["injured"] = false
		result["attracted_enemy"] = false
	return {
		"blocked": false,
		"coords": coords,
		"search_result": result,
		"loot_ids": result.get("loot_ids", []),
		"search_label": str(search_option.get("label", "Search")),
		"injured": bool(result.get("injured", false)),
		"injury_limb": result.get("injury_limb", GameEnums.LimbRegion.LEFT_ARM),
		"injury_damage": float(result.get("injury_damage", 0.0)),
		"attracted_enemy": bool(result.get("attracted_enemy", false)),
	}


static func get_camp_access(
	hex_data: MacroHexData,
	has_hostile_entity: bool
) -> Dictionary:
	return WorldRules.get_camp_access(
		hex_data.has_landmark(),
		hex_data.hazard_level,
		has_hostile_entity
	)


static func available_interaction_options(inventory_items: Array) -> Array:
	var descriptors: Array = []
	for item in inventory_items:
		if item is ItemData and not item.interaction_roles.is_empty():
			var roles: Array = item.interaction_roles.duplicate()
			var descriptor: Dictionary = item.to_interaction_descriptor()
			descriptor["item_id"] = item.id
			descriptor["sprite_path"] = item.get_inventory_sprite_path()
			descriptor["tags"] = item.tags.duplicate()
			descriptor["roles"] = roles
			descriptor["interaction_roles"] = roles
			descriptors.append(descriptor)
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
		if item and (
			item.has_interaction_role(GameEnums.InteractionItemRole.CAMP_GEAR)
			or item.has_interaction_role(GameEnums.InteractionItemRole.TRAP_GEAR)
		):
			states_by_id[instance_id] = item.to_runtime_state()
	var selected_states: Array = []
	for instance_id in selected_item_ids:
		if states_by_id.has(instance_id):
			selected_states.append(states_by_id[instance_id])
	return selected_states


static func build_landmark_search_options(
	hex_data: MacroHexData,
	world_seed: String,
	coords: Vector2i
) -> Array:
	if hex_data.poi_id == "arm_core":
		var restored := hex_data.searched_targets.has("restore_regional_core")
		return [{
			"id": "restore_regional_core",
			"label": "Restore Regional Core",
			"description": "Bring this regional infrastructure Core back into the network.",
			"requirements": {},
			"metric_modifiers": {"loot": 0.0, "safety": 0.0, "sneak": 0.0},
			"priority": 0,
			"locked": restored,
			"depleted": restored,
			"lock_reason": "This regional Core has already been restored." if restored else "",
		}]
	const PoiVisualCatalog := preload("res://PresentationCore/PoiVisualCatalog.gd")
	var props := PoiVisualCatalog.build_prop_descriptors(
		hex_data,
		world_seed,
		coords
	)
	var searched: Array = hex_data.searched_targets
	var options: Array = []
	if props.is_empty():
		options.append({
			"id": "primary_search",
			"label": (
				hex_data.poi_name
				if not hex_data.poi_name.is_empty()
				else "Scavenge Area"
			),
			"description": "Search the landmark for usable supplies.",
			"requirements": {},
			"metric_modifiers": {"loot": 1.0, "safety": 0.0, "sneak": 0.0},
			"priority": 0,
			"locked": false,
			"lock_reason": "",
		})
	else:
		for index in range(props.size()):
			if not props[index] is Dictionary:
				continue
			var prop: Dictionary = props[index]
			var option_id := str(prop.get("search_option_id", "structure_%d" % index))
			var depleted := searched.has(option_id)
			options.append({
				"id": option_id,
				"label": str(prop.get("label", "Search Target")),
				"description": "Search this structure for salvage.",
				"requirements": {},
				"metric_modifiers": {
					"loot": 1.0 + float(index) * 0.35,
					"safety": -0.25 * float(index),
					"sneak": -0.15 * float(index),
				},
				"priority": index,
				"locked": depleted,
				"depleted": depleted,
				"lock_reason": (
					"This structure has already been searched."
					if depleted
					else ""
				),
			})
	if hex_data.poi_id == "plains_homestead":
		var event_option_id := "event_locked_treatment_room"
		var event_completed := searched.has(event_option_id)
		options.append({
			"id": event_option_id,
			"label": "Locked Treatment Room",
			"description": "Investigate the sealed treatment wing inside the homestead.",
			"requirements": {},
			"metric_modifiers": {"loot": 0.0, "safety": -1.0, "sneak": 0.0},
			"priority": options.size(),
			"locked": event_completed,
			"depleted": event_completed,
			"lock_reason": (
				"The treatment room event has already been resolved."
				if event_completed
				else ""
			),
		})
	return options


static func format_slot_label(slot_id: String) -> String:
	match slot_id:
		"sleep_spot", "sleep_assist":
			return "Sleep with…"
		"tool_assist", "tool_0":
			return "Tool"
		"camp_assist":
			return "Bedroll / Gear"
		"trap_assist", "trap_0":
			return "Door Frame Trap"
		"trap_1":
			return "Brush Line Trap"
		_:
			if slot_id.begins_with("camp_gear_"):
				return "Camp Gear"
			if slot_id.begins_with("tool_"):
				return "Tool"
			return slot_id.replace("_", " ").capitalize()


static func build_search_gear_slots() -> Array:
	return [{
		"id": "tool_assist",
		"label": format_slot_label("tool_assist"),
		"accepted_roles": [GameEnums.InteractionItemRole.SEARCH_TOOL],
		"assigned_instance_id": "",
		"assigned_name": "",
	}]


static func build_search_drop_targets(
	_hex_data: MacroHexData,
	_search_options: Array
) -> Array:
	return build_search_gear_slots()


static func build_camp_drop_targets(hex_data: MacroHexData) -> Array:
	var targets: Array = [{
		"id": "sleep_spot",
		"label": format_slot_label("sleep_spot"),
		"accepted_roles": [GameEnums.InteractionItemRole.CAMP_GEAR],
		"assigned_instance_id": hex_data.sleep_gear_instance_id,
		"assigned_name": "",
	}]
	for gear_index in range(3):
		var assigned_id := ""
		if gear_index < hex_data.camp_item_states.size():
			assigned_id = str(hex_data.camp_item_states[gear_index].get("instance_id", ""))
		targets.append({
			"id": "camp_gear_%d" % gear_index,
			"label": "Camp gear" if gear_index == 0 else "Extra gear %d" % (gear_index + 1),
			"accepted_roles": [GameEnums.InteractionItemRole.CAMP_GEAR],
			"assigned_instance_id": assigned_id,
			"assigned_name": "",
		})
	for trap_index in range(2):
		var trap_state: Dictionary = (
			hex_data.camp_traps[trap_index]
			if trap_index < hex_data.camp_traps.size()
			else {}
		)
		targets.append({
			"id": "trap_%d" % trap_index,
			"label": format_slot_label("trap_%d" % trap_index),
			"accepted_roles": [GameEnums.InteractionItemRole.TRAP_GEAR],
			"assigned_instance_id": str(trap_state.get("instance_id", "")),
			"assigned_name": "",
			"anchor_id": str(trap_state.get("anchor_id", "door_frame")),
			"sector": Vector2i(
				int(trap_state.get("sector_x", 1)),
				int(trap_state.get("sector_y", 2 + trap_index))
			),
		})
	return targets


static func build_fixture_drop_targets(site: Dictionary, fixture_id: String) -> Array:
	var fixture := SiteCatalog.fixture_by_id(site, fixture_id)
	if fixture.is_empty():
		return []
	var verbs: Array = fixture.get("verbs", [])
	var targets: Array = []
	if SiteCatalog.VERB_SEARCH in verbs:
		targets.append({
			"id": "tool_assist",
			"label": "Tool for %s" % str(fixture.get("label", "fixture")),
			"accepted_roles": [GameEnums.InteractionItemRole.SEARCH_TOOL],
			"assigned_instance_id": "",
			"assigned_name": "",
		})
	if SiteCatalog.VERB_SLEEP in verbs:
		targets.append({
			"id": "sleep_assist",
			"label": "Sleep with…",
			"accepted_roles": [GameEnums.InteractionItemRole.CAMP_GEAR],
			"assigned_instance_id": "",
			"assigned_name": "",
		})
	if SiteCatalog.VERB_TRAP in verbs:
		targets.append({
			"id": "trap_assist",
			"label": "Arm trap",
			"accepted_roles": [GameEnums.InteractionItemRole.TRAP_GEAR],
			"assigned_instance_id": "",
			"assigned_name": "",
			"anchor_id": str(fixture.get("id", "door_frame")),
			"sector": Vector2i(1, 2),
		})
	return targets


static func build_landmark_session_snapshot(
	coords: Vector2i,
	hex_data: MacroHexData,
	world_seed: String,
	world_time: Dictionary,
	hex_label: String,
	camp_access: Dictionary,
	available_items: Array,
	ground_items: Array,
	inventory_has_item_id: Callable,
	inventory_has_tag: Callable,
	inventory_has_role: Callable
) -> Dictionary:
	const EventBgCatalog := preload("res://PresentationCore/EventBgCatalog.gd")
	const PoiVisualCatalog := preload("res://PresentationCore/PoiVisualCatalog.gd")
	var search_options := evaluated_search_options(
		world_seed,
		coords,
		hex_data,
		inventory_has_item_id,
		inventory_has_tag,
		inventory_has_role
	)
	var site := SiteCatalog.site_for_hex(
		hex_data,
		search_options,
		camp_access,
		world_seed,
		coords
	)
	var default_fixture_id := _default_fixture_id(site)
	var default_fixture := SiteCatalog.fixture_by_id(site, default_fixture_id)
	var scene_descriptor := EventBgCatalog.build_scene_descriptor(
		hex_data,
		world_seed,
		coords
	)
	scene_descriptor["props"] = align_props_to_site_fixtures(
		scene_descriptor.get("props", []),
		site,
		hex_data,
		world_seed,
		coords
	)
	return {
		"poi_name": hex_data.poi_name,
		"hex_label": hex_label,
		"has_search": not SiteCatalog.searchable_fixtures(site).is_empty(),
		"place_centric": true,
		"site": site,
		"selected_fixture_id": default_fixture_id,
		"scene_descriptor": scene_descriptor,
		"available_items": available_items,
		"search_drop_targets": build_fixture_drop_targets(site, default_fixture_id),
		"search_gear_slots": build_search_gear_slots(),
		"camp_drop_targets": build_camp_drop_targets(hex_data),
		"fixture_drop_targets": build_fixture_drop_targets(site, default_fixture_id),
		"ground_items": ground_items,
		"search_options": search_options,
		"searched_targets": hex_data.searched_targets.duplicate(),
		"camp_allowed": camp_access.get("allowed", false),
		"camp_block_reason": camp_access.get("reason", ""),
		"rest_in_progress": hex_data.rest_in_progress,
		"sleep_anchor_label": PoiVisualCatalog.sleep_anchor_label(hex_data.sleep_anchor),
		"world_time": world_time,
		"selected_search_option_id": str(
			default_fixture.get(
				"search_option_id",
				str(search_options[0].get("id", "primary_search"))
				if not search_options.is_empty()
				else "primary_search"
			)
		),
	}


static func build_hex_session_snapshot(
	coords: Vector2i,
	hex_data: MacroHexData,
	world_seed: String,
	world_time: Dictionary,
	hex_label: String,
	camp_access: Dictionary,
	available_items: Array,
	ground_items: Array,
	inventory_has_item_id: Callable = Callable(),
	inventory_has_tag: Callable = Callable(),
	inventory_has_role: Callable = Callable()
) -> Dictionary:
	const EventBgCatalog := preload("res://PresentationCore/EventBgCatalog.gd")
	const WorldSectorCatalog := preload("res://WorldCore/WorldSectorCatalog.gd")
	var search_options: Array = []
	if (
		inventory_has_item_id.is_valid()
		and inventory_has_tag.is_valid()
		and inventory_has_role.is_valid()
	):
		search_options = evaluated_search_options(
			world_seed,
			coords,
			hex_data,
			inventory_has_item_id,
			inventory_has_tag,
			inventory_has_role
		)
	else:
		search_options = MacroInteractionResolver.build_search_options(
			world_seed,
			coords,
			hex_data
		)
	var site := SiteCatalog.site_for_hex(hex_data, search_options, camp_access, world_seed, coords)
	var default_fixture_id := _default_fixture_id(site)
	var default_fixture := SiteCatalog.fixture_by_id(site, default_fixture_id)
	var searchable := SiteCatalog.searchable_fixtures(site)
	var props := align_props_to_site_fixtures(
		[],
		site,
		hex_data,
		world_seed,
		coords
	)
	return {
		"poi_name": hex_label if not hex_label.is_empty() else "Neighborhood Parcel",
		"hex_label": hex_label,
		"has_search": not searchable.is_empty(),
		"place_centric": true,
		"site": site,
		"selected_fixture_id": default_fixture_id,
		"scene_descriptor": {
			"background_path": EventBgCatalog.resolve_background(hex_data),
			"props": props,
			"zone_name": WorldSectorCatalog.wedge_display_name(hex_data.zone_id),
		},
		"available_items": available_items,
		"search_drop_targets": build_fixture_drop_targets(site, default_fixture_id),
		"search_gear_slots": build_search_gear_slots(),
		"camp_drop_targets": build_camp_drop_targets(hex_data),
		"fixture_drop_targets": build_fixture_drop_targets(site, default_fixture_id),
		"ground_items": ground_items,
		"search_options": search_options,
		"searched_targets": hex_data.searched_targets.duplicate(),
		"camp_allowed": camp_access.get("allowed", false),
		"camp_block_reason": camp_access.get("reason", ""),
		"rest_in_progress": hex_data.rest_in_progress,
		"world_time": world_time,
		"selected_search_option_id": str(
			default_fixture.get("search_option_id", "")
		),
	}


static func align_props_to_site_fixtures(
	existing_props: Array,
	site: Dictionary,
	hex_data: MacroHexData,
	world_seed: String,
	coords: Vector2i
) -> Array:
	const PoiVisualCatalog := preload("res://PresentationCore/PoiVisualCatalog.gd")
	var searchable := SiteCatalog.searchable_fixtures(site)
	if searchable.is_empty():
		return existing_props.duplicate(true)
	var by_option: Dictionary = {}
	for prop in existing_props:
		if not prop is Dictionary:
			continue
		var option_id := str(prop.get("search_option_id", prop.get("id", "")))
		if not option_id.is_empty():
			by_option[option_id] = prop.duplicate(true)
	var aligned: Array = []
	for fixture in searchable:
		if not fixture is Dictionary:
			continue
		var option_id := str(fixture.get("search_option_id", ""))
		if option_id.is_empty():
			continue
		var prop: Dictionary = {}
		if by_option.has(option_id):
			prop = by_option[option_id].duplicate(true)
		else:
			var sprite_path := ""
			if hex_data.flora_layer != GameEnums.MacroFloraLayer.NONE:
				sprite_path = PoiVisualCatalog.pick_flora_path(world_seed, coords)
			if sprite_path.is_empty() and not hex_data.structure_sprite_path.is_empty():
				sprite_path = hex_data.structure_sprite_path
			if sprite_path.is_empty():
				var structures := PoiVisualCatalog.pick_structure_paths(
					hex_data.landmark_id if not hex_data.landmark_id.is_empty() else hex_data.poi_id,
					world_seed,
					coords,
					1
				)
				if not structures.is_empty():
					sprite_path = str(structures[0])
			if sprite_path.is_empty():
				continue
			prop = {
				"id": option_id,
				"label": str(fixture.get("label", option_id)),
				"sprite_path": sprite_path,
				"search_option_id": option_id,
			}
		prop["anchor"] = fixture.get("anchor", prop.get("anchor", Vector2(0.5, 0.55)))
		prop["label"] = str(fixture.get("label", prop.get("label", option_id)))
		prop["search_option_id"] = option_id
		aligned.append(prop)
	return aligned


static func _default_fixture_id(site: Dictionary) -> String:
	for fixture in site.get("fixtures", []):
		if fixture is Dictionary and not str(fixture.get("id", "")).is_empty():
			return str(fixture.get("id", ""))
	return ""


static func camp_states_for_session_preview(
	hex_data: MacroHexData,
	selected_item_ids: Array,
	find_item_callback: Callable
) -> Array:
	var states := camp_states_for_preview(
		hex_data.camp_item_states,
		selected_item_ids,
		find_item_callback
	)
	if not hex_data.sleep_gear_instance_id.is_empty():
		var sleep_item: ItemData = find_item_callback.call(
			hex_data.sleep_gear_instance_id
		)
		if sleep_item != null:
			var sleep_state := sleep_item.to_runtime_state()
			var already_present := false
			for item_state in states:
				if item_state.get("instance_id", "") == hex_data.sleep_gear_instance_id:
					already_present = true
					break
			if not already_present:
				states.append(sleep_state)
	for instance_id in selected_item_ids:
		if instance_id == hex_data.sleep_gear_instance_id:
			continue
		var item: ItemData = find_item_callback.call(instance_id)
		if (
			item != null
			and item.has_interaction_role(GameEnums.InteractionItemRole.CAMP_GEAR)
			and item.camp_sleep_bonus > 0.0
		):
			var sleep_state := item.to_runtime_state()
			var duplicate := false
			for item_state in states:
				if item_state.get("instance_id", "") == instance_id:
					duplicate = true
					break
			if not duplicate:
				states.append(sleep_state)
	return states


static func evaluated_search_options(
	world_seed: String,
	coords: Vector2i,
	hex_data: MacroHexData,
	inventory_has_item_id: Callable,
	inventory_has_tag: Callable,
	inventory_has_role: Callable
) -> Array:
	if hex_data.has_landmark():
		return build_landmark_search_options(hex_data, world_seed, coords)
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
