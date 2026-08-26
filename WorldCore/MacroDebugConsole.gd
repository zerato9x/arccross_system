extends RefCounted
class_name MacroDebugConsole

## Debug/QA tooling extracted from MacroGameManager. Holds a weak-style
## reference to its owning manager and drives the same live systems (map,
## player token, world state, HUD). MacroGameManager keeps its public debug_*
## API unchanged and thin-forwards into this console so tests are unaffected.

var host: MacroGameManager


func _init(host_manager: MacroGameManager = null) -> void:
	host = host_manager


## Instantly relocate the player to any hex without walking, survival-time
## cost, or triggering pending interactions. Rebuilds fog, proximity tokens,
## and the HUD so the jump is fully reflected.
func teleport_player(target_coords: Vector2i) -> void:
	if host.map_visualizer == null or host.player_token == null:
		return
	var pixel_pos := host.map_visualizer.map_to_local(target_coords)
	host.player_token.snap_to_hex(target_coords, pixel_pos)
	host._world_state.update_player_runtime(
		host.player_token.get_humanoid_core().capture_runtime_state().to_dict(),
		target_coords
	)
	host._select_hex_for_hud(target_coords)
	host._mark_hex_explored(target_coords)
	host._refresh_map_visuals(target_coords, false)
	host.refresh_proximity(target_coords)
	host._macro_log("Debug teleport to %s." % str(target_coords))
	host._refresh_world_hud()


## Persist the live player runtime into WorldState and rebuild every
## player-facing surface (token pose, inventory panel, exploration ground,
## HUD). Call after directly mutating the HumanoidCore/body/inventory so the
## change becomes visible and save-safe.
func sync_player_after_mutation() -> void:
	if host.player_token == null:
		return
	var core := host.player_token.get_humanoid_core()
	host._world_state.update_player_runtime(
		core.capture_runtime_state().to_dict(),
		host.player_token.current_hex_coords
	)
	if host.player_token.humanoid_token:
		host.player_token.humanoid_token.refresh_from_record(
			host.player_token.capture_runtime_record()
		)
		host.player_token.refresh_token_pose()
	var snapshot := host._build_inventory_snapshot()
	if host.inventory_panel and host.inventory_panel.is_open():
		host.inventory_panel.refresh_snapshot(snapshot, "")
	host._refresh_exploration_ground()
	host._refresh_world_hud()


## Spawn a procedural enemy on the first free, passable hex adjacent to the
## player. Returns true if an encounter was projected.
func spawn_enemy_near_player(
	faction: GameEnums.Faction = GameEnums.Faction.SCAVENGER_CELL,
	difficulty: int = 0
) -> bool:
	if host.player_token == null or host.world_generator == null:
		return false
	for delta in MacroGameManager.HEX_NEIGHBORS:
		var coords: Vector2i = host.player_token.current_hex_coords + delta
		if not host.world_generator.get_hex_at(coords).is_passable():
			continue
		if host._world_state.has_entity_at(coords):
			continue
		host.spawn_procedural_enemy(coords, faction, difficulty)
		host._refresh_world_hud()
		return true
	return false


func open_central_hub(coords: Vector2i) -> void:
	if not host._pending_interaction.is_empty():
		return
	host._pending_interaction = {
		"type": GameEnums.MacroInteractionType.MACRO_EVENT,
		"coords": coords,
		"event_id": "debug_central_hub",
	}
	host.player_token.play_interaction()
	host.set_process_unhandled_input(false)
	if host.macro_hud == null:
		host.close_macro_interaction()
		return
	host.macro_hud.open_event({
		"id": "debug_central_hub",
		"mode": "event",
		"title": "CENTRAL CORE — DEBUG HUB",
		"body": (
			"Campaign control node. Use the live meta path, or fire isolated "
			+ "probes for exploration, events, collisions, and loot."
		),
		"tags": ["CENTRAL", "DEBUG"],
		"can_close": true,
		"fx": {"kind": "landmark", "intensity": 0.35},
		"choices": [
			_choice("meta_quest", "Continue Meta Quest", "talk", ["LIVE"],
				"Runs the North Core Regulator fetch / install flow."),
			_choice("dbg_event", "DEBUG: Open Treatment Room Event", "observe", ["EVENT"],
				"Opens the authored locked_treatment_room macro event."),
			_choice("dbg_hostile", "DEBUG: Spawn Hostile Collision", "ambush", ["COMBAT"],
				"Spawns a scavenger on this hex and opens Talk/Ambush."),
			_choice("dbg_loot", "DEBUG: Drop Ground Loot", "item", ["LOOT"],
				"Drops sample items on this hex for ground pickup tests."),
			_choice("dbg_poi", "DEBUG: Open Landmark Explore", "observe", ["POI"],
				"Injects a homestead landmark here and opens Search/Camp."),
			_choice("dbg_travel", "DEBUG: Sample Travel Feedback", "pass", ["TRAVEL"],
				"Writes a travel log line, leaves a trail, and soft look-ahead."),
			_choice("leave", "Leave", "pass", [], "Close the hub."),
		],
	})


func resolve_central_hub_choice(choice_id: String) -> void:
	var coords: Vector2i = host._pending_interaction.get(
		"coords", host.player_token.current_hex_coords
	)
	match choice_id:
		"meta_quest":
			host.close_macro_interaction()
			host._handle_central_meta_quest()
		"dbg_event":
			host.close_macro_interaction()
			host.begin_macro_event(
				MacroEventResolver.EVENT_LOCKED_TREATMENT_ROOM, coords
			)
		"dbg_hostile":
			host.close_macro_interaction()
			if not spawn_enemy_near_player(GameEnums.Faction.SCAVENGER_CELL, 0):
				_set_event("DEBUG: Hostile spawn failed (no free adjacent hex).")
				return
			var enemy_id := ""
			for delta in MacroGameManager.HEX_NEIGHBORS:
				var probe: Vector2i = coords + delta
				var record_snapshot := host._world_state.get_entity_snapshot_at(probe)
				if (
					not record_snapshot.is_empty()
					and host._world_state.is_entity_hostile(
						str(record_snapshot.get("entity_id", ""))
					)
				):
					enemy_id = str(record_snapshot.get("entity_id", ""))
					host._world_state.move_entity(enemy_id, coords)
					break
			if enemy_id.is_empty():
				_set_event("DEBUG: Hostile spawned but collision handoff failed.")
				return
			host.begin_entity_collision(enemy_id, coords)
		"dbg_loot":
			host.close_macro_interaction()
			drop_sample_loot(coords)
		"dbg_poi":
			host.close_macro_interaction()
			open_landmark_here(coords)
		"dbg_travel":
			host.close_macro_interaction()
			var hex_data := host.world_generator.get_hex_at(coords)
			host._present_travel_beat(
				coords, coords + Vector2i(1, 0), hex_data, [coords], false
			)
			host._refresh_world_hud()
		"leave", _:
			host.close_macro_interaction()


func drop_sample_loot(coords: Vector2i) -> void:
	if host._loot_catalog == null:
		_set_event("DEBUG: Loot catalog unavailable.")
		return
	var drops: Array = []
	for item_id in ["water_bottle", "crackers", "bandage", "matches", "bottle"]:
		if not host._loot_catalog.has_item(item_id):
			continue
		var state: Dictionary = host._loot_catalog.create_runtime_item_state(item_id)
		if not state.is_empty():
			drops.append(state)
		if drops.size() >= 3:
			break
	if drops.is_empty():
		host._last_macro_event = "DEBUG: No sample loot definitions found."
	else:
		host._world_state.add_ground_items(coords, drops)
		host._last_macro_event = "DEBUG: Dropped %d ground item(s) at HEX %d,%d." % [
			drops.size(), coords.x, coords.y,
		]
	if host.macro_hud != null:
		host.macro_hud.append_exploration_log(host._last_macro_event)
	host._refresh_world_hud()


func open_landmark_here(coords: Vector2i) -> void:
	var hex := host.world_generator.get_hex_at(coords)
	hex.rock_layer = GameEnums.MacroRockLayer.NONE
	hex.water_layer = GameEnums.MacroWaterLayer.NONE
	hex.structure_layer = GameEnums.MacroStructureLayer.STRUCTURES
	hex.is_poi = true
	hex.landmark_id = "homestead_b"
	hex.poi_id = "plains_homestead"
	hex.poi_name = "Debug Homestead"
	hex.sleep_anchor = "ground"
	host.world_generator.world_hex_cache[coords] = hex
	host.world_generator.commit_hex_projection(coords, hex)
	host.begin_poi_interaction(coords, hex)


func _set_event(message: String) -> void:
	host._last_macro_event = message
	host._refresh_world_hud()


func _choice(
	id: String,
	label: String,
	kind: String,
	stakes: Array,
	reason: String
) -> Dictionary:
	return {
		"id": id,
		"label": label,
		"kind": kind,
		"enabled": true,
		"stakes": stakes,
		"reason": reason,
	}
