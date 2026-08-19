extends SceneTree


func _init() -> void:
	var failures: Array[String] = []
	for path in _world_core_scripts():
		var source := FileAccess.get_file_as_string(path)
		if ".set_hex_record(" in source:
			failures.append(path + " calls migration-only set_hex_record().")
		for public_dictionary in [
			".hex_records", ".entity_records", ".ground_item_records",
			".active_world_actions", ".world_signal_records", ".campaign_graph",
			".run_flags",
		]:
			if public_dictionary in source:
				failures.append(path + " reaches into store state through " + public_dictionary)
	var zone_source := FileAccess.get_file_as_string("res://WorldCore/MacroZoneGenerator.gd")
	for forbidden in ["set_hex_record", "replace_hex_record", "transition_active_node"]:
		if forbidden in zone_source:
			failures.append("MacroZoneGenerator mutates runtime state through " + forbidden)
	var combat_result_source := FileAccess.get_file_as_string(
		"res://SystemCore/CombatResultApplicationService.gd"
	)
	if ".set_hex_record(" in combat_result_source:
		failures.append("CombatResultApplicationService calls migration-only set_hex_record().")
	var builder_source := FileAccess.get_file_as_string("res://WorldCore/MacroSnapshotBuilder.gd")
	if "default_wound_treatments.tres" in builder_source:
		failures.append("MacroSnapshotBuilder still loads BiologicalCore treatment resources.")
	var facade_source := FileAccess.get_file_as_string("res://WorldCore/MacroSnapshotFacade.gd")
	for required in ["BiologicalSnapshotService.capture", "InventorySnapshotService.capture"]:
		if required not in facade_source:
			failures.append("MacroSnapshotFacade is missing neutral capture: " + required)
	for path in _production_scripts():
		if path == "res://SystemCore/RuntimeStateStore.gd":
			continue
		var source := FileAccess.get_file_as_string(path)
		for forbidden in [
			".get_entity(", ".get_entity_at(", ".get_all_entity_records("
		]:
			if forbidden in source:
				failures.append(
					path + " depends on a live-resource compatibility accessor: " + forbidden
				)
	if not failures.is_empty():
		for failure in failures:
			push_error("[WORLD_STATE_ARCHITECTURE] " + failure)
		quit(1)
		return
	print("WORLD_STATE_ARCHITECTURE_SMOKE: PASS")
	quit(0)


func _world_core_scripts() -> Array[String]:
	var paths: Array[String] = []
	_collect_world_core_scripts("res://WorldCore", paths)
	return paths


func _production_scripts() -> Array[String]:
	var paths: Array[String] = []
	for root in [
		"res://WorldCore",
		"res://SystemCore",
		"res://UI",
		"res://CombatCore",
		"res://ItemCore",
		"res://BiologicalCore",
	]:
		_collect_world_core_scripts(root, paths)
	return paths


func _collect_world_core_scripts(path: String, paths: Array[String]) -> void:
	var directory := DirAccess.open(path)
	if directory == null:
		return
	directory.list_dir_begin()
	var name := directory.get_next()
	while not name.is_empty():
		var child_path := path.path_join(name)
		if directory.current_is_dir():
			_collect_world_core_scripts(child_path, paths)
		elif name.ends_with(".gd"):
			paths.append(child_path)
		name = directory.get_next()
	directory.list_dir_end()
