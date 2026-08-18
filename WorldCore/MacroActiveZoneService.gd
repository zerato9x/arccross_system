extends RefCounted
class_name MacroActiveZoneService

## Applies the generated campaign zone to the run-scoped world projection.
##
## RuntimeStateStore has already completed the node transaction. This service
## rebuilds scene projections and places the live token from canonical records.

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
	_world_generator.rebuild_projection_from_store()
	_world_generator.inject_zone_decorations(zone.zone_decorations)

	if _world_state.player_record == null:
		return {"applied": false, "start_coords": Vector2i.ZERO}
	_player_token.restore_runtime_record(_world_state.player_record)
	var start_coords := _world_state.player_record.coords

	var start_pixel := Vector2.ZERO
	if _map_visualizer != null:
		start_pixel = _map_visualizer.map_to_local(start_coords)
	_player_token.snap_to_hex(start_coords, start_pixel)
	return {"applied": true, "start_coords": start_coords}
