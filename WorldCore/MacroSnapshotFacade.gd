extends RefCounted
class_name MacroSnapshotFacade

## Application-facing snapshot builder. It accepts callbacks for domain-owned
## queries and returns neutral dictionaries; presentation never receives live
## world records from this boundary.

var player_token: MacroPlayer
var world_state: RuntimeStateStore
var world_generator: HexWorldGenerator
var campaign: MacroProgressController
var selected_hex_coords: Vector2i = Vector2i.ZERO
var visible_hexes: Dictionary = {}
var active_enemies: Dictionary = {}
var last_macro_event: String = ""
var macro_turn_index: int = 0
var callbacks: Dictionary = {}
const _SnapshotBuilder := preload("res://WorldCore/MacroSnapshotBuilder.gd")


func configure(
	player: MacroPlayer,
	state: RuntimeStateStore,
	generator: HexWorldGenerator,
	progression: MacroProgressController,
	selected_coords: Vector2i,
	visible: Dictionary,
	enemies: Dictionary,
	last_event: String,
	turn_index: int,
	query_callbacks: Dictionary
) -> void:
	player_token = player
	world_state = state
	world_generator = generator
	campaign = progression
	selected_hex_coords = selected_coords
	visible_hexes = visible
	active_enemies = enemies
	last_macro_event = last_event
	macro_turn_index = turn_index
	callbacks = query_callbacks


func build_inventory_snapshot() -> Dictionary:
	if player_token == null or world_state == null:
		return {}
	var core := player_token.get_humanoid_core()
	return _SnapshotBuilder.build_inventory_snapshot_from_neutral(
		BiologicalSnapshotService.capture(core),
		InventorySnapshotService.capture(
			core,
			world_state.get_ground_items(player_token.current_hex_coords),
			callbacks.get("can_offer_equip", Callable()),
			callbacks.get("allowed_equipment_slots", Callable())
		),
		player_token.current_hex_coords,
		world_state.get_world_time_snapshot()
	)


func build_world_hud_snapshot() -> Dictionary:
	if player_token == null or world_state == null or world_generator == null:
		return {}
	var core := player_token.get_humanoid_core()
	var snapshot := _SnapshotBuilder.build_world_hud_snapshot_from_neutral(
		BiologicalSnapshotService.capture(core),
		InventorySnapshotService.capture(
			core,
			world_state.get_ground_items(player_token.current_hex_coords),
			callbacks.get("can_offer_equip", Callable()),
			callbacks.get("allowed_equipment_slots", Callable())
		),
		player_token.current_hex_coords,
		selected_hex_coords,
		world_state.get_world_time_snapshot(),
		last_macro_event,
		macro_turn_index,
		active_enemies.size(),
		world_state,
		world_generator,
		callbacks.get("ensure_npc_purpose", Callable()),
		callbacks.get("hex_distance", Callable()),
		callbacks.get("hex_label", Callable()),
		Callable(world_state, "is_entity_alive"),
		Callable(world_state, "is_entity_hostile")
	)
	if campaign != null:
		var active := campaign.get_active_node()
		var next_ids: Array[String] = []
		var next_callback: Callable = callbacks.get("next_incomplete_nodes", Callable())
		if next_callback.is_valid():
			next_ids = next_callback.call()
		snapshot["campaign"] = {
			"active_node_id": campaign.active_node_id,
			"available_nodes": campaign.get_available_nodes(),
			"next_nodes": next_ids,
			"active_display_name": active.display_name if active != null else "",
			"active_traversed": active != null and active.traversed,
			"pending_exit_direction": int(callbacks.get("pending_exit_direction", 0)),
			"advance_hint": (
				"Leave through the active rim sector to reach %s." % next_ids[0]
				if not next_ids.is_empty()
				else ""
			),
		}
	snapshot["minimap"] = build_minimap_snapshot()
	return snapshot


func build_minimap_snapshot() -> Dictionary:
	if world_generator == null or player_token == null:
		return {}
	var cells: Array[Dictionary] = []
	for coords in world_generator.world_hex_cache.keys():
		if not coords is Vector2i:
			continue
		if world_generator.zone_bounds_enabled and not world_generator.is_in_zone_bounds(coords):
			continue
		var hex_data := world_generator.world_hex_cache.get(coords) as MacroHexData
		if hex_data == null:
			continue
		var label := hex_data.poi_name
		if label.is_empty():
			label = hex_data.landmark_id.replace("_", " ").capitalize()
		if label.is_empty():
			label = _SnapshotBuilder.feature_title(hex_data)
		cells.append({
			"coords": coords,
			"terrain": int(hex_data.terrain_tile),
			"flora": int(hex_data.flora_layer),
			"rock": int(hex_data.rock_layer),
			"water": int(hex_data.water_layer),
			"structure": int(hex_data.structure_layer),
			"explored": hex_data.is_explored,
			"visible": visible_hexes.has(coords),
			"is_poi": hex_data.is_poi,
			"has_landmark": not hex_data.landmark_id.is_empty(),
			"label": label,
			"passable": hex_data.is_passable(),
		})
	var visible_hostiles: Array[Vector2i] = []
	for coords in active_enemies.keys():
		if coords is Vector2i and visible_hexes.has(coords):
			visible_hostiles.append(coords)
	var exits: Array[Dictionary] = []
	if campaign != null and campaign.graph != null:
		for direction in [
			GameEnums.MacroTravelDirection.NORTH,
			GameEnums.MacroTravelDirection.NORTHEAST,
			GameEnums.MacroTravelDirection.EAST,
			GameEnums.MacroTravelDirection.SOUTHEAST,
			GameEnums.MacroTravelDirection.SOUTH,
			GameEnums.MacroTravelDirection.SOUTHWEST,
			GameEnums.MacroTravelDirection.WEST,
			GameEnums.MacroTravelDirection.NORTHWEST,
		]:
			if campaign.get_directional_destinations(direction).is_empty():
				continue
			var anchor := HexCoordUtils.rim_anchor(direction, world_generator.zone_radius)
			var anchor_hex := world_generator.world_hex_cache.get(anchor) as MacroHexData
			if anchor_hex == null or not anchor_hex.is_explored:
				continue
			exits.append({"coords": anchor, "direction": int(direction)})
	return {
		"radius": world_generator.zone_radius,
		"cells": cells,
		"player_coords": player_token.current_hex_coords,
		"selected_coords": selected_hex_coords,
		"visible_hostiles": visible_hostiles,
		"exits": exits,
	}


func build_hex_descriptor(coords: Vector2i) -> Dictionary:
	if player_token == null or world_state == null or world_generator == null:
		return {}
	var hex_data := world_generator.get_hex_at(coords)
	var entity_snapshot := world_state.get_entity_snapshot_at(coords)
	var entity_record := (
		EntityRecord.from_dict(entity_snapshot)
		if not entity_snapshot.is_empty()
		else null
	)
	var hex_label_callback: Callable = callbacks.get("hex_label", Callable())
	var label := str(coords)
	if hex_label_callback.is_valid():
		label = hex_label_callback.call(coords, hex_data)
	return _SnapshotBuilder.build_hex_descriptor(
		coords,
		player_token.current_hex_coords,
		hex_data,
		entity_record,
		world_state.get_ground_items(coords),
		label,
		Callable(world_state, "is_entity_alive"),
		Callable(world_state, "is_entity_hostile"),
		callbacks.get("ensure_npc_purpose", Callable()),
		callbacks.get("hex_distance", Callable())
	)


func build_macro_activity_snapshot() -> Dictionary:
	if player_token == null or world_state == null:
		return {}
	var entity_snapshots: Array = []
	for snapshot_value in world_state.get_all_entity_snapshots():
		if snapshot_value is Dictionary:
			entity_snapshots.append(EntityRecord.from_dict(snapshot_value))
	return _SnapshotBuilder.build_macro_activity_snapshot(
		player_token.current_hex_coords,
		macro_turn_index,
		active_enemies.size(),
		entity_snapshots,
		callbacks.get("ensure_npc_purpose", Callable()),
		callbacks.get("hex_distance", Callable())
	)
