extends SceneTree

const SEED := "NORTH_ROUTE_GAMEPLAY_SMOKE"
const RoutePopulationCatalogScript := preload("res://WorldCore/RoutePopulationCatalog.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var graph := MacroGraphGenerator.generate_web(SEED)
	var route_one_ids := ["north_random_1", "east_random_1", "south_random_1", "west_random_1"]
	for route_id in route_one_ids:
		var node := graph.get_node(route_id)
		if node == null or not node.unlocked or not node.discovered:
			return _fail("Act 1 route is not accessible: " + route_id)
	if MacroGraphGenerator.allowed_start_node_ids() != PackedStringArray(route_one_ids):
		return _fail("All four Route 1 arms must be valid eviction starts.")
	for link in [["north_random_1", "east_random_1"], ["east_random_1", "south_random_1"], ["south_random_1", "west_random_1"], ["west_random_1", "north_random_1"]]:
		if graph.get_edge(link[0], link[1]).is_empty():
			return _fail("Act 1 inner-ring link is missing: " + str(link))
	var north_two := graph.get_node("north_random_2")
	if north_two == null or north_two.unlocked:
		return _fail("North Route 2 must begin locked until relay restoration.")

	var expected_arm_sites := {
		"north_random_1": "route1_rubble_key_cache",
		"east_random_1": "route1_relic_fuse",
		"south_random_1": "route1_relic_insulator",
		"west_random_1": "route1_relic_seal",
	}
	for route_id in route_one_ids:
		var zone := MacroZoneGenerator.new()
		zone.configure_seed(SEED)
		var arrival := MacroGraphGenerator.arrival_direction_for_start(route_id)
		zone.generate_node_zone(graph.get_node(route_id), arrival, [arrival, HexCoordUtils.opposite_travel_direction(arrival)])
		var assigned_sites: Array[String] = []
		for coords in zone.world_hex_cache.keys():
			var hex_data := zone.get_hex_at(coords)
			if not hex_data.search_site_id.is_empty():
				assigned_sites.append(hex_data.search_site_id)
		if assigned_sites.size() != 7:
			return _fail("%s generated %d searchable rubble sites instead of 7." % [route_id, assigned_sites.size()])
		if not assigned_sites.has("route1_rubble_tutorial") or not assigned_sites.has(expected_arm_sites[route_id]):
			return _fail("%s is missing its tutorial or Act 1 objective cache." % route_id)

	var search_catalog := SearchSiteCatalog.data()
	if search_catalog == null:
		return _fail("Search-site catalog is missing.")
	var errors := search_catalog.validate()
	if not errors.is_empty():
		return _fail("Search-site data invalid: " + "; ".join(errors))
	if not search_catalog.get_site("route1_rubble_tutorial").requirements.is_empty():
		return _fail("Tutorial rubble must be searchable without starting gear.")
	if search_catalog.get_site("route1_rubble_locked").requirements.is_empty():
		return _fail("Locked rubble does not teach a tool requirement.")

	var objective_catalog := RouteObjectiveCatalog.data()
	var objective := objective_catalog.get_objective("restore_north_fringe_relay") if objective_catalog != null else null
	if objective == null or objective.required_item_ids.size() != 3:
		return _fail("North relay objective does not require exactly three relics.")
	if not objective.completion_trigger_ids.has("objective:north_relay_restored"):
		return _fail("North relay objective cannot reveal the next node.")

	var loadouts := NpcLoadoutCatalog.data()
	for role_id in ["technician", "salvager", "raider", "sentry", "plot_agent"]:
		var profile := loadouts.for_role(role_id) if loadouts != null else null
		if profile == null or profile.slot_pools.size() < 4:
			return _fail("NPC role lacks a varied data loadout: " + role_id)
	var populations: Variant = RoutePopulationCatalogScript.data()
	for route_id in route_one_ids:
		var population: RoutePopulationProfile = populations.for_node(route_id) if populations != null else null
		if population == null or population.spawn_entries.is_empty():
			return _fail("Route 1 population profile is missing: " + route_id)
	var visuals := load("res://UI/Humanoid/equipment_visuals.tres") as HumanoidEquipmentVisualCatalog
	if visuals == null or visuals.directory_for("bent_pry_bar").is_empty():
		return _fail("Equipment visual aliases are not data-driven.")

	print("[TEST PASS] Four-arm Act 1 circuit, distributed relics, North gate, and varied NPC data are valid.")
	quit(0)


func _fail(message: String) -> void:
	push_error("[TEST FAIL] " + message)
	quit(1)
