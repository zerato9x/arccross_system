extends RefCounted
class_name MacroActiveZoneService

## Applies the generated campaign zone to the run-scoped world projection.
##
## This service owns the stateful part of a node swap: replacing the legacy
## world-generator cache, copying the generated hex records into the runtime
## store, and preserving the player's live runtime while moving the token to
## the authored arrival rim. Presentation refreshes remain with the manager so
## existing HUD ordering and compatibility signals stay unchanged.

var _world_state: RuntimeStateStore
var _world_generator: HexWorldGenerator
var _player_token: MacroPlayer
var _map_visualizer: HexMapVisualizer


func configure(
	world_state: RuntimeStateStore,
	world_generator: HexWorldGenerator,
	player_token: MacroPlayer,
	map_visualizer: HexMapVisualizer
) -> void:
	_world_state = world_state
	_world_generator = world_generator
	_player_token = player_token
	_map_visualizer = map_visualizer


func apply(campaign: MacroProgressController) -> Dictionary:
	if (
		campaign == null
		or campaign.zone_generator == null
		or _world_state == null
		or _world_generator == null
		or _player_token == null
	):
		return {"applied": false, "start_coords": Vector2i.ZERO}

	var zone := campaign.zone_generator
	_world_generator.enable_zone_bounds(GameEnums.MACRO_ZONE_RADIUS)
	_world_generator.configure_seed(_world_state.world_seed + ":node:" + zone.node_id)
	_world_generator.inject_zone_hexes(zone.world_hex_cache)
	_world_generator.inject_zone_decorations(zone.zone_decorations)
	for coords in zone.world_hex_cache.keys():
		var hex: MacroHexData = zone.world_hex_cache[coords]
		_world_state.set_hex_record(coords, hex.to_state())

	var start_coords := zone.start_coords
	# Preserve player runtime (inventory) across node swaps.
	var player_core := _player_token.get_humanoid_core()
	if player_core != null and _world_state.player_record != null:
		_world_state.update_player_runtime(
			player_core.capture_runtime_state().to_dict(),
			start_coords
		)
	else:
		_world_state.set_player_record(
			_player_token.capture_runtime_record(),
			start_coords
		)

	var start_pixel := Vector2.ZERO
	if _map_visualizer != null:
		start_pixel = _map_visualizer.map_to_local(start_coords)
	_player_token.snap_to_hex(start_coords, start_pixel)
	return {"applied": true, "start_coords": start_coords}
