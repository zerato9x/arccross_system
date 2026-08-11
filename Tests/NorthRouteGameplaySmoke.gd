extends SceneTree

const SEED := "NORTH_ROUTE_GAMEPLAY_SYSTEMIC_SMOKE"

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var graph := MacroGraphGenerator.generate_web(SEED)
	var starts := MacroGraphGenerator.allowed_start_node_ids()
	if starts.size() != 4:
		return _fail("The four Central-adjacent Route 1 arms must remain playable.")
	for route_id in ["north_random_1", "east_random_1", "south_random_1", "west_random_1"]:
		var node := graph.get_node(route_id)
		if node == null or not node.unlocked:
			return _fail("Route 1 arm is not open: " + route_id)
	var north_two := graph.get_node("north_random_2")
	var shelter := graph.get_node("north_r2_shelter")
	if north_two == null or not north_two.unlocked:
		return _fail("North Route 2 must exist without an objective permission flag.")
	if shelter == null or shelter.persistence != GameEnums.MacroNodePersistence.PERMANENT_META:
		return _fail("The Route 2 shelter must be a stable permanent-meta node.")
	if graph.get_edge("north_random_2", "north_r2_shelter").is_empty():
		return _fail("North Route 2 has no physical shelter connection.")
	if not RouteObjectiveCatalog.data().get_objective("restore_north_fringe_relay") == null:
		return _fail("The retired North Route 1 relay objective still exists.")
	var zone := MacroZoneGenerator.new()
	var state := RuntimeStateStore.new()
	state.begin_new_world(SEED)
	zone.configure_services(state)
	zone.configure_seed(SEED)
	zone.generate_node_zone(shelter, MacroGraphGenerator.arrival_direction_for_start(shelter.id), [])
	var shelter_hex := zone.get_hex_at(Vector2i.ZERO)
	if shelter_hex.world_objects.is_empty():
		return _fail("Shelter generation produced no physical world object.")
	var found_shelter := false
	for value in shelter_hex.world_objects:
		if value is Dictionary and str(value.get("definition_id", "")) == "shelter":
			found_shelter = true
			var components: Dictionary = value.get("components", {})
			if not components.has("repairable") or not components.has("bed") or not components.has("power"):
				return _fail("Shelter object is missing required physical sockets.")
	if not found_shelter:
		return _fail("Shelter center is not represented by a component-backed object.")
	print("[TEST PASS] Route 1 is open, North Route 2 is physical, and the permanent shelter has real sockets.")
	quit(0)


func _fail(message: String) -> void:
	push_error("[NorthRouteGameplaySmoke] " + message)
	quit(1)
