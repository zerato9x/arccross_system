extends RefCounted
class_name MacroPlayerMovementCoordinator

## Owns the player macro-movement lifecycle from authored walk through atomic
## arrival, world-turn interruption, presentation, cancellation, and retreat.
## MacroGameManager remains the scene-facing facade and composition root.

var host: MacroGameManager


func _init(host_manager: MacroGameManager = null) -> void:
	host = host_manager


func execute_step(
	target_coords: Vector2i,
	animate: bool = true,
	continuation: bool = false
) -> void:
	if not continuation and host.blocks_world_commands() and (
		animate or not host._pending_player_step.is_empty()
	):
		return
	if continuation and not host._turn_resolution.is_active():
		return
	if not host.world_generator.is_in_zone_bounds(target_coords):
		if host._is_player_movement_active():
			finish("MOVEMENT FAILED // OUTSIDE THIS ZONE", "failed")
			return
		host._try_begin_directional_exit(
			host.player_token.current_hex_coords, target_coords
		)
		return
	var origin_coords := host.player_token.current_hex_coords
	var target_hex := host.world_generator.get_hex_at(target_coords)
	if not target_hex.is_passable():
		finish("MOVEMENT FAILED // HEX IS NOT PASSABLE", "failed")
		return
	if not animate:
		if host._is_player_movement_active():
			return
		host._select_hex_for_hud(target_coords)
		host.player_token.snap_to_hex(
			target_coords, host.map_visualizer.map_to_local(target_coords)
		)
		commit_step(origin_coords, target_coords)
		return
	if not bool(host._movement_state.get("active", false)):
		begin_route([target_coords], "travel", true)
	host._movement_state["phase"] = "walking"
	host._movement_state["current_coords"] = origin_coords
	host._movement_state["step_target_coords"] = target_coords
	host._movement_state["message"] = "TURN RESOLVE // WALKING TO HEX %d,%d..." % [
		target_coords.x, target_coords.y,
	]
	debug_mark("next route step start")
	var pixel_pos := host.map_visualizer.map_to_local(target_coords)
	var movement_id := host.player_token.walk_to_hex(target_coords, pixel_pos)
	host._pending_player_step = {
		"kind": "travel",
		"resolution_id": int(host._movement_state.get("resolution_id", 0)),
		"movement_id": movement_id,
		"from": origin_coords,
		"to": target_coords,
		"started_minute": host._world_state.world_time_minutes,
	}
	host._movement_state["can_cancel"] = true
	host._last_macro_event = host._movement_state["message"]
	host._refresh_world_hud()


func begin_route(
	route: Array[Vector2i],
	kind: String = "travel",
	can_cancel: bool = true
) -> void:
	if route.is_empty() or host.player_token == null:
		return
	host._travel_route = route.duplicate()
	host._travel_route_total_steps = host._travel_route.size()
	host._travel_completed_steps = 0
	host._route_cancel_requested = false
	var origin_coords := host.player_token.current_hex_coords
	var destination_coords: Vector2i = host._travel_route[-1]
	var resolution_id := host._turn_resolution.begin(
		kind,
		origin_coords,
		destination_coords,
		host._travel_route_total_steps,
		can_cancel
	)
	if resolution_id == 0:
		reset_route_bookkeeping()
		return
	host._movement_state["step_target_coords"] = host._travel_route[0]
	host._movement_state["message"] = (
		"TURN RESOLVE // WALKING // ROUTE %d STEP(S)"
		% host._travel_route_total_steps
	)
	debug_mark("movement request accepted")
	host._refresh_world_hud()


func movement_started(
	from_coords: Vector2i,
	target_coords: Vector2i,
	_movement_id: int
) -> void:
	debug_mark("tween started %s -> %s" % [str(from_coords), str(target_coords)])


func movement_arrived(
	from_coords: Vector2i,
	target_coords: Vector2i,
	movement_id: int
) -> void:
	if host._pending_player_step.is_empty():
		return
	if int(host._pending_player_step.get("movement_id", -1)) != movement_id:
		return
	var resolution_id := int(host._pending_player_step.get("resolution_id", 0))
	if resolution_id != int(host._movement_state.get("resolution_id", 0)):
		return
	debug_mark("arrival signal %s -> %s" % [str(from_coords), str(target_coords)])
	host._turn_resolution.set_phase(
		"resolving",
		"TURN RESOLVE // ARRIVAL COMMIT AT HEX %d,%d..." % [
			target_coords.x, target_coords.y,
		]
	)
	host._movement_state["current_coords"] = target_coords
	host._movement_state["step_target_coords"] = target_coords
	host._refresh_world_hud()
	call_deferred(
		"_resolve_arrived_step",
		movement_id,
		from_coords,
		target_coords,
		resolution_id
	)


func _resolve_arrived_step(
	movement_id: int,
	from_coords: Vector2i,
	target_coords: Vector2i,
	resolution_id: int
) -> void:
	if host._pending_player_step.is_empty():
		return
	if int(host._pending_player_step.get("movement_id", -1)) != movement_id:
		return
	if int(host._movement_state.get("resolution_id", 0)) != resolution_id:
		return
	if str(host._pending_player_step.get("kind", "travel")) == "retreat":
		commit_retreat(target_coords)
		return
	commit_step(from_coords, target_coords)


func reset_route_bookkeeping() -> void:
	host._travel_route.clear()
	host._travel_route_total_steps = 0
	host._travel_completed_steps = 0
	host._route_cancel_requested = false


func finish(message: String, phase: String = "failed") -> void:
	if not host._is_player_movement_active():
		host._last_macro_event = message
		host._refresh_world_hud()
		return
	host._pending_player_step.clear()
	reset_route_bookkeeping()
	var current_coords := host.player_token.current_hex_coords
	host._turn_resolution.finish(message, phase)
	host._movement_state["current_coords"] = current_coords
	host._movement_state["step_target_coords"] = current_coords
	host._last_macro_event = message
	host._refresh_world_hud()


func finish_success(message: String) -> void:
	host._pending_player_step.clear()
	reset_route_bookkeeping()
	var current_coords := host.player_token.current_hex_coords
	host._turn_resolution.finish(message, "idle")
	host._movement_state["current_coords"] = current_coords
	host._movement_state["step_target_coords"] = current_coords
	host._last_macro_event = message


func cancel_route() -> bool:
	if not bool(host._movement_state.get("active", false)):
		return false
	if str(host._movement_state.get("kind", "travel")) != "travel":
		return false
	if str(host._movement_state.get("phase", "idle")) not in ["walking", "resolving"]:
		return false
	if not bool(host._movement_state.get("can_cancel", false)):
		return false
	host._route_cancel_requested = true
	host._travel_route.clear()
	host._movement_state["can_cancel"] = false
	host._movement_state["remaining_steps"] = 1
	host._movement_state["message"] = "CANCELLING // FINISHING CURRENT STEP..."
	host._last_macro_event = host._movement_state["message"]
	host._refresh_world_hud()
	return true


func debug_mark(label: String) -> void:
	if not OS.is_debug_build() or not host.debug_macro_logging:
		return
	var now := Time.get_ticks_usec()
	if label == "movement request accepted":
		host._movement_debug_request_usec = now
	var elapsed := (
		now - host._movement_debug_request_usec
		if host._movement_debug_request_usec > 0
		else 0
	)
	print("[MacroTiming] %s // +%.1f ms" % [label, float(elapsed) / 1000.0])


func present_travel_beat(
	origin_coords: Vector2i,
	target_coords: Vector2i,
	hex_data: MacroHexData,
	newly_explored: Array,
	has_ground_loot: bool
) -> void:
	var beat: Dictionary = MacroTravelBeatResolver.build_step_beat(
		origin_coords, target_coords, hex_data, newly_explored, has_ground_loot
	)
	if beat.is_empty():
		return
	var title := str(beat.get("title", "EXPLORING"))
	var body := str(beat.get("body", ""))
	var first_line := body.split("\n")[0].strip_edges() if not body.is_empty() else ""
	host._last_macro_event = (
		"%s — %s" % [title, first_line] if not first_line.is_empty() else title
	)
	if host.macro_hud != null:
		host.macro_hud.present_travel_beat(beat)
	guide_camera(origin_coords, target_coords)
	leave_trail(origin_coords, target_coords)


func commit_retreat(target_coords: Vector2i) -> void:
	var origin_coords := (
		host._world_state.player_record.coords
		if host._world_state.player_record != null
		else target_coords
	)
	var retreat_hex := host.world_generator.get_hex_at(target_coords)
	var request := WorldActionRequest.new()
	request.actor_id = "player"
	request.target_id = "retreat:%s" % str(target_coords)
	request.target_coords = target_coords
	request.verb_id = "retreat"
	request.payload["action_id"] = "retreat:%s:%s:%d" % [
		str(origin_coords), str(target_coords), host._world_state.player_revision,
	]
	var receipt := host._world_action_coordinator.resolve_direct_action(
		request, 0, 0.0, 0.0, "Retreat relocation committed."
	)
	receipt.mutations.append({
		"type": "move_actor", "from": origin_coords, "to": target_coords,
	})
	receipt.mutations.append({"type": "set_hex_explored"})
	host._movement_service.append_trace_to_receipt(
		receipt,
		"player",
		origin_coords,
		target_coords,
		str(host.campaign.active_node_id) if host.campaign != null else "",
		host._world_state.world_time_minutes,
		retreat_hex
	)
	debug_mark("receipt application start")
	var application := host._commit_world_action_receipt(receipt, target_coords)
	debug_mark("receipt application end")
	if application == null or not application.applied:
		host._macro_log(
			"Movement transaction rejected: %s"
			% (application.error if application != null else "no application receipt")
		)
		host.player_token.snap_to_hex(
			origin_coords, host.map_visualizer.map_to_local(origin_coords)
		)
		finish("RETREAT FAILED // RELOCATION REJECTED", "failed")
		host._refresh_world_hud()
		return
	host._pending_player_step.clear()
	mark_step_committed(target_coords)
	host._refresh_map_visuals(target_coords, false)
	host.refresh_proximity(target_coords)
	host._last_macro_event = "Escaped combat; fell back to HEX %d,%d." % [
		target_coords.x, target_coords.y,
	]
	finish_success(host._last_macro_event)
	host._refresh_world_hud()


func commit_step(origin_coords: Vector2i, target_coords: Vector2i) -> void:
	var hex_data := host.world_generator.get_hex_at(target_coords)
	var request := WorldActionRequest.new()
	request.actor_id = "player"
	request.target_id = "hex:%s" % str(target_coords)
	request.target_coords = target_coords
	request.verb_id = "travel"
	request.payload["world_time_minutes"] = host._world_state.world_time_minutes
	request.payload["action_id"] = "travel:player:%s:%s:%d" % [
		str(origin_coords), str(target_coords), host._world_state.player_revision,
	]
	var receipt := host._world_action_coordinator.resolve_direct_action(
		request,
		host._time_rules_service.move_minutes_for_hex(hex_data),
		host._time_rules_service.exertion_for_hex(hex_data),
		0.0,
		"Arrived at HEX %d,%d." % [target_coords.x, target_coords.y]
	)
	receipt.mutations.append({
		"type": "move_actor", "from": origin_coords, "to": target_coords,
	})
	receipt.mutations.append({"type": "set_hex_explored"})
	host._movement_service.append_trace_to_receipt(
		receipt,
		"player",
		origin_coords,
		target_coords,
		str(host.campaign.active_node_id) if host.campaign != null else "",
		host._world_state.world_time_minutes,
		hex_data
	)
	debug_mark("receipt application start")
	var application := host._commit_world_action_receipt(receipt, target_coords)
	debug_mark("receipt application end")
	if application == null or not application.applied:
		host._macro_log(
			"Movement transaction rejected: %s"
			% (application.error if application != null else "no application receipt")
		)
		host.player_token.snap_to_hex(
			origin_coords, host.map_visualizer.map_to_local(origin_coords)
		)
		host._last_macro_event = (
			application.error
			if application != null and not application.error.is_empty()
			else "Movement transaction was rejected."
		)
		if bool(host._movement_state.get("active", false)):
			finish("MOVEMENT FAILED // %s" % host._last_macro_event, "failed")
		else:
			host._refresh_world_hud()
		return
	host._pending_player_step.clear()
	mark_step_committed(target_coords)
	host._macro_log("Player stepped to %s." % str(target_coords))
	var newly_explored := host._refresh_map_visuals(target_coords, false)
	host.refresh_proximity(target_coords)
	host._turn_resolution.set_phase("world_turn", "TURN RESOLVE // NPC WORLD TURN...")
	host._movement_state["current_coords"] = target_coords
	host._last_macro_event = "Resolving the world turn at HEX %d,%d..." % [
		target_coords.x, target_coords.y,
	]
	host._refresh_world_hud()
	call_deferred(
		"_resolve_committed_step",
		origin_coords,
		target_coords,
		hex_data,
		newly_explored,
		int(host._movement_state.get("resolution_id", 0))
	)


func _resolve_committed_step(
	origin_coords: Vector2i,
	target_coords: Vector2i,
	hex_data: MacroHexData,
	newly_explored: Array,
	resolution_id: int
) -> void:
	if not host._turn_resolution.is_active():
		return
	if int(host._movement_state.get("resolution_id", 0)) != resolution_id:
		return
	var target_snapshot := host._world_state.get_entity_snapshot_at(target_coords)
	if not target_snapshot.is_empty():
		var target_entity := EntityRecord.from_dict(target_snapshot)
		if not host._world_state.is_entity_active(target_entity.entity_id):
			host.unload_enemy_token(target_coords)
		else:
			host._force_project_npc_token(target_entity)
			if host._world_state.is_entity_hostile(target_entity.entity_id):
				host._advance_player_world_turn()
			finish(
				"MOVEMENT INTERRUPTED // HOSTILE CONTACT AT HEX %d,%d"
				% [target_coords.x, target_coords.y],
				"interrupted"
			)
			host.begin_entity_collision(
				target_entity.entity_id, target_coords, origin_coords
			)
			return
	if host._world_state.has_ground_items(target_coords):
		finish(
			"MOVEMENT INTERRUPTED // GROUND ITEMS AT HEX %d,%d"
			% [target_coords.x, target_coords.y],
			"interrupted"
		)
		return
	host._advance_player_world_turn()
	if not host._pending_interaction.is_empty():
		finish("MOVEMENT INTERRUPTED // CONTACT REQUIRES ATTENTION", "interrupted")
		return
	host._turn_resolution.set_phase("presentation", "TURN RESOLVE // PRESENTATION...")
	present_travel_beat(
		origin_coords, target_coords, hex_data, newly_explored, false
	)
	host._refresh_world_hud()
	call_deferred("_finish_step_presentation", target_coords, resolution_id)


func _finish_step_presentation(target_coords: Vector2i, resolution_id: int) -> void:
	if not host._turn_resolution.is_active():
		return
	if int(host._movement_state.get("resolution_id", 0)) != resolution_id:
		return
	if not host._pending_interaction.is_empty():
		finish("MOVEMENT INTERRUPTED // CONTACT REQUIRES ATTENTION", "interrupted")
		return
	if host._route_cancel_requested:
		finish(
			"ROUTE CANCELLED AT HEX %d,%d" % [target_coords.x, target_coords.y],
			"interrupted"
		)
		host._refresh_world_hud()
		return
	if not host._travel_route.is_empty():
		host._turn_resolution.set_phase("walking", "TURN RESOLVE // NEXT STEP...")
		execute_step(host._travel_route.pop_front(), true, true)
		return
	finish_success("ARRIVED AT HEX %d,%d." % [target_coords.x, target_coords.y])
	host._refresh_world_hud()


func mark_step_committed(target_coords: Vector2i) -> void:
	host._travel_completed_steps += 1
	host._turn_resolution.mark_step_committed(
		target_coords, host._travel_route_total_steps
	)


func guide_camera(origin_coords: Vector2i, target_coords: Vector2i) -> void:
	var camera := host.get_node_or_null("Camera2D") as MacroCamera
	if camera == null or host.map_visualizer == null:
		return
	var from_pos: Vector2 = host.map_visualizer.map_to_local(origin_coords)
	var to_pos: Vector2 = host.map_visualizer.map_to_local(target_coords)
	camera.begin_travel_look_ahead(from_pos, to_pos)
	host.get_tree().create_timer(MacroPlayer.WALK_DURATION_SECONDS).timeout.connect(
		func() -> void:
			if is_instance_valid(camera):
				camera.end_travel_look_ahead()
	)


func leave_trail(origin_coords: Vector2i, target_coords: Vector2i) -> void:
	if host.map_visualizer == null:
		return
	if host._movement_trail == null:
		host._movement_trail = MacroMovementTrail.new()
		host._movement_trail.name = "MacroMovementTrail"
		host._movement_trail.z_index = -1
		host.add_child(host._movement_trail)
	var from_pos: Vector2 = host.map_visualizer.map_to_local(origin_coords)
	var to_pos: Vector2 = host.map_visualizer.map_to_local(target_coords)
	var facing := to_pos - from_pos
	host._movement_trail.add_step(from_pos.lerp(to_pos, 0.35), facing)
	host._movement_trail.add_step(from_pos.lerp(to_pos, 0.7), facing)
