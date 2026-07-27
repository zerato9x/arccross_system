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
