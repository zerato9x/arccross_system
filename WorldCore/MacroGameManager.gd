extends Node2D
class_name MacroGameManager

# Cross-system handoff contains only IDs, primitives, and GameEnums values.
signal combat_requested(request: Dictionary)
signal save_requested
signal load_requested
signal core_activated
signal campaign_node_changed(node_id: String)
signal campaign_nodes_unlocked(node_ids: Array)

@export_group("The Strings")
@export var world_generator: HexWorldGenerator
@export var map_visualizer: HexMapVisualizer
@export var player_token: MacroPlayer
@export var enemy_token_scene: PackedScene
@export var mob_spawner: MobSpawner
@export var inventory_panel: InventoryUI
@export var macro_hud: MacroHudController
@export var exploration_window_scene: PackedScene
@export var node_map_system_scene: PackedScene
@export var node_map_medical_scene: PackedScene

@onready var vision_vignette: VisionVignetteOverlay = $VisionVignette

var exploration_window: MacroExplorationWindow
## Fullscreen Node Map System (independent of MacroHudShell).
var node_map_system: CanvasLayer
## Directional campaign-web progression and local-zone ownership.
var campaign: MacroProgressController
var _node_map_inventory_layer_restore := 1
var _inventory_home_layer: CanvasLayer
var _node_map_overlay_layer: CanvasLayer
var _node_map_medical: Control
var _movement_trail: MacroMovementTrail

@export_group("Proximity Loading")
@export_range(1, 12) var active_radius: int = 3
@export_range(2, 16) var unload_radius: int = 6
@export_range(1, 12) var generation_radius: int = 4
@export_range(0, 4) var safe_start_radius: int = 1
@export_range(0.0, 1.0) var base_enemy_spawn_chance: float = 0.025
@export_range(1, 8) var max_visible_npc_tokens: int = 3
@export_range(0, 8) var max_new_encounters_per_refresh: int = 1

@export_group("Fog Of War")
## Hexes within this radius of the player are currently "visible" (in sight).
## Visited hexes stay "explored" forever; everything else is unseen fog.
@export_range(1, 8) var vision_radius: int = 2
## When true, encounters only seed in explored territory that is NOT currently
## visible, so hostiles can never pop into existence inside the player's sight.
@export var fog_gated_spawning: bool = true
## Emit verbose [MacroMap] traces for the spawn/despawn/movement pipeline.
@export var debug_macro_logging: bool = true

@export_group("NPC Evaluation")
@export_range(1, 12) var npc_evaluation_radius: int = 7
@export_range(1, 12) var npc_pursuit_radius: int = 5
## Craven Hive thralls are cowardly: they only commit to a chase when prey is
## almost on top of them and break off quickly. This is a much shorter aggro
## leash than the relentless default pursuit radius.
@export_range(1, 12) var craven_pursuit_radius: int = 2
@export_range(0.0, 1.0) var npc_wander_chance: float = 0.35

const NPC_PURPOSE_SCAVENGE := GameEnums.NPC_PURPOSE_SCAVENGE
const NPC_PURPOSE_PATROL := GameEnums.NPC_PURPOSE_PATROL
const NPC_PURPOSE_HUNT := GameEnums.NPC_PURPOSE_HUNT
const NPC_PURPOSE_ROAM := GameEnums.NPC_PURPOSE_ROAM

## Aliases director-owned token projections so existing call sites keep working.
var active_enemies: Dictionary:
	get:
		return _get_proximity_director().active_enemies
	set(value):
		_get_proximity_director().active_enemies = value if value != null else {}
var _visible_hexes: Dictionary = {} # Vector2i -> true for the current line of sight
var _world_state: RuntimeStateStore
var _loot_catalog: Node
var _world_bootstrapped := false
var _interaction_state := MacroInteractionState.new()
var _collision_coordinator: MacroCollisionCoordinator
var _proximity_director: MacroProximityDirector
## Aliases `_interaction_state.data` so existing call sites keep working while
## collision coordinator shares the same MacroInteractionState instance.
var _pending_interaction: Dictionary:
	get:
		return _interaction_state.data
	set(value):
		_interaction_state.data = value if value != null else {}
var _last_inventory_error: String = ""
var _selected_hex_coords: Vector2i = Vector2i.ZERO
var _macro_turn_index := 0
var _last_macro_event := "Macro systems nominal."
var _mutation_store: Node
var _meta_progress: Node
var _pending_exit_direction: GameEnums.MacroTravelDirection = GameEnums.MacroTravelDirection.NONE
var _debug_console: MacroDebugConsole

const HEX_NEIGHBORS = [
	Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1), 
	Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1)
]
const _SnapshotBuilder := preload("res://WorldCore/MacroSnapshotBuilder.gd")
const _PoiController := preload("res://WorldCore/MacroPoiController.gd")
const _NpcSimulator := preload("res://WorldCore/MacroNpcSimulator.gd")
const _NODE_MAP_INVENTORY_LAYER := 36
const _NODE_MAP_OVERLAY_LAYER := 36

func configure_services(
	world_state: RuntimeStateStore,
	loot_catalog: Node
) -> void:
	_world_state = world_state
	_loot_catalog = loot_catalog
	if world_generator:
		world_generator.configure_services(world_state)
	_ensure_campaign()
	_connect_world_time_lighting()
	if is_node_ready() and not _world_bootstrapped:
		_bootstrap_world()


func _connect_world_time_lighting() -> void:
	if _world_state == null:
		return
	if not _world_state.world_time_advanced.is_connected(_on_world_time_advanced_lighting):
		_world_state.world_time_advanced.connect(_on_world_time_advanced_lighting)
	_apply_world_lighting_from_minutes(_world_state.world_time_minutes)


func _on_world_time_advanced_lighting(
	_previous: int,
	current: int,
	_elapsed: int
) -> void:
	_apply_world_lighting_from_minutes(current)


func _apply_world_lighting_from_minutes(total_minutes: int) -> void:
	MacroWorldLighting.apply_from_minutes(total_minutes, vision_vignette, macro_hud)


func _ensure_campaign() -> void:
	if campaign == null:
		campaign = MacroProgressController.new()
	campaign.configure(_world_state)
	if not campaign.node_entered.is_connected(_on_campaign_node_entered):
		campaign.node_entered.connect(_on_campaign_node_entered)
	if not campaign.nodes_unlocked.is_connected(_on_campaign_nodes_unlocked):
		campaign.nodes_unlocked.connect(_on_campaign_nodes_unlocked)


func get_available_nodes() -> Array[String]:
	_ensure_campaign()
	return campaign.get_available_nodes()


func enter_campaign_node(
	node_id: String,
	exit_direction: int = GameEnums.MacroTravelDirection.NONE
) -> bool:
	_ensure_campaign()
	if not campaign.can_enter_node(node_id, exit_direction):
		if (
			node_id == MacroGraphGenerator.CENTRAL_ID
			and campaign.active_node_id != MacroGraphGenerator.CENTRAL_ID
		):
			_last_macro_event = MacroEntityCollisionResolver.central_reentry_refused_line()
			_macro_log(_last_macro_event)
		return false
	# Keep player inventory; unload tokens before zone swap.
	_unload_all_enemy_tokens()
	var ok := campaign.enter_node(node_id, exit_direction)
	if not ok:
		return false
	_pending_exit_direction = GameEnums.MacroTravelDirection.NONE
	_apply_active_zone_to_world()
	_ensure_central_rim_guards()
	_ensure_meta_component_source()
	return true


func mark_node_completed(node_id: String) -> void:
	_ensure_campaign()
	campaign.mark_node_completed(node_id)


func evaluate_unlocks(player_progress: Dictionary = {}) -> Array[String]:
	_ensure_campaign()
	return campaign.evaluate_unlocks(player_progress)


func apply_campaign_discovery_trigger(trigger_id: String) -> PackedStringArray:
	_ensure_campaign()
	var revealed := campaign.apply_discovery_trigger(trigger_id)
	if revealed.is_empty():
		return revealed
	_last_macro_event = "Route intelligence revealed: %s" % ", ".join(revealed)
	_macro_log(_last_macro_event)
	if is_node_map_open():
		node_map_system.call("refresh", build_node_map_ui_snapshot())
	_refresh_boundary_previews()
	_refresh_world_hud()
	return revealed


func debug_print_campaign_map() -> String:
	_ensure_campaign()
	return campaign.debug_print_map()


func _ensure_node_map_system() -> void:
	if node_map_system != null:
		return
	var packed := node_map_system_scene
	if packed == null:
		push_error("MacroGameManager requires an authored node_map_system_scene.")
		return
	node_map_system = packed.instantiate() as CanvasLayer
	node_map_system.name = "NodeMapSystem"
	add_child(node_map_system)
	node_map_system.connect("closed", _on_node_map_closed)
	node_map_system.connect("enter_node_requested", _on_node_map_enter_requested)
	node_map_system.connect("advance_requested", _on_node_map_advance_requested)
	node_map_system.connect("inventory_requested", _on_node_map_inventory_requested)
	node_map_system.connect("medical_requested", _on_node_map_medical_requested)


func open_node_map() -> void:
	_pending_exit_direction = GameEnums.MacroTravelDirection.NONE
	_open_node_map_with_context()


func _open_node_map_with_context() -> void:
	_ensure_campaign()
	_ensure_node_map_system()
	if node_map_system == null:
		return
	node_map_system.call("open", build_node_map_ui_snapshot())


func close_node_map() -> void:
	if node_map_system != null and bool(node_map_system.call("is_open")):
		node_map_system.call("close")


func toggle_node_map() -> void:
	if is_node_map_open():
		close_node_map()
	else:
		open_node_map()


func is_node_map_open() -> bool:
	return node_map_system != null and bool(node_map_system.call("is_open"))


## Full graph + player presentation for the fullscreen Node Map System window.
func build_node_map_ui_snapshot() -> Dictionary:
	_ensure_campaign()
	var hud_snapshot: Dictionary = {}
	var inventory_snapshot: Dictionary = {}
	if player_token != null:
		hud_snapshot = _build_world_hud_snapshot()
		inventory_snapshot = _build_inventory_snapshot()
	return MacroNodeMapSnapshot.build(
		campaign,
		int(_pending_exit_direction),
		hud_snapshot,
		inventory_snapshot
	)


func _on_node_map_closed() -> void:
	_close_node_map_overlays()
	_pending_exit_direction = GameEnums.MacroTravelDirection.NONE


func _on_node_map_enter_requested(node_id: String) -> void:
	if enter_campaign_node(node_id, _pending_exit_direction):
		_last_macro_event = "Entered campaign node: %s" % node_id
		_refresh_world_hud()
		close_node_map()
	elif is_node_map_open():
		node_map_system.call("refresh", build_node_map_ui_snapshot())


func _on_node_map_advance_requested() -> void:
	# The legacy global "advance" button cannot bypass directional travel.
	_last_macro_event = "Choose an eligible adjacent node from the directional web."
	if is_node_map_open():
		node_map_system.call("refresh", build_node_map_ui_snapshot())


func _on_node_map_inventory_requested() -> void:
	if inventory_panel == null:
		return
	_close_node_map_medical(false)
	if macro_hud:
		var corner := macro_hud.get_inventory_corner_panel()
		if corner != null and corner.is_expanded():
			corner.collapse()
	if _inventory_home_layer == null:
		_inventory_home_layer = inventory_panel.get_parent() as CanvasLayer
	if (
		_inventory_home_layer != null
		and inventory_panel.get_parent() != _inventory_home_layer
	):
		inventory_panel.reparent(_inventory_home_layer)
	var snapshot := _build_inventory_snapshot()
	if _inventory_home_layer:
		_node_map_inventory_layer_restore = _inventory_home_layer.layer
	inventory_panel.open_inventory(snapshot)
	if _inventory_home_layer:
		_inventory_home_layer.layer = _NODE_MAP_INVENTORY_LAYER


func _on_node_map_medical_requested() -> void:
	if inventory_panel != null and inventory_panel.is_open():
		inventory_panel.close_panel(false)
		_restore_node_map_inventory_layer()
	_ensure_node_map_overlay_layer()
	if _node_map_medical == null:
		if node_map_medical_scene == null:
			push_error("MacroGameManager requires an authored node_map_medical_scene.")
			return
		var host := Control.new()
		host.name = "NodeMapMedicalHost"
		host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		host.mouse_filter = Control.MOUSE_FILTER_STOP
		_node_map_overlay_layer.add_child(host)

		var dim := ColorRect.new()
		dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		dim.color = Color(0, 0, 0, 0.55)
		dim.mouse_filter = Control.MOUSE_FILTER_STOP
		host.add_child(dim)

		_node_map_medical = node_map_medical_scene.instantiate() as Control
		_node_map_medical.set("display_mode", 1)
		host.add_child(_node_map_medical)
		_node_map_medical.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_node_map_medical.offset_left = 48.0
		_node_map_medical.offset_top = 48.0
		_node_map_medical.offset_right = -48.0
		_node_map_medical.offset_bottom = -72.0
		_node_map_medical.connect("limb_treatment_requested", _on_medical_action_requested)

		var close_button := Button.new()
		close_button.name = "CloseMedicalButton"
		close_button.text = "Close Medical"
		close_button.custom_minimum_size = HUDAssetLibrary.macro_button_minimum_size(140.0)
		HUDAssetLibrary.apply_button(close_button, "pass")
		close_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		close_button.offset_left = -180.0
		close_button.offset_top = -52.0
		close_button.offset_right = -48.0
		close_button.offset_bottom = -20.0
		close_button.pressed.connect(_close_node_map_medical)
		host.add_child(close_button)
	var snapshot := _build_world_hud_snapshot()
	var inventory_snapshot := _build_inventory_snapshot()
	snapshot["equipment"] = inventory_snapshot.get("equipment", [])
	snapshot["containers"] = inventory_snapshot.get("containers", [])
	snapshot["backpack"] = inventory_snapshot.get("backpack", [])
	snapshot["current_capacity"] = inventory_snapshot.get("current_capacity", 0)
	snapshot["maximum_capacity"] = inventory_snapshot.get("maximum_capacity", 0)
	snapshot["loadout_stats"] = inventory_snapshot.get("loadout_stats", {})
	_node_map_medical.call("apply_snapshot", snapshot)
	_node_map_medical.visible = true
	_node_map_overlay_layer.visible = true


func _on_node_map_medical_closed() -> void:
	if _node_map_overlay_layer:
		_node_map_overlay_layer.visible = (
			_node_map_medical != null and _node_map_medical.visible
		)


func _ensure_node_map_overlay_layer() -> void:
	if _node_map_overlay_layer != null:
		return
	_node_map_overlay_layer = CanvasLayer.new()
	_node_map_overlay_layer.name = "NodeMapOverlayLayer"
	_node_map_overlay_layer.layer = _NODE_MAP_OVERLAY_LAYER
	_node_map_overlay_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_node_map_overlay_layer)


func _close_node_map_medical(_emit_closed: bool = true) -> void:
	if _node_map_medical == null or not _node_map_medical.visible:
		return
	_node_map_medical.visible = false
	if _node_map_overlay_layer:
		_node_map_overlay_layer.visible = false


func _close_node_map_overlays() -> void:
	if inventory_panel != null and inventory_panel.is_open():
		# Only auto-close inventory if it was raised for the node map.
		if (
			_inventory_home_layer != null
			and _inventory_home_layer.layer == _NODE_MAP_INVENTORY_LAYER
		):
			inventory_panel.close_panel(false)
	_restore_node_map_inventory_layer()
	_close_node_map_medical(false)


func _restore_node_map_inventory_layer() -> void:
	if _inventory_home_layer == null:
		return
	if _inventory_home_layer.layer == _NODE_MAP_INVENTORY_LAYER:
		_inventory_home_layer.layer = _node_map_inventory_layer_restore


func _on_campaign_node_entered(node_id: String) -> void:
	campaign_node_changed.emit(node_id)
	_macro_log("Entered campaign node %s." % node_id)


func _on_campaign_nodes_unlocked(node_ids: Array) -> void:
	campaign_nodes_unlocked.emit(node_ids)
	_last_macro_event = "Path unlocked: %s" % ", ".join(PackedStringArray(node_ids))
	_macro_log(_last_macro_event)
	_refresh_boundary_previews()
	_refresh_world_hud()


func _unload_all_enemy_tokens() -> void:
	_get_proximity_director().unload_all()


func _apply_active_zone_to_world() -> void:
	if campaign == null or campaign.zone_generator == null:
		return
	var zone := campaign.zone_generator
	world_generator.enable_zone_bounds(MacroZoneGenerator.ZONE_RADIUS)
	world_generator.configure_seed(_world_state.world_seed + ":node:" + zone.node_id)
	world_generator.inject_zone_hexes(zone.world_hex_cache)
	world_generator.inject_zone_decorations(zone.zone_decorations)
	for coords in zone.world_hex_cache.keys():
		var hex: MacroHexData = zone.world_hex_cache[coords]
		_world_state.set_hex_record(coords, hex.to_state())

	var start_coords := zone.start_coords
	# Preserve player runtime (inventory) across node swaps.
	if player_token.get_humanoid_core() != null and _world_state.player_record != null:
		_world_state.update_player_runtime(
			player_token.get_humanoid_core().capture_runtime_state().to_dict(),
			start_coords
		)
	else:
		_world_state.set_player_record(
			player_token.capture_runtime_record(),
			start_coords
		)

	var start_pixel := map_visualizer.map_to_local(start_coords)
	player_token.snap_to_hex(start_coords, start_pixel)
	_visible_hexes.clear()
	_mark_hex_explored(start_coords)
	_select_hex_for_hud(start_coords)
	_refresh_map_visuals(start_coords, true)
	_refresh_boundary_previews()
	refresh_proximity(start_coords)
	_refresh_world_hud()
	print(MacroMapDebug.print_campaign(campaign))


## Posts one pair of Central Guards on the rim edge facing locked Central Core.
func _ensure_central_rim_guards() -> void:
	_ensure_campaign()
	if campaign == null or mob_spawner == null:
		return
	var node_id := str(campaign.active_node_id)
	if not _is_route_one_node(node_id):
		return
	if _has_central_guard_pair():
		return

	var toward_central := _central_facing_direction_for_route_one(node_id)
	if toward_central == GameEnums.MacroTravelDirection.NONE:
		return
	var pair_coords := _pick_central_rim_pair_coords(toward_central)
	if pair_coords.size() < 2:
		push_warning(
			"[MacroGameManager] Could not place Central Guard pair on %s rim."
			% node_id
		)
		return

	var squad_id := "central_guard_pair_%s" % node_id
	var seed_base := "%s:%s:central_guard" % [_world_state.world_seed, node_id]
	var variants := [false, true] # AK-47, then Kar98k
	for i in range(2):
		var coords: Vector2i = pair_coords[i]
		var record := mob_spawner.generate_central_guard_record(
			coords,
			bool(variants[i]),
			squad_id,
			"%s:%d" % [seed_base, i]
		)
		_initialize_npc_runtime(record)
		# Posted rim pair: hold hex, never wander.
		record.runtime["macro_purpose"] = GameEnums.NPC_PURPOSE_HOLD
		record.runtime["macro_purpose_label"] = "Hold"
		record.runtime["macro_origin_coords"] = coords
		record.runtime["macro_target_coords"] = coords
		var entity_id := _world_state.register_entity(record)
		var hex_data := world_generator.get_hex_at(coords)
		hex_data.encounter_entity_id = entity_id
		hex_data.encounter_evaluated = true
		_world_state.set_hex_record(coords, hex_data.to_state())
		_spawn_enemy_token_from_record(record)
		_macro_log(
			"Posted Central Guard %s @%s facing Central."
			% [entity_id, str(coords)]
		)
	_last_macro_event = (
		"A posted pair in service kit holds the Central-facing rim."
	)


func _is_route_one_node(node_id: String) -> bool:
	return (
		node_id == "north_random_1"
		or node_id == "east_random_1"
		or node_id == "south_random_1"
		or node_id == "west_random_1"
	)


func _central_facing_direction_for_route_one(node_id: String) -> int:
	match node_id:
		"north_random_1":
			return GameEnums.MacroTravelDirection.SOUTH
		"east_random_1":
			return GameEnums.MacroTravelDirection.WEST
		"south_random_1":
			return GameEnums.MacroTravelDirection.NORTH
		"west_random_1":
			return GameEnums.MacroTravelDirection.EAST
		_:
			return GameEnums.MacroTravelDirection.NONE


func _has_central_guard_pair() -> bool:
	var count := 0
	for entity in _world_state.entity_records.values():
		if not (entity is EntityRecord):
			continue
		var record := entity as EntityRecord
		if record.kind != GameEnums.RuntimeEntityKind.NPC:
			continue
		var template_id := str(record.definition.get("template_id", ""))
		if template_id.is_empty():
			template_id = str(record.runtime.get("template_id", ""))
		if template_id == "central_guard":
			count += 1
	return count >= 2


func _pick_central_rim_pair_coords(toward_central: int) -> Array[Vector2i]:
	var radius := MacroZoneGenerator.ZONE_RADIUS
	var primary := HexCoordUtils.rim_anchor(toward_central, radius)
	var candidates: Array[Vector2i] = []
	if _is_guard_spawn_hex(primary):
		candidates.append(primary)
	for neighbor in HexCoordUtils.AXIAL_DIRECTIONS:
		var coords: Vector2i = primary + neighbor
		if HexCoordUtils.distance_from_origin(coords) != radius:
			continue
		if not _is_guard_spawn_hex(coords):
			continue
		if not candidates.has(coords):
			candidates.append(coords)
	# Prefer hexes that still face Central strongly.
	candidates.sort_custom(
		func(a: Vector2i, b: Vector2i) -> bool:
			var target := HexCoordUtils.travel_direction_vector(toward_central)
			var score_a := HexCoordUtils.axial_to_visual_vector(a).normalized().dot(target)
			var score_b := HexCoordUtils.axial_to_visual_vector(b).normalized().dot(target)
			return score_a > score_b
	)
	var pair: Array[Vector2i] = []
	for coords in candidates:
		if pair.size() >= 2:
			break
		pair.append(coords)
	if pair.size() >= 2:
		return pair
	# Fallback: walk the ring for any two passable rim hexes near primary.
	for coords in HexCoordUtils.cells_in_ring(radius):
		if HexCoordUtils.distance(primary, coords) > 2:
			continue
		if not _is_guard_spawn_hex(coords):
			continue
		if not pair.has(coords):
			pair.append(coords)
		if pair.size() >= 2:
			break
	return pair


func _is_guard_spawn_hex(coords: Vector2i) -> bool:
	var hex_data := world_generator.get_hex_at(coords)
	if hex_data == null or not hex_data.is_passable():
		return false
	if _world_state.has_entity_at(coords):
		return false
	if active_enemies.has(coords):
		return false
	if (
		player_token != null
		and player_token.current_hex_coords == coords
	):
		return false
	return true


func _refresh_boundary_previews() -> void:
	if map_visualizer == null or campaign == null or campaign.graph == null:
		return
	var previews: Dictionary = {}
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
		var node_ids := campaign.get_directional_destinations(direction)
		var node_names: Array[String] = []
		for destination_id in node_ids:
			var destination := campaign.graph.get_node(destination_id)
			if destination != null:
				node_names.append(destination.display_name)
		previews[int(direction)] = {
			"direction_name": GameEnums.MacroTravelDirection.keys()[direction],
			"node_ids": node_ids,
			"node_names": node_names,
		}
	map_visualizer.configure_boundary_previews(previews)


func _ensure_meta_component_source() -> void:
	if campaign == null or campaign.active_node_id != MacroGraphGenerator.FETCH_BRANCH_ID:
		return
	if (
		_meta_progress != null
		and _meta_progress.has_method("is_event_completed")
		and _meta_progress.is_event_completed(MacroGraphGenerator.META_FETCH_EVENT_ID)
	):
		return
	if _run_has_meta_component():
		return
	if _loot_catalog == null or not _loot_catalog.has_item(MacroGraphGenerator.FETCH_ITEM_ID):
		push_error("[MacroGameManager] Missing authored Meta quest item.")
		return
	var item_state: Dictionary = _loot_catalog.create_runtime_item_state(
		MacroGraphGenerator.FETCH_ITEM_ID
	)
	if item_state.is_empty():
		return
	_world_state.add_ground_items(Vector2i.ZERO, [item_state])
	_last_macro_event = "A North Core Regulator rests inside the Component Vault."


func _run_has_meta_component() -> bool:
	if player_token != null and player_token.get_humanoid_core() != null:
		for item in player_token.get_humanoid_core().inventory.get_all_items():
			if item.id == MacroGraphGenerator.FETCH_ITEM_ID:
				return true
	for ground_stack in _world_state.ground_item_records.values():
		for item_state in ground_stack:
			if (
				item_state is Dictionary
				and _runtime_item_state_id(item_state) == MacroGraphGenerator.FETCH_ITEM_ID
			):
				return true
	for snapshot in _world_state.node_runtime_snapshots.values():
		if not snapshot is Dictionary:
			continue
		for ground_entry in snapshot.get("ground_items", []):
			if not ground_entry is Dictionary:
				continue
			for item_state in ground_entry.get("items", []):
				if (
					item_state is Dictionary
					and _runtime_item_state_id(item_state) == MacroGraphGenerator.FETCH_ITEM_ID
				):
					return true
	return false


func _runtime_item_state_id(item_state: Dictionary) -> String:
	var item_id := str(item_state.get("id", ""))
	if not item_id.is_empty():
		return item_id
	var definition: Dictionary = item_state.get("definition", {})
	return str(definition.get("id", ""))


func get_runtime_state_store() -> RuntimeStateStore:
	return _world_state


func debug_step_player_to(target_coords: Vector2i) -> void:
	_execute_player_step(target_coords)


## Debug tooling: instantly relocate the player to any hex without walking,
## survival-time cost, or triggering pending interactions. Rebuilds fog,
## proximity tokens, and the HUD so the jump is fully reflected.
func _get_debug_console() -> MacroDebugConsole:
	if _debug_console == null:
		_debug_console = MacroDebugConsole.new(self)
	return _debug_console


func _get_collision_coordinator() -> MacroCollisionCoordinator:
	if _collision_coordinator == null:
		_collision_coordinator = MacroCollisionCoordinator.new(
			self,
			_interaction_state
		)
	return _collision_coordinator


func _get_proximity_director() -> MacroProximityDirector:
	if _proximity_director == null:
		_proximity_director = MacroProximityDirector.new(self)
	else:
		_proximity_director.sync_host_refs()
	return _proximity_director


func debug_teleport_player(target_coords: Vector2i) -> void:
	_get_debug_console().teleport_player(target_coords)


## Debug tooling: persist the live player runtime into WorldState and rebuild
## every player-facing surface (token pose, inventory panel, exploration ground,
## HUD). Call this after directly mutating the HumanoidCore/body/inventory so
## the change becomes visible and save-safe.
func debug_sync_player_after_mutation() -> void:
	_get_debug_console().sync_player_after_mutation()


## Debug tooling: spawn a procedural enemy on the first free, passable hex
## adjacent to the player. Returns true if an encounter was projected.
func debug_spawn_enemy_near_player(
	faction: GameEnums.Faction = GameEnums.Faction.SCAVENGER_CELL,
	difficulty: int = 0
) -> bool:
	return _get_debug_console().spawn_enemy_near_player(faction, difficulty)


func debug_project_npc_token(record: EntityRecord) -> MacroEnemy:
	return _force_project_npc_token(record)


func hex_distance(from_coords: Vector2i, to_coords: Vector2i) -> int:
	return _NpcSimulator.hex_distance(from_coords, to_coords)


func debug_initialize_npc_runtime(record: EntityRecord) -> void:
	_initialize_npc_runtime(record)


func debug_evaluate_npc_step(
	record: EntityRecord,
	player_coords: Vector2i
) -> Vector2i:
	return _evaluate_npc_step(record, player_coords)


func debug_advance_npc_macro_turn() -> bool:
	return _advance_npc_macro_turn()


func _npc_get_hex_at(coords: Vector2i) -> MacroHexData:
	return world_generator.get_hex_at(coords)


func _npc_has_ground_items(coords: Vector2i) -> bool:
	return _world_state.has_ground_items(coords)


func _npc_get_occupying_entity_id(coords: Vector2i) -> String:
	return _world_state.entity_ids_by_coords.get(coords, "")

func _ready() -> void:
	if _world_state == null:
		_world_state = get_node("/root/WorldState") as RuntimeStateStore
	_mutation_store = get_node_or_null("/root/WorldMutationStore")
	_meta_progress = get_node_or_null("/root/MetaProgression")
	if _loot_catalog == null:
		_loot_catalog = get_node("/root/LootCatalog")
	if not mob_spawner:
		mob_spawner = get_node_or_null("/root/MobSpawner") as MobSpawner
	if world_generator and _world_state:
		world_generator.configure_services(_world_state)

	if not world_generator or not map_visualizer or not player_token or not mob_spawner:
		push_error("The Puppet Master is missing its strings. Check the inspector.")
		return

	if exploration_window_scene:
		exploration_window = (
			exploration_window_scene.instantiate() as MacroExplorationWindow
		)
		exploration_window.name = "MacroExplorationWindow"
		add_child(exploration_window)
	else:
		push_error("[MacroGameManager] Missing exploration_window_scene.")

	_ensure_node_map_system()

	if inventory_panel:
		inventory_panel.inventory_action_requested.connect(resolve_inventory_action)
		inventory_panel.inventory_closed.connect(_on_inventory_closed)
		_inventory_home_layer = inventory_panel.get_parent() as CanvasLayer

	if macro_hud:
		macro_hud.inventory_requested.connect(_toggle_fullscreen_inventory)
		macro_hud.hex_preview_expand_requested.connect(_expand_hex_at)
		macro_hud.hex_preview_travel_requested.connect(_on_hex_preview_travel)
		macro_hud.viewport_insets_changed.connect(_on_hud_viewport_insets_changed)
		macro_hud.medical_action_requested.connect(_on_medical_action_requested)
		macro_hud.event_choice_submitted.connect(_on_macro_hud_choice_submitted)
		macro_hud.event_closed.connect(_on_macro_hud_event_closed)
		macro_hud.node_map_requested.connect(open_node_map)
		if inventory_panel:
			macro_hud.get_inventory_corner_panel().inventory_ui = inventory_panel
		if exploration_window:
			macro_hud.bind_exploration_window(exploration_window)
			macro_hud.poi_action_submitted.connect(resolve_poi_action)
			macro_hud.poi_preview_requested.connect(preview_poi_action)
			macro_hud.exploration_inventory_action_requested.connect(
				resolve_inventory_action
			)
			macro_hud.exploration_interaction_closed.connect(close_macro_interaction)
	var player_inventory := player_token.get_humanoid_core().inventory
	player_inventory.inventory_error.connect(_on_player_inventory_error)
	player_inventory.items_spilled.connect(_on_player_items_spilled)
		
	if not _world_bootstrapped:
		_bootstrap_world()
	_connect_world_time_lighting()


func _process(_delta: float) -> void:
	_update_vision_soft_focus()


func _bootstrap_world() -> void:
	if _world_bootstrapped or _world_state == null:
		return
	_world_bootstrapped = true
	if _world_state.consume_pending_loaded_world():
		_initialize_loaded_world()
	elif _world_state.has_pending_new_run_setup():
		_initialize_new_run(_world_state.consume_pending_new_run_setup())
	else:
		_initialize_demo()
	_refresh_world_hud()


func _initialize_new_run(setup: Dictionary) -> void:
	var definition_state: Dictionary = setup.get("definition", {})
	var start_node_id := str(setup.get("start_node_id", ""))
	var arrival_direction := int(setup.get(
		"arrival_direction",
		MacroGraphGenerator.arrival_direction_for_start(start_node_id)
	))
	if definition_state.is_empty() or start_node_id.is_empty():
		push_error("[MacroGameManager] New-run setup is incomplete.")
		_initialize_demo()
		return
	if not player_token.initialize_new_definition(definition_state):
		push_error("[MacroGameManager] Could not apply the selected player identity.")
		_initialize_demo()
		return
	_ensure_campaign()
	_configure_campaign_player_capabilities(player_token.get_humanoid_core().definition)
	campaign.begin_campaign(_world_state.world_seed)
	world_generator.configure_services(_world_state)
	world_generator.enable_zone_bounds(MacroZoneGenerator.ZONE_RADIUS)
	_world_state.set_player_record(player_token.capture_runtime_record(), Vector2i.ZERO)
	if _meta_progress != null and _meta_progress.has_method("apply_eviction_lock"):
		_meta_progress.apply_eviction_lock()
	_unload_all_enemy_tokens()
	if not campaign.enter_initial_node(start_node_id, arrival_direction):
		push_error("[MacroGameManager] Failed to enter selected start node: %s" % start_node_id)
		return
	_pending_exit_direction = GameEnums.MacroTravelDirection.NONE
	_apply_active_zone_to_world()
	_ensure_central_rim_guards()
	_ensure_meta_component_source()
	_macro_log("Eviction complete. Deployed to %s." % start_node_id)

func _initialize_demo() -> void:
	var seed := "ARCCROSS_DIRECTIONAL_WEB_01"
	_world_state.begin_new_world(seed)
	_ensure_campaign()
	campaign.begin_campaign(seed)
	world_generator.configure_services(_world_state)
	world_generator.enable_zone_bounds(MacroZoneGenerator.ZONE_RADIUS)

	# Preserve freshly created player token inventory into the run, then enter hub.
	_world_state.set_player_record(
		player_token.capture_runtime_record(),
		Vector2i.ZERO
	)
	if not enter_campaign_node(MacroGraphGenerator.HUB_ID):
		push_error("[MacroGameManager] Failed to enter hub campaign node.")
		return
	_macro_log("Directional campaign initialized at the Central Core south rim.")


func _initialize_loaded_world() -> void:
	if _world_state.world_seed.is_empty() or _world_state.player_record == null:
		push_error("Loaded world state is incomplete. Starting a new demo world.")
		_initialize_demo()
		return

	_ensure_campaign()
	world_generator.configure_services(_world_state)
	world_generator.enable_zone_bounds(MacroZoneGenerator.ZONE_RADIUS)
	player_token.restore_runtime_record(_world_state.player_record)
	_configure_campaign_player_capabilities(player_token.get_humanoid_core().definition)

	if not _world_state.campaign_graph.is_empty():
		var loaded_coords := _world_state.player_coords
		campaign.load_campaign(
			_world_state.campaign_graph,
			_world_state.active_node_id
		)
		_apply_active_zone_to_world()
		if world_generator.is_in_zone_bounds(loaded_coords):
			player_token.snap_to_hex(
				loaded_coords,
				map_visualizer.map_to_local(loaded_coords)
			)
			_world_state.update_player_runtime(
				player_token.get_humanoid_core().capture_runtime_state().to_dict(),
				loaded_coords
			)
			_mark_hex_explored(loaded_coords)
			_select_hex_for_hud(loaded_coords)
			_refresh_map_visuals(loaded_coords, true)
			refresh_proximity(loaded_coords)
	else:
		campaign.begin_campaign(_world_state.world_seed)
		enter_campaign_node(MacroGraphGenerator.HUB_ID)

	_macro_log(
		"Loaded campaign node=%s at %s."
		% [_world_state.active_node_id, str(player_token.current_hex_coords)]
	)


func _configure_campaign_player_capabilities(definition: EntityDefinition) -> void:
	if campaign == null or definition == null:
		return
	campaign.set_player_capabilities(IdentityCatalog.capability_ids_for_selection(
		definition.occupation_id,
		definition.trait_ids,
		definition.flaw_ids
	))

func synchronize_runtime_state() -> void:
	_world_state.set_player_record(
		player_token.capture_runtime_record(),
		player_token.current_hex_coords
	)
	for coords in world_generator.world_hex_cache.keys():
		var hex_data: MacroHexData = world_generator.world_hex_cache[coords]
		_world_state.set_hex_record(coords, hex_data.to_state())
	if campaign != null and campaign.graph != null:
		_world_state.campaign_graph = campaign.graph.to_dict()
		_world_state.active_node_id = campaign.active_node_id
		_world_state.active_arrival_direction = int(campaign.last_arrival_direction)
		_world_state.capture_node_runtime(campaign.active_node_id)
		var active_node := campaign.get_active_node()
		if (
			active_node != null
			and active_node.persistence == GameEnums.MacroNodePersistence.PERMANENT_META
			and _meta_progress != null
			and _meta_progress.has_method("capture_node_mutations")
		):
			_meta_progress.capture_node_mutations(
				active_node.id,
				campaign.zone_generator.permanent_baseline_records,
				_world_state.hex_records
			)
	flush_world_mutations()


func flush_world_mutations() -> void:
	if campaign != null and not campaign.active_node_id.is_empty():
		# Directional node worlds use node-scoped Meta patches. The legacy
		# coordinate-only store must never receive these overlapping coordinates.
		return
	if _mutation_store == null or world_generator.authored_map == null:
		return
	if not _mutation_store.has_method("capture_run_mutations"):
		return
	_mutation_store.capture_run_mutations(
		world_generator.authored_map.map_id,
		_build_mutation_baseline_records(_world_state.hex_records.keys()),
		_world_state.hex_records
	)


func _build_mutation_baseline_records(coords_list: Array) -> Dictionary:
	var baseline_records: Dictionary = {}
	for coords in coords_list:
		if not coords is Vector2i:
			continue
		var baseline_hex: MacroHexData
		if world_generator.authored_map.has_hex(coords):
			baseline_hex = world_generator.authored_map.build_hex_data(
				coords,
				_world_state.world_seed
			)
		else:
			baseline_hex = HexWorldGenerator.build_void_hex(coords)
		baseline_records[coords] = baseline_hex.to_state()
	return baseline_records


func _bind_authored_map_profile() -> void:
	if _mutation_store == null or world_generator.authored_map == null:
		return
	if _mutation_store.map_id.is_empty():
		_mutation_store.map_id = world_generator.authored_map.map_id
	world_generator.world_hex_cache.clear()

## Spawn a procedurally generated enemy at the given hex coordinates.
func spawn_procedural_enemy(coords: Vector2i, faction: GameEnums.Faction, difficulty: int = 0) -> void:
	_get_proximity_director().spawn_procedural_enemy(coords, faction, difficulty)

# ---------------------------------------------------------
# INPUT & MOVEMENT LOGIC
# ---------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if is_node_map_open():
		if (
			event is InputEventKey
			and event.pressed
			and not event.echo
			and event.keycode == KEY_ESCAPE
		):
			if _node_map_medical != null and _node_map_medical.visible:
				_close_node_map_medical()
				get_viewport().set_input_as_handled()
				return
			if (
				inventory_panel != null
				and inventory_panel.is_open()
				and _inventory_home_layer != null
				and _inventory_home_layer.layer == _NODE_MAP_INVENTORY_LAYER
			):
				inventory_panel.close_panel()
				get_viewport().set_input_as_handled()
				return
			close_node_map()
			get_viewport().set_input_as_handled()
			return
		if event is InputEventKey or event is InputEventMouseButton:
			get_viewport().set_input_as_handled()
		return
	if macro_hud != null and macro_hud.is_event_open():
		if (
			event is InputEventKey
			and event.pressed
			and not event.echo
			and event.keycode == KEY_ESCAPE
		):
			close_macro_interaction()
			get_viewport().set_input_as_handled()
			return
		if event is InputEventKey or event is InputEventMouseButton:
			get_viewport().set_input_as_handled()
		return
	if (
		_pending_interaction.get("type", GameEnums.MacroInteractionType.NONE)
		== GameEnums.MacroInteractionType.MACRO_EVENT
	):
		if event is InputEventKey or event is InputEventMouseButton:
			get_viewport().set_input_as_handled()
		return
	if (
		event is InputEventKey
		and event.pressed
		and not event.echo
		and (event.keycode == KEY_I or event.keycode == KEY_TAB)
	):
		if macro_hud:
			macro_hud.toggle_inventory_panel()
		get_viewport().set_input_as_handled()
		return
	if not _pending_interaction.is_empty():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_P:
				toggle_node_map()
				get_viewport().set_input_as_handled()
				return
			KEY_E:
				_resolve_current_hex_action()
				get_viewport().set_input_as_handled()
				return
			KEY_T:
				_try_travel_to_selected_hex()
				get_viewport().set_input_as_handled()
				return
			KEY_R:
				_select_hex_for_hud(_selected_hex_coords)
				get_viewport().set_input_as_handled()
				return
	if (
		event is InputEventMouseButton
		and event.pressed
		and event.button_index == MOUSE_BUTTON_RIGHT
	):
		_select_hex_at_mouse()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_attempt_move_to_mouse()

func _attempt_move_to_mouse() -> bool:
	var mouse_pos = map_visualizer.get_local_mouse_position()
	var clicked_hex_coords = map_visualizer.local_to_map(mouse_pos)
	
	var distance_vector = clicked_hex_coords - player_token.current_hex_coords
	if not HEX_NEIGHBORS.has(distance_vector):
		return false # Ignored. Too far away.

	if not world_generator.is_in_zone_bounds(clicked_hex_coords):
		return _try_begin_directional_exit(
			player_token.current_hex_coords,
			clicked_hex_coords
		)
	_select_hex_for_hud(clicked_hex_coords)
		
	var target_hex := world_generator.get_hex_at(clicked_hex_coords)
	if not target_hex.is_passable():
		return false # Ignored. Rock fields are unpassable.

	_execute_player_step(clicked_hex_coords)
	return true

func _execute_player_step(target_coords: Vector2i) -> void:
	if not _pending_interaction.is_empty():
		return
	if not world_generator.is_in_zone_bounds(target_coords):
		_try_begin_directional_exit(player_token.current_hex_coords, target_coords)
		return
	var origin_coords := player_token.current_hex_coords
	var pixel_pos = map_visualizer.map_to_local(target_coords)
	player_token.walk_to_hex(target_coords, pixel_pos)
	_select_hex_for_hud(target_coords)
	_world_state.update_player_runtime(
		player_token.get_humanoid_core().capture_runtime_state().to_dict(),
		target_coords
	)
	_macro_log("Player stepped to %s." % str(target_coords))
	var newly_explored := _refresh_map_visuals(target_coords, false)
	refresh_proximity(target_coords)

	var hex_data := world_generator.get_hex_at(target_coords)
	_mark_hex_explored(target_coords, hex_data)
	_advance_survival_time(
		GameTimeRules.move_minutes_for_hex(hex_data),
		_get_exertion_for_hex(hex_data),
		target_coords
	)
	
	var target_entity := _world_state.get_entity_at(target_coords)
	if target_entity != null:
		if not _world_state.is_entity_alive(target_entity.entity_id):
			unload_enemy_token(target_coords)
		elif _world_state.is_entity_hostile(target_entity.entity_id):
			_force_project_npc_token(target_entity)
			advance_macro_world(1)
			begin_entity_collision(
				target_entity.entity_id,
				target_coords,
				origin_coords
			)
			return

	var has_ground_loot := _world_state.has_ground_items(target_coords)
	if has_ground_loot:
		_last_macro_event = "Ground items detected at HEX %d,%d." % [
			target_coords.x,
			target_coords.y,
		]
	_present_travel_beat(
		origin_coords,
		target_coords,
		hex_data,
		newly_explored,
		has_ground_loot
	)

	advance_macro_world(1)
	# Campaign progress resolves via directional rim departure / node map — not
	# a hard-coded objective hex on ordinary steps.
	_refresh_world_hud()


func _present_travel_beat(
	origin_coords: Vector2i,
	target_coords: Vector2i,
	hex_data: MacroHexData,
	newly_explored: Array,
	has_ground_loot: bool
) -> void:
	var beat: Dictionary = MacroTravelBeatResolver.build_step_beat(
		origin_coords,
		target_coords,
		hex_data,
		newly_explored,
		has_ground_loot
	)
	if beat.is_empty():
		return
	var title := str(beat.get("title", "EXPLORING"))
	var body := str(beat.get("body", ""))
	var first_line := body.split("\n")[0].strip_edges() if not body.is_empty() else ""
	_last_macro_event = (
		"%s — %s" % [title, first_line] if not first_line.is_empty() else title
	)
	if macro_hud:
		macro_hud.present_travel_beat(beat)
	_guide_camera_for_travel(origin_coords, target_coords)
	_leave_movement_trail(origin_coords, target_coords)


func _guide_camera_for_travel(origin_coords: Vector2i, target_coords: Vector2i) -> void:
	## Soft look-ahead toward the destination — never zoom/vignette pulse.
	var camera := get_node_or_null("Camera2D") as MacroCamera
	if camera == null or map_visualizer == null:
		return
	var from_pos: Vector2 = map_visualizer.map_to_local(origin_coords)
	var to_pos: Vector2 = map_visualizer.map_to_local(target_coords)
	camera.begin_travel_look_ahead(from_pos, to_pos)
	get_tree().create_timer(MacroPlayer.WALK_DURATION_SECONDS).timeout.connect(
		func() -> void:
			if is_instance_valid(camera):
				camera.end_travel_look_ahead()
	)


func _leave_movement_trail(origin_coords: Vector2i, target_coords: Vector2i) -> void:
	if map_visualizer == null:
		return
	if _movement_trail == null:
		_movement_trail = MacroMovementTrail.new()
		_movement_trail.name = "MacroMovementTrail"
		_movement_trail.z_index = -1
		add_child(_movement_trail)
	var from_pos: Vector2 = map_visualizer.map_to_local(origin_coords)
	var to_pos: Vector2 = map_visualizer.map_to_local(target_coords)
	var facing := to_pos - from_pos
	_movement_trail.add_step(from_pos.lerp(to_pos, 0.35), facing)
	_movement_trail.add_step(from_pos.lerp(to_pos, 0.7), facing)

func _try_begin_directional_exit(
	origin_coords: Vector2i,
	target_coords: Vector2i
) -> bool:
	if campaign == null or campaign.active_node_id.is_empty():
		return false
	if HexCoordUtils.distance_from_origin(origin_coords) != MacroZoneGenerator.ZONE_RADIUS:
		return false
	var step := target_coords - origin_coords
	if not HEX_NEIGHBORS.has(step):
		return false
	var direction := HexCoordUtils.travel_direction_for_boundary_target(target_coords)
	if direction == GameEnums.MacroTravelDirection.NONE:
		return false
	_pending_exit_direction = direction as GameEnums.MacroTravelDirection
	var destinations := campaign.get_directional_destinations(direction)
	_last_macro_event = (
		"Boundary reached: %s. Select an adjacent node."
		% GameEnums.MacroTravelDirection.keys()[direction]
	)
	if destinations.is_empty():
		_last_macro_event += " No unlocked route leaves this sector."
	_open_node_map_with_context()
	_refresh_world_hud()
	return true


## Compatibility shim: unrestricted global node advancement is forbidden.
func advance_to_next_node() -> bool:
	_last_macro_event = "Global advance is disabled. Leave through a directional rim."
	_refresh_world_hud()
	return false


func _next_incomplete_available_nodes() -> Array[String]:
	if campaign == null:
		return []
	return campaign.get_directional_destinations(_pending_exit_direction)


func advance_macro_world(turns: int = 1, bypass_interaction_check: bool = false) -> void:
	for i in range(turns):
		if not bypass_interaction_check and not _pending_interaction.is_empty():
			break
		var collision := _advance_npc_macro_turn(bypass_interaction_check)
		if collision:
			break

func _select_hex_at_mouse() -> void:
	var mouse_pos = map_visualizer.get_local_mouse_position()
	_select_hex_for_hud(map_visualizer.local_to_map(mouse_pos))

func _select_hex_for_hud(coords: Vector2i) -> void:
	_selected_hex_coords = coords
	if map_visualizer and map_visualizer.has_method("show_selection"):
		map_visualizer.call("show_selection", coords)
	_refresh_world_hud()

func _resolve_hex_hud_action(action: String) -> void:
	if not _pending_interaction.is_empty():
		return
	match action:
		GameEnums.MACRO_HEX_SCAN:
			_select_hex_for_hud(_selected_hex_coords)
		GameEnums.MACRO_HEX_TRAVEL:
			_try_travel_to_selected_hex()
		GameEnums.MACRO_HEX_ACT:
			_resolve_current_hex_action()

func _try_travel_to_selected_hex() -> void:
	if _selected_hex_coords == player_token.current_hex_coords:
		_resolve_current_hex_action()
		return
	var distance_vector := _selected_hex_coords - player_token.current_hex_coords
	if not HEX_NEIGHBORS.has(distance_vector):
		_last_macro_event = "Selected hex is not adjacent."
		_refresh_world_hud()
		return
	if not world_generator.is_in_zone_bounds(_selected_hex_coords):
		_last_macro_event = "Selected hex is outside this zone."
		_refresh_world_hud()
		return
	var target_hex := world_generator.get_hex_at(_selected_hex_coords)
	if not target_hex.is_passable():
		_last_macro_event = "Selected hex is blocked by rock fields."
		_refresh_world_hud()
		return
	_execute_player_step(_selected_hex_coords)

func _resolve_current_hex_action() -> void:
	_expand_hex_at(player_token.current_hex_coords)

func _on_hex_preview_travel(coords: Vector2i) -> void:
	_selected_hex_coords = coords
	_try_travel_to_selected_hex()

func _expand_hex_at(coords: Vector2i) -> void:
	if coords != player_token.current_hex_coords:
		_on_hex_preview_travel(coords)
		return
	var hex_data := world_generator.get_hex_at(coords)
	if active_enemies.has(coords):
		var enemy: MacroEnemy = active_enemies[coords]
		begin_entity_collision(enemy.entity_id, coords)
		return
	begin_poi_interaction(coords, hex_data)

func _mark_hex_explored(
	coords: Vector2i,
	hex_data: MacroHexData = null
) -> void:
	var target_hex := hex_data if hex_data != null else world_generator.get_hex_at(coords)
	if target_hex.is_explored:
		return
	target_hex.is_explored = true
	_world_state.set_hex_record(coords, target_hex.to_state())

# ---------------------------------------------------------
# FOG OF WAR
# ---------------------------------------------------------

## Tagged, filterable trace for the spawn/despawn/movement pipeline.
func _macro_log(message: String) -> void:
	if debug_macro_logging:
		print("[MacroMap] ", message)

## Recompute the player's line of sight around a center and reveal it.
## "Visible" = currently in sight this turn. "Explored" = seen at least once.
## Returns axial coords newly marked explored this call.
func _update_fog_of_war(center_coords: Vector2i) -> Array[Vector2i]:
	_visible_hexes.clear()
	var newly_explored: Array[Vector2i] = []
	for coords in _coords_in_radius(center_coords, vision_radius):
		if world_generator.zone_bounds_enabled and not world_generator.is_in_zone_bounds(coords):
			continue
		_visible_hexes[coords] = true
		var hex_data := world_generator.get_hex_at(coords)
		if not hex_data.is_explored:
			hex_data.is_explored = true
			_world_state.set_hex_record(coords, hex_data.to_state())
			newly_explored.append(coords)
	_macro_log(
		"Fog update @%s: %d visible hex(es), %d newly explored."
		% [str(center_coords), _visible_hexes.size(), newly_explored.size()]
	)
	return newly_explored


## Paint / refresh zone visuals and push black fog states to the visualizer.
## Returns axial coords newly marked explored this call.
func _refresh_map_visuals(center_coords: Vector2i, repaint_zone: bool = false) -> Array[Vector2i]:
	if map_visualizer == null:
		return []
	var newly_explored := _update_fog_of_war(center_coords)
	var animate_fog := true
	if world_generator != null and world_generator.zone_bounds_enabled:
		if repaint_zone or map_visualizer.rendered_cells.is_empty():
			map_visualizer.render_zone()
			animate_fog = false
		map_visualizer.apply_fog(_visible_hexes, animate_fog)
	else:
		map_visualizer.render_radius(center_coords, 3)
		map_visualizer.apply_fog(_visible_hexes, animate_fog)
	_refresh_enemy_visibility()
	_update_vision_soft_focus()
	return newly_explored


## Soft screen-space vision disk around the player. Follows camera/zoom.
func _update_vision_soft_focus() -> void:
	if vision_vignette == null or player_token == null or map_visualizer == null:
		return
	var viewport := get_viewport()
	if viewport == null:
		return
	var vp_size := viewport.get_visible_rect().size
	if vp_size.x < 1.0 or vp_size.y < 1.0:
		return
	var canvas := viewport.get_canvas_transform()
	var focus_world := player_token.global_position
	var focus_px: Vector2 = canvas * focus_world
	var center_hex := map_visualizer.map_to_local(player_token.current_hex_coords)
	var neighbor_hex := map_visualizer.map_to_local(
		player_token.current_hex_coords + Vector2i(1, 0)
	)
	var pitch_px := ((canvas * neighbor_hex) - (canvas * center_hex)).length()
	pitch_px = maxf(pitch_px, 24.0)
	# Clear through the inner vision rings; soft band feathers across the
	# outermost visible hexes into fog so the radius edge reads circular.
	var inner_px := pitch_px * maxf(float(vision_radius) - 0.35, 0.9)
	var soft_px := pitch_px * 1.35
	vision_vignette.set_vision_disk(focus_px, inner_px, soft_px)


func _refresh_enemy_visibility() -> void:
	for coords in active_enemies.keys():
		_apply_enemy_visibility(active_enemies[coords], coords)


## Enemies are fully visible only inside vision. No translucent alpha fog.
func _apply_enemy_visibility(enemy: MacroEnemy, coords: Vector2i) -> void:
	if enemy == null:
		return
	enemy.modulate = Color(1, 1, 1, 1)
	enemy.visible = _is_hex_visible(coords)

func _is_hex_visible(coords: Vector2i) -> bool:
	return _visible_hexes.has(coords)

func _is_hex_explored(coords: Vector2i) -> bool:
	return world_generator.get_hex_at(coords).is_explored

func _advance_survival_time(
	elapsed_minutes: int,
	exertion: float,
	target_coords: Vector2i,
	insulation_bonus: float = 0.0
) -> void:
	_world_state.advance_world_time(elapsed_minutes)
	var current_player_core := player_token.get_humanoid_core()
	if current_player_core:
		current_player_core.process_survival_time(
			elapsed_minutes,
			15.0,
			exertion,
			insulation_bonus
		)
		_world_state.update_player_runtime(
			current_player_core.capture_runtime_state().to_dict(),
			target_coords
		)
	_refresh_world_hud()

func _get_exertion_for_biome(biome: GameEnums.GridBiome) -> float:
	if biome == GameEnums.GridBiome.HILLS:
		return 2.0
	if biome == GameEnums.GridBiome.SWAMP or biome == GameEnums.GridBiome.MUD:
		return 1.5
	if biome == GameEnums.GridBiome.FOREST:
		return 1.2
	return 1.0

func _get_exertion_for_hex(hex_data: MacroHexData) -> float:
	return hex_data.travel_exertion()

func begin_poi_interaction(
	coords: Vector2i,
	hex_data: MacroHexData
) -> void:
	# Campaign objective / unique-event sites intercept the normal POI flow.
	if _try_handle_campaign_site(coords, hex_data):
		return
	_pending_interaction = {
		"type": GameEnums.MacroInteractionType.POI,
		"coords": coords,
	}
	player_token.play_interaction()
	set_process_unhandled_input(false)
	if exploration_window == null:
		push_error("POI interaction opened without a presentation subscriber.")
		close_macro_interaction()
		return
	_present_poi_session(coords, hex_data)


func _try_handle_campaign_site(coords: Vector2i, hex_data: MacroHexData) -> bool:
	if campaign == null or campaign.active_node_id.is_empty():
		return false
	var node := campaign.get_active_node()
	if node == null:
		return false
	if node.role == GameEnums.MacroNodeRole.CENTRAL_CORE and hex_data.poi_id == "central_core":
		_begin_central_core_debug_hub(coords)
		return true

	if str(hex_data.poi_id).begins_with("macro_event_"):
		var event_id := node.event_id
		if event_id.is_empty():
			event_id = MacroEventResolver.EVENT_LOCKED_TREATMENT_ROOM
		begin_macro_event(event_id, coords)
		return true

	return false


func _handle_central_meta_quest() -> void:
	player_token.play_interaction()
	if _meta_progress == null:
		_last_macro_event = "Meta Progress profile is unavailable."
		_refresh_world_hud()
		return
	if _meta_progress.is_event_completed(MacroGraphGenerator.META_FETCH_EVENT_ID):
		_last_macro_event = "North Core Regulator installed. The north gateway is permanently unsealed."
		_refresh_world_hud()
		return
	var inventory := player_token.get_humanoid_core().inventory
	var component: ItemData = null
	for item in inventory.get_all_items():
		if item.id == MacroGraphGenerator.FETCH_ITEM_ID:
			component = item
			break
	if component == null:
		campaign.reveal_fetch_branch()
		_last_macro_event = (
			"META QUEST: Recover the North Core Regulator from the revealed east-arm branch "
			+ "and return it to the Central Core."
		)
		_world_state.campaign_graph = campaign.graph.to_dict()
		_refresh_world_hud()
		return
	inventory.remove_item_by_instance_id(component.instance_id)
	_meta_progress.complete_event(
		MacroGraphGenerator.META_FETCH_EVENT_ID,
		[{
			"type": "set_gateway",
			"gateway_id": "north",
			"unsealed": true,
		}]
	)
	campaign.refresh_meta_unlocks()
	_last_macro_event = (
		"META EVENT COMPLETE: North Core Regulator installed. "
		+ "The north gateway is unsealed for every future character."
	)
	_macro_log(_last_macro_event)
	_refresh_world_hud()


func debug_begin_poi_interaction(
	coords: Vector2i,
	hex_data: MacroHexData
) -> void:
	begin_poi_interaction(coords, hex_data)


func get_camp_access(
	coords: Vector2i,
	hex_data: MacroHexData
) -> Dictionary:
	return _get_camp_access(coords, hex_data)


func debug_requirements_met(requirements: Dictionary) -> bool:
	return _PoiController.requirements_met(
		requirements,
		Callable(self, "_inventory_has_any_item_id"),
		Callable(self, "_inventory_has_any_tag"),
		Callable(self, "_inventory_has_any_role")
	)


func begin_macro_event(
	event_id: String,
	coords: Vector2i = Vector2i(2147483647, 2147483647),
	context_overrides: Dictionary = {}
) -> void:
	if not _pending_interaction.is_empty():
		return
	if coords == Vector2i(2147483647, 2147483647):
		coords = player_token.current_hex_coords
	var hex_data := world_generator.get_hex_at(coords)
	var context := _build_macro_event_context(coords, hex_data)
	context.merge(context_overrides, true)
	var session: Dictionary = MacroEventResolver.build_event_session(event_id, context)
	if session.is_empty():
		push_error("[MacroGameManager] Unknown macro event: " + event_id)
		return
	_pending_interaction = {
		"type": GameEnums.MacroInteractionType.MACRO_EVENT,
		"coords": coords,
		"event_id": event_id,
		"context": context,
	}
	player_token.play_interaction()
	set_process_unhandled_input(false)
	if macro_hud == null:
		push_error("Macro event opened without a HUD subscriber.")
		close_macro_interaction()
		return
	macro_hud.open_event(session)


func debug_begin_macro_event(
	event_id: String = "locked_treatment_room",
	coords: Vector2i = Vector2i(2147483647, 2147483647),
	context_overrides: Dictionary = {}
) -> void:
	begin_macro_event(event_id, coords, context_overrides)


func _present_poi_session(
	coords: Vector2i,
	hex_data: MacroHexData
) -> void:
	var camp_access := _get_camp_access(coords, hex_data)
	var inventory_snapshot := _build_inventory_snapshot()
	var session := (
		_PoiController.build_landmark_session_snapshot(
			coords,
			hex_data,
			_world_state.world_seed,
			_world_state.get_world_time_snapshot(),
			_hex_label(coords, hex_data),
			camp_access,
			_PoiController.available_interaction_options(
				player_token.get_humanoid_core().inventory.get_all_items()
			),
			inventory_snapshot.get("ground", []),
			Callable(self, "_inventory_has_any_item_id"),
			Callable(self, "_inventory_has_any_tag"),
			Callable(self, "_inventory_has_any_role")
		)
		if hex_data.has_landmark()
		else _PoiController.build_hex_session_snapshot(
			coords,
			hex_data,
			_world_state.world_seed,
			_world_state.get_world_time_snapshot(),
			_hex_label(coords, hex_data),
			camp_access,
			_PoiController.available_interaction_options(
				player_token.get_humanoid_core().inventory.get_all_items()
			),
			inventory_snapshot.get("ground", [])
		)
	)
	if macro_hud:
		macro_hud.present_poi(session, inventory_snapshot)
	elif exploration_window:
		exploration_window.open_landmark(session, inventory_snapshot)
	else:
		push_error("POI session opened without a presentation subscriber.")
		close_macro_interaction()

func begin_entity_collision(
	enemy_id: String,
	coords: Vector2i,
	approach_from: Vector2i = Vector2i(2147483647, 2147483647)
) -> void:
	if not queue_entity_collision(enemy_id, coords, approach_from):
		return
	player_token.play_interaction()
	if active_enemies.has(coords):
		var enemy: MacroEnemy = active_enemies[coords]
		enemy.play_interaction()
	set_process_unhandled_input(false)
	if macro_hud == null:
		push_error("Entity interaction opened without a HUD subscriber.")
		close_macro_interaction()
		return
	_open_entity_collision_session(
		MacroEntityCollisionResolver.MODE_ROOT
	)

func preview_poi_action(
	action: GameEnums.PoiAction,
	selected_item_ids: Array,
	selected_search_option_id: String = ""
) -> void:
	if (
		_pending_interaction.get("type")
		!= GameEnums.MacroInteractionType.POI
		or exploration_window == null
	):
		return
	var coords: Vector2i = _pending_interaction.get("coords", Vector2i.ZERO)
	var hex_data := world_generator.get_hex_at(coords)
	var loot_profile := _get_loot_profile(hex_data)
	var tool_descriptors := _PoiController.inventory_descriptors_for_ids(
		selected_item_ids,
		GameEnums.InteractionItemRole.SEARCH_TOOL,
		Callable(self, "_find_inventory_item_by_instance_id")
	)
	var camp_preview_states := _PoiController.camp_states_for_session_preview(
		hex_data,
		selected_item_ids,
		Callable(self, "_find_inventory_item_by_instance_id")
	)
	var metrics := _PoiController.preview_metrics(
		action,
		_world_state.world_seed,
		coords,
		hex_data,
		selected_item_ids,
		selected_search_option_id,
		tool_descriptors,
		camp_preview_states,
		loot_profile,
		Callable(self, "_inventory_has_any_item_id"),
		Callable(self, "_inventory_has_any_tag"),
		Callable(self, "_inventory_has_any_role")
	)
	exploration_window.show_poi_preview(action, metrics)

func resolve_poi_action(
	action: GameEnums.PoiAction,
	selected_item_ids: Array,
	selected_search_option_id: String = ""
) -> void:
	if _pending_interaction.get("type") != GameEnums.MacroInteractionType.POI:
		return
	player_token.play_interaction()
	var coords: Vector2i = _pending_interaction.get("coords", Vector2i.ZERO)
	var hex_data := world_generator.get_hex_at(coords)
	var profile := MacroInteractionResolver.build_poi_profile(
		_world_state.world_seed,
		coords,
		hex_data.biome,
		hex_data.poi_id
	)
	if action == GameEnums.PoiAction.SEARCH:
		if selected_search_option_id == "restore_regional_core":
			_resolve_regional_core_restoration(coords, hex_data)
			return
		if selected_search_option_id == "activate_core":
			_resolve_core_activation(coords, hex_data)
			return
		if selected_search_option_id == "event_locked_treatment_room":
			_begin_macro_event_from_poi(
				MacroEventResolver.EVENT_LOCKED_TREATMENT_ROOM,
				selected_search_option_id,
				coords,
				hex_data
			)
			return
		_resolve_search(
			coords,
			hex_data,
			profile["search"],
			selected_item_ids,
			selected_search_option_id
		)
	elif action == GameEnums.PoiAction.STOP_REST:
		hex_data.rest_in_progress = false
		_world_state.set_hex_record(coords, hex_data.to_state())
		_present_poi_session(coords, hex_data)
	elif action == GameEnums.PoiAction.REST or action == GameEnums.PoiAction.CAMP:
		var camp_access := _get_camp_access(coords, hex_data)
		if not camp_access.get("allowed", false):
			_show_interaction_result(
				"CAMP UNAVAILABLE",
				camp_access.get("reason", "This location is unsafe.")
			)
			return
		_apply_poi_session_selections(coords, hex_data, selected_item_ids)
		hex_data.rest_in_progress = true
		_world_state.set_hex_record(coords, hex_data.to_state())
		_resolve_camp(coords, hex_data, profile["camp"], selected_item_ids)
		hex_data = world_generator.get_hex_at(coords)
		hex_data.rest_in_progress = false
		_world_state.set_hex_record(coords, hex_data.to_state())


func _on_macro_hud_choice_submitted(choice_id: String) -> void:
	var pending_type: int = _pending_interaction.get(
		"type",
		GameEnums.MacroInteractionType.NONE
	)
	if pending_type == GameEnums.MacroInteractionType.ENTITY_COLLISION:
		resolve_entity_collision_choice(choice_id)
		return
	if pending_type == GameEnums.MacroInteractionType.MACRO_EVENT:
		if str(_pending_interaction.get("event_id", "")) == "debug_central_hub":
			_resolve_central_core_debug_choice(choice_id)
			return
		resolve_macro_event_choice(choice_id)


func _begin_central_core_debug_hub(coords: Vector2i) -> void:
	if not _pending_interaction.is_empty():
		return
	_pending_interaction = {
		"type": GameEnums.MacroInteractionType.MACRO_EVENT,
		"coords": coords,
		"event_id": "debug_central_hub",
	}
	player_token.play_interaction()
	set_process_unhandled_input(false)
	if macro_hud == null:
		close_macro_interaction()
		return
	macro_hud.open_event({
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
			{
				"id": "meta_quest",
				"label": "Continue Meta Quest",
				"kind": "talk",
				"enabled": true,
				"stakes": ["LIVE"],
				"reason": "Runs the North Core Regulator fetch / install flow.",
			},
			{
				"id": "dbg_event",
				"label": "DEBUG: Open Treatment Room Event",
				"kind": "observe",
				"enabled": true,
				"stakes": ["EVENT"],
				"reason": "Opens the authored locked_treatment_room macro event.",
			},
			{
				"id": "dbg_hostile",
				"label": "DEBUG: Spawn Hostile Collision",
				"kind": "ambush",
				"enabled": true,
				"stakes": ["COMBAT"],
				"reason": "Spawns a scavenger on this hex and opens Talk/Ambush.",
			},
			{
				"id": "dbg_loot",
				"label": "DEBUG: Drop Ground Loot",
				"kind": "item",
				"enabled": true,
				"stakes": ["LOOT"],
				"reason": "Drops sample items on this hex for ground pickup tests.",
			},
			{
				"id": "dbg_poi",
				"label": "DEBUG: Open Landmark Explore",
				"kind": "observe",
				"enabled": true,
				"stakes": ["POI"],
				"reason": "Injects a homestead landmark here and opens Search/Camp.",
			},
			{
				"id": "dbg_travel",
				"label": "DEBUG: Sample Travel Feedback",
				"kind": "pass",
				"enabled": true,
				"stakes": ["TRAVEL"],
				"reason": "Writes a travel log line, leaves a trail, and soft look-ahead.",
			},
			{
				"id": "leave",
				"label": "Leave",
				"kind": "pass",
				"enabled": true,
				"stakes": [],
				"reason": "Close the hub.",
			},
		],
	})


func _resolve_central_core_debug_choice(choice_id: String) -> void:
	var coords: Vector2i = _pending_interaction.get(
		"coords",
		player_token.current_hex_coords
	)
	match choice_id:
		"meta_quest":
			close_macro_interaction()
			_handle_central_meta_quest()
		"dbg_event":
			close_macro_interaction()
			begin_macro_event(MacroEventResolver.EVENT_LOCKED_TREATMENT_ROOM, coords)
		"dbg_hostile":
			close_macro_interaction()
			var spawned := debug_spawn_enemy_near_player(
				GameEnums.Faction.SCAVENGER_CELL,
				0
			)
			if not spawned:
				_last_macro_event = "DEBUG: Hostile spawn failed (no free adjacent hex)."
				_refresh_world_hud()
				return
			var enemy_id := ""
			for delta in HEX_NEIGHBORS:
				var probe: Vector2i = coords + delta
				var record := _world_state.get_entity_at(probe)
				if record != null and _world_state.is_entity_hostile(record.entity_id):
					enemy_id = record.entity_id
					_world_state.move_entity(enemy_id, coords)
					break
			if enemy_id.is_empty():
				_last_macro_event = "DEBUG: Hostile spawned but collision handoff failed."
				_refresh_world_hud()
				return
			begin_entity_collision(enemy_id, coords)
		"dbg_loot":
			close_macro_interaction()
			_debug_drop_sample_loot(coords)
		"dbg_poi":
			close_macro_interaction()
			_debug_open_landmark_here(coords)
		"dbg_travel":
			close_macro_interaction()
			var hex_data := world_generator.get_hex_at(coords)
			_present_travel_beat(
				coords,
				coords + Vector2i(1, 0),
				hex_data,
				[coords],
				false
			)
			_refresh_world_hud()
		"leave", _:
			close_macro_interaction()


func _debug_drop_sample_loot(coords: Vector2i) -> void:
	if _loot_catalog == null:
		_last_macro_event = "DEBUG: Loot catalog unavailable."
		_refresh_world_hud()
		return
	var drops: Array = []
	for item_id in ["water_bottle", "crackers", "bandage", "matches", "bottle"]:
		if not _loot_catalog.has_item(item_id):
			continue
		var state: Dictionary = _loot_catalog.create_runtime_item_state(item_id)
		if not state.is_empty():
			drops.append(state)
		if drops.size() >= 3:
			break
	if drops.is_empty():
		_last_macro_event = "DEBUG: No sample loot definitions found."
	else:
		_world_state.add_ground_items(coords, drops)
		_last_macro_event = "DEBUG: Dropped %d ground item(s) at HEX %d,%d." % [
			drops.size(),
			coords.x,
			coords.y,
		]
	if macro_hud:
		macro_hud.append_exploration_log(_last_macro_event)
	_refresh_world_hud()


func _debug_open_landmark_here(coords: Vector2i) -> void:
	var hex := world_generator.get_hex_at(coords)
	hex.rock_layer = GameEnums.MacroRockLayer.NONE
	hex.water_layer = GameEnums.MacroWaterLayer.NONE
	hex.structure_layer = GameEnums.MacroStructureLayer.STRUCTURES
	hex.is_poi = true
	hex.landmark_id = "homestead_b"
	hex.poi_id = "plains_homestead"
	hex.poi_name = "Debug Homestead"
	hex.sleep_anchor = "ground"
	world_generator.world_hex_cache[coords] = hex
	_world_state.set_hex_record(coords, hex.to_state())
	begin_poi_interaction(coords, hex)


func _on_macro_hud_event_closed() -> void:
	if (
		_pending_interaction.get("type")
		== GameEnums.MacroInteractionType.ENTITY_COLLISION
	):
		var resume := str(_pending_interaction.get("resume_after_result", ""))
		_pending_interaction.erase("resume_after_result")
		if resume == MacroEntityCollisionResolver.MODE_PEACEFUL:
			_open_entity_collision_session(
				MacroEntityCollisionResolver.MODE_PEACEFUL
			)
			return
		if resume == MacroEntityCollisionResolver.MODE_ASK:
			_open_entity_collision_session(
				MacroEntityCollisionResolver.MODE_ASK
			)
			return
		if bool(_pending_interaction.get("keep_open_on_close", false)):
			_pending_interaction.erase("keep_open_on_close")
			return
	close_macro_interaction()


func resolve_macro_event_choice(choice_id: String) -> void:
	if (
		_pending_interaction.get("type")
		!= GameEnums.MacroInteractionType.MACRO_EVENT
	):
		return
	var event_id := str(_pending_interaction.get("event_id", ""))
	var context: Dictionary = _pending_interaction.get("context", {})
	var result: Dictionary = MacroEventResolver.resolve_choice(
		event_id,
		choice_id,
		context
	)
	if result.has("choice_id"):
		_complete_macro_event_source()
	_apply_macro_event_effects(result.get("effects", {}))
	apply_campaign_discovery_trigger("event_resolved:%s" % event_id)
	_last_macro_event = "%s: %s" % [
		str(_pending_interaction.get("event_id", "Macro event")),
		str(result.get("title", "Resolved")),
	]
	# Unique-event campaign nodes complete after any resolved choice.
	if campaign != null:
		campaign.complete_active_event_objective()
	_refresh_world_hud()
	if macro_hud:
		macro_hud.show_event_result(result)


func resolve_entity_collision_choice(choice_id: String) -> void:
	_get_collision_coordinator().resolve_choice(choice_id)


func _resolve_entity_collision_back() -> void:
	_get_collision_coordinator().resolve_back()


func _resolve_entity_collision_trade() -> void:
	_get_collision_coordinator().resolve_trade()


func _resolve_entity_collision_ask(choice_id: String) -> void:
	_get_collision_coordinator().resolve_ask(choice_id)


func _resolve_entity_collision_leave() -> void:
	_get_collision_coordinator().resolve_leave()


func _open_entity_collision_session(mode: String) -> void:
	_get_collision_coordinator().open_session(mode)


func _begin_macro_event_from_poi(
	event_id: String,
	search_option_id: String,
	coords: Vector2i,
	hex_data: MacroHexData
) -> void:
	if hex_data.searched_targets.has(search_option_id):
		_present_poi_session(coords, hex_data)
		return
	if exploration_window and exploration_window.is_open():
		exploration_window.close_window(false)
	if macro_hud:
		macro_hud.collapse_hex_panel()
	_pending_interaction.clear()
	begin_macro_event(
		event_id,
		coords,
		{"source_search_option_id": search_option_id}
	)


func _complete_macro_event_source() -> void:
	var context: Dictionary = _pending_interaction.get("context", {})
	var search_option_id := str(context.get("source_search_option_id", ""))
	if search_option_id.is_empty():
		return
	var coords: Vector2i = _pending_interaction.get(
		"coords",
		player_token.current_hex_coords
	)
	var hex_data := world_generator.get_hex_at(coords)
	if not hex_data.searched_targets.has(search_option_id):
		hex_data.searched_targets.append(search_option_id)
		_world_state.set_hex_record(coords, hex_data.to_state())

func resolve_talk_action(action: GameEnums.TalkAction) -> void:
	if (
		_pending_interaction.get("type")
		!= GameEnums.MacroInteractionType.ENTITY_COLLISION
	):
		return
	player_token.play_interaction()
	var interaction_coords: Vector2i = _pending_interaction.get(
		"coords",
		Vector2i.ZERO
	)
	if active_enemies.has(interaction_coords):
		var interaction_enemy: MacroEnemy = active_enemies[
			interaction_coords
		]
		interaction_enemy.play_interaction()
	var enemy_id: String = _pending_interaction.get("enemy_id", "")
	var enemy_record := _world_state.get_entity(enemy_id)
	if enemy_record == null:
		return
	var attempt: int = enemy_record.negotiation_attempts
	var player_core := player_token.get_humanoid_core()
	var outcome := MacroInteractionResolver.resolve_negotiation(
		_world_state.world_seed,
		enemy_id,
		attempt,
		action,
		{
			"threat": player_core.get_effective_threat(),
			"brawn": player_core.definition.brawn,
			"finesse": player_core.definition.finesse,
			"will": player_core.definition.will,
		},
		enemy_record.definition
	)
	_world_state.patch_entity_record(
		enemy_id,
		{"negotiation_attempts": attempt + 1}
	)

	if outcome == GameEnums.NegotiationOutcome.COMBAT:
		_request_pending_combat(GameEnums.EncounterContext.DIALOGUE_BREAKDOWN)
		return

	if outcome == GameEnums.NegotiationOutcome.INTIMIDATED:
		_world_state.set_entity_world_status(
			enemy_id,
			GameEnums.EntityWorldStatus.WITHDRAWN
		)
		var threat_result: Dictionary = (
			MacroInteractionResolver.resolve_threat_surrender(
				_world_state.world_seed,
				enemy_id,
				attempt,
				enemy_record.definition,
				_loot_catalog
			)
		)
		var definition: Dictionary = enemy_record.definition.duplicate(true)
		definition["loadout"] = threat_result.get(
			"kept_loadout",
			definition.get("loadout", {})
		)
		_world_state.patch_entity_record(
			enemy_id,
			{"definition": definition}
		)
		if not threat_result.get("ground_items", []).is_empty():
			_world_state.add_ground_items(
				player_token.current_hex_coords,
				threat_result.get("ground_items", [])
			)
		unload_enemy_token(_pending_interaction.get("coords", Vector2i.ZERO))
		_show_collision_result(
			"THREAT SUCCESS",
			str(threat_result.get("message", "")),
			""
		)
		return

	_world_state.set_entity_world_status(
		enemy_id,
		GameEnums.EntityWorldStatus.CEASEFIRE
	)
	var updated_record := _world_state.get_entity(enemy_id)
	if updated_record != null and active_enemies.has(interaction_coords):
		active_enemies[interaction_coords].setup_from_record(updated_record)
	_open_entity_collision_session(
		MacroEntityCollisionResolver.MODE_PEACEFUL
	)


func resolve_entity_ambush(position: GameEnums.AmbushPosition) -> void:
	if (
		_pending_interaction.get("type")
		!= GameEnums.MacroInteractionType.ENTITY_COLLISION
	):
		return
	_request_pending_combat(
		GameEnums.EncounterContext.PLAYER_AMBUSH,
		position
	)


func close_macro_interaction() -> void:
	_pending_interaction.clear()
	set_process_unhandled_input(true)
	if exploration_window and exploration_window.is_open():
		exploration_window.close_window(false)
	if macro_hud:
		macro_hud.clear_exploration_presentation(false)
		macro_hud.collapse_hex_panel()
	_refresh_world_hud()


func get_pending_interaction_type() -> int:
	return _pending_interaction.get("type", GameEnums.MacroInteractionType.NONE)


func queue_entity_collision(
	enemy_id: String,
	coords: Vector2i,
	approach_from: Vector2i = Vector2i(2147483647, 2147483647)
) -> bool:
	if not _pending_interaction.is_empty():
		return false
	var enemy_record := _world_state.get_entity(enemy_id)
	if enemy_record == null or not _world_state.is_entity_hostile(enemy_id):
		return false
	var resolved_approach := (
		player_token.current_hex_coords
		if approach_from == Vector2i(2147483647, 2147483647)
		else approach_from
	)
	_pending_interaction = {
		"type": GameEnums.MacroInteractionType.ENTITY_COLLISION,
		"coords": coords,
		"enemy_id": enemy_id,
		"approach_from": resolved_approach,
	}
	return true

func open_inventory() -> void:
	_toggle_fullscreen_inventory()


func _toggle_fullscreen_inventory() -> void:
	if inventory_panel == null:
		return
	if inventory_panel.is_open():
		inventory_panel.close_panel()
		return
	if (
		_inventory_home_layer != null
		and inventory_panel.get_parent() != _inventory_home_layer
	):
		inventory_panel.reparent(_inventory_home_layer)
	inventory_panel.open_inventory(_build_inventory_snapshot())


func _on_hud_viewport_insets_changed(insets: Rect2i) -> void:
	var camera := get_node_or_null("Camera2D") as MacroCamera
	if camera:
		camera.set_viewport_insets(insets)


func _on_medical_action_requested(instance_id: String, limb_region: int) -> void:
	var player_core := player_token.get_humanoid_core()
	var result := MacroMedicalResolver.resolve_apply_to_limb(
		player_core,
		instance_id,
		limb_region
	)
	if not bool(result.get("success", false)):
		_last_inventory_error = str(result.get("message", "Treatment failed."))
	_world_state.update_player_runtime(
		player_core.capture_runtime_state().to_dict(),
		player_token.current_hex_coords
	)
	_refresh_world_hud()

func _on_inventory_closed() -> void:
	_restore_node_map_inventory_layer()


func _build_macro_event_context(
	coords: Vector2i,
	hex_data: MacroHexData
) -> Dictionary:
	var player_core := player_token.get_humanoid_core()
	var inventory := player_core.inventory
	var item_ids: Array[String] = []
	var item_tags: Array[String] = []
	var item_roles: Array[String] = []
	var item_names: Dictionary = {}
	for item in inventory.get_all_items():
		if item == null:
			continue
		if not item_ids.has(item.id):
			item_ids.append(item.id)
		item_names[item.id] = item.display_name
		for tag in item.tags:
			if not item_tags.has(tag):
				item_tags.append(tag)
		for role in item.interaction_roles:
			var role_id := str(role)
			if not item_roles.has(role_id):
				item_roles.append(role_id)
	var scene_descriptor := EventBgCatalog.build_scene_descriptor(
		hex_data,
		_world_state.world_seed,
		coords
	)
	return {
		"coords": coords,
		"location_label": _hex_label(coords, hex_data),
		"time_label": _format_world_time(),
		"background_path": scene_descriptor.get("background_path", ""),
		"item_ids": item_ids,
		"item_tags": item_tags,
		"item_roles": item_roles,
		"item_names": item_names,
		"occupations": _player_context_list("occupations"),
		"traits": _player_context_list("traits"),
		"flaws": _player_context_list("flaws"),
		"stats": {
			"brawn": player_core.definition.brawn,
			"finesse": player_core.definition.finesse,
			"fortitude": player_core.definition.fortitude,
			"will": player_core.definition.will,
		},
	}


func _player_context_list(key: String) -> Array[String]:
	var player_definition := player_token.get_humanoid_core().definition
	if player_definition != null:
		match key:
			"occupations":
				if not player_definition.occupation_id.is_empty():
					return [player_definition.occupation_id]
			"traits":
				return _packed_string_values(player_definition.trait_ids)
			"flaws":
				return _packed_string_values(player_definition.flaw_ids)
		if player_definition.has_meta("macro_context"):
			var metadata = player_definition.get_meta("macro_context")
			if metadata is Dictionary and metadata.has(key):
				var values: Array[String] = []
				for value in metadata.get(key, []):
					values.append(str(value))
				return values
	return []


func _packed_string_values(values: PackedStringArray) -> Array[String]:
	var result: Array[String] = []
	for value in values:
		var text := str(value)
		if not text.is_empty():
			result.append(text)
	return result


func _apply_macro_event_effects(effects: Dictionary) -> void:
	if effects.is_empty():
		return
	var coords: Vector2i = _pending_interaction.get(
		"coords",
		player_token.current_hex_coords
	)
	var elapsed_minutes := int(effects.get("elapsed_minutes", 0))
	if elapsed_minutes > 0:
		_advance_survival_time(
			elapsed_minutes,
			float(effects.get("exertion", 0.0)),
			coords
		)

func resolve_inventory_action(
	action_id: String,
	instance_id: String,
	equipment_slot: int,
	action_payload: Dictionary = {}
) -> void:
	_last_inventory_error = ""
	var player_core := player_token.get_humanoid_core()
	var coords := player_token.current_hex_coords
	var result := MacroInventoryResolver.resolve_action(
		action_id,
		instance_id,
		equipment_slot,
		player_core,
		coords,
		_world_state.take_ground_item,
		_world_state.add_ground_items,
		_can_offer_equip,
		_inventory_error_or,
		action_payload
	)

	for item_state in result.get("ground_restore", []):
		_world_state.add_ground_items(coords, [item_state])
	if not result.get("ground_mutations", []).is_empty():
		_world_state.add_ground_items(
			coords,
			result.get("ground_mutations", [])
		)
	var elapsed_minutes := int(result.get("elapsed_minutes", 0))
	if elapsed_minutes > 0:
		_world_state.advance_world_time(elapsed_minutes)
		player_core.process_survival_time(elapsed_minutes, 15.0, 0.0)
		result["player_runtime"] = player_core.capture_runtime_state().to_dict()

	_world_state.update_player_runtime(
		result.get("player_runtime", {}),
		coords
	)
	_emit_inventory_item_used(result)
	var snapshot := _build_inventory_snapshot()
	if inventory_panel and inventory_panel.is_open():
		inventory_panel.refresh_snapshot(snapshot, "")
	_refresh_exploration_ground()
	_refresh_world_hud()

func _refresh_exploration_ground() -> void:
	if exploration_window == null or not exploration_window.is_open():
		return
	var snapshot := _build_inventory_snapshot()
	var available := _PoiController.available_interaction_options(
		player_token.get_humanoid_core().inventory.get_all_items()
	)
	exploration_window.refresh_session_state(
		available,
		snapshot.get("ground", [])
	)

func _build_inventory_snapshot() -> Dictionary:
	return _SnapshotBuilder.build_inventory_snapshot(
		player_token.get_humanoid_core(),
		player_token.current_hex_coords,
		_world_state,
		_can_offer_equip,
		_allowed_equipment_slots
	)

func _build_world_hud_snapshot() -> Dictionary:
	if not player_token:
		return {}
	var snapshot := _SnapshotBuilder.build_world_hud_snapshot(
		player_token.get_humanoid_core(),
		player_token.current_hex_coords,
		_selected_hex_coords,
		_world_state.get_world_time_snapshot(),
		_last_macro_event,
		_macro_turn_index,
		active_enemies.size(),
		_world_state,
		world_generator,
		Callable(self, "_ensure_npc_purpose"),
		Callable(self, "_hex_distance"),
		Callable(self, "_hex_label"),
		Callable(_world_state, "is_entity_alive"),
		Callable(_world_state, "is_entity_hostile")
	)
	if campaign != null:
		var active := campaign.get_active_node()
		var next_ids := _next_incomplete_available_nodes()
		snapshot["campaign"] = {
			"active_node_id": campaign.active_node_id,
			"available_nodes": campaign.get_available_nodes(),
			"next_nodes": next_ids,
			"active_display_name": (
				active.display_name if active != null else ""
			),
			"active_traversed": active != null and active.traversed,
			"pending_exit_direction": int(_pending_exit_direction),
			"advance_hint": (
				"Leave through the active rim sector to reach %s." % next_ids[0]
				if not next_ids.is_empty()
				else ""
			),
		}
	return snapshot


func _build_hex_descriptor(coords: Vector2i) -> Dictionary:
	var hex_data := world_generator.get_hex_at(coords)
	var player_coords := player_token.current_hex_coords
	return _SnapshotBuilder.build_hex_descriptor(
		coords,
		player_coords,
		hex_data,
		_world_state.get_entity_at(coords),
		_world_state.get_ground_items(coords),
		_hex_label(coords, hex_data),
		Callable(_world_state, "is_entity_alive"),
		Callable(_world_state, "is_entity_hostile"),
		Callable(self, "_ensure_npc_purpose"),
		Callable(self, "_hex_distance")
	)


func _build_macro_activity_snapshot() -> Dictionary:
	return _SnapshotBuilder.build_macro_activity_snapshot(
		player_token.current_hex_coords,
		_macro_turn_index,
		active_enemies.size(),
		_world_state.get_all_entity_records(),
		Callable(self, "_ensure_npc_purpose"),
		Callable(self, "_hex_distance")
	)


func _refresh_world_hud() -> void:
	if macro_hud == null:
		return
	var snapshot := _build_world_hud_snapshot()
	var inventory_snapshot := _build_inventory_snapshot()
	snapshot["equipment"] = inventory_snapshot.get("equipment", [])
	snapshot["containers"] = inventory_snapshot.get("containers", [])
	snapshot["backpack"] = inventory_snapshot.get("backpack", [])
	snapshot["current_capacity"] = inventory_snapshot.get("current_capacity", 0)
	snapshot["maximum_capacity"] = inventory_snapshot.get("maximum_capacity", 0)
	snapshot["capacity_breakdown"] = inventory_snapshot.get("capacity_breakdown", [])
	snapshot["loadout_stats"] = inventory_snapshot.get("loadout_stats", {})
	var hex_data := world_generator.get_hex_at(_selected_hex_coords)
	var scene_descriptor := EventBgCatalog.build_scene_descriptor(
		hex_data,
		_world_state.world_seed,
		_selected_hex_coords
	)
	if not hex_data.water_sprite_path.is_empty():
		scene_descriptor["background_path"] = hex_data.water_sprite_path
	snapshot["selected_scene_descriptor"] = scene_descriptor
	macro_hud.refresh(snapshot)
	var world_time: Dictionary = snapshot.get("world_time", {})
	var hour := int(world_time.get("hour", 8))
	var phase := GameTimeRules.phase_for_hour(hour)
	if vision_vignette != null:
		vision_vignette.apply_lighting_phase(phase)
	if macro_hud.has_method("apply_lighting_phase"):
		macro_hud.apply_lighting_phase(phase)
	if is_node_map_open():
		node_map_system.call("refresh", build_node_map_ui_snapshot())

func _can_offer_equip(item: ItemData) -> bool:
	return MacroInventoryBridge.can_offer_equip(item)

func _allowed_equipment_slots(item: ItemData) -> Array[int]:
	return MacroInventoryBridge.allowed_equipment_slots(item)

func _on_player_inventory_error(message: String) -> void:
	_last_inventory_error = message

func _inventory_error_or(fallback: String) -> String:
	return _last_inventory_error if not _last_inventory_error.is_empty() else fallback

func _on_player_items_spilled(spilled_items: Array[ItemData]) -> void:
	if not is_visible_in_tree():
		return
	var item_states: Array = []
	for item in spilled_items:
		item_states.append(item.to_runtime_state())
	_world_state.add_ground_items(player_token.current_hex_coords, item_states)

func _resolve_core_activation(coords: Vector2i, hex_data: MacroHexData) -> void:
	if hex_data.poi_id != "central_core":
		_show_interaction_result(
			"ACTIVATION BLOCKED",
			"This location cannot bring the Alpha Core online."
		)
		return
	var core_state: Dictionary = (
		_meta_progress.get_core_state("central_core")
		if _meta_progress != null and _meta_progress.has_method("get_core_state")
		else {}
	)
	if bool(core_state.get("activated", false)):
		_show_interaction_result(
			"CORE ONLINE",
			"The Alpha Core is already active. The wasteland remembers."
		)
		return

	_advance_survival_time(GameTimeRules.SEARCH_MINUTES, 1.5, coords)
	if _meta_progress != null:
		_meta_progress.complete_event(
			"central_core_activated",
			[{"type": "set_core_state", "core_id": "central_core", "state": {"activated": true}}]
		)
	close_macro_interaction()
	_last_macro_event = "Alpha Core activated at %s." % str(coords)
	_refresh_world_hud()
	core_activated.emit()


func _resolve_regional_core_restoration(coords: Vector2i, hex_data: MacroHexData) -> void:
	var active_node := campaign.get_active_node() if campaign != null else null
	if (
		active_node == null
		or active_node.role != GameEnums.MacroNodeRole.ARM_CORE
		or hex_data.poi_id != "arm_core"
	):
		_show_interaction_result("RESTORATION BLOCKED", "No regional Core is connected here.")
		return
	var core_id := active_node.id
	var state: Dictionary = (
		_meta_progress.get_core_state(core_id)
		if _meta_progress != null and _meta_progress.has_method("get_core_state")
		else {}
	)
	if bool(state.get("restored", false)):
		_show_interaction_result("CORE STABLE", "This regional Core is already restored.")
		return
	_advance_survival_time(GameTimeRules.SEARCH_MINUTES, 1.5, coords)
	state["restored"] = true
	if _meta_progress != null and _meta_progress.has_method("set_core_state"):
		_meta_progress.set_core_state(core_id, state)
	if not hex_data.searched_targets.has("restore_regional_core"):
		hex_data.searched_targets.append("restore_regional_core")
	_world_state.set_hex_record(coords, hex_data.to_state())
	campaign.refresh_meta_unlocks()
	apply_campaign_discovery_trigger("core_restored:%s" % core_id)
	close_macro_interaction()
	_last_macro_event = "%s restored." % active_node.display_name
	_refresh_world_hud()
	_show_interaction_result(
		"REGIONAL CORE RESTORED",
		"%s is back in the infrastructure network." % active_node.display_name
	)

func _resolve_search(
	coords: Vector2i,
	hex_data: MacroHexData,
	base_metrics: Dictionary,
	selected_item_ids: Array,
	selected_search_option_id: String = ""
) -> void:
	var loot_profile := _get_loot_profile(hex_data)
	var tool_descriptors := _PoiController.inventory_descriptors_for_ids(
		selected_item_ids,
		GameEnums.InteractionItemRole.SEARCH_TOOL,
		Callable(self, "_find_inventory_item_by_instance_id")
	)
	var outcome := _PoiController.resolve_search_outcome(
		_world_state.world_seed,
		coords,
		hex_data,
		base_metrics,
		selected_item_ids,
		selected_search_option_id,
		tool_descriptors,
		loot_profile,
		Callable(self, "_inventory_has_any_item_id"),
		Callable(self, "_inventory_has_any_tag"),
		Callable(self, "_inventory_has_any_role")
	)
	if bool(outcome.get("blocked", false)):
		_show_interaction_result(
			str(outcome.get("title", "SEARCH BLOCKED")),
			str(outcome.get("message", ""))
		)
		return

	var result: Dictionary = outcome.get("search_result", {})
	var search_label: String = outcome.get("search_label", "Search")
	_advance_survival_time(
		GameTimeRules.SEARCH_MINUTES,
		1.0,
		coords
	)

	var found_names: Array[String] = []
	for loot_id in outcome.get("loot_ids", []):
		var item_state: Dictionary = _loot_catalog.call(
			"create_runtime_item_state",
			loot_id
		)
		if item_state.is_empty():
			continue
		found_names.append(
			str(item_state.get("definition", {}).get("display_name", loot_id))
		)
		_world_state.add_ground_items(coords, [item_state])

	if bool(outcome.get("injured", false)):
		player_token.get_humanoid_core().body.apply_targeted_hit(
			outcome.get("injury_limb", GameEnums.LimbRegion.LEFT_ARM),
			outcome.get("injury_damage", 0.0),
			0.0
		)

	_world_state.set_hex_record(coords, outcome.get("hex_state", {}))
	if not selected_search_option_id.is_empty():
		apply_campaign_discovery_trigger("poi_resolved:%s" % selected_search_option_id)
	if not hex_data.poi_id.is_empty():
		apply_campaign_discovery_trigger("poi_resolved:%s" % hex_data.poi_id)
	_world_state.update_player_runtime(
		player_token.get_humanoid_core().capture_runtime_state().to_dict(),
		coords
	)
	_refresh_world_hud()

	var message := "Target: %s\n" % search_label
	message += (
		"Found: " + ", ".join(found_names)
		if not found_names.is_empty()
		else "The search produced no usable supplies."
	)
	message += "\nTime: " + _format_world_time()
	if bool(outcome.get("injured", false)):
		message += "\nUnstable debris caused an injury."

	if bool(outcome.get("attracted_enemy", false)):
		message += "\nThe noise attracted a hostile."
		advance_macro_world(1, true)
		_spawn_search_intruder(coords)
		return
	_last_macro_event = "Searched %s at HEX %d,%d." % [
		search_label,
		coords.x,
		coords.y,
	]

	advance_macro_world(1, true)
	if (
		not _pending_interaction.is_empty()
		and _pending_interaction.get("type")
		== GameEnums.MacroInteractionType.ENTITY_COLLISION
	):
		return

	if exploration_window and exploration_window.is_open():
		hex_data = world_generator.get_hex_at(coords)
		_present_poi_session(coords, hex_data)
		_refresh_exploration_ground()

	_show_interaction_result("SEARCH COMPLETE", message)

func _resolve_camp(
	coords: Vector2i,
	hex_data: MacroHexData,
	base_metrics: Dictionary,
	_selected_item_ids: Array
) -> void:
	var descriptors: Array = _PoiController.camp_item_descriptors(
		hex_data.camp_item_states
	)
	if not hex_data.sleep_gear_instance_id.is_empty():
		var sleep_item := _find_inventory_item_by_instance_id(
			hex_data.sleep_gear_instance_id
		)
		if sleep_item != null:
			descriptors.append(sleep_item.to_interaction_descriptor())
	var metrics := MacroInteractionResolver.calculate_camp_metrics(
		base_metrics,
		descriptors
	)
	var result := MacroInteractionResolver.resolve_camp(
		_world_state.world_seed,
		coords,
		hex_data.camp_rest_count,
		metrics
	)
	if hex_data.region in [
		GameEnums.MacroRegion.CENTRAL_HUB,
		GameEnums.MacroRegion.HUB_BORDER,
	]:
		result["interrupted"] = false
	hex_data.camp_rest_count += 1

	var body := player_token.get_humanoid_core().body
	
	var missing_fatigue = body.fatigue
	var fatigue_rec = float(result.get("fatigue_recovery", 0.0))
	var fatigue_turns = ceil(missing_fatigue / maxf(0.1, fatigue_rec))
	
	var total_missing_limb: float = 0.0
	for limb in body.limb_hp.keys():
		total_missing_limb += maxf(0.0, body.get_limb_max(limb) - body.limb_hp[limb])
	var healing_amount: float = result.get("healing_amount", 0.0)
	var healing_turns = ceil(total_missing_limb / maxf(0.1, healing_amount)) if healing_amount > 0 else 0
	
	var turns_to_rest = maxi(1, mini(8, int(maxf(fatigue_turns, healing_turns))))
	
	var turns_rested = 0
	var total_healed = 0.0
	var total_fatigue = 0.0
	
	for i in range(turns_to_rest):
		if i > 0:
			result = MacroInteractionResolver.resolve_camp(
				_world_state.world_seed,
				coords,
				hex_data.camp_rest_count,
				metrics
			)
			if hex_data.region in [
				GameEnums.MacroRegion.CENTRAL_HUB,
				GameEnums.MacroRegion.HUB_BORDER,
			]:
				result["interrupted"] = false
				
		var healed_this_turn = 0.0
		body.fatigue = maxf(
			0.0,
			body.fatigue - float(result.get("fatigue_recovery", 0.0))
		)
		total_fatigue += float(result.get("fatigue_recovery", 0.0))
		
		for limb in body.limb_hp.keys():
			if body.limb_hp[limb] > 0.0:
				var to_heal = minf(
					body.get_limb_max(limb) - body.limb_hp[limb],
					healing_amount
				)
				body.limb_hp[limb] += to_heal
				healed_this_turn += to_heal
		total_healed += healed_this_turn
		
		_advance_survival_time(
			GameTimeRules.CAMP_MINUTES,
			0.25,
			coords,
			float(metrics.get("shelter", 0.0))
		)
		
		hex_data.camp_rest_count += 1
		turns_rested += 1
		advance_macro_world(1, true)
		
		if result.get("interrupted", false):
			_world_state.set_hex_record(coords, hex_data.to_state())
			_world_state.update_player_runtime(
				player_token.get_humanoid_core().capture_runtime_state().to_dict(),
				coords
			)
			_refresh_world_hud()
			_spawn_search_intruder(coords)
			return
			
		if not _pending_interaction.is_empty() and _pending_interaction.get("type") == GameEnums.MacroInteractionType.ENTITY_COLLISION:
			_world_state.set_hex_record(coords, hex_data.to_state())
			_world_state.update_player_runtime(
				player_token.get_humanoid_core().capture_runtime_state().to_dict(),
				coords
			)
			_refresh_world_hud()
			return

	_world_state.set_hex_record(coords, hex_data.to_state())
	_world_state.update_player_runtime(
		player_token.get_humanoid_core().capture_runtime_state().to_dict(),
		coords
	)
	_refresh_world_hud()

	_last_macro_event = "Camp rest resolved at HEX %d,%d." % [
		coords.x,
		coords.y,
	]
	_show_interaction_result(
		"REST COMPLETE",
		(
			"Rested for %d turn(s). Fatigue recovered by %.1f. Camp healing restored %.1f limb health."
			+ "\nTime: %s"
		) % [
			turns_rested,
			total_fatigue,
			total_healed,
			_format_world_time(),
		]
	)

func _spawn_search_intruder(coords: Vector2i) -> void:
	if not _world_state.has_entity_at(coords):
		spawn_procedural_enemy(
			coords,
			GameEnums.Faction.SCAVENGER_CELL,
			0
		)
	var record := _world_state.get_entity_at(coords)
	if record == null:
		_show_interaction_result(
			"INTERRUPTED",
			"A hostile was heard nearby, but no encounter could be projected."
		)
		return
	_pending_interaction = {
		"type": GameEnums.MacroInteractionType.ENTITY_COLLISION,
		"coords": coords,
		"enemy_id": record.entity_id,
	}
	_request_pending_combat(
		GameEnums.EncounterContext.ENEMY_AMBUSH,
		GameEnums.AmbushPosition.STANDARD,
		record.entity_id
	)

func _request_pending_combat(
	context: GameEnums.EncounterContext,
	ambush_position: GameEnums.AmbushPosition = GameEnums.AmbushPosition.STANDARD,
	initiator_id: String = "player"
) -> void:
	var request := {
		"enemy_id": _pending_interaction.get("enemy_id", ""),
		"coords": _pending_interaction.get("coords", Vector2i.ZERO),
		"approach_from": _pending_interaction.get(
			"approach_from",
			_pending_interaction.get("coords", Vector2i.ZERO)
		),
		"context": context,
		"initiator_id": initiator_id,
		"ambush_position": ambush_position,
	}
	var combat_coords: Vector2i = request.get("coords", Vector2i.ZERO)
	var trap_context := _consume_hex_trap_for_combat(
		player_token.current_hex_coords
	)
	if not trap_context.is_empty():
		request["trap_context"] = trap_context
	_pending_interaction.clear()
	if exploration_window and exploration_window.is_open():
		exploration_window.close_window(false)
	if macro_hud:
		# Hard-reset the complete exploration surface before the director adds
		# combat. A collision dimmer with MOUSE_FILTER_STOP must never survive
		# merely because its modal state changed during the same frame.
		macro_hud.clear_exploration_presentation(false)
	combat_requested.emit(request)

func _get_loot_profile(hex_data: MacroHexData) -> Dictionary:
	var profile_id := WorldRules.get_loot_profile_id(
		hex_data.biome,
		hex_data.poi_id,
		hex_data.region
	)
	return _loot_catalog.call("get_profile_descriptor", profile_id)


func _get_camp_access(
	coords: Vector2i,
	hex_data: MacroHexData
) -> Dictionary:
	var hostile_present := false
	var entity_record := _world_state.get_entity_at(coords)
	if entity_record != null:
		var entity_id: String = entity_record.entity_id
		hostile_present = (
			_world_state.is_entity_alive(entity_id)
			and _world_state.is_entity_hostile(entity_id)
		)
	return _PoiController.get_camp_access(hex_data, hostile_present)


func _find_inventory_item_by_instance_id(instance_id: String) -> ItemData:
	return MacroInventoryBridge.find_item_by_instance_id(
		player_token.get_humanoid_core().inventory,
		instance_id
	)


func _inventory_has_any_item_id(item_ids: Array) -> bool:
	return MacroInventoryBridge.has_any_item_id(
		player_token.get_humanoid_core().inventory,
		item_ids
	)

func _inventory_has_any_tag(tags: Array) -> bool:
	return MacroInventoryBridge.has_any_tag(
		player_token.get_humanoid_core().inventory,
		tags
	)

func _inventory_has_any_role(roles: Array) -> bool:
	return MacroInventoryBridge.has_any_role(
		player_token.get_humanoid_core().inventory,
		roles
	)


func _hex_label(coords: Vector2i, hex_data: MacroHexData) -> String:
	var region := _SnapshotBuilder.enum_key(
		GameEnums.MacroRegion.keys(),
		int(hex_data.region)
	)
	return "HEX %d,%d // %s" % [coords.x, coords.y, region]

func _show_interaction_result(title: String, message: String) -> void:
	if exploration_window and exploration_window.is_open():
		exploration_window.show_result(title, message)
	else:
		_show_collision_result(title, message, "")


func _show_collision_result(
	title: String,
	message: String,
	resume_mode: String
) -> void:
	if resume_mode.is_empty():
		_pending_interaction.erase("resume_after_result")
	else:
		_pending_interaction["resume_after_result"] = resume_mode
	if macro_hud == null:
		close_macro_interaction()
		return
	macro_hud.show_event_result({
		"title": title,
		"body": message,
		"effects": {},
		"resume": resume_mode,
	})

func _apply_poi_session_selections(
	coords: Vector2i,
	hex_data: MacroHexData,
	selected_item_ids: Array
) -> void:
	var inventory := player_token.get_humanoid_core().inventory
	_PoiController.apply_sleep_gear_selection(
		hex_data,
		selected_item_ids,
		Callable(self, "_find_inventory_item_by_instance_id")
	)
	var trap_outcome := _PoiController.apply_trap_install(
		hex_data,
		selected_item_ids,
		Callable(self, "_find_inventory_item_by_instance_id"),
		Callable(inventory, "remove_item_by_instance_id")
	)
	var gear_outcome := _PoiController.apply_camp_gear_selection(
		hex_data,
		coords,
		selected_item_ids,
		Callable(self, "_find_inventory_item_by_instance_id"),
		Callable(inventory, "remove_item_by_instance_id"),
		Callable(inventory, "add_to_backpack")
	)
	for item_state in gear_outcome.get("ground_restore", []):
		_world_state.add_ground_items(coords, [item_state])
	for item_state in trap_outcome.get("ground_restore", []):
		_world_state.add_ground_items(coords, [item_state])
	_world_state.set_hex_record(coords, hex_data.to_state())
	_world_state.update_player_runtime(
		player_token.get_humanoid_core().capture_runtime_state().to_dict(),
		coords
	)

func _build_trap_context_from_hex(hex_data: MacroHexData) -> Dictionary:
	if hex_data.camp_traps.is_empty():
		return {}
	var trap_state: Dictionary = hex_data.camp_traps[0]
	return {
		"lane_index": int(trap_state.get("lane_index", 8)),
		"trap_item_id": str(trap_state.get("item_id", "trap_makeshift")),
		"trap_instance_id": str(trap_state.get("instance_id", "")),
		"trigger_on_entry": true,
		"trap_damage": float(trap_state.get("trap_damage", 2.5)),
	}

func _consume_hex_trap_for_combat(coords: Vector2i) -> Dictionary:
	var hex_data := world_generator.get_hex_at(coords)
	var trap_context := _build_trap_context_from_hex(hex_data)
	if trap_context.is_empty():
		return {}
	hex_data.camp_traps.clear()
	hex_data.rest_in_progress = false
	_world_state.set_hex_record(coords, hex_data.to_state())
	return trap_context

func _format_world_time() -> String:
	var snapshot := _world_state.get_world_time_snapshot()
	return "Day %d, %02d:%02d" % [
		snapshot.get("day", 1),
		snapshot.get("hour", 0),
		snapshot.get("minute", 0),
	]


func _emit_inventory_item_used(result: Dictionary) -> void:
	if not result.has("item_used_category"):
		return
	var bus := get_node_or_null("/root/GameEventBus")
	if bus and bus.has_method("emit_item_used"):
		bus.emit_item_used(
			player_token.get_humanoid_core(),
			result.get("item_used_category", GameEnums.ItemCategory.MISC)
		)


func unload_enemy_token(coords: Vector2i) -> void:
	_get_proximity_director().unload_enemy_token(coords)

func load_enemy_token(entity_id: String) -> MacroEnemy:
	return _get_proximity_director().load_enemy_token(entity_id)

func _bind_enemy_inspect_signals(enemy: MacroEnemy) -> void:
	if enemy == null:
		return
	if not enemy.entity_hovered.is_connected(_on_enemy_entity_hovered):
		enemy.entity_hovered.connect(_on_enemy_entity_hovered)
	if not enemy.entity_unhovered.is_connected(_on_enemy_entity_unhovered):
		enemy.entity_unhovered.connect(_on_enemy_entity_unhovered)


func _on_enemy_entity_hovered(entity_id: String, _coords: Vector2i) -> void:
	if macro_hud == null or entity_id.is_empty():
		return
	if macro_hud.get_exploration_stage() != null and macro_hud.get_exploration_stage().is_open():
		return
	var record := _world_state.get_entity(entity_id) if _world_state else null
	if record == null:
		return
	macro_hud.show_entity_inspect(
		MacroEntityCollisionResolver.build_opponent_summary(record)
	)


func _on_enemy_entity_unhovered(_entity_id: String) -> void:
	if macro_hud:
		macro_hud.hide_entity_inspect()

func add_ground_item_states(coords: Vector2i, item_states: Array) -> void:
	_world_state.add_ground_items(coords, item_states)

func retreat_player_from_combat(
	collision_coords: Vector2i,
	approach_from: Vector2i,
	initiator_id: String = "player"
) -> bool:
	var collision_delta := collision_coords - approach_from
	if not HEX_NEIGHBORS.has(collision_delta):
		_last_macro_event = "Escape resolved, but no clean collision vector was found."
		_refresh_world_hud()
		return false

	var retreat_coords := approach_from
	if initiator_id != "player":
		retreat_coords = collision_coords + collision_delta

	var current_coords := player_token.current_hex_coords
	if retreat_coords == current_coords:
		_last_macro_event = "Escaped combat and held position at HEX %d,%d." % [
			current_coords.x,
			current_coords.y,
		]
		_refresh_world_hud()
		return true
	if _hex_distance(current_coords, retreat_coords) != 1:
		_last_macro_event = "Escape route was invalid from HEX %d,%d." % [
			current_coords.x,
			current_coords.y,
		]
		_refresh_world_hud()
		return false

	var retreat_hex := world_generator.get_hex_at(retreat_coords)
	if not retreat_hex.is_passable():
		_last_macro_event = "Escape route blocked at HEX %d,%d." % [
			retreat_coords.x,
			retreat_coords.y,
		]
		_refresh_world_hud()
		return false

	var occupying_record := _world_state.get_entity_at(retreat_coords)
	if (
		occupying_record != null
		and _world_state.is_entity_alive(occupying_record.entity_id)
	):
		_last_macro_event = "Escape route occupied at HEX %d,%d." % [
			retreat_coords.x,
			retreat_coords.y,
		]
		_refresh_world_hud()
		return false

	player_token.walk_to_hex(
		retreat_coords,
		map_visualizer.map_to_local(retreat_coords)
	)
	_select_hex_for_hud(retreat_coords)
	_world_state.update_player_runtime(
		player_token.get_humanoid_core().capture_runtime_state().to_dict(),
		retreat_coords
	)
	_mark_hex_explored(retreat_coords, retreat_hex)
	_refresh_map_visuals(retreat_coords, false)
	refresh_proximity(retreat_coords)
	_last_macro_event = "Escaped combat; fell back to HEX %d,%d." % [
		retreat_coords.x,
		retreat_coords.y,
	]
	_refresh_world_hud()
	return true

func refresh_proximity(center_coords: Vector2i) -> void:
	_get_proximity_director().refresh_proximity(center_coords)

func _force_project_npc_token(record: EntityRecord) -> MacroEnemy:
	return _get_proximity_director().force_project_npc_token(record)

func _advance_npc_macro_turn(allow_during_interaction: bool = false) -> bool:
	if _pending_interaction.is_empty() == false and not allow_during_interaction:
		return false
	_macro_turn_index += 1
	var player_coords := player_token.current_hex_coords
	_macro_log(
		"NPC macro turn %d begins (player @%s, %d total records)."
		% [
			_macro_turn_index,
			str(player_coords),
			_world_state.get_all_entity_records().size(),
		]
	)
	var plan := _NpcSimulator.plan_macro_turn(
		_world_state.get_all_entity_records(),
		player_coords,
		_world_state.world_seed,
		_macro_turn_index,
		npc_evaluation_radius,
		npc_wander_chance,
		npc_pursuit_radius,
		craven_pursuit_radius,
		Callable(self, "_npc_get_hex_at"),
		Callable(self, "_npc_has_ground_items"),
		Callable(self, "_npc_get_occupying_entity_id"),
	)
	var moved_count := 0
	for move in plan.get("moves", []):
		var record := _world_state.get_entity(str(move.get("entity_id", "")))
		if record == null:
			continue
		if _move_npc_record(record, move.get("to", record.coords)):
			moved_count += 1

	refresh_proximity(player_coords)
	var collision: Dictionary = plan.get("collision", {})
	if not collision.is_empty():
		_last_macro_event = "A hostile closes on your hex."
		_macro_log("NPC macro turn %d ended in a collision." % _macro_turn_index)
		begin_entity_collision(
			str(collision.get("enemy_id", "")),
			collision.get("coords", player_coords),
			collision.get("approach_from", player_coords)
		)
		return true
	if moved_count > 0:
		_last_macro_event = "NPC turn %d: %d token(s) repositioned." % [
			_macro_turn_index,
			moved_count,
		]
	else:
		_last_macro_event = "NPC turn %d: no nearby token committed." % _macro_turn_index
	_macro_log(
		"NPC macro turn %d ended: %d moved." % [_macro_turn_index, moved_count]
	)
	_refresh_world_hud()
	return false

func _evaluate_npc_step(
	record: EntityRecord,
	player_coords: Vector2i
) -> Vector2i:
	return _NpcSimulator.evaluate_npc_step(
		record,
		player_coords,
		_world_state.world_seed,
		_macro_turn_index,
		npc_wander_chance,
		npc_pursuit_radius,
		craven_pursuit_radius,
		Callable(self, "_npc_get_hex_at"),
		Callable(self, "_npc_has_ground_items"),
		Callable(self, "_npc_get_occupying_entity_id"),
	)


func _ensure_npc_purpose(record: EntityRecord) -> String:
	return _NpcSimulator.ensure_npc_purpose(record)


func _initialize_npc_runtime(record: EntityRecord) -> void:
	_NpcSimulator.initialize_npc_runtime(
		record,
		_world_state.world_seed,
		_macro_turn_index,
		player_token.current_hex_coords,
		Callable(self, "_npc_get_hex_at"),
		Callable(self, "_npc_has_ground_items"),
	)

func _move_npc_record(
	record: EntityRecord,
	target_coords: Vector2i
) -> bool:
	var old_coords := record.coords
	if not _world_state.move_entity(record.entity_id, target_coords):
		return false
	var token: MacroEnemy = active_enemies.get(old_coords, null)
	if token != null:
		active_enemies.erase(old_coords)
		# Defensive: if some stale token already occupies the destination key,
		# discard it before relocating so we never strand or double-count tokens.
		if active_enemies.has(target_coords) and active_enemies[target_coords] != token:
			unload_enemy_token(target_coords)
		active_enemies[target_coords] = token
		token.walk_to_hex(target_coords, map_visualizer.map_to_local(target_coords))
		_apply_enemy_visibility(token, target_coords)
		_macro_log(
			"Token %s moved %s -> %s."
			% [record.entity_id, str(old_coords), str(target_coords)]
		)
	return true

func _ensure_encounter_records(center_coords: Vector2i) -> void:
	for outcome in _NpcSimulator.plan_encounter_refresh(
		center_coords,
		_world_state.world_seed,
		generation_radius,
		max_new_encounters_per_refresh,
		safe_start_radius,
		base_enemy_spawn_chance,
		fog_gated_spawning,
		Callable(self, "_is_hex_visible"),
		Callable(self, "_npc_get_hex_at"),
	):
		var coords: Vector2i = outcome.get("coords", Vector2i.ZERO)
		var hex_data := world_generator.get_hex_at(coords)
		if bool(outcome.get("mark_evaluated", false)):
			hex_data.encounter_evaluated = true
		var spawn: Variant = outcome.get("spawn")
		if spawn is Dictionary and not spawn.is_empty():
			var spawn_info: Dictionary = spawn
			var faction: GameEnums.Faction = spawn_info.get(
				"faction",
				GameEnums.Faction.SCAVENGER_CELL
			)
			var record := mob_spawner.generate_mob_record(
				coords,
				faction,
				int(spawn_info.get("difficulty", 0)),
				str(spawn_info.get("deterministic_key", ""))
			)
			_initialize_npc_runtime(record)
			var entity_id := _world_state.register_entity(record)
			hex_data.encounter_entity_id = entity_id
			_macro_log(
				"Seeded encounter %s (%s) @%s [chance %.3f, out-of-sight fog]."
				% [
					entity_id,
					GameEnums.Faction.keys()[faction],
					str(coords),
					float(spawn_info.get("spawn_chance", 0.0)),
				]
			)
		_world_state.set_hex_record(coords, hex_data.to_state())


func _coords_in_radius(center_coords: Vector2i, radius: int) -> Array[Vector2i]:
	return _NpcSimulator.coords_in_radius(center_coords, radius)


func _hex_distance(from_coords: Vector2i, to_coords: Vector2i) -> int:
	return _NpcSimulator.hex_distance(from_coords, to_coords)


func _encounter_key(coords: Vector2i) -> String:
	return _NpcSimulator.encounter_key(_world_state.world_seed, coords)

func _spawn_enemy_token_from_record(record: EntityRecord) -> MacroEnemy:
	return _get_proximity_director().spawn_from_record(record)
