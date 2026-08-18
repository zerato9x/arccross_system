extends RefCounted
class_name MacroWorldBootstrapService

## Selects and applies the authored lifecycle branch without constructing
## nodes or touching presentation directly. MacroGameManager supplies the
## application callbacks that preserve scene wiring and compatibility signals.

const MODE_LOADED := "loaded"
const MODE_NEW_RUN := "new_run"
const MODE_DEMO := "demo"
const DEMO_SEED := "ARCCROSS_DIRECTIONAL_WEB_01"


func select_startup(world_state: RuntimeStateStore) -> Dictionary:
	if world_state == null:
		return {"mode": MODE_DEMO, "setup": {}}
	if world_state.consume_pending_loaded_world():
		return {"mode": MODE_LOADED, "setup": {}}
	if world_state.has_pending_new_run_setup():
		return {
			"mode": MODE_NEW_RUN,
			"setup": world_state.consume_pending_new_run_setup(),
		}
	return {"mode": MODE_DEMO, "setup": {}}


## Applies the authored new-run lifecycle through neutral application callbacks.
## The callbacks keep scene wiring, presentation, and compatibility signals out
## of this service while the branch policy remains in one place.
func initialize_new_run(setup: Dictionary, callbacks: Dictionary) -> Dictionary:
	var definition_state: Dictionary = setup.get("definition", {})
	var start_node_id := str(setup.get("start_node_id", ""))
	var arrival_direction := int(setup.get(
		"arrival_direction",
		MacroGraphGenerator.arrival_direction_for_start(start_node_id)
	))
	if definition_state.is_empty() or start_node_id.is_empty():
		_report_error(callbacks, "[MacroGameManager] New-run setup is incomplete.")
		return initialize_demo(callbacks)
	if not bool(_invoke(callbacks, "initialize_player", [definition_state])):
		_report_error(callbacks, "[MacroGameManager] Could not apply the selected player identity.")
		return initialize_demo(callbacks)

	_invoke(callbacks, "ensure_campaign")
	_invoke(callbacks, "configure_player_capabilities", [
		_invoke(callbacks, "player_definition")
	])
	var world_state := callbacks.get("world_state") as RuntimeStateStore
	if world_state == null:
		_report_error(callbacks, "[MacroGameManager] New-run world state is unavailable.")
		return {"ok": false}
	_invoke(callbacks, "begin_campaign", [world_state.world_seed])
	_invoke(callbacks, "configure_world")
	_invoke(callbacks, "set_player_record", [
		_invoke(callbacks, "capture_player_record"),
		Vector2i.ZERO,
	])
	_invoke(callbacks, "apply_eviction_lock")
	_invoke(callbacks, "unload_enemy_tokens")
	if not bool(_invoke(callbacks, "enter_initial_node", [start_node_id, arrival_direction])):
		_report_error(
			callbacks,
			"[MacroGameManager] Failed to enter selected start node: %s" % start_node_id
		)
		return {"ok": false}
	_invoke(callbacks, "reset_pending_exit")
	_invoke(callbacks, "apply_active_zone")
	_invoke(callbacks, "ensure_central_rim_guards")
	_invoke(callbacks, "ensure_route_one_population")
	_invoke(callbacks, "ensure_shelter_ecology")
	_invoke(callbacks, "ensure_meta_component_source")
	var last_event := (
		"The road is open. Search what is physically reachable, follow fresh evidence, "
		+ "and decide which direction is worth the risk."
	)
	_invoke(callbacks, "set_last_event", [last_event])
	_invoke(callbacks, "log", ["Eviction complete. Deployed to %s." % start_node_id])
	return {"ok": true, "last_event": last_event}


## Creates the authored fallback/demo run while keeping scene refreshes behind
## callbacks supplied by MacroGameManager.
func initialize_demo(callbacks: Dictionary) -> Dictionary:
	var world_state := callbacks.get("world_state") as RuntimeStateStore
	if world_state == null:
		_report_error(callbacks, "[MacroGameManager] Demo world state is unavailable.")
		return {"ok": false}
	world_state.begin_new_world(DEMO_SEED)
	_invoke(callbacks, "ensure_campaign")
	_invoke(callbacks, "begin_campaign", [DEMO_SEED])
	_invoke(callbacks, "configure_world")
	_invoke(callbacks, "set_player_record", [
		_invoke(callbacks, "capture_player_record"),
		Vector2i.ZERO,
	])
	if not bool(_invoke(callbacks, "enter_campaign_node", [MacroGraphGenerator.HUB_ID])):
		_report_error(callbacks, "[MacroGameManager] Failed to enter hub campaign node.")
		return {"ok": false}
	_invoke(callbacks, "log", ["Directional campaign initialized at the Central Core south rim."])
	return {"ok": true}


## Restores a run-scoped world and delegates the final player/presentation
## placement to the manager-owned compatibility callback.
func initialize_loaded_world(callbacks: Dictionary) -> Dictionary:
	var world_state := callbacks.get("world_state") as RuntimeStateStore
	if (
		world_state == null
		or world_state.world_seed.is_empty()
		or world_state.player_record == null
	):
		_report_error(
			callbacks,
			"Loaded world state is incomplete. Starting a new demo world."
		)
		return initialize_demo(callbacks)

	_invoke(callbacks, "ensure_campaign")
	_invoke(callbacks, "configure_world")
	_invoke(callbacks, "restore_player", [world_state.player_record])
	_invoke(callbacks, "configure_player_capabilities", [
		_invoke(callbacks, "player_definition")
	])

	var campaign_graph := world_state.get_campaign_graph_snapshot()
	if not campaign_graph.is_empty():
		var loaded_coords: Vector2i = world_state.player_record.coords
		_invoke(callbacks, "load_campaign", [
			campaign_graph,
			world_state.active_node_id,
		])
		_invoke(callbacks, "apply_active_zone")
		_invoke(callbacks, "ensure_central_rim_guards")
		_invoke(callbacks, "ensure_route_one_population")
		_invoke(callbacks, "ensure_shelter_ecology")
		if bool(_invoke(callbacks, "is_in_zone_bounds", [loaded_coords])):
			_invoke(callbacks, "restore_loaded_player_position", [loaded_coords])
	else:
		_invoke(callbacks, "begin_campaign", [world_state.world_seed])
		_invoke(callbacks, "enter_campaign_node", [MacroGraphGenerator.HUB_ID])

	var current_coords: Variant = _invoke(callbacks, "current_player_coords")
	_invoke(callbacks, "log", [
		"Loaded campaign node=%s at %s."
		% [world_state.active_node_id, str(current_coords)]
	])
	return {"ok": true}


func _get_callback(callbacks: Dictionary, key: String) -> Callable:
	var value: Variant = callbacks.get(key, Callable())
	if value is Callable:
		return value
	return Callable()


func _invoke(callbacks: Dictionary, key: String, args: Array = []) -> Variant:
	var callback := _get_callback(callbacks, key)
	if not callback.is_valid():
		return null
	match args.size():
		0:
			return callback.call()
		1:
			return callback.call(args[0])
		2:
			return callback.call(args[0], args[1])
	return null


func _report_error(callbacks: Dictionary, message: String) -> void:
	var error_callback := _get_callback(callbacks, "error")
	if error_callback.is_valid():
		error_callback.call(message)
	else:
		push_error(message)
