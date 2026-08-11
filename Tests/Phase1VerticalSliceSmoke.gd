extends SceneTree

## Replaced the retired authored Phase 1 walkthrough. The current smoke keeps
## the useful persistence boundary while asserting systemic Route 1/HERE
## contracts instead of depending on the removed settlement and exploration
## window.

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var seed := "SYSTEMIC_PHASE_1_SMOKE"
	var state := RuntimeStateStore.new()
	state.begin_new_world(seed)
	var graph := MacroGraphGenerator.generate_web(seed)
	for node_id in ["north_random_1", "east_random_1", "south_random_1", "west_random_1"]:
		var node := graph.get_node(node_id)
		if node == null or not node.unlocked:
			return _fail("Route 1 arm is not available: " + node_id)
	var shelter := graph.get_node("north_r2_shelter") as MacroNodeData
	if shelter == null or shelter.persistence != GameEnums.MacroNodePersistence.PERMANENT_META:
		return _fail("Permanent Route 2 shelter is missing.")
	var zone := MacroZoneGenerator.new()
	zone.configure_services(state)
	zone.configure_seed(seed)
	zone.generate_node_zone(shelter, MacroGraphGenerator.arrival_direction_for_start(shelter.id), [])
	var center := zone.get_hex_at(Vector2i.ZERO)
	var shelter_object: WorldObjectRecord = null
	for value in center.world_objects:
		if value is Dictionary:
			var object := WorldObjectRecord.from_dict(value)
			if object.definition_id == "shelter":
				shelter_object = object
				break
	if shelter_object == null:
		return _fail("Shelter was not generated as a physical object.")
	var affordances := WorldActionResolver.query_affordances(
		{"actor_id": "player", "capabilities": ["hands", "material"]},
		shelter_object
	)
	if not _has_affordance(affordances, WorldActionResolver.VERB_REPAIR):
		return _fail("Shelter repair is not a HERE affordance.")
	var request := WorldActionRequest.new()
	request.actor_id = "player"
	request.target_id = shelter_object.object_id
	request.target_coords = Vector2i.ZERO
	request.verb_id = WorldActionResolver.VERB_REPAIR
	var receipt := WorldActionResolver.resolve_work_attempt(
		request,
		WorldActionResolver.profile_for_id("repair_manual"),
		{"action_id": "phase1-shelter", "completed_units": 0, "elapsed_minutes": 15},
		true
	)
	if not receipt.committed or receipt.mutations.is_empty():
		return _fail("Shared repair did not emit an atomic receipt.")
	print("[TEST PASS] Systemic Phase 1 route, physical shelter, HERE affordance, and receipt boundary.")
	quit(0)


func _has_affordance(values: Array, verb_id: String) -> bool:
	for value in values:
		if value is WorldAffordance and value.verb_id == verb_id:
			return true
	return false


func _fail(message: String) -> void:
	push_error("[Phase1VerticalSliceSmoke] " + message)
	quit(1)
