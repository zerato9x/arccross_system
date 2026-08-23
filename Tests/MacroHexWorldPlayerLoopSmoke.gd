extends SceneTree

const _SENTINEL := Vector2i(999999, 999999)

var _resolving_seen := false
var _authoritative_changed_during_resolving := false
var _authoritative_before := Vector2i.ZERO
var _cancel_signal_sent := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var packed := load("res://SystemCore/game_director.tscn") as PackedScene
	var director := packed.instantiate()
	root.add_child(director)
	await process_frame
	await process_frame
	await process_frame
	var macro := director.get_node_or_null("MainWorld") as MacroGameManager
	var state := root.get_node_or_null("WorldState") as RuntimeStateStore
	if macro == null or state == null or macro.macro_hud == null:
		_fail("Macro player-loop dependencies did not initialize.")
		return

	var idle_movement: Dictionary = macro.call("_movement_snapshot")
	if bool(idle_movement.get("active", true)) or str(idle_movement.get("phase", "")) != "idle":
		_fail("Movement snapshot did not start idle.")
		return
	var initial_snapshot: Dictionary = macro.macro_hud.get("_snapshot")
	if not initial_snapshot.has("movement"):
		_fail("World HUD snapshot did not expose the transient movement dictionary.")
		return
	if not bool(initial_snapshot.get("current_location", {}).get("can_open", false)):
		_fail("Current Explore was not enabled while movement was idle.")
		return

	var unknown := _find_unknown_hex(macro)
	if unknown == _SENTINEL:
		_fail("No unexplored hex was available for redaction coverage.")
		return
	macro.call("_select_hex_for_hud", unknown)
	await process_frame
	var unknown_snapshot: Dictionary = macro.macro_hud.get("_snapshot")
	var unknown_hex: Dictionary = unknown_snapshot.get("selected_hex", {})
	var unknown_target: Dictionary = unknown_snapshot.get("target_location", {})
	if unknown_hex.get("intel_signals", []).size() != 3:
		_fail("Unknown target did not expose the three fixed intel signal slots.")
		return
	for signal_value in unknown_hex.get("intel_signals", []):
		if not signal_value is Dictionary or str(signal_value.get("state", "")) != "unknown":
			_fail("Unknown target leaked a non-unknown intel state: %s" % str(signal_value))
			return
	for exact_key in [
		"search_site_id", "search_site_name", "search_site_description", "search_marker_kind",
	]:
		if not str(unknown_hex.get(exact_key, "")).is_empty():
			_fail("Unknown target leaked exact information: %s" % exact_key)
			return
	if bool(unknown_target.get("exploration", {}).get("available", true)):
		_fail("Remote Explore was not locked.")
		return
	if str(unknown_target.get("exploration", {}).get("lock_reason", "")) != "Travel here first":
		_fail("Remote Explore did not expose TRAVEL HERE FIRST.")
		return
	if not unknown_target.get("presentation", {}).is_empty():
		_fail("Unknown target exposed a composition preview.")
		return
	macro.call("_expand_hex_at", unknown)
	await process_frame
	if macro.macro_hud.is_location_open():
		_fail("Remote Explore opened the current-location board.")
		return

	var origin: Vector2i = macro.player_token.current_hex_coords
	var route_target := _find_two_step_target(macro, origin)
	if route_target == _SENTINEL:
		_fail("No safe known two-step route was available.")
		return
	macro.call("_select_hex_for_hud", route_target)
	await process_frame
	var target_snapshot: Dictionary = macro.macro_hud.get("_snapshot")
	var target_location: Dictionary = target_snapshot.get("target_location", {})
	if target_location.get("presentation", {}).is_empty():
		_fail("Known target did not receive a compact composition preview.")
		return
	if target_location.get("intel_signals", []).size() != 3:
		_fail("Known target did not expose loot, structure, and risk signals.")
		return
	if not bool(target_location.get("can_travel", false)):
		_fail("Known two-step target was not travel-enabled.")
		return
	var synthetic_route: Array[Vector2i] = [route_target]
	macro.call("_begin_player_route", synthetic_route, "travel", true)
	var escape_event := InputEventKey.new()
	escape_event.physical_keycode = KEY_ESCAPE
	escape_event.pressed = true
	macro.call("_unhandled_input", escape_event)
	if not bool(macro.get("_route_cancel_requested")):
		_fail("Escape did not use the shared route cancellation path.")
		return
	macro.call("_finish_player_movement", "INPUT OWNERSHIP TEST RESET", "interrupted")
	macro.call("_begin_player_route", synthetic_route, "travel", true)
	var right_click := InputEventMouseButton.new()
	right_click.button_index = MOUSE_BUTTON_RIGHT
	right_click.pressed = true
	macro.call("_unhandled_input", right_click)
	if not bool(macro.get("_route_cancel_requested")):
		_fail("Right-click did not use the shared route cancellation path.")
		return
	macro.call("_finish_player_movement", "INPUT OWNERSHIP TEST RESET", "interrupted")

	_authoritative_before = state.player_record.coords
	macro.player_token.movement_arrived.connect(
		_on_movement_arrived.bind(macro, state)
	)
	macro.call("_try_travel_to_selected_hex")
	await process_frame
	var walking: Dictionary = macro.call("_movement_snapshot")
	if not bool(walking.get("active", false)) or str(walking.get("phase", "")) != "walking":
		_fail("Movement snapshot did not enter WALKING.")
		return
	if int(walking.get("total_steps", 0)) != 2 or int(walking.get("remaining_steps", 0)) != 2:
		_fail("Movement route totals were not initialized for the selected route.")
		return
	var target_panel := macro.macro_hud.get_node("%MacroHexTargetPanel") as MacroHexTargetPanel
	var cancel_button := target_panel.get("_cancel_button") as Button
	if cancel_button == null or not cancel_button.visible or cancel_button.disabled:
		_fail("Target panel did not expose an active Cancel Route button.")
		return
	var explore_button := target_panel.get("_explore_button") as Button
	if explore_button == null or not explore_button.disabled or explore_button.text != "TRAVEL HERE FIRST":
		_fail("Target panel did not keep remote Explore locked with its reason.")
		return
	var world_status := macro.macro_hud.get_node("%MacroWorldStatusPanel") as MacroWorldStatusPanel
	var movement_label := world_status.get_node("%MovementStateLabel") as Label
	if movement_label == null or not movement_label.visible:
		_fail("World Status did not expose active movement progress.")
		return

	# Input ownership is asserted through the same manager guards used by Escape,
	# right-click, and the target-panel Cancel Route signal.
	macro.call("_select_hex_for_hud", origin)
	macro.call("_expand_hex_at", origin)
	macro.open_hex_world_map()
	if macro.get("_selected_hex_coords") != route_target or macro.macro_hud.is_location_open() or macro.macro_hud.is_hex_world_map_open():
		_fail("Active movement did not consume selection, Explore, and map input.")
		return

	await create_timer(MacroPlayer.WALK_DURATION_SECONDS + 0.15).timeout
	await process_frame
	if not _resolving_seen:
		_fail("Arrival did not expose a resolving snapshot before receipt application.")
		return
	if _authoritative_changed_during_resolving:
		_fail("Authoritative coordinates changed before the resolving receipt boundary.")
		return
	if not _cancel_signal_sent:
		_fail("Target-panel Cancel Route did not reach the manager during resolving.")
		return

	# The active step must still finish, but the second route step must never
	# start after the cancellation request.
	await create_timer(6.5).timeout
	await process_frame
	var cancelled: Dictionary = macro.call("_movement_snapshot")
	if bool(cancelled.get("active", true)) or str(cancelled.get("phase", "")) != "interrupted":
		_fail("Cancelled route did not terminate as an interrupted movement state.")
		return
	if not str(cancelled.get("message", "")).begins_with("ROUTE CANCELLED AT HEX"):
		_fail("Cancelled route did not expose its destination message.")
		return
	if not (macro.get("_travel_route") as Array).is_empty() or not (macro.get("_pending_player_step") as Dictionary).is_empty():
		_fail("Cancelled route left pending route bookkeeping behind.")
		return
	if macro.get("_selected_hex_coords") != route_target:
		_fail("Cancelled route did not keep the destination selected.")
		return
	if state.player_record.coords == route_target:
		_fail("Cancelled route incorrectly committed the final destination.")
		return

	var arrived_coords: Vector2i = macro.player_token.current_hex_coords
	macro.call("_expand_hex_at", arrived_coords)
	await process_frame
	if not macro.macro_hud.is_location_open():
		_fail("Explore did not unlock after physical arrival on the committed step.")
		return
	print("[TEST PASS] Macro movement state, deferred receipt, intel redaction, target preview, and route cancellation.")
	director.queue_free()
	await process_frame
	quit(0)


func _on_movement_arrived(
	_from_coords: Vector2i,
	_to_coords: Vector2i,
	_movement_id: int,
	macro: MacroGameManager,
	state: RuntimeStateStore
) -> void:
	var movement: Dictionary = macro.call("_movement_snapshot")
	if str(movement.get("phase", "")) == "resolving":
		_resolving_seen = true
		_authoritative_changed_during_resolving = state.player_record.coords != _authoritative_before
		var target_panel := macro.macro_hud.get_node("%MacroHexTargetPanel") as MacroHexTargetPanel
		var cancel_button := target_panel.get("_cancel_button") as Button
		if cancel_button != null and cancel_button.visible and not cancel_button.disabled:
			_cancel_signal_sent = true
			cancel_button.pressed.emit()


func _find_unknown_hex(macro: MacroGameManager) -> Vector2i:
	for value in macro.world_generator.world_hex_cache.keys():
		if not value is Vector2i:
			continue
		var coords: Vector2i = value
		if coords != macro.player_token.current_hex_coords and not macro.world_generator.get_hex_at(coords).is_explored:
			return coords
	return _SENTINEL


func _find_two_step_target(macro: MacroGameManager, origin: Vector2i) -> Vector2i:
	for value in macro.world_generator.world_hex_cache.keys():
		if not value is Vector2i:
			continue
		var coords: Vector2i = value
		if coords == origin:
			continue
		var route: Array = macro.call("_build_travel_route", origin, coords)
		if route.size() != 2:
			continue
		var safe := true
		for step in route:
			if macro.world_generator.get_hex_at(step).is_passable() == false:
				safe = false
			if macro.get_runtime_state_store().has_ground_items(step):
				safe = false
			if not macro.get_runtime_state_store().get_entity_snapshot_at(step).is_empty():
				safe = false
		if safe:
			return coords
	return _SENTINEL


func _fail(message: String) -> void:
	push_error("[TEST FAIL] " + message)
	quit(1)
