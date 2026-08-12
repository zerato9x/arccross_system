extends SceneTree

const ARENA_SCRIPT := preload("res://CombatCore/Tactical/TacticalArenaView.gd")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await _verify_arena_intents()
	_verify_interaction_state()
	_verify_map_composition()
	_verify_legacy_firearm_hydration()
	if failures.is_empty():
		print("TACTICAL_AUTHORITY_RECOVERY_SMOKE: PASS")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func _verify_arena_intents() -> void:
	var arena := ARENA_SCRIPT.new() as TacticalArenaView
	arena.size = Vector2(320.0, 200.0)
	root.add_child(arena)
	await process_frame
	arena.show_snapshot({"width": 1, "height": 1, "sectors": [{"coords": Vector2i.ZERO, "occupant_ids": []}]})
	var received := {"inspect": 0, "context": 0}
	arena.inspect_requested.connect(func(_coords: Vector2i, _actor_id: String) -> void: received.inspect += 1)
	arena.context_requested.connect(func(_coords: Vector2i, _actor_id: String) -> void: received.context += 1)
	var left := InputEventMouseButton.new()
	left.button_index = MOUSE_BUTTON_LEFT
	left.pressed = true
	left.position = arena.size * 0.5
	arena._on_gui_input(left)
	if received.inspect != 1 or received.context != 0:
		_fail("LMB did not emit inspect-only arena intent.")
	var right := InputEventMouseButton.new()
	right.button_index = MOUSE_BUTTON_RIGHT
	right.pressed = true
	right.position = arena.size * 0.5
	arena._on_gui_input(right)
	if received.inspect != 1 or received.context != 1:
		_fail("RMB did not emit context-only arena intent.")
	arena.queue_free()
	await process_frame


func _verify_interaction_state() -> void:
	var state := CombatInteractionState.new()
	state.select("sector", {"sector": Vector2i(2, 2)})
	if state.phase != CombatInteractionState.Phase.INSPECTING:
		_fail("Selection did not enter INSPECTING.")
	state.open_root_menu()
	state.open_actions()
	state.cancel_one_step()
	if state.phase != CombatInteractionState.Phase.ROOT_MENU:
		_fail("Cancellation did not return from ACTION_MENU to ROOT_MENU.")
	state.cancel_one_step()
	if state.phase != CombatInteractionState.Phase.INSPECTING:
		_fail("Cancellation did not return from ROOT_MENU to linked inspectors.")


func _verify_map_composition() -> void:
	var generator := CombatArenaGenerator.new()
	var encounter := CombatEncounterRecord.new()
	encounter.topology_id = "squad_7x5"
	encounter.world_seed = "AUTHORITY_RECOVERY_A"
	encounter.center_hex = HexRecord.new()
	encounter.center_hex.terrain_tile = GameEnums.MacroTerrainTile.PLAINS_GRASS
	encounter.center_hex.road_mask = (1 << 0) | (1 << 3)
	encounter.center_hex.landmark_id = "recovery_landmark"
	var first := generator.generate(encounter)
	var second := generator.generate(CombatEncounterRecord.from_dict(encounter.to_dict()))
	if first.map_composition != second.map_composition:
		_fail("Map composition is not deterministic for identical input.")
	if first.map_composition.get("road_cells", []).is_empty():
		_fail("Road-mask composition produced no continuous road cells.")
	if str(first.map_composition.get("dominant_landmark", {}).get("id", "")) != "recovery_landmark":
		_fail("Macro landmark did not become the single dominant landmark.")
	if first.map_composition.get("sector_facts", {}).size() != first.sector_count():
		_fail("Composition sector facts do not cover the logical board.")
	var variants: Dictionary = {}
	for index in range(8):
		encounter.world_seed = "AUTHORITY_RECOVERY_%d" % index
		variants[str(generator.generate(encounter).map_composition.get("variant_id", ""))] = true
	if variants.size() < 2:
		_fail("Weighted battlefield selection did not expose multiple deterministic variants.")


func _verify_legacy_firearm_hydration() -> void:
	var definition := preload("res://ItemCore/Items/revolver.tres") as ItemData
	if definition == null:
		return
	var state := definition.create_runtime_instance().to_runtime_state()
	state["needs_cycling"] = true
	state["is_jammed"] = false
	var restored := ItemData.from_runtime_state(state)
	if restored != null and restored.needs_cycling:
		_fail("Legacy needs_cycling state still blocks a healthy firearm.")


func _fail(message: String) -> void:
	failures.append(message)
