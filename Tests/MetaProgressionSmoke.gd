extends SceneTree

const PROFILE_PATH := "user://meta_progression_smoke.json"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if FileAccess.file_exists(PROFILE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PROFILE_PATH))
	var store := MetaProgressionStore.new()
	store.profile_path = PROFILE_PATH
	store.set_gateway_unsealed("north", true, false)
	store.complete_event("fetch_probe", [{
		"type": "set_core_state",
		"core_id": "north_core",
		"state": {"component_count": 1},
	}])

	var baseline := HexRecord.new()
	baseline.poi_name = "Unchanged"
	var changed := HexRecord.from_dict(baseline.to_dict())
	changed.poi_name = "Permanent Change"
	store.capture_node_mutations(
		"permanent_probe",
		{Vector2i.ZERO: baseline},
		{Vector2i.ZERO: changed}
	)
	if not store.save_profile():
		return _fail("Could not save isolated Meta profile: %s" % store.get_last_save_error())

	var loaded := MetaProgressionStore.new()
	loaded.profile_path = PROFILE_PATH
	if not loaded.load_profile():
		return _fail("Could not reload isolated Meta profile: %s" % loaded.get_last_save_error())
	if not loaded.is_event_completed("fetch_probe"):
		return _fail("Completed Meta Event did not survive reload.")
	if not loaded.is_gateway_unsealed("north"):
		return _fail("Gateway state did not survive reload.")
	if int(loaded.get_core_state("north_core").get("component_count", 0)) != 1:
		return _fail("Core reconstruction state did not survive reload.")
	var restored := HexRecord.from_dict(baseline.to_dict())
	loaded.apply_patch_to_record("permanent_probe", Vector2i.ZERO, restored)
	if restored.poi_name != "Permanent Change":
		return _fail("Node-scoped structural patch did not survive reload.")
	var other_node := HexRecord.from_dict(baseline.to_dict())
	loaded.apply_patch_to_record("different_node", Vector2i.ZERO, other_node)
	if other_node.poi_name != "Unchanged":
		return _fail("A coordinate patch leaked into a different node.")

	DirAccess.remove_absolute(ProjectSettings.globalize_path(PROFILE_PATH))
	print("MetaProgressionSmoke PASSED")
	quit(0)


func _fail(message: String) -> bool:
	push_error("MetaProgressionSmoke: " + message)
	quit(1)
	return false
