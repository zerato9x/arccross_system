extends RefCounted
class_name MacroLocationSnapshotService

## Builds the neutral current/target location snapshots consumed by macro UI.
## The service owns no UI nodes and never exposes authoritative records.

const _PoiController := preload("res://WorldCore/MacroPoiController.gd")
const _HexPresentation := preload(
	"res://PresentationCore/HexPresentationDescriptor.gd"
)

var player_token: MacroPlayer
var world_state: RuntimeStateStore
var world_generator: HexWorldGenerator
var map_visualizer: HexMapVisualizer
var callbacks: Dictionary = {}


func configure(
	player: MacroPlayer,
	state: RuntimeStateStore,
	generator: HexWorldGenerator,
	visualizer: HexMapVisualizer,
	query_callbacks: Dictionary
) -> void:
	player_token = player
	world_state = state
	world_generator = generator
	map_visualizer = visualizer
	callbacks = query_callbacks


func build_current(inventory_snapshot: Dictionary) -> Dictionary:
	if player_token == null or world_state == null or world_generator == null:
		return {}
	var coords := player_token.current_hex_coords
	var hex_data := world_generator.get_hex_at(coords)
	var build_hex_descriptor: Callable = callbacks.get(
		"build_hex_descriptor",
		Callable()
	)
	var hex_descriptor: Dictionary = (
		build_hex_descriptor.call(coords)
		if build_hex_descriptor.is_valid()
		else {}
	)
	var camp_access_callback: Callable = callbacks.get(
		"camp_access",
		Callable()
	)
	var camp_access: Dictionary = (
		camp_access_callback.call(coords, hex_data)
		if camp_access_callback.is_valid()
		else {}
	)
	var available_items := _PoiController.available_interaction_options(
		player_token.get_humanoid_core().inventory.get_all_items()
	)
	var ground_items: Array = inventory_snapshot.get("ground", [])
	var world_time := world_state.get_world_time_snapshot()
	var hex_label := _hex_label(coords, hex_data)
	var inventory_has_item_id: Callable = callbacks.get(
		"inventory_has_item_id",
		Callable()
	)
	var inventory_has_tag: Callable = callbacks.get(
		"inventory_has_tag",
		Callable()
	)
	var inventory_has_role: Callable = callbacks.get(
		"inventory_has_role",
		Callable()
	)
	var session: Dictionary
	if hex_data.has_landmark():
		session = _PoiController.build_landmark_session_snapshot(
			coords,
			hex_data,
			world_state.world_seed,
			world_time,
			hex_label,
			camp_access,
			available_items,
			ground_items,
			inventory_has_item_id,
			inventory_has_tag,
			inventory_has_role
		)
	else:
		session = _PoiController.build_hex_session_snapshot(
			coords,
			hex_data,
			world_state.world_seed,
			world_time,
			hex_label,
			camp_access,
			available_items,
			ground_items,
			inventory_has_item_id,
			inventory_has_tag,
			inventory_has_role
		)
	var enrich_session: Callable = callbacks.get(
		"enrich_session",
		Callable()
	)
	if enrich_session.is_valid():
		enrich_session.call(session, hex_data)
	var presentation := _build_compact_presentation(
		coords,
		hex_descriptor,
		ground_items
	)
	presentation["scene"] = _HexPresentation.merge_scene(
		presentation.get("scene", {}),
		session.get("scene_descriptor", {})
	)
	var revision_payload := {
		"coords": str(coords),
		"hex": hex_data.to_state().to_dict(),
		"ground": ground_items,
		"available_item_ids": available_items.map(
			func(item: Dictionary): return str(item.get("instance_id", ""))
		),
		"world_time": world_state.get_world_time_snapshot(),
	}
	return {
		"coords": coords,
		"revision": hash(str(revision_payload)),
		"hex": hex_descriptor,
		"presentation": presentation,
		"session": session,
		"fixture_count": session.get("site", {}).get("fixtures", []).size(),
		"can_open": not _is_movement_active(),
	}


func build_target(snapshot: Dictionary) -> Dictionary:
	if player_token == null or world_state == null or world_generator == null:
		return {}
	var target: Dictionary = snapshot.get("selected_hex", {}).duplicate(true)
	var current_coords := player_token.current_hex_coords
	var target_coords: Vector2i = target.get("coords", current_coords)
	if target_coords == current_coords:
		return {}
	target["exploration"] = {
		"available": false,
		"lock_reason": "Travel here first",
	}
	if bool(target.get("explored", false)):
		target["presentation"] = _build_compact_presentation(
			target_coords,
			target,
		[]
		)
	var blocked_reason := ""
	var route: Array = []
	if not world_generator.is_in_zone_bounds(target_coords):
		blocked_reason = "Outside this zone"
	elif _is_movement_active():
		blocked_reason = "Movement in progress"
	elif not bool(target.get("travel_known", false)):
		blocked_reason = "That hex is not known well enough to plot a route"
	elif not bool(target.get("passable", false)):
		blocked_reason = "Blocked terrain"
	else:
		var route_callback: Callable = callbacks.get(
			"build_travel_route",
			Callable()
		)
		if route_callback.is_valid():
			var route_value: Variant = route_callback.call(current_coords, target_coords)
			if route_value is Array:
				route = route_value
			if route.is_empty():
				blocked_reason = "No passable route is known to the selected hex"
			else:
				target["route_steps"] = route.size()
				target["travel_minutes"] = _route_travel_minutes(route)
				target["travel_km"] = GameTimeRules.travel_distance_km(route.size())
	target["blocked_reason"] = blocked_reason
	target["can_travel"] = blocked_reason.is_empty()
	return target


func _build_compact_presentation(
	coords: Vector2i,
	hex_descriptor: Dictionary,
	ground_items: Array
) -> Dictionary:
	if (
		world_state == null
		or world_generator == null
		or not world_generator.is_in_zone_bounds(coords)
		or not bool(hex_descriptor.get("explored", false))
	):
		return {}
	var hex_data := world_generator.get_hex_at(coords)
	var decorations: Array = []
	if world_generator.has_method("get_decorations_at"):
		decorations = world_generator.get_decorations_at(coords)
	var catalog: MacroTileCatalog = (
		map_visualizer.tile_catalog if map_visualizer != null else null
	)
	return _HexPresentation.build(
		hex_data,
		catalog,
		decorations,
		world_state.world_seed,
		coords,
		hex_descriptor.get("entity_inspect", {}),
		ground_items
	)


func _route_travel_minutes(route: Array) -> int:
	var minutes := 0
	for value in route:
		if value is Vector2i:
			minutes += GameTimeRules.move_minutes_for_hex(
				world_generator.get_hex_at(value)
			)
	return minutes


func _hex_label(coords: Vector2i, hex_data: MacroHexData) -> String:
	var callback: Callable = callbacks.get("hex_label", Callable())
	if callback.is_valid():
		return str(callback.call(coords, hex_data))
	return str(coords)


func _is_movement_active() -> bool:
	var callback: Callable = callbacks.get("is_movement_active", Callable())
	return bool(callback.call()) if callback.is_valid() else false
