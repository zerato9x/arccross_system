extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var state := RuntimeStateStore.new()
	state.begin_new_world("SYSTEMIC_SHELTER_SMOKE")
	var meta := root.get_node_or_null("MetaProgression") as MetaProgressionStore
	if meta == null:
		return _fail("Meta progression store is unavailable.")
	meta.set_shelter_state("north_r2_shelter", {"state": "ruined"}, false)
	var graph := MacroGraphGenerator.generate_web(state.world_seed)
	var shelter := graph.get_node("north_r2_shelter") as MacroNodeData
	if shelter == null or shelter.persistence != GameEnums.MacroNodePersistence.PERMANENT_META:
		return _fail("Permanent shelter node is missing.")
	var zone := MacroZoneGenerator.new()
	zone.configure_services(state)
	zone.configure_seed(state.world_seed)
	for expected_state in ["ruined", "habitable", "repaired_overrun", "secured", "secured_damaged"]:
		meta.set_shelter_state("north_r2_shelter", {"state": expected_state}, false)
		zone.generate_node_zone(shelter, MacroGraphGenerator.arrival_direction_for_start(shelter.id), [])
		var center := zone.get_hex_at(Vector2i.ZERO)
		var object := _find_object(center.world_objects, "shelter")
		if object == null:
			return _fail("Shelter center object is missing for state %s." % expected_state)
		if str(object.component("shelter").get("state", "")) != expected_state:
			return _fail("Shelter state did not persist as %s." % expected_state)
		for component_id in ["repairable", "roof", "door", "power", "water", "storage", "bed", "barricade"]:
			if not object.has_component(component_id):
				return _fail("Shelter lost required component: " + component_id)
	var role_sockets := {}
	for coords in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1)]:
		for object_value in zone.get_hex_at(coords).world_objects:
			if object_value is Dictionary:
				var socket := WorldObjectRecord.from_dict(object_value)
				var role := str(socket.runtime.get("shelter_role_socket", ""))
				if not role.is_empty():
					role_sockets[role] = true
	for required_role in ["material_salvage", "utility_water", "craven_approach"]:
		if not role_sockets.has(required_role):
			return _fail("Shelter is missing connected role socket: " + required_role)
	var center_object := _find_object(zone.get_hex_at(Vector2i.ZERO).world_objects, "shelter")
	var affordances := WorldActionResolver.query_affordances(
		{"capabilities": ["hands", "material"]}, center_object
	)
	if _find_affordance(affordances, WorldActionResolver.VERB_REPAIR) == null:
		return _fail("Shelter repair is not a shared affordance.")
	var profile := WorldActionResolver.profile_for_id("repair_manual")
	var player_request := WorldActionRequest.new()
	player_request.actor_id = "player"
	player_request.target_id = center_object.object_id
	player_request.target_coords = Vector2i.ZERO
	player_request.verb_id = WorldActionResolver.VERB_REPAIR
	var ai_request := WorldActionRequest.new()
	ai_request.actor_id = "craven-test-worker"
	ai_request.target_id = center_object.object_id
	ai_request.target_coords = Vector2i.ZERO
	ai_request.verb_id = WorldActionResolver.VERB_REPAIR
	var player_receipt := WorldActionResolver.resolve_work_attempt(
		player_request, profile, {"action_id": "shelter-parity", "completed_units": 0, "elapsed_minutes": 15}, true
	)
	var ai_receipt := WorldActionResolver.resolve_work_attempt(
		ai_request, profile, {"action_id": "shelter-parity", "completed_units": 0, "elapsed_minutes": 15}, true
	)
	var player_dict := player_receipt.to_dict()
	var ai_dict := ai_receipt.to_dict()
	player_dict["actor_id"] = ""
	ai_dict["actor_id"] = ""
	if player_dict != ai_dict:
		return _fail("Shelter work diverged between player and AI receipts.")
	print("[SystemicShelterSmoke] PASSED")
	quit(0)


func _find_object(values: Array, definition_id: String) -> WorldObjectRecord:
	for value in values:
		if value is Dictionary:
			var record := WorldObjectRecord.from_dict(value)
			if record.definition_id == definition_id:
				return record
	return null


func _find_affordance(values: Array, verb_id: String) -> WorldAffordance:
	for value in values:
		var affordance := value as WorldAffordance
		if affordance != null and affordance.verb_id == verb_id:
			return affordance
	return null


func _fail(message: String) -> void:
	push_error("[SystemicShelterSmoke] " + message)
	quit(1)
