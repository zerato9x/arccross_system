extends RefCounted
class_name MacroWorldObjectSeeder

## Converts generator evidence into stable, neutral object records. Runtime
## components remain dictionaries so SystemCore never imports presentation.


func seed_hex_objects(
	node_id: String,
	coords: Vector2i,
	hex: MacroHexData,
	shelter_profile: ShelterProgressionProfile,
	meta_progress: Node,
	last_simulated_minute: int
) -> Array[Dictionary]:
	var objects: Array[Dictionary] = []
	if hex == null:
		return objects
	var is_shelter_node := (
		shelter_profile != null and node_id == shelter_profile.profile_id
	)
	if hex.road_mask != 0:
		objects.append(build_record(
			node_id,
			"road",
			"road",
			coords,
			{"road": {"mask": hex.road_mask, "surface": "paved"}},
			{"travel_multiplier": 0.72, "noise_damping": 0.9},
			last_simulated_minute
		))
	if not hex.search_site_id.is_empty():
		objects.append(build_record(
			node_id,
			"rubble",
			"rubble",
			coords,
			{
				"rubble": {"material_units": 3, "depleted": false},
				"container": {"finite": true},
				"dismantlable": {"methods": ["hands", "crowbar", "multitool"]},
			},
			{"search_site_id": hex.search_site_id},
			last_simulated_minute
		))
	if (
		hex.is_poi
		or not hex.landmark_id.is_empty()
		or hex.structure_layer == GameEnums.MacroStructureLayer.STRUCTURES
	):
		var components := {
			"structure": {"landmark_id": hex.landmark_id, "poi_id": hex.poi_id},
			"container": {"finite": true, "remaining_searches": 2},
			"door": {"state": "closed", "locked": false},
			"roof": {"integrity": 0.65},
			"storage": {"capacity": 4},
			"trap_anchor": {"approach": "nearest_road"},
		}
		var structure_definition := "structure"
		if is_shelter_node and coords == Vector2i.ZERO:
			components = _shelter_components(shelter_profile, node_id, meta_progress)
			structure_definition = "shelter"
		var structure_runtime := {
			"poi_id": hex.poi_id,
			"shelter_state": str(components.get("shelter", {}).get("state", "")),
		}
		if (
			is_shelter_node
			and coords == Vector2i.ZERO
			and meta_progress != null
			and meta_progress.has_method("get_shelter_state")
		):
			structure_runtime["service_stage"] = int(
				meta_progress.get_shelter_state(node_id).get("service_stage", 0)
			)
		objects.append(build_record(
			node_id,
			"structure",
			structure_definition,
			coords,
			components,
			structure_runtime,
			last_simulated_minute
		))
	if is_shelter_node:
		if coords == Vector2i(1, 0):
			objects.append(build_record(
				node_id,
				"material_socket",
				"salvage_rubble",
				coords,
				{
					"rubble": {"material_units": 5, "depleted": false},
					"container": {"finite": true},
					"dismantlable": {"methods": ["hands", "crowbar", "multitool"]},
				},
				{"shelter_role_socket": "material_salvage"},
				last_simulated_minute
			))
		elif coords == Vector2i(-1, 0):
			objects.append(build_record(
				node_id,
				"utility_socket",
				"utility_access",
				coords,
				{
					"power": {"state": "offline"},
					"water": {"state": "offline"},
					"repairable": {
						"task_profile_id": "repair_manual",
						"stages": ["power", "water"],
					},
				},
				{"shelter_role_socket": "utility_water"},
				last_simulated_minute
			))
		elif coords == Vector2i(0, 1):
			objects.append(build_record(
				node_id,
				"approach_socket",
				"craven_approach",
				coords,
				{
					"road": {"mask": 0, "surface": "broken"},
					"signal_source": {
						"kind": "approach_territory",
						"strength": 0.8,
					},
					"trap_anchor": {"approach": "craven_territory"},
				},
				{"shelter_role_socket": "craven_approach"},
				last_simulated_minute
			))
	return objects


func _shelter_components(
	profile: ShelterProgressionProfile,
	node_id: String,
	meta_progress: Node
) -> Dictionary:
	var state := profile.initial_state
	if meta_progress != null and meta_progress.has_method("get_shelter_state"):
		state = str(
			meta_progress.get_shelter_state(node_id).get("state", profile.initial_state)
		)
	var components := {
		"structure": {"kind": "permanent_shelter", "state": profile.initial_state},
		"repairable": {
			"task_profile_id": "repair_manual",
			"methods": ["multitool", "crowbar", "hands"],
			"stages": profile.stages.duplicate(),
		},
		"roof": {"integrity": 0.20, "required": 0.80},
		"access": {"state": "blocked", "integrity": 0.25},
		"door": {"state": "breached", "integrity": 0.25},
		"power": {"state": "offline", "required": true},
		"water": {"state": "offline", "required": true},
		"storage": {"capacity": 8, "state": "damaged"},
		"bed": {"count": 0, "state": "unusable"},
		"barricade": {"integrity": 0.0, "state": "missing"},
		"trap_anchor": {"approach": "north_route"},
		"shelter": {
			"state": profile.initial_state,
			"required_services": profile.stages.duplicate(),
		},
	}
	profile.apply_component_patches(components, state)
	components["structure"]["state"] = state
	components["shelter"]["state"] = state
	return components

func build_record(
	node_id: String,
	kind: String,
	definition_id: String,
	coords: Vector2i,
	components: Dictionary,
	runtime: Dictionary,
	last_simulated_minute: int
) -> Dictionary:
	var object := WorldObjectRecord.new()
	object.object_id = "%s:%s:%s" % [node_id, str(coords), kind]
	object.node_id = node_id
	object.coords = coords
	object.definition_id = definition_id
	object.condition = 1.0
	object.revision = 1
	object.last_simulated_minute = last_simulated_minute
	object.components = components.duplicate(true)
	object.runtime = runtime.duplicate(true)
	return object.to_dict()
