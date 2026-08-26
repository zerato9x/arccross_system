extends Node2D
class_name MacroGameManager

# Cross-system handoff contains only IDs, primitives, and GameEnums values.
signal combat_requested(request: Dictionary)
signal save_requested
signal load_requested
signal core_activated
signal campaign_node_changed(node_id: String)
signal campaign_nodes_unlocked(node_ids: Array)
signal work_surface_changed(surface: int)

enum WorkSurface {
	NONE,
	INVENTORY,
	HEALTH,
	HERE,
	HEX_MAP,
	SETTINGS,
	SAVE_LOAD,
	NODE_MAP,
	EVENT,
}

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
## Shared world-action application kernel. Legacy static callers remain valid,
## while player and NPC orchestration now resolve through the same instance.
var _world_action_kernel := WorldActionKernel.new()
var _world_action_coordinator := _WorldActionCoordinator.new()
var _world_action_execution_service := _WorldActionExecutionService.new()
var _receipt_application_service := _ReceiptApplicationService.new()
var _world_bootstrap_service := _BootstrapService.new()
var _active_zone_service := _ActiveZoneService.new()
var _world_bootstrapped := false
var _movement_service := MacroMovementService.new()
var _turn_resolution := _TurnResolutionState.new()
var _visibility_service := MacroVisibilityService.new()
var _time_rules_service := MacroTimeRulesService.new()
var _snapshot_facade := MacroSnapshotFacade.new()
var _npc_runtime_service := _NpcRuntimeService.new()
var _npc_turn_service := _NpcTurnService.new()
var _npc_perception_service := _NpcPerceptionService.new()
var _npc_work_service := _NpcWorkService.new()
var _location_snapshot_service := _LocationSnapshotService.new()
var _persistence_bridge := _PersistenceBridge.new()
var _shelter_runtime_service := _ShelterRuntimeService.new()
var _campaign_progression_service := _CampaignProgressionService.new()
var _combat_encounter_service := _CombatEncounterService.new()
var _search_resource_service := _SearchResourceService.new()
var _search_action_service := _SearchActionService.new()
var _camp_action_service := _CampActionService.new()
var _campaign_content_service := _CampaignContentService.new()
var _population_service := _PopulationService.new()
var _inventory_action_service := MacroInventoryActionService.new()
var _poi_selection_action_service := _PoiSelectionActionService.new()
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
var _pending_player_step: Dictionary = {}
var _travel_route: Array[Vector2i] = []
## Compatibility alias for callers that still read the movement projection.
## The lifecycle now belongs to the explicit turn-resolution state object.
var _movement_state: Dictionary:
	get:
		return _turn_resolution.data
	set(value):
		_turn_resolution.replace_state(value)
var _travel_route_total_steps := 0
var _travel_completed_steps := 0
var _route_cancel_requested := false
var _movement_debug_request_usec := 0
var _resolving_player_world_turn := false

const HEX_NEIGHBORS = [
	Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1), 
	Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1)
]
const _SnapshotBuilder := preload("res://WorldCore/MacroSnapshotBuilder.gd")
const _TurnResolutionState := preload(
	"res://WorldCore/MacroTurnResolutionState.gd"
)
const _PoiController := preload("res://WorldCore/MacroPoiController.gd")
const _HexPresentation := preload("res://PresentationCore/HexPresentationDescriptor.gd")
const _NpcSimulator := preload("res://WorldCore/MacroNpcSimulator.gd")
const _WorldActionCoordinator := preload("res://WorldCore/MacroWorldActionCoordinator.gd")
const _WorldActionExecutionService := preload(
	"res://WorldCore/MacroWorldActionExecutionService.gd"
)
const _ReceiptApplicationService := preload(
	"res://WorldCore/MacroReceiptApplicationService.gd"
)
const _BootstrapService := preload("res://WorldCore/MacroWorldBootstrapService.gd")
const _ActiveZoneService := preload("res://WorldCore/MacroActiveZoneService.gd")
const _NpcRuntimeService := preload("res://WorldCore/MacroNpcRuntimeService.gd")
const _NpcTurnService := preload("res://WorldCore/MacroNpcTurnService.gd")
const _NpcPerceptionService := preload(
	"res://WorldCore/MacroNpcPerceptionService.gd"
)
const _NpcWorkService := preload("res://WorldCore/MacroNpcWorkService.gd")
const _LocationSnapshotService := preload(
	"res://WorldCore/MacroLocationSnapshotService.gd"
)
const _PersistenceBridge := preload("res://WorldCore/MacroPersistenceBridge.gd")
const _CampaignProgressionService := preload(
	"res://WorldCore/MacroCampaignProgressionService.gd"
)
const _CombatEncounterService := preload(
	"res://WorldCore/MacroCombatEncounterService.gd"
)
const _SearchResourceService := preload(
	"res://WorldCore/MacroSearchResourceService.gd"
)
const _SearchActionService := preload(
	"res://WorldCore/MacroSearchActionService.gd"
)
const _CampActionService := preload(
	"res://WorldCore/MacroCampActionService.gd"
)
const _PoiSelectionActionService := preload(
	"res://WorldCore/MacroPoiSelectionActionService.gd"
)
const _CampaignContentService := preload(
	"res://WorldCore/MacroCampaignContentService.gd"
)
const _ShelterRuntimeService := preload(
	"res://WorldCore/MacroShelterRuntimeService.gd"
)
const _PopulationService := preload(
	"res://WorldCore/MacroCampaignPopulationService.gd"
)
const _ShelterProfile: ShelterProgressionProfile = preload(
	"res://WorldCore/default_shelter_progression_profile.tres"
)
const _PlotDirector := preload("res://WorldCore/NpcPlotDirector.gd")
const _NODE_MAP_INVENTORY_LAYER := 36
const _NODE_MAP_OVERLAY_LAYER := 36

func configure_services(
	world_state: RuntimeStateStore,
	loot_catalog: Node
) -> void:
	_world_state = world_state
	_loot_catalog = loot_catalog
	_world_action_coordinator.configure(_world_action_kernel)
	_configure_extracted_world_services()
	if world_generator:
		world_generator.configure_services(world_state)
	_ensure_campaign()
	_connect_world_time_lighting()
	if is_node_ready() and not _world_bootstrapped:
		_bootstrap_world()


func _configure_extracted_world_services() -> void:
	_movement_service.configure(
		world_generator,
		Callable(self, "_is_hex_travel_known")
	)
	_shelter_runtime_service.configure(
		_world_state,
		world_generator,
		_meta_progress,
		_ShelterProfile
	)
	_active_zone_service.configure(
		_world_state,
		world_generator,
		player_token,
		map_visualizer
	)
	_combat_encounter_service.configure(
		_world_state,
		world_generator,
		map_visualizer
	)
	_search_resource_service.configure(_world_state)
	_visibility_service.configure(_world_state, world_generator, vision_radius)
	_time_rules_service.configure()
	_inventory_action_service.configure(
		_world_state,
		_world_action_coordinator,
		_time_rules_service,
		Callable(self, "_commit_world_action_receipt")
	)
	_poi_selection_action_service.configure(
		_world_state,
		_world_action_coordinator,
		Callable(self, "_commit_world_action_receipt")
	)
	_search_action_service.configure(
		_world_state,
		world_generator,
		_loot_catalog,
		{
			"get_loot_profile": Callable(self, "_get_loot_profile"),
			"find_inventory_item": Callable(
				self,
				"_find_inventory_item_by_instance_id"
			),
			"resolve_shared_work": Callable(self, "_resolve_shared_work_action"),
			"method_id_for_item_ids": Callable(self, "_method_id_for_item_ids"),
			"search_minutes": Callable(_time_rules_service, "search_minutes"),
			"world_object_record_at": Callable(self, "_world_object_record_at"),
			"inventory_has_any_item_id": Callable(
				self,
				"_inventory_has_any_item_id"
			),
			"inventory_has_any_tag": Callable(self, "_inventory_has_any_tag"),
			"inventory_has_any_role": Callable(self, "_inventory_has_any_role"),
			"build_depletion": Callable(_search_resource_service, "build_depletion"),
			"commit_search_transaction": Callable(self, "_commit_search_transaction"),
			"apply_campaign_trigger": Callable(
				self,
				"apply_campaign_discovery_trigger"
			),
			"refresh_hud": Callable(self, "_refresh_world_hud"),
			"format_world_time": Callable(self, "_format_world_time"),
			"set_event": Callable(self, "_set_macro_event"),
			"last_event": Callable(self, "_last_macro_event_text"),
			"notify_noise": Callable(self, "_notify_npcs_of_noise"),
			"advance_world": Callable(self, "advance_macro_world"),
			"has_pending_collision": Callable(self, "_has_pending_entity_collision"),
			"is_exploration_open": Callable(
				self,
				"_is_exploration_window_open"
			),
			"present_poi_session": Callable(self, "_present_poi_session"),
			"refresh_exploration_ground": Callable(
				self,
				"_refresh_exploration_ground"
			),
			"spawn_intruder": Callable(self, "_spawn_search_intruder"),
			"show_result": Callable(self, "_show_interaction_result"),
		}
	)
	_camp_action_service.configure(
		_world_state,
		{
			"find_inventory_item": Callable(
				self,
				"_find_inventory_item_by_instance_id"
			),
			"commit_camp_cycle": Callable(self, "_commit_camp_cycle"),
			"camp_minutes": Callable(_time_rules_service, "camp_minutes"),
			"advance_world": Callable(self, "advance_macro_world"),
			"has_pending_collision": Callable(self, "_has_pending_entity_collision"),
			"refresh_hud": Callable(self, "_refresh_world_hud"),
			"spawn_intruder": Callable(self, "_spawn_search_intruder"),
			"set_event": Callable(self, "_set_macro_event"),
			"show_result": Callable(self, "_show_interaction_result"),
			"format_world_time": Callable(self, "_format_world_time"),
		}
	)
	_world_action_execution_service.configure(
		_world_state,
		world_generator,
		_world_action_coordinator,
		_time_rules_service,
		{
			"actor_context": Callable(self, "_world_actor_context"),
			"commit_receipt": Callable(self, "_commit_world_action_receipt"),
			"consume_repair_material": Callable(
				self,
				"_consume_player_repair_material"
			),
			"set_event": Callable(self, "_set_macro_event"),
		}
	)
	_npc_turn_service.configure(_world_state)
	_npc_work_service.configure(
		_world_state,
		world_generator,
		_world_action_coordinator,
		_loot_catalog
	)
	_campaign_content_service.configure(_world_state, _loot_catalog)
	_location_snapshot_service.configure(
		player_token,
		_world_state,
		world_generator,
		map_visualizer,
		{
			"build_hex_descriptor": Callable(self, "_build_hex_descriptor"),
			"build_travel_route": Callable(self, "_build_travel_route"),
			"camp_access": Callable(self, "_get_camp_access"),
			"hex_label": Callable(self, "_hex_label"),
			"inventory_has_item_id": Callable(self, "_inventory_has_any_item_id"),
			"inventory_has_tag": Callable(self, "_inventory_has_any_tag"),
			"inventory_has_role": Callable(self, "_inventory_has_any_role"),
			"enrich_session": Callable(self, "_enrich_location_session"),
			"is_movement_active": Callable(self, "_is_player_movement_active"),
			"is_hex_travel_known": Callable(self, "_is_hex_travel_known"),
		}
	)
	_receipt_application_service.configure(
		_world_state,
		world_generator,
		player_token,
		Callable(self, "_notify_npcs_of_signal"),
		Callable(self, "_apply_player_tool_wear"),
		Callable(self, "_emit_world_action_presentation"),
		Callable(self, "_refresh_world_hud_after_receipt"),
		Callable(self, "_movement_debug_mark")
	)
	_visible_hexes = _visibility_service.visible_hexes
	_configure_snapshot_facade()


func _configure_snapshot_facade() -> void:
	_snapshot_facade.configure(
		player_token,
		_world_state,
		world_generator,
		campaign,
		_selected_hex_coords,
		_visible_hexes,
		active_enemies,
		_last_macro_event,
		_macro_turn_index,
		{
			"can_offer_equip": Callable(self, "_can_offer_equip"),
			"allowed_equipment_slots": Callable(self, "_allowed_equipment_slots"),
			"ensure_npc_purpose": Callable(self, "_ensure_npc_purpose"),
			"hex_distance": Callable(self, "_hex_distance"),
			"hex_label": Callable(self, "_hex_label"),
			"next_incomplete_nodes": Callable(self, "_next_incomplete_available_nodes"),
			"pending_exit_direction": int(_pending_exit_direction),
			"movement_snapshot": Callable(self, "_movement_snapshot"),
			"is_movement_active": Callable(self, "_is_player_movement_active"),
			"is_hex_travel_known": Callable(self, "_is_hex_travel_known"),
		}
	)


func _connect_world_time_lighting() -> void:
	if _world_state == null:
		return
	if not _world_state.world_time_advanced.is_connected(_on_world_time_advanced_lighting):
		_world_state.world_time_advanced.connect(_on_world_time_advanced_lighting)
	if not _world_state.world_time_advanced.is_connected(_on_world_time_advanced_npcs):
		_world_state.world_time_advanced.connect(_on_world_time_advanced_npcs)
	_apply_world_lighting_from_minutes(_world_state.world_time_minutes)


func _on_world_time_advanced_lighting(
	_previous: int,
	current: int,
	_elapsed: int
) -> void:
	_apply_world_lighting_from_minutes(current)


func _on_world_time_advanced_npcs(
	_previous_minutes: int,
	current_minutes: int,
	elapsed_minutes: int
) -> void:
	_npc_runtime_service.advance(_world_state, current_minutes, elapsed_minutes)
	return


func _reconcile_active_node_elapsed() -> void:
	## A dormant node does not invent a pre-arrival story, but actors and
	## evidence that already existed there still age deterministically while the
	## player was elsewhere. This is the coarse boundary before full hourly AI
	## planning is introduced.
	if _world_state == null:
		return
	var current := _world_state.world_time_minutes
	_npc_runtime_service.reconcile_dormant(_world_state, current)
	return


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
	_campaign_progression_service.configure(
		campaign,
		{
			"search_minutes": Callable(_time_rules_service, "search_minutes"),
			"advance_time": Callable(self, "_advance_survival_time"),
			"persist_hex": Callable(self, "_persist_campaign_hex"),
			"apply_trigger": Callable(self, "apply_campaign_discovery_trigger"),
			"close_interaction": Callable(self, "close_macro_interaction"),
			"set_event": Callable(self, "_set_macro_event"),
			"refresh_hud": Callable(self, "_refresh_world_hud"),
			"emit_core_activated": Callable(self, "_emit_core_activated"),
			"show_result": Callable(self, "_show_interaction_result"),
		}
	)


func get_available_nodes() -> Array[String]:
	_ensure_campaign()
	return _campaign_progression_service.available_nodes()


func enter_campaign_node(
	node_id: String,
	exit_direction: int = GameEnums.MacroTravelDirection.NONE
) -> bool:
	_ensure_campaign()
	if not _campaign_progression_service.can_enter(node_id, exit_direction):
		if (
			node_id == MacroGraphGenerator.CENTRAL_ID
			and campaign.active_node_id != MacroGraphGenerator.CENTRAL_ID
		):
			_last_macro_event = MacroEntityCollisionResolver.central_reentry_refused_line()
			_macro_log(_last_macro_event)
		return false
	# Keep player inventory; unload tokens before zone swap.
	_unload_all_enemy_tokens()
	var ok := _campaign_progression_service.enter(node_id, exit_direction)
	if not ok:
		return false
	_pending_exit_direction = GameEnums.MacroTravelDirection.NONE
	_apply_active_zone_to_world()
	_reconcile_active_node_elapsed()
	_ensure_central_rim_guards()
	_ensure_route_one_population()
	_ensure_route_two_shelter_ecology()
	_ensure_meta_component_source()
	return true


func mark_node_completed(node_id: String) -> void:
	_ensure_campaign()
	_campaign_progression_service.mark_completed(node_id)


func evaluate_unlocks(player_progress: Dictionary = {}) -> Array[String]:
	_ensure_campaign()
	return _campaign_progression_service.evaluate_unlocks(player_progress)


func apply_campaign_discovery_trigger(trigger_id: String) -> PackedStringArray:
	_ensure_campaign()
	var revealed := _campaign_progression_service.apply_discovery_trigger(trigger_id)
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
	return _campaign_progression_service.debug_map()


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
	if _is_player_movement_active():
		return
	_close_ordinary_work_surfaces(WorkSurface.NODE_MAP)
	_pending_exit_direction = GameEnums.MacroTravelDirection.NONE
	_open_node_map_with_context()


func _open_node_map_with_context() -> void:
	if _is_player_movement_active():
		return
	_close_ordinary_work_surfaces(WorkSurface.NODE_MAP)
	_ensure_campaign()
	_ensure_node_map_system()
	if node_map_system == null:
		return
	node_map_system.call("open", build_node_map_ui_snapshot())
	_emit_work_surface_changed()


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


func get_active_work_surface() -> int:
	if is_node_map_open():
		return WorkSurface.NODE_MAP
	if (
		macro_hud != null
		and macro_hud.is_event_open()
	) or (
		_pending_interaction.get("type", GameEnums.MacroInteractionType.NONE)
		in [
			GameEnums.MacroInteractionType.MACRO_EVENT,
			GameEnums.MacroInteractionType.ENTITY_COLLISION,
		]
	):
		return WorkSurface.EVENT
	if inventory_panel != null and inventory_panel.is_open():
		return WorkSurface.INVENTORY
	if macro_hud == null:
		return WorkSurface.NONE
	match macro_hud.get_active_primary_surface():
		&"health":
			return WorkSurface.HEALTH
		&"here":
			return WorkSurface.HERE
		&"hex_map":
			return WorkSurface.HEX_MAP
		&"settings":
			return WorkSurface.SETTINGS
		&"save_load":
			return WorkSurface.SAVE_LOAD
	return WorkSurface.NONE


func blocks_world_commands() -> bool:
	return (
		get_active_work_surface() != WorkSurface.NONE
		or not _pending_interaction.is_empty()
		or _turn_resolution.is_active()
		or not _pending_player_step.is_empty()
	)


func _is_player_movement_active() -> bool:
	return _turn_resolution.is_active() or not _pending_player_step.is_empty()


func _movement_snapshot() -> Dictionary:
	var snapshot := _turn_resolution.snapshot()
	if not bool(snapshot.get("active", false)) and player_token != null:
		snapshot["from_coords"] = player_token.current_hex_coords
		snapshot["current_coords"] = player_token.current_hex_coords
	return snapshot


func turn_resolution_snapshot() -> Dictionary:
	return _movement_snapshot()


func close_active_work_surface() -> bool:
	if is_node_map_open():
		if _node_map_medical != null and _node_map_medical.visible:
			_close_node_map_medical()
			return true
		if (
			inventory_panel != null
			and inventory_panel.is_open()
			and _inventory_home_layer != null
			and _inventory_home_layer.layer == _NODE_MAP_INVENTORY_LAYER
		):
			inventory_panel.close_top_surface()
			return true
		close_node_map()
		return true
	if macro_hud != null and macro_hud.is_event_open():
		close_macro_interaction()
		return true
	if inventory_panel != null and inventory_panel.is_open():
		inventory_panel.close_top_surface()
		return true
	if macro_hud != null and macro_hud.close_active_primary_surface():
		return true
	return false


func open_hex_world_map() -> void:
	if _is_player_movement_active() or macro_hud == null or macro_hud.is_event_open():
		return
	_close_ordinary_work_surfaces(WorkSurface.HEX_MAP)
	macro_hud.open_hex_world_map()
	_emit_work_surface_changed()


func _on_hex_world_map_selected(coords: Vector2i) -> void:
	_select_hex_for_hud(coords, true)


func _on_hex_world_map_travel_requested(coords: Vector2i) -> void:
	if _is_player_movement_active():
		return
	_selected_hex_coords = coords
	if macro_hud != null:
		macro_hud.close_hex_world_map()
	_try_travel_to_selected_hex()


func _on_hud_primary_surface_changed(_surface_id: StringName) -> void:
	_emit_work_surface_changed()


func _emit_work_surface_changed() -> void:
	work_surface_changed.emit(int(get_active_work_surface()))


func _close_ordinary_work_surfaces(except: int = WorkSurface.NONE) -> void:
	if except != WorkSurface.NODE_MAP and is_node_map_open():
		close_node_map()
	if (
		except != WorkSurface.INVENTORY
		and inventory_panel != null
		and inventory_panel.is_open()
	):
		inventory_panel.close_panel(false)
	if macro_hud != null:
		var hud_except := &""
		match except:
			WorkSurface.HEALTH:
				hud_except = &"health"
			WorkSurface.HERE:
				hud_except = &"here"
			WorkSurface.HEX_MAP:
				hud_except = &"hex_map"
			WorkSurface.SETTINGS:
				hud_except = &"settings"
			WorkSurface.SAVE_LOAD:
				hud_except = &"save_load"
		macro_hud.close_primary_surfaces(hud_except)
	_emit_work_surface_changed()


## Full graph + player presentation for the fullscreen Node Map System window.
func build_node_map_ui_snapshot() -> Dictionary:
	_ensure_campaign()
	var hud_snapshot: Dictionary = {}
	var inventory_snapshot: Dictionary = {}
	if player_token != null:
		hud_snapshot = _build_world_hud_snapshot()
		inventory_snapshot = _build_inventory_snapshot()
	var knowledge_catalog := get_node_or_null("/root/KnowledgeCatalog")
	if knowledge_catalog != null and _meta_progress != null:
		var known_entries: Array = []
		for entry_id in _meta_progress.get_codex_entry_ids():
			var descriptor: Dictionary = knowledge_catalog.get_entry_descriptor(str(entry_id))
			if not descriptor.is_empty():
				known_entries.append(descriptor)
		hud_snapshot["codex_entries"] = known_entries
	return MacroNodeMapSnapshot.build(
		campaign,
		int(_pending_exit_direction),
		hud_snapshot,
		inventory_snapshot
	)


func _on_node_map_closed() -> void:
	_close_node_map_overlays()
	_pending_exit_direction = GameEnums.MacroTravelDirection.NONE
	_emit_work_surface_changed()


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
	var activation := _active_zone_service.apply(campaign)
	if not bool(activation.get("applied", false)):
		return
	var start_coords: Vector2i = activation.get("start_coords", Vector2i.ZERO)
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
	var placed := _population_service.ensure_central_rim_guards(
		campaign,
		_world_state,
		world_generator,
		mob_spawner,
		active_enemies,
		player_token.current_hex_coords if player_token != null else Vector2i(9999, 9999),
		Callable(self, "_initialize_npc_runtime"),
		Callable(self, "_spawn_enemy_token_from_record"),
		Callable(self, "_macro_log")
	)
	if placed:
		_last_macro_event = "A posted pair in service kit holds the Central-facing rim."


func _ensure_route_one_population() -> void:
	_ensure_campaign()
	_population_service.ensure_route_one_population(
		campaign,
		_world_state,
		world_generator,
		mob_spawner,
		Callable(self, "_initialize_npc_runtime"),
		Callable(self, "_spawn_enemy_token_from_record")
	)


func _ensure_route_two_shelter_ecology() -> void:
	_population_service.ensure_shelter_ecology(
		campaign,
		_world_state,
		world_generator,
		mob_spawner,
		_ShelterProfile,
		Callable(self, "_initialize_npc_runtime"),
		Callable(self, "_spawn_enemy_token_from_record")
	)


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
	var result := _campaign_content_service.ensure_meta_component_source(
		campaign,
		_meta_progress,
		player_token
	)
	var status := str(result.get("status", "inactive"))
	if status == "missing_catalog":
		push_error("[MacroGameManager] Missing authored Meta quest item.")
		return
	if status == "seeded":
		_last_macro_event = "A North Core Regulator rests inside the Component Vault."


func get_runtime_state_store() -> RuntimeStateStore:
	return _world_state


func debug_step_player_to(target_coords: Vector2i) -> void:
	# Debug stepping is intentionally instantaneous; shipping movement uses the
	# arrival signal below so the domain never commits before the token arrives.
	_execute_player_step(target_coords, false)


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
	return _world_state.get_entity_id_at(coords)

func _ready() -> void:
	_ensure_macro_input_actions()
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
	_configure_extracted_world_services()

	if not world_generator or not map_visualizer or not player_token or not mob_spawner:
		push_error("The Puppet Master is missing its strings. Check the inspector.")
		return
	if not player_token.movement_arrived.is_connected(_on_player_movement_arrived):
		player_token.movement_arrived.connect(_on_player_movement_arrived)
	if not player_token.movement_started.is_connected(_on_player_movement_started):
		player_token.movement_started.connect(_on_player_movement_started)

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
		macro_hud.hex_preview_cancel_requested.connect(cancel_player_route)
		macro_hud.location_action_requested.connect(resolve_location_action)
		macro_hud.viewport_insets_changed.connect(_on_hud_viewport_insets_changed)
		macro_hud.medical_action_requested.connect(_on_medical_action_requested)
		macro_hud.event_choice_submitted.connect(_on_macro_hud_choice_submitted)
		macro_hud.event_closed.connect(_on_macro_hud_event_closed)
		macro_hud.node_map_requested.connect(open_node_map)
		macro_hud.hex_map_requested.connect(open_hex_world_map)
		macro_hud.minimap_hex_selected.connect(_select_hex_for_hud)
		macro_hud.hex_map_hex_selected.connect(_on_hex_world_map_selected)
		macro_hud.hex_map_travel_requested.connect(_on_hex_world_map_travel_requested)
		macro_hud.primary_surface_changed.connect(_on_hud_primary_surface_changed)
		if inventory_panel:
			macro_hud.get_inventory_corner_panel().inventory_ui = inventory_panel
		macro_hud.poi_action_submitted.connect(resolve_poi_action)
		macro_hud.poi_preview_requested.connect(preview_poi_action)
		macro_hud.exploration_inventory_action_requested.connect(
			resolve_inventory_action
		)
		macro_hud.exploration_interaction_closed.connect(close_macro_interaction)
		if exploration_window:
			macro_hud.bind_exploration_window(exploration_window)
	var player_inventory := player_token.get_humanoid_core().inventory
	player_inventory.inventory_error.connect(_on_player_inventory_error)
	player_inventory.items_spilled.connect(_on_player_items_spilled)
	if not _world_bootstrapped:
		_bootstrap_world()
	_connect_world_time_lighting()


func _ensure_macro_input_actions() -> void:
	_register_macro_input_action("macro_here", KEY_E)
	_register_macro_input_action("macro_travel", KEY_T)
	_register_macro_input_action("macro_inventory", KEY_I)
	_register_macro_input_action("macro_inventory", KEY_TAB)
	_register_macro_input_action("macro_health", KEY_H)
	_register_macro_input_action("macro_hex_map", KEY_M)
	_register_macro_input_action("macro_node_map", KEY_N)
	_register_macro_input_action("macro_node_map", KEY_P)
	_register_macro_input_action("macro_reset_map", KEY_F)
	_register_macro_input_action("macro_settings", KEY_O)
	_register_macro_input_action("macro_confirm", KEY_ENTER)
	_register_macro_input_action("macro_cancel", KEY_ESCAPE)
	_register_macro_input_action("macro_timing", KEY_SPACE)


func _register_macro_input_action(action: StringName, keycode: Key) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var key := InputEventKey.new()
	key.physical_keycode = keycode
	if not InputMap.action_has_event(action, key):
		InputMap.action_add_event(action, key)


func _process(_delta: float) -> void:
	_update_vision_soft_focus()


func _bootstrap_world() -> void:
	if _world_bootstrapped or _world_state == null:
		return
	_world_bootstrapped = true
	var startup := _world_bootstrap_service.select_startup(_world_state)
	match str(startup.get("mode", _BootstrapService.MODE_DEMO)):
		_BootstrapService.MODE_LOADED:
			_initialize_loaded_world()
		_BootstrapService.MODE_NEW_RUN:
			_initialize_new_run(startup.get("setup", {}))
		_:
			_initialize_demo()
	_refresh_world_hud()


func _build_bootstrap_callbacks() -> Dictionary:
	var callbacks := {
		"world_state": _world_state,
		"initialize_player": Callable(player_token, "initialize_new_definition"),
		"restore_player": Callable(player_token, "restore_runtime_record"),
		"capture_player_record": Callable(player_token, "capture_runtime_record"),
		"player_definition": Callable(self, "_bootstrap_player_definition"),
		"ensure_campaign": Callable(self, "_ensure_campaign"),
		"configure_player_capabilities": Callable(
			self,
			"_configure_campaign_player_capabilities"
		),
		"begin_campaign": Callable(self, "_bootstrap_begin_campaign"),
		"load_campaign": Callable(self, "_bootstrap_load_campaign"),
		"enter_initial_node": Callable(self, "_bootstrap_enter_initial_node"),
		"enter_campaign_node": Callable(self, "enter_campaign_node"),
		"configure_world": Callable(self, "_bootstrap_configure_world"),
		"set_player_record": Callable(_world_state, "set_player_record"),
		"unload_enemy_tokens": Callable(self, "_unload_all_enemy_tokens"),
		"reset_pending_exit": Callable(self, "_bootstrap_reset_pending_exit"),
		"apply_active_zone": Callable(self, "_apply_active_zone_to_world"),
		"ensure_central_rim_guards": Callable(self, "_ensure_central_rim_guards"),
		"ensure_route_one_population": Callable(self, "_ensure_route_one_population"),
		"ensure_shelter_ecology": Callable(self, "_ensure_route_two_shelter_ecology"),
		"ensure_meta_component_source": Callable(self, "_ensure_meta_component_source"),
		"is_in_zone_bounds": Callable(world_generator, "is_in_zone_bounds"),
		"restore_loaded_player_position": Callable(
			self,
			"_bootstrap_restore_loaded_player_position"
		),
		"current_player_coords": Callable(self, "_bootstrap_current_player_coords"),
		"log": Callable(self, "_macro_log"),
		"error": Callable(self, "_bootstrap_error"),
	}
	if _meta_progress != null and _meta_progress.has_method("apply_eviction_lock"):
		callbacks["apply_eviction_lock"] = Callable(
			_meta_progress,
			"apply_eviction_lock"
		)
	return callbacks


func _bootstrap_configure_world() -> void:
	if world_generator == null or _world_state == null:
		return
	world_generator.configure_services(_world_state)
	world_generator.enable_zone_bounds(MacroZoneGenerator.ZONE_RADIUS)


func _bootstrap_begin_campaign(seed: String) -> void:
	_ensure_campaign()
	campaign.begin_campaign(seed)


func _bootstrap_load_campaign(graph: Dictionary, active_node_id: String) -> void:
	_ensure_campaign()
	campaign.load_campaign(graph, active_node_id)


func _bootstrap_enter_initial_node(
	start_node_id: String,
	arrival_direction: int
) -> bool:
	_ensure_campaign()
	return campaign.enter_initial_node(start_node_id, arrival_direction)


func _bootstrap_player_definition() -> EntityDefinition:
	if player_token == null or player_token.get_humanoid_core() == null:
		return null
	return player_token.get_humanoid_core().definition


func _bootstrap_reset_pending_exit() -> void:
	_pending_exit_direction = GameEnums.MacroTravelDirection.NONE


func _bootstrap_restore_loaded_player_position(coords: Vector2i) -> void:
	if player_token == null or _world_state == null or map_visualizer == null:
		return
	player_token.snap_to_hex(coords, map_visualizer.map_to_local(coords))
	_select_hex_for_hud(coords)
	_refresh_map_visuals(coords, true)
	refresh_proximity(coords)


func _bootstrap_current_player_coords() -> Vector2i:
	if player_token == null:
		return Vector2i.ZERO
	return player_token.current_hex_coords


func _bootstrap_error(message: String) -> void:
	push_error(message)


func _initialize_new_run(setup: Dictionary) -> void:
	var result := _world_bootstrap_service.initialize_new_run(
		setup,
		_build_bootstrap_callbacks()
	)
	if result.has("last_event"):
		_last_macro_event = str(result.get("last_event", ""))

func _initialize_demo() -> void:
	_world_bootstrap_service.initialize_demo(_build_bootstrap_callbacks())


func _initialize_loaded_world() -> void:
	_world_bootstrap_service.initialize_loaded_world(_build_bootstrap_callbacks())


func _configure_campaign_player_capabilities(definition: EntityDefinition) -> void:
	if campaign == null or definition == null:
		return
	campaign.set_player_capabilities(IdentityCatalog.capability_ids_for_selection(
		definition.occupation_id,
		definition.trait_ids,
		definition.flaw_ids
	))

func synchronize_runtime_state() -> void:
	_persistence_bridge.synchronize(
		_world_state,
		player_token.capture_runtime_record(),
		player_token.current_hex_coords,
		world_generator.world_hex_cache,
		campaign,
		_meta_progress
	)
	flush_world_mutations()


func flush_world_mutations() -> void:
	_persistence_bridge.flush_world_mutations(
		_mutation_store,
		_world_state,
		campaign,
		world_generator
	)


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
	if _is_player_movement_active():
		if (
			event is InputEventKey
			and event.pressed
			and not event.echo
			and event.is_action_pressed("macro_cancel")
		):
			if str(_movement_state.get("kind", "travel")) == "travel":
				cancel_player_route()
		elif (
			event is InputEventMouseButton
			and event.pressed
			and event.button_index == MOUSE_BUTTON_RIGHT
		):
			if str(_movement_state.get("kind", "travel")) == "travel":
				cancel_player_route()
		if event is InputEventKey or event is InputEventMouseButton:
			get_viewport().set_input_as_handled()
		return
	if is_node_map_open():
		if (
			event is InputEventKey
			and event.pressed
			and not event.echo
			and event.is_action_pressed("macro_cancel")
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
				inventory_panel.close_top_surface()
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
			and event.is_action_pressed("macro_cancel")
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
	if event is InputEventKey and event.pressed and not event.echo:
		if event.is_action_pressed("macro_inventory"):
			_toggle_fullscreen_inventory()
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed("macro_health"):
			if macro_hud:
				if get_active_work_surface() != WorkSurface.HEALTH:
					_close_ordinary_work_surfaces(WorkSurface.HEALTH)
				macro_hud.toggle_health_panel()
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed("macro_hex_map"):
			open_hex_world_map()
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed("macro_node_map"):
			open_node_map()
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed("macro_settings"):
			if macro_hud:
				if get_active_work_surface() == WorkSurface.SETTINGS:
					macro_hud.close_settings()
				else:
					_close_ordinary_work_surfaces(WorkSurface.SETTINGS)
					macro_hud.open_settings()
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed("macro_cancel"):
			if close_active_work_surface():
				get_viewport().set_input_as_handled()
				return
	if blocks_world_commands():
		if event is InputEventKey or event is InputEventMouseButton:
			get_viewport().set_input_as_handled()
		return
	if not _pending_interaction.is_empty():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.is_action_pressed("macro_here"):
			_resolve_current_hex_action()
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed("macro_travel"):
			_try_travel_to_selected_hex()
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed("macro_cancel"):
			if close_active_work_surface():
				get_viewport().set_input_as_handled()
				return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_reset_route_bookkeeping()
			if not close_active_work_surface():
				_selected_hex_coords = player_token.current_hex_coords
				_refresh_world_hud()
			get_viewport().set_input_as_handled()
			return
		if event.button_index == MOUSE_BUTTON_LEFT:
			_select_hex_at_mouse()
			get_viewport().set_input_as_handled()
			return

func _attempt_move_to_mouse() -> bool:
	if _is_player_movement_active() or blocks_world_commands():
		return false
	_select_hex_at_mouse()
	return true

func _execute_player_step(
	target_coords: Vector2i,
	animate: bool = true,
	continuation: bool = false
) -> void:
	if not continuation and blocks_world_commands() and (
		animate or not _pending_player_step.is_empty()
	):
		return
	if continuation and not _turn_resolution.is_active():
		return
	if not world_generator.is_in_zone_bounds(target_coords):
		if _is_player_movement_active():
			_finish_player_movement("MOVEMENT FAILED // OUTSIDE THIS ZONE", "failed")
			return
		_try_begin_directional_exit(player_token.current_hex_coords, target_coords)
		return
	var origin_coords := player_token.current_hex_coords
	var target_hex := world_generator.get_hex_at(target_coords)
	if not target_hex.is_passable():
		_finish_player_movement("MOVEMENT FAILED // HEX IS NOT PASSABLE", "failed")
		return
	if not animate:
		if _is_player_movement_active():
			return
		_select_hex_for_hud(target_coords)
		player_token.snap_to_hex(target_coords, map_visualizer.map_to_local(target_coords))
		_commit_player_step(origin_coords, target_coords)
		return
	if not bool(_movement_state.get("active", false)):
		_begin_player_route([target_coords], "travel", true)
	_movement_state["phase"] = "walking"
	_movement_state["current_coords"] = origin_coords
	_movement_state["step_target_coords"] = target_coords
	_movement_state["message"] = "TURN RESOLVE // WALKING TO HEX %d,%d..." % [
		target_coords.x,
		target_coords.y,
	]
	_movement_debug_mark("next route step start")
	var pixel_pos = map_visualizer.map_to_local(target_coords)
	var movement_id := player_token.walk_to_hex(target_coords, pixel_pos)
	_pending_player_step = {
		"kind": "travel",
		"resolution_id": int(_movement_state.get("resolution_id", 0)),
		"movement_id": movement_id,
		"from": origin_coords,
		"to": target_coords,
		"started_minute": _world_state.world_time_minutes,
	}
	_movement_state["can_cancel"] = true
	_last_macro_event = _movement_state["message"]
	_refresh_world_hud()


func _begin_player_route(
	route: Array[Vector2i],
	kind: String = "travel",
	can_cancel: bool = true
) -> void:
	if route.is_empty() or player_token == null:
		return
	_travel_route = route.duplicate()
	_travel_route_total_steps = _travel_route.size()
	_travel_completed_steps = 0
	_route_cancel_requested = false
	var origin_coords := player_token.current_hex_coords
	var destination_coords: Vector2i = _travel_route[_travel_route.size() - 1]
	var resolution_id := _turn_resolution.begin(
		kind,
		origin_coords,
		destination_coords,
		_travel_route_total_steps,
		can_cancel
	)
	if resolution_id == 0:
		_reset_route_bookkeeping()
		return
	_movement_state["step_target_coords"] = _travel_route[0]
	_movement_state["message"] = (
		"TURN RESOLVE // WALKING // ROUTE %d STEP(S)"
		% _travel_route_total_steps
	)
	_movement_debug_mark("movement request accepted")
	_refresh_world_hud()


func _on_player_movement_started(
	from_coords: Vector2i,
	target_coords: Vector2i,
	_movement_id: int
) -> void:
	_movement_debug_mark(
		"tween started %s -> %s" % [str(from_coords), str(target_coords)]
	)


func _on_player_movement_arrived(
	from_coords: Vector2i,
	target_coords: Vector2i,
	movement_id: int
) -> void:
	if _pending_player_step.is_empty():
		return
	if int(_pending_player_step.get("movement_id", -1)) != movement_id:
		return
	var resolution_id := int(_pending_player_step.get("resolution_id", 0))
	if resolution_id != int(_movement_state.get("resolution_id", 0)):
		return
	_movement_debug_mark(
		"arrival signal %s -> %s" % [str(from_coords), str(target_coords)]
	)
	_turn_resolution.set_phase(
		"resolving",
		"TURN RESOLVE // ARRIVAL COMMIT AT HEX %d,%d..." % [
			target_coords.x,
			target_coords.y,
		]
	)
	_movement_state["current_coords"] = target_coords
	_movement_state["step_target_coords"] = target_coords
	_refresh_world_hud()
	# Keep the pending step alive for the transaction boundary. Deferring one
	# frame makes RESOLVING observable and prevents post-arrival projection work
	# from hiding the end of the authored walk.
	call_deferred(
		"_resolve_arrived_player_step",
		movement_id,
		from_coords,
		target_coords,
		resolution_id
	)


func _resolve_arrived_player_step(
	movement_id: int,
	from_coords: Vector2i,
	target_coords: Vector2i,
	resolution_id: int
) -> void:
	if _pending_player_step.is_empty():
		return
	if int(_pending_player_step.get("movement_id", -1)) != movement_id:
		return
	if int(_movement_state.get("resolution_id", 0)) != resolution_id:
		return
	var movement_kind := str(_pending_player_step.get("kind", "travel"))
	if movement_kind == "retreat":
		_commit_player_retreat(target_coords)
		return
	_commit_player_step(from_coords, target_coords)


func _reset_route_bookkeeping() -> void:
	_travel_route.clear()
	_travel_route_total_steps = 0
	_travel_completed_steps = 0
	_route_cancel_requested = false


func _finish_player_movement(message: String, phase: String = "failed") -> void:
	if not _is_player_movement_active():
		_last_macro_event = message
		_refresh_world_hud()
		return
	_pending_player_step.clear()
	_reset_route_bookkeeping()
	var current_coords := player_token.current_hex_coords
	_turn_resolution.finish(message, phase)
	_movement_state["current_coords"] = current_coords
	_movement_state["step_target_coords"] = current_coords
	_last_macro_event = message
	_refresh_world_hud()


func _finish_player_movement_success(message: String) -> void:
	_pending_player_step.clear()
	_reset_route_bookkeeping()
	var current_coords := player_token.current_hex_coords
	_turn_resolution.finish(message, "idle")
	_movement_state["current_coords"] = current_coords
	_movement_state["step_target_coords"] = current_coords
	_last_macro_event = message


func cancel_player_route() -> bool:
	if not bool(_movement_state.get("active", false)):
		return false
	if str(_movement_state.get("kind", "travel")) != "travel":
		return false
	if str(_movement_state.get("phase", "idle")) not in ["walking", "resolving"]:
		return false
	if not bool(_movement_state.get("can_cancel", false)):
		return false
	_route_cancel_requested = true
	_travel_route.clear()
	_movement_state["can_cancel"] = false
	_movement_state["remaining_steps"] = 1
	_movement_state["message"] = "CANCELLING // FINISHING CURRENT STEP..."
	_last_macro_event = _movement_state["message"]
	_refresh_world_hud()
	return true


func _movement_step_committed(target_coords: Vector2i) -> void:
	_travel_completed_steps += 1
	_turn_resolution.mark_step_committed(
		target_coords,
		_travel_route_total_steps
	)


func _movement_debug_mark(label: String) -> void:
	if not OS.is_debug_build() or not debug_macro_logging:
		return
	var now := Time.get_ticks_usec()
	if label == "movement request accepted":
		_movement_debug_request_usec = now
	var elapsed := now - _movement_debug_request_usec if _movement_debug_request_usec > 0 else 0
	print("[MacroTiming] %s // +%.1f ms" % [label, float(elapsed) / 1000.0])


func _commit_player_retreat(target_coords: Vector2i) -> void:
	var origin_coords := (
		_world_state.player_record.coords
		if _world_state.player_record != null
		else target_coords
	)
	var retreat_hex := world_generator.get_hex_at(target_coords)
	var request := WorldActionRequest.new()
	request.actor_id = "player"
	request.target_id = "retreat:%s" % str(target_coords)
	request.target_coords = target_coords
	request.verb_id = "retreat"
	request.payload["action_id"] = "retreat:%s:%s:%d" % [
		str(origin_coords),
		str(target_coords),
		_world_state.player_revision,
	]
	var receipt := _world_action_coordinator.resolve_direct_action(
		request, 0, 0.0, 0.0, "Retreat relocation committed."
	)
	receipt.mutations.append({
		"type": "move_actor",
		"from": origin_coords,
		"to": target_coords,
	})
	receipt.mutations.append({"type": "set_hex_explored"})
	_movement_service.append_trace_to_receipt(
		receipt,
		"player",
		origin_coords,
		target_coords,
		str(campaign.active_node_id) if campaign != null else "",
		_world_state.world_time_minutes,
		retreat_hex
	)
	_movement_debug_mark("receipt application start")
	var application := _commit_world_action_receipt(receipt, target_coords)
	_movement_debug_mark("receipt application end")
	if application == null or not application.applied:
		_macro_log(
			"Movement transaction rejected: %s"
			% (application.error if application != null else "no application receipt")
		)
		player_token.snap_to_hex(origin_coords, map_visualizer.map_to_local(origin_coords))
		_finish_player_movement("RETREAT FAILED // RELOCATION REJECTED", "failed")
		_refresh_world_hud()
		return
	_pending_player_step.clear()
	_movement_step_committed(target_coords)
	_refresh_map_visuals(target_coords, false)
	refresh_proximity(target_coords)
	_last_macro_event = "Escaped combat; fell back to HEX %d,%d." % [
		target_coords.x,
		target_coords.y,
	]
	_finish_player_movement_success(_last_macro_event)
	_refresh_world_hud()


func _commit_player_step(origin_coords: Vector2i, target_coords: Vector2i) -> void:
	var hex_data := world_generator.get_hex_at(target_coords)
	var move_request := WorldActionRequest.new()
	move_request.actor_id = "player"
	move_request.target_id = "hex:%s" % str(target_coords)
	move_request.target_coords = target_coords
	move_request.verb_id = "travel"
	move_request.payload["world_time_minutes"] = _world_state.world_time_minutes
	move_request.payload["action_id"] = "travel:player:%s:%s:%d" % [
		str(origin_coords),
		str(target_coords),
		_world_state.player_revision,
	]
	var move_receipt := _world_action_coordinator.resolve_direct_action(
		move_request,
		_time_rules_service.move_minutes_for_hex(hex_data),
		_time_rules_service.exertion_for_hex(hex_data),
		0.0,
		"Arrived at HEX %d,%d." % [target_coords.x, target_coords.y]
	)
	move_receipt.mutations.append({
		"type": "move_actor",
		"from": origin_coords,
		"to": target_coords,
	})
	move_receipt.mutations.append({"type": "set_hex_explored"})
	_movement_service.append_trace_to_receipt(
		move_receipt,
		"player",
		origin_coords,
		target_coords,
		str(campaign.active_node_id) if campaign != null else "",
		_world_state.world_time_minutes,
		hex_data
	)
	_movement_debug_mark("receipt application start")
	var application := _commit_world_action_receipt(move_receipt, target_coords)
	_movement_debug_mark("receipt application end")
	if application == null or not application.applied:
		_macro_log(
			"Movement transaction rejected: %s"
			% (application.error if application != null else "no application receipt")
		)
		player_token.snap_to_hex(origin_coords, map_visualizer.map_to_local(origin_coords))
		_last_macro_event = (
			application.error
			if application != null and not application.error.is_empty()
			else "Movement transaction was rejected."
		)
		if bool(_movement_state.get("active", false)):
			_finish_player_movement(
				"MOVEMENT FAILED // %s" % _last_macro_event,
				"failed"
			)
		else:
			_refresh_world_hud()
		return
	_pending_player_step.clear()
	_movement_step_committed(target_coords)
	_macro_log("Player stepped to %s." % str(target_coords))
	var newly_explored := _refresh_map_visuals(target_coords, false)
	refresh_proximity(target_coords)
	_turn_resolution.set_phase(
		"world_turn",
		"TURN RESOLVE // NPC WORLD TURN..."
	)
	_movement_state["current_coords"] = target_coords
	_last_macro_event = "Resolving the world turn at HEX %d,%d..." % [
		target_coords.x,
		target_coords.y,
	]
	_refresh_world_hud()
	call_deferred(
		"_resolve_committed_player_step",
		origin_coords,
		target_coords,
		hex_data,
		newly_explored,
		int(_movement_state.get("resolution_id", 0))
	)


func _resolve_committed_player_step(
	origin_coords: Vector2i,
	target_coords: Vector2i,
	hex_data: MacroHexData,
	newly_explored: Array,
	resolution_id: int
) -> void:
	if not _turn_resolution.is_active():
		return
	if int(_movement_state.get("resolution_id", 0)) != resolution_id:
		return
	var target_snapshot := _world_state.get_entity_snapshot_at(target_coords)
	if not target_snapshot.is_empty():
		var target_entity := EntityRecord.from_dict(target_snapshot)
		if not _world_state.is_entity_active(target_entity.entity_id):
			unload_enemy_token(target_coords)
		else:
			_force_project_npc_token(target_entity)
			if _world_state.is_entity_hostile(target_entity.entity_id):
				_advance_player_world_turn()
			_finish_player_movement(
				"MOVEMENT INTERRUPTED // HOSTILE CONTACT AT HEX %d,%d"
				% [target_coords.x, target_coords.y],
				"interrupted"
			)
			begin_entity_collision(
				target_entity.entity_id,
				target_coords,
				origin_coords
			)
			return

	var has_ground_loot := _world_state.has_ground_items(target_coords)
	if has_ground_loot:
		_finish_player_movement(
			"MOVEMENT INTERRUPTED // GROUND ITEMS AT HEX %d,%d"
			% [target_coords.x, target_coords.y],
			"interrupted"
		)
		return

	_advance_player_world_turn()
	if not _pending_interaction.is_empty():
		_finish_player_movement(
			"MOVEMENT INTERRUPTED // CONTACT REQUIRES ATTENTION",
			"interrupted"
		)
		return

	_turn_resolution.set_phase(
		"presentation",
		"TURN RESOLVE // PRESENTATION..."
	)
	_present_travel_beat(
		origin_coords,
		target_coords,
		hex_data,
		newly_explored,
		has_ground_loot
	)
	_refresh_world_hud()
	call_deferred(
		"_finish_player_step_presentation",
		target_coords,
		resolution_id
	)


func _finish_player_step_presentation(
	target_coords: Vector2i,
	resolution_id: int
) -> void:
	if not _turn_resolution.is_active():
		return
	if int(_movement_state.get("resolution_id", 0)) != resolution_id:
		return
	if not _pending_interaction.is_empty():
		_finish_player_movement(
			"MOVEMENT INTERRUPTED // CONTACT REQUIRES ATTENTION",
			"interrupted"
		)
		return
	# Campaign progress resolves via directional rim departure / node map — not
	# a hard-coded objective hex on ordinary steps.
	if _route_cancel_requested:
		_finish_player_movement(
			"ROUTE CANCELLED AT HEX %d,%d" % [target_coords.x, target_coords.y],
			"interrupted"
		)
		_refresh_world_hud()
		return

	if not _travel_route.is_empty():
		_turn_resolution.set_phase(
			"walking",
			"TURN RESOLVE // NEXT STEP..."
		)
		_execute_player_step(_travel_route.pop_front(), true, true)
		return
	_finish_player_movement_success(
		"ARRIVED AT HEX %d,%d." % [target_coords.x, target_coords.y]
	)
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
	if blocks_world_commands():
		return false
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
	if _is_player_movement_active() and not _resolving_player_world_turn:
		return
	if _is_player_movement_active():
		_movement_debug_mark("world-time advance")
	for i in range(turns):
		if not bypass_interaction_check and not _pending_interaction.is_empty():
			break
		var collision := _advance_npc_macro_turn(bypass_interaction_check)
		if collision:
			break


func _advance_player_world_turn() -> void:
	if not _turn_resolution.is_active():
		return
	_resolving_player_world_turn = true
	advance_macro_world(1)
	_resolving_player_world_turn = false

func _select_hex_at_mouse() -> void:
	if _is_player_movement_active() or blocks_world_commands():
		return
	var mouse_pos = map_visualizer.get_local_mouse_position()
	_select_hex_for_hud(map_visualizer.local_to_map(mouse_pos))

func _select_hex_for_hud(coords: Vector2i, allow_while_blocked: bool = false) -> void:
	if _is_player_movement_active():
		return
	if blocks_world_commands() and not allow_while_blocked:
		return
	_selected_hex_coords = coords
	if map_visualizer and map_visualizer.has_method("show_selection"):
		map_visualizer.call("show_selection", coords)
	_refresh_world_hud()

func _resolve_hex_hud_action(action: String) -> void:
	if _is_player_movement_active() or not _pending_interaction.is_empty():
		return
	match action:
		GameEnums.MACRO_HEX_SCAN:
			_select_hex_for_hud(_selected_hex_coords)
		GameEnums.MACRO_HEX_TRAVEL:
			_try_travel_to_selected_hex()
		GameEnums.MACRO_HEX_ACT:
			_resolve_current_hex_action()

func _try_travel_to_selected_hex() -> void:
	if _is_player_movement_active() or blocks_world_commands():
		return
	if _selected_hex_coords == player_token.current_hex_coords:
		_resolve_current_hex_action()
		return
	if not world_generator.is_in_zone_bounds(_selected_hex_coords):
		_last_macro_event = "Selected hex is outside this zone."
		_refresh_world_hud()
		return
	var selected_hex := world_generator.get_hex_at(_selected_hex_coords)
	if selected_hex == null or not _is_hex_travel_known(_selected_hex_coords):
		_last_macro_event = "That hex is not known well enough to plot a route."
		_refresh_world_hud()
		return
	_travel_route = _build_travel_route(
		player_token.current_hex_coords,
		_selected_hex_coords
	)
	if _travel_route.is_empty():
		_last_macro_event = "No passable route is known to the selected hex."
		_refresh_world_hud()
		return
	_begin_player_route(_travel_route, "travel", true)
	_execute_player_step(_travel_route.pop_front(), true, true)


func _build_travel_route(from_coords: Vector2i, to_coords: Vector2i) -> Array[Vector2i]:
	return _movement_service.build_known_route(from_coords, to_coords)

func _resolve_current_hex_action() -> void:
	if _is_player_movement_active() or blocks_world_commands():
		return
	_expand_hex_at(player_token.current_hex_coords)

func _on_hex_preview_travel(coords: Vector2i) -> void:
	if _is_player_movement_active() or blocks_world_commands():
		return
	_selected_hex_coords = coords
	_try_travel_to_selected_hex()

func _expand_hex_at(coords: Vector2i) -> void:
	if _is_player_movement_active():
		return
	if blocks_world_commands() and get_active_work_surface() != WorkSurface.HERE:
		return
	if coords != player_token.current_hex_coords:
		_select_hex_for_hud(coords)
		_last_macro_event = "TRAVEL HERE FIRST // HEX %d,%d" % [coords.x, coords.y]
		_refresh_world_hud()
		return
	var hex_data := world_generator.get_hex_at(coords)
	if active_enemies.has(coords):
		var enemy: MacroEnemy = active_enemies[coords]
		if _world_state.is_entity_active(enemy.entity_id):
			begin_entity_collision(enemy.entity_id, coords)
			return
		unload_enemy_token(coords)
	begin_poi_interaction(coords, hex_data)

func _mark_hex_explored(
	coords: Vector2i,
	hex_data: MacroHexData = null
) -> void:
	var target_hex := hex_data if hex_data != null else world_generator.get_hex_at(coords)
	if target_hex.is_explored:
		return
	target_hex.is_explored = true
	world_generator.commit_hex_projection(coords, target_hex)

# ---------------------------------------------------------
# FOG OF WAR
# ---------------------------------------------------------

## Tagged, filterable trace for the spawn/despawn/movement pipeline.
func _macro_log(message: String) -> void:
	if debug_macro_logging:
		print("[MacroMap] ", message)


func _set_macro_event(message: String) -> void:
	_last_macro_event = message

## Recompute the player's line of sight around a center and reveal it.
## "Visible" = currently in sight this turn. "Explored" = seen at least once.
## Returns axial coords newly marked explored this call.
func _update_fog_of_war(center_coords: Vector2i) -> Array[Vector2i]:
	_configure_extracted_world_services()
	return _visibility_service.update_fog(
		center_coords,
		_world_actor_context(),
		Callable(self, "_macro_log")
	)


## Paint / refresh zone visuals and push black fog states to the visualizer.
## Returns axial coords newly marked explored this call.
func _refresh_map_visuals(center_coords: Vector2i, repaint_zone: bool = false) -> Array[Vector2i]:
	if map_visualizer == null:
		return []
	if _is_player_movement_active():
		_movement_debug_mark("map/fog refresh start")
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
	if _is_player_movement_active():
		_movement_debug_mark("map/fog refresh end")
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
	return _visibility_service.is_visible(coords)

func _is_hex_explored(coords: Vector2i) -> bool:
	return _visibility_service.is_explored(coords)

func _is_hex_travel_known(coords: Vector2i) -> bool:
	if world_generator == null or not world_generator.is_in_zone_bounds(coords):
		return false
	var hex_data := world_generator.get_hex_at(coords)
	if hex_data == null:
		return false
	return hex_data.is_explored or _is_hex_visible(coords)

func _advance_survival_time(
	elapsed_minutes: int,
	exertion: float,
	target_coords: Vector2i,
	insulation_bonus: float = 0.0,
	verb_id: String = "time_advance"
) -> WorldActionApplicationReceipt:
	var request := WorldActionRequest.new()
	request.actor_id = "player"
	request.target_id = "hex:%s" % str(target_coords)
	request.target_coords = target_coords
	request.verb_id = verb_id
	request.method_id = "survival"
	request.expected_actor_revision = _world_state.player_revision
	request.payload["world_time_minutes"] = _world_state.world_time_minutes
	request.payload["action_id"] = "%s:%s:%d" % [
		verb_id,
		str(target_coords),
		_world_state.player_revision,
	]
	var receipt := _world_action_coordinator.resolve_direct_action(
		request,
		elapsed_minutes,
		exertion,
		0.0,
		"Elapsed time committed."
	)
	if receipt == null:
		return null
	receipt.presentation["insulation_bonus"] = insulation_bonus
	var application := _commit_world_action_receipt(receipt, target_coords)
	if application == null or not application.applied:
		_world_state.cancel_world_action(receipt.action_id)
	return application


func _commit_camp_cycle(
	coords: Vector2i,
	hex_data: MacroHexData,
	elapsed_minutes: int,
	exertion: float,
	insulation_bonus: float,
	fatigue_recovery: float,
	healing_amount: float,
	camp_rest_count_delta: int
) -> bool:
	var request := WorldActionRequest.new()
	request.actor_id = "player"
	request.target_id = "camp:%s" % str(coords)
	request.target_coords = coords
	request.verb_id = WorldActionResolver.VERB_SLEEP
	request.method_id = "camp"
	request.payload["world_time_minutes"] = _world_state.world_time_minutes
	request.payload["action_id"] = "camp:%s:%d:%d" % [
		str(coords),
		hex_data.camp_rest_count,
		_world_state.player_revision,
	]
	var receipt := _world_action_coordinator.resolve_direct_action(
		request,
		elapsed_minutes,
		exertion,
		0.0,
		"Camp cycle committed."
	)
	receipt.presentation["insulation_bonus"] = insulation_bonus
	receipt.mutations.append({
		"type": WorldActionCampTransactionService.MUTATION_TYPE,
		"fatigue_recovery": fatigue_recovery,
		"healing_amount": healing_amount,
		"camp_rest_count_delta": camp_rest_count_delta,
	})
	var application := _commit_world_action_receipt(receipt, coords)
	if application == null or not application.applied:
		return false
	hex_data.apply_state(_world_state.get_hex_record(coords))
	return true


func _player_body_for_survival() -> HumanoidBody:
	if player_token == null or player_token.get_humanoid_core() == null:
		return null
	return player_token.get_humanoid_core().body


func _capture_player_runtime_for_survival() -> Dictionary:
	if player_token == null or player_token.get_humanoid_core() == null:
		return {}
	return player_token.get_humanoid_core().capture_runtime_state().to_dict()


func _persist_campaign_hex(coords: Vector2i, state: Variant) -> void:
	if _world_state == null:
		return
	if state is MacroHexData:
		world_generator.commit_hex_projection(coords, state)
	elif state is HexRecord:
		_world_state.replace_hex_record(coords, state, state.revision)
	elif state is Dictionary:
		_world_state.replace_hex_record(
			coords, state, int(state.get("revision", -1))
		)


func _emit_core_activated() -> void:
	core_activated.emit()


func _has_pending_entity_collision() -> bool:
	return (
		not _pending_interaction.is_empty()
		and _pending_interaction.get("type")
		== GameEnums.MacroInteractionType.ENTITY_COLLISION
	)


func _last_macro_event_text() -> String:
	return _last_macro_event


func _is_exploration_window_open() -> bool:
	return exploration_window != null and exploration_window.is_open()


func _world_object_record_at(coords: Vector2i, preferred_id: String = "") -> WorldObjectRecord:
	return _world_action_execution_service.world_object_record_at(coords, preferred_id)


func _world_actor_context() -> Dictionary:
	var capabilities: Array[String] = ["hands", "light_source"]
	var inventory := player_token.get_humanoid_core().inventory
	for item in inventory.get_all_items():
		if item == null:
			continue
		if item.get_functional_roles().has("repair_material") or item.tags.has("materials"):
			if not capabilities.has("material"):
				capabilities.append("material")
		if item.has_interaction_role(GameEnums.InteractionItemRole.SEARCH_TOOL):
			if not capabilities.has("search_tool"):
				capabilities.append("search_tool")
		if item.has_interaction_role(GameEnums.InteractionItemRole.CAMP_GEAR):
			if not capabilities.has("sleep_gear"):
				capabilities.append("sleep_gear")
		if item.has_interaction_role(GameEnums.InteractionItemRole.TRAP_GEAR):
			if not capabilities.has("trap_gear"):
				capabilities.append("trap_gear")
		if item.id in ["crowbar", "bent_pry_bar"]:
			if not capabilities.has("force_tool"):
				capabilities.append("force_tool")
		if item.id in ["multitool", "lockpick"]:
			if not capabilities.has("repair_tool"):
				capabilities.append("repair_tool")
	return {
		"actor_id": "player",
		"revision": _world_state.player_revision,
		"capabilities": capabilities,
		"work_skill": float(player_token.get_humanoid_core().definition.finesse) / 12.0,
	}


func _commit_world_action_receipt(
	receipt: WorldActionReceipt,
	coords: Vector2i,
	target: WorldObjectRecord = null,
	actor_id: String = "player"
) -> WorldActionApplicationReceipt:
	return _receipt_application_service.commit(receipt, coords, target, actor_id)


func _refresh_world_hud_after_receipt() -> void:
	# Movement owns the visible resolving -> projection -> arrival refresh. A
	# receipt-level refresh here would build the full HUD snapshot before fog,
	# proximity, and world-time work, then build it again at the terminal path.
	if _is_player_movement_active():
		_movement_debug_mark("receipt HUD refresh skipped during movement")
		return
	_refresh_world_hud()


func _emit_world_action_presentation(presentation_receipt: Dictionary) -> void:
	var event_bus := get_node_or_null("/root/GameEventBus")
	if event_bus != null and event_bus.has_method("emit_world_action_presentation"):
		event_bus.emit_world_action_presentation(presentation_receipt)


func _emit_movement_trace(
	actor_id: String,
	from_coords: Vector2i,
	to_coords: Vector2i
) -> void:
	_movement_service.emit_trace(
		_world_state,
		actor_id,
		from_coords,
		to_coords,
		str(campaign.active_node_id) if campaign != null else ""
	)


func _resolve_shared_work_action(
	coords: Vector2i,
	verb_id: String,
	preferred_target_id: String = "",
	method_id: String = "",
	noise_intensity: float = 0.0,
	elapsed_minutes: int = 15,
	hit_success_window: bool = true
) -> WorldActionReceipt:
	return _world_action_execution_service.resolve_shared_work_action(
		coords,
		verb_id,
		preferred_target_id,
		method_id,
		noise_intensity,
		elapsed_minutes,
		hit_success_window
	)


func _resolve_world_object_direct_action(
	coords: Vector2i,
	target_id: String,
	verb_id: String
) -> WorldActionReceipt:
	return _world_action_execution_service.resolve_direct_action(
		coords,
		target_id,
		verb_id
	)


func _consume_player_repair_material() -> Dictionary:
	var inventory := player_token.get_humanoid_core().inventory
	for item in inventory.get_all_items():
		if item == null:
			continue
		if not (
			item.get_functional_roles().has("repair_material")
			or item.tags.has("materials")
		):
			continue
		var state := item.to_runtime_state()
		# Selection is side-effect free. WorldActionApplicationService consumes the
		# exact instance in the detached runtime transaction.
		return {
			"instance_id": state.get("instance_id", ""),
			"item_id": item.id,
		}
	return {}


func _apply_player_tool_wear(receipt: WorldActionReceipt) -> void:
	if receipt == null or player_token == null or player_token.get_humanoid_core() == null:
		return
	var inventory := player_token.get_humanoid_core().inventory
	inventory.condition_service.apply_tool_wear(
		inventory,
		receipt.method_id,
		receipt.tool_wear
	)


func _npc_actor_context(record: EntityRecord) -> Dictionary:
	return _npc_work_service.actor_context(record)


func _npc_has_material(record: EntityRecord) -> bool:
	return _npc_work_service.has_material(record)


func _npc_carried_item_states(record: EntityRecord) -> Array:
	return _npc_work_service.carried_item_states(record)


func _materialize_npc_loadout(record: EntityRecord) -> void:
	_npc_work_service.materialize_loadout(record)


func _npc_method_for_record(record: EntityRecord) -> String:
	return _npc_work_service.method_for_record(record)


func _apply_work_method_profile(profile: WorldWorkTaskProfile, method_id: String) -> void:
	_world_action_coordinator.apply_method_profile(profile, method_id)


func _npc_try_work(record: EntityRecord) -> void:
	_npc_work_service.try_work(record, _macro_turn_index, {
		"commit_receipt": Callable(self, "_commit_world_action_receipt"),
	})


func begin_poi_interaction(
	coords: Vector2i,
	hex_data: MacroHexData
) -> void:
	if _is_player_movement_active():
		return
	# Campaign objective / unique-event sites intercept the normal POI flow.
	if _try_handle_campaign_site(coords, hex_data):
		return
	_pending_interaction = {
		"type": GameEnums.MacroInteractionType.POI,
		"coords": coords,
	}
	player_token.play_interaction()
	set_process_unhandled_input(false)
	if macro_hud == null and exploration_window == null:
		push_error("POI interaction opened without a presentation subscriber.")
		close_macro_interaction()
		return
	_present_poi_session(coords, hex_data)


func _try_handle_campaign_site(coords: Vector2i, hex_data: MacroHexData) -> bool:
	return _campaign_content_service.resolve_campaign_site(
		campaign,
		coords,
		hex_data,
		{
			"begin_central_core": Callable(self, "_begin_central_core_debug_hub"),
			"begin_macro_event": Callable(self, "begin_macro_event"),
		}
	)


func _handle_central_meta_quest() -> void:
	var result := _campaign_content_service.resolve_central_meta_quest(
		campaign,
		_meta_progress,
		player_token
	)
	_last_macro_event = str(result.get("message", ""))
	if bool(result.get("log", false)):
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
	_close_ordinary_work_surfaces()
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
	# SiteCatalog is only a presentation adapter; give it the same live actor
	# capabilities used by the authoritative affordance query so the HUD never
	# advertises repair or force work that the actor cannot actually perform.
	camp_access["capabilities"] = _world_actor_context().get("capabilities", [])
	var inventory_snapshot := _build_inventory_snapshot()
	var player_record := player_token.capture_runtime_record()
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
			inventory_snapshot.get("ground", []),
			Callable(self, "_inventory_has_any_item_id"),
			Callable(self, "_inventory_has_any_tag"),
			Callable(self, "_inventory_has_any_role")
		)
	)
	_enrich_location_session(session, hex_data)
	var affordances: Array = []
	for object_value in hex_data.world_objects:
		if not object_value is Dictionary:
			continue
		var object := WorldObjectRecord.from_dict(object_value)
		for affordance in _world_action_coordinator.query_affordances(_world_actor_context(), object):
			if affordance != null:
				affordances.append(affordance.to_dict())
	session["world_objects"] = hex_data.world_objects.duplicate(true)
	session["world_affordances"] = affordances
	session["world_signals"] = hex_data.world_signals.duplicate(true)
	session["active_work"] = hex_data.active_work.duplicate(true)
	session["player_record"] = player_record
	if macro_hud:
		macro_hud.present_poi(session, inventory_snapshot, player_record)
	elif exploration_window:
		exploration_window.open_landmark(session, inventory_snapshot, player_record)
	else:
		push_error("POI session opened without a presentation subscriber.")
		close_macro_interaction()

func begin_entity_collision(
	enemy_id: String,
	coords: Vector2i,
	approach_from: Vector2i = Vector2i(2147483647, 2147483647)
) -> void:
	_close_ordinary_work_surfaces()
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
	var record_snapshot := _world_state.get_entity_snapshot(enemy_id)
	var record := (
		EntityRecord.from_dict(record_snapshot)
		if not record_snapshot.is_empty()
		else null
	)
	var opening_mode := (
		MacroEntityCollisionResolver.MODE_ROOT
		if record != null and record.world_status == GameEnums.EntityWorldStatus.HOSTILE
		else MacroEntityCollisionResolver.MODE_PEACEFUL
	)
	_open_entity_collision_session(opening_mode)

func preview_poi_action(
	action: GameEnums.PoiAction,
	selected_item_ids: Array,
	selected_search_option_id: String = ""
) -> void:
	if _is_player_movement_active():
		return
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
	selected_search_option_id: String = "",
	selected_target_id: String = "",
	work_hit_success_window: bool = true
) -> void:
	if _is_player_movement_active():
		return
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
			selected_search_option_id,
			selected_target_id,
			work_hit_success_window
		)
	elif action == GameEnums.PoiAction.STOP_REST:
		hex_data.rest_in_progress = false
		world_generator.commit_hex_projection(coords, hex_data)
		_present_poi_session(coords, hex_data)
	elif action == GameEnums.PoiAction.REST or action == GameEnums.PoiAction.CAMP:
		var camp_access := _get_camp_access(coords, hex_data)
		if not camp_access.get("allowed", false):
			_show_interaction_result(
				"CAMP UNAVAILABLE",
				camp_access.get("reason", "This location is unsafe.")
			)
			return
		var selection_result := _apply_poi_session_selections(
			coords,
			selected_item_ids,
			(
				_PoiSelectionActionService.MODE_CAMP_SETUP
				if action == GameEnums.PoiAction.CAMP
				else _PoiSelectionActionService.MODE_SLEEP_SETUP
			)
		)
		if not bool(selection_result.get("committed", false)):
			_show_interaction_result(
				"CAMP GEAR CHANGED",
				str(selection_result.get(
					"message",
					"The selected camp gear is no longer available."
				))
			)
			return
		hex_data = world_generator.get_hex_at(coords)
		hex_data.rest_in_progress = true
		world_generator.commit_hex_projection(coords, hex_data)
		_resolve_camp(coords, hex_data, profile["camp"], selected_item_ids)
		hex_data = world_generator.get_hex_at(coords)
		hex_data.rest_in_progress = false
		world_generator.commit_hex_projection(coords, hex_data)


func resolve_location_action(command: Dictionary) -> void:
	if _is_player_movement_active():
		return
	if _pending_interaction.get("type") != GameEnums.MacroInteractionType.POI:
		return
	var coords: Vector2i = command.get("coords", Vector2i.ZERO)
	if coords != player_token.current_hex_coords:
		_last_macro_event = "That location is no longer HERE."
		_refresh_world_hud()
		return
	var current := _build_current_location_snapshot(_build_inventory_snapshot())
	if int(command.get("location_revision", -1)) != int(current.get("revision", 0)):
		_last_macro_event = "The location changed before that action could begin."
		_refresh_world_hud()
		if macro_hud:
			macro_hud.show_location_outcome("LOCATION CHANGED", _last_macro_event)
		return
	var verb := str(command.get("verb", ""))
	var selected_item_ids: Array = command.get("selected_item_ids", [])
	if verb in ["take", "inspect"]:
		var ground_id := str(selected_item_ids[0]) if not selected_item_ids.is_empty() else ""
		var ground_exists := false
		for item in current.get("session", {}).get("ground_items", []):
			if item is Dictionary and str(item.get("instance_id", "")) == ground_id:
				ground_exists = true
				break
		if not ground_exists:
			_show_interaction_result("ITEM MOVED", "That item is no longer on the ground here.")
			return
		var inventory_result := resolve_inventory_action(
			GameEnums.MACRO_INV_TAKE if verb == "take" else GameEnums.MACRO_INV_INTERACT,
			ground_id,
			GameEnums.EquipmentSlot.NONE,
			{}
		)
		_show_interaction_result(
			(
				"ITEM TAKEN"
				if verb == "take" and inventory_result.get("ground_restore", []).is_empty()
				else ("ITEM INSPECTED" if verb == "inspect" else "PACK FULL")
			),
			str(inventory_result.get("message", "The location has been refreshed."))
		)
		return
	var fixture := SiteCatalog.fixture_by_id(
		current.get("session", {}).get("site", {}),
		str(command.get("fixture_id", ""))
	)
	if fixture.is_empty() or not fixture.get("verbs", []).has(verb):
		_show_interaction_result(
			"ACTION UNAVAILABLE",
			"That fixture no longer supports the requested action."
		)
		return
	var accepted_roles: Array = fixture.get("accepted_roles", [])
	var available_by_id := {}
	for item in current.get("session", {}).get("available_items", []):
		if item is Dictionary:
			available_by_id[str(item.get("instance_id", ""))] = item
	for item_id_value in selected_item_ids:
		var item_id := str(item_id_value)
		if not available_by_id.has(item_id):
			_show_interaction_result("GEAR CHANGED", "Selected gear is no longer carried.")
			return
		if verb == WorldActionResolver.VERB_REPAIR:
			# Repair consumes an actual material instance through the shared
			# resolver; the optional timing selection may be a tool, a material, or
			# both, so do not reject a valid material as if it were search gear.
			continue
		var item_roles: Array = available_by_id[item_id].get("interaction_roles", [])
		var eligible := accepted_roles.is_empty()
		for role in item_roles:
			if accepted_roles.has(role):
				eligible = true
				break
		if not eligible:
			_show_interaction_result("GEAR INELIGIBLE", "That item cannot be used at this fixture.")
			return
	match verb:
		SiteCatalog.VERB_SEARCH:
			resolve_poi_action(
				GameEnums.PoiAction.SEARCH,
				selected_item_ids,
				str(fixture.get("search_option_id", "")),
				str(fixture.get("target_id", "")),
				bool(command.get("hit_success_window", true))
			)
		WorldActionResolver.VERB_OPEN, WorldActionResolver.VERB_INSPECT:
			var direct_receipt := _resolve_world_object_direct_action(
				coords,
				str(fixture.get("target_id", "")),
				verb
			)
			if direct_receipt == null:
				_show_interaction_result("ACTION BLOCKED", _last_macro_event)
				return
			_show_interaction_result("INSPECTED" if verb == WorldActionResolver.VERB_INSPECT else "OPENED", direct_receipt.message)
		WorldActionResolver.VERB_REPAIR, WorldActionResolver.VERB_DISMANTLE, \
		WorldActionResolver.VERB_FORCE:
			var work_receipt := _resolve_shared_work_action(
				coords,
				verb,
				str(fixture.get("target_id", "")),
				str(command.get("method_id", _method_id_for_item_ids(selected_item_ids))),
				1.25 if verb == WorldActionResolver.VERB_REPAIR else 2.0,
				_time_rules_service.search_minutes(),
				bool(command.get("hit_success_window", true))
			)
			if work_receipt == null:
				_show_interaction_result("WORK BLOCKED", _last_macro_event)
				return
			if verb == WorldActionResolver.VERB_REPAIR:
				_apply_shelter_repair_progress(coords, str(fixture.get("target_id", "")), work_receipt)
			_show_interaction_result(
				"WORK COMPLETE" if work_receipt.work_completed else "WORK INTERRUPTED",
				str(work_receipt.message)
			)
		SiteCatalog.VERB_SLEEP:
			if str(fixture.get("target_id", "")).is_empty():
				resolve_poi_action(GameEnums.PoiAction.REST, selected_item_ids)
			else:
				var sleep_receipt := _resolve_world_object_direct_action(
					coords,
					str(fixture.get("target_id", "")),
					WorldActionResolver.VERB_SLEEP
				)
				if sleep_receipt == null:
					_show_interaction_result("REST BLOCKED", _last_macro_event)
					return
				_show_interaction_result("REST COMPLETE", sleep_receipt.message)
		SiteCatalog.VERB_TRAP:
			_resolve_location_trap(coords, selected_item_ids)
		_:
			_show_interaction_result(
				"ACTION UNAVAILABLE",
				"This place does not support that action yet."
			)


func _resolve_location_trap(coords: Vector2i, selected_item_ids: Array) -> void:
	var result := _poi_selection_action_service.resolve(
		coords,
		selected_item_ids,
		_PoiSelectionActionService.MODE_TRAP_INSTALL,
		_time_rules_service.action_minutes("action"),
		0.25,
		0.55
	)
	if not bool(result.get("committed", false)):
		_show_interaction_result(
			"TRAP NOT SET",
			str(result.get(
				"message",
				"Choose an eligible trap from the gear tray."
			))
		)
		return
	_last_macro_event = "Trap armed at HEX %d,%d." % [coords.x, coords.y]
	_refresh_world_hud()
	_show_interaction_result(
		"TRAP ARMED",
		"The selected approach is trapped. The device remains here until triggered."
	)


func _method_id_for_item_ids(item_ids: Array) -> String:
	for item_id_value in item_ids:
		var item := _find_inventory_item_by_instance_id(str(item_id_value))
		if item == null:
			continue
		if item.id in ["crowbar", "bent_pry_bar"]:
			return "crowbar"
		if item.id in ["multitool", "lockpick"]:
			return "multitool"
	return "hands"


func _apply_shelter_repair_progress(
	coords: Vector2i,
	target_id: String,
	receipt: WorldActionReceipt
) -> void:
	_shelter_runtime_service.apply_repair(campaign, coords, target_id, receipt)


func preserve_shelter_after_player_defeat() -> void:
	_shelter_runtime_service.preserve_after_player_defeat(campaign)


func reconcile_shelter_after_hostile_change() -> void:
	_shelter_runtime_service.reconcile_after_hostile_change(campaign)


func _enrich_location_session(session: Dictionary, hex_data: MacroHexData) -> void:
	var profile := MacroInteractionResolver.build_poi_profile(
		_world_state.world_seed,
		player_token.current_hex_coords,
		hex_data.biome,
		hex_data.poi_id
	)
	var loot_profile := _get_loot_profile(hex_data)
	session["preview_base_metrics"] = {
		"search": profile.get("search", {}).duplicate(true),
		"camp": profile.get("camp", {}).duplicate(true),
	}
	session["search_count"] = hex_data.search_count
	session["max_searches"] = int(loot_profile.get("max_searches", 4))
	_attach_work_timing_snapshots(session)


func _attach_work_timing_snapshots(session: Dictionary) -> void:
	var method_ids := _world_action_coordinator.method_ids()
	if method_ids.is_empty():
		return
	var site: Dictionary = session.get("site", {})
	for fixture_value in site.get("fixtures", []):
		if not fixture_value is Dictionary:
			continue
		var fixture: Dictionary = fixture_value
		var profile_id := str(fixture.get("task_profile_id", ""))
		if profile_id.is_empty():
			continue
		var base_profile := _world_action_coordinator.profile_for_id(profile_id)
		if base_profile == null:
			continue
		var timing_profiles: Dictionary = {}
		for method_id_value in method_ids:
			var method_id := str(method_id_value)
			var method_profile := base_profile.duplicate(true) as WorldWorkTaskProfile
			_world_action_coordinator.apply_method_profile(method_profile, method_id)
			timing_profiles[method_id] = method_profile.to_dict()
		fixture["timing_profiles"] = timing_profiles


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
				var record_snapshot := _world_state.get_entity_snapshot_at(probe)
				if (
					not record_snapshot.is_empty()
					and _world_state.is_entity_hostile(str(record_snapshot.get("entity_id", "")))
				):
					enemy_id = str(record_snapshot.get("entity_id", ""))
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
	world_generator.commit_hex_projection(coords, hex)
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
	if not result.has("choice_id"):
		if macro_hud:
			macro_hud.show_event_result(result)
		return
	var application := _commit_macro_event_choice(event_id, result)
	if application == null or not application.applied:
		var interrupted := result.duplicate(true)
		interrupted["title"] = "EVENT INTERRUPTED"
		interrupted["body"] = (
			application.error
			if application != null and not application.error.is_empty()
			else "The event outcome changed before it could commit."
		)
		interrupted["effects"] = {}
		if macro_hud:
			macro_hud.show_event_result(interrupted)
		return
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


func resolve_talk_action(action: GameEnums.TalkAction) -> void:
	if (
		_pending_interaction.get("type")
		!= GameEnums.MacroInteractionType.ENTITY_COLLISION
	):
		return
	var interaction_coords: Vector2i = _pending_interaction.get(
		"coords",
		Vector2i.ZERO
	)
	var enemy_id: String = _pending_interaction.get("enemy_id", "")
	var enemy_snapshot := _world_state.get_entity_snapshot(enemy_id)
	if enemy_snapshot.is_empty():
		return
	var enemy_record := EntityRecord.from_dict(enemy_snapshot)
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
	var event_id := "ceasefire_reached"
	var trust_delta := 3.0
	var threat_delta := 0.0
	var next_status := GameEnums.EntityWorldStatus.CEASEFIRE
	var next_relationship := CombatRelationshipLedger.Relation.NEUTRAL
	var threat_result: Dictionary = {}
	if outcome == GameEnums.NegotiationOutcome.COMBAT:
		event_id = "talk_broke_down"
		trust_delta = -2.0
		threat_delta = 5.0
		next_status = WorldActionNegotiationTransactionService.NO_CHANGE
		next_relationship = WorldActionNegotiationTransactionService.NO_CHANGE
	elif outcome == GameEnums.NegotiationOutcome.INTIMIDATED:
		event_id = "player_intimidated"
		trust_delta = -3.0
		threat_delta = 8.0
		next_status = GameEnums.EntityWorldStatus.WITHDRAWN
		threat_result = MacroInteractionResolver.resolve_threat_surrender(
			_world_state.world_seed,
			enemy_id,
			attempt,
			enemy_record.definition,
			_loot_catalog
		)
	# Resolve the role against a detached record. The receipt carries only this
	# semantic default and one memory event, never the caller-owned runtime.
	var ai: Dictionary = _NpcSimulator.ensure_npc_memory(enemy_record)
	var request := WorldActionRequest.new()
	request.actor_id = "player"
	request.target_id = enemy_id
	request.target_coords = interaction_coords
	request.verb_id = WorldActionNegotiationTransactionService.VERB_ID
	request.expected_actor_revision = _world_state.player_revision
	request.payload["world_time_minutes"] = _world_state.world_time_minutes
	var receipt := _world_action_coordinator.resolve_direct_action(
		request,
		_time_rules_service.action_minutes("action"),
		0.1,
		0.0,
		"Negotiation outcome committed."
	)
	receipt.mutations.append({
		"type": WorldActionNegotiationTransactionService.MUTATION_TYPE,
		"expected_enemy_revision": enemy_record.revision,
		"expected_negotiation_attempt": attempt,
		"next_negotiation_attempt": attempt + 1,
		"outcome": outcome,
		"npc_role_id": str(ai.get("role_id", "salvager")),
		"memory_event": {
			"id": event_id,
			"turn": _macro_turn_index,
			"coords": player_token.current_hex_coords,
			"trust_delta": trust_delta,
			"threat_delta": threat_delta,
		},
		"next_world_status": next_status,
		"next_relationship": next_relationship,
		"ground_coords": player_token.current_hex_coords,
		"kept_loadout": threat_result.get("kept_loadout", {}),
		"created_ground_items": threat_result.get("ground_items", []),
	})
	var application := _commit_world_action_receipt(receipt, interaction_coords)
	if application == null or not application.applied:
		_world_state.cancel_world_action(receipt.action_id)
		_show_collision_result(
			"NEGOTIATION INTERRUPTED",
			application.error if application != null else "Negotiation was rejected.",
			""
		)
		return
	if active_enemies.has(interaction_coords):
		active_enemies[interaction_coords].play_interaction()
	if outcome == GameEnums.NegotiationOutcome.COMBAT:
		_request_pending_combat(GameEnums.EncounterContext.DIALOGUE_BREAKDOWN)
		return
	if outcome == GameEnums.NegotiationOutcome.INTIMIDATED:
		unload_enemy_token(interaction_coords)
		_show_collision_result(
			"THREAT SUCCESS",
			str(threat_result.get("message", "")),
			""
		)
		return
	var updated_snapshot := _world_state.get_entity_snapshot(enemy_id)
	if not updated_snapshot.is_empty() and active_enemies.has(interaction_coords):
		var updated_record := EntityRecord.from_dict(updated_snapshot)
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
	var enemy_snapshot := _world_state.get_entity_snapshot(enemy_id)
	var enemy_record := (
		EntityRecord.from_dict(enemy_snapshot)
		if not enemy_snapshot.is_empty()
		else null
	)
	if (
		enemy_record == null
		or enemy_record.kind != GameEnums.RuntimeEntityKind.NPC
		or not _world_state.is_entity_active(enemy_id)
	):
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
	if _is_player_movement_active() or inventory_panel == null:
		return
	if inventory_panel.is_open():
		inventory_panel.close_panel()
		return
	if macro_hud != null and macro_hud.is_event_open():
		return
	_close_ordinary_work_surfaces(WorkSurface.INVENTORY)
	if (
		_inventory_home_layer != null
		and inventory_panel.get_parent() != _inventory_home_layer
	):
		inventory_panel.reparent(_inventory_home_layer)
	inventory_panel.open_inventory(_build_inventory_snapshot())
	_emit_work_surface_changed()


func _on_hud_viewport_insets_changed(insets: Rect2i) -> void:
	var camera := get_node_or_null("Camera2D") as MacroCamera
	if camera:
		camera.set_viewport_insets(insets)


func _on_medical_action_requested(instance_id: String, limb_region: int) -> void:
	var player_core := player_token.get_humanoid_core()
	var validation := MacroMedicalResolver.validate_apply_to_limb(
		player_core,
		instance_id,
		limb_region
	)
	if not bool(validation.get("valid", false)):
		_last_inventory_error = str(validation.get("message", "Treatment failed."))
		_refresh_world_hud()
		return

	var treatment_request := WorldActionRequest.new()
	treatment_request.actor_id = "player"
	treatment_request.target_id = instance_id
	treatment_request.target_coords = player_token.current_hex_coords
	treatment_request.verb_id = "treat"
	treatment_request.method_id = "medical_item"
	treatment_request.expected_actor_revision = _world_state.player_revision
	treatment_request.payload["world_time_minutes"] = _world_state.world_time_minutes
	var treatment_receipt := _world_action_coordinator.resolve_direct_action(
		treatment_request,
		_time_rules_service.action_minutes("action"),
		0.35,
		0.15,
		"Treatment applied."
	)
	treatment_receipt.mutations.append({
		"type": "medical_application",
		"instance_id": instance_id,
		"limb_region": limb_region,
	})
	var application := _commit_world_action_receipt(
		treatment_receipt,
		player_token.current_hex_coords
	)
	if application != null and application.applied:
		_last_inventory_error = ""
		return
	_last_inventory_error = (
		application.error
		if application != null and not application.error.is_empty()
		else "Treatment failed to commit."
	)
	if not treatment_receipt.action_id.is_empty():
		_world_state.cancel_world_action(treatment_receipt.action_id)
	_refresh_world_hud()

func _on_inventory_closed() -> void:
	_restore_node_map_inventory_layer()
	_emit_work_surface_changed()


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


func _apply_macro_event_effects(
	effects: Dictionary
) -> WorldActionApplicationReceipt:
	if effects.is_empty():
		return null
	var coords: Vector2i = _pending_interaction.get(
		"coords",
		player_token.current_hex_coords
	)
	var elapsed_minutes := int(effects.get("elapsed_minutes", 0))
	if elapsed_minutes > 0:
		var request := WorldActionRequest.new()
		request.actor_id = "player"
		request.target_id = str(_pending_interaction.get("enemy_id", _pending_interaction.get("event_id", "social")))
		request.target_coords = coords
		request.verb_id = "talk"
		var receipt := _world_action_coordinator.resolve_direct_action(
			request,
			elapsed_minutes,
			float(effects.get("exertion", 0.0)),
			0.0,
			"Conversation or event choice committed."
		)
		if receipt == null:
			return null
		var application := _commit_world_action_receipt(receipt, coords)
		if application == null or not application.applied:
			_world_state.cancel_world_action(receipt.action_id)
		return application
	return null


func _commit_macro_event_choice(
	event_id: String,
	result: Dictionary
) -> WorldActionApplicationReceipt:
	var coords: Vector2i = _pending_interaction.get(
		"coords",
		player_token.current_hex_coords
	)
	var effects_value: Variant = result.get("effects", {})
	var effects: Dictionary = (
		effects_value if effects_value is Dictionary else {}
	)
	var request := WorldActionRequest.new()
	request.actor_id = "player"
	request.target_id = event_id
	request.target_coords = coords
	request.verb_id = WorldActionMacroEventTransactionService.VERB_ID
	request.expected_actor_revision = _world_state.player_revision
	request.payload["world_time_minutes"] = _world_state.world_time_minutes
	var receipt := _world_action_coordinator.resolve_direct_action(
		request,
		maxi(0, int(effects.get("elapsed_minutes", 0))),
		maxf(0.0, float(effects.get("exertion", 0.0))),
		0.0,
		"Macro-event choice committed."
	)
	var context: Dictionary = _pending_interaction.get("context", {})
	receipt.mutations.append({
		"type": WorldActionMacroEventTransactionService.MUTATION_TYPE,
		"event_id": event_id,
		"choice_id": str(result.get("choice_id", "")),
		"source_search_option_id": str(context.get(
			"source_search_option_id", ""
		)),
	})
	var application := _commit_world_action_receipt(receipt, coords)
	if application == null or not application.applied:
		_world_state.cancel_world_action(receipt.action_id)
	return application

func resolve_inventory_action(
	action_id: String,
	instance_id: String,
	equipment_slot: int,
	action_payload: Dictionary = {}
) -> Dictionary:
	if _is_player_movement_active():
		return {"committed": false, "message": "Movement is still resolving."}
	_last_inventory_error = ""
	var coords := player_token.current_hex_coords
	var result := _inventory_action_service.resolve(
		action_id,
		instance_id,
		equipment_slot,
		coords,
		action_payload
	)
	if action_id == GameEnums.MACRO_INV_INSPECT and bool(
		result.get("committed", false)
	):
		_apply_knowledge_inspection(result)
	if not bool(result.get("committed", false)):
		_last_inventory_error = str(result.get("message", "Inventory action rejected."))
	_emit_inventory_item_used(result)
	var snapshot := _build_inventory_snapshot()
	if inventory_panel and inventory_panel.is_open():
		inventory_panel.refresh_snapshot(snapshot, "")
	_refresh_exploration_ground()
	_refresh_world_hud()
	return result


func _apply_knowledge_inspection(result: Dictionary) -> void:
	var neutral_action: Dictionary = result.get("neutral_action", {})
	var entry_id := str(neutral_action.get("knowledge_entry_id", ""))
	if entry_id.is_empty():
		return
	var knowledge_catalog := get_node_or_null("/root/KnowledgeCatalog")
	if knowledge_catalog == null:
		result["message"] = "The knowledge catalog is unavailable."
		return
	var player_core := player_token.get_humanoid_core()
	var item_tags: Array[String] = []
	for carried_item in player_core.inventory.get_all_items():
		if carried_item == null:
			continue
		for tag in carried_item.tags:
			if not item_tags.has(tag):
				item_tags.append(tag)
	var known_ids: Array = []
	if _meta_progress != null and _meta_progress.has_method("get_codex_entry_ids"):
		known_ids = Array(_meta_progress.get_codex_entry_ids())
	var decode: Dictionary = knowledge_catalog.evaluate_decode(entry_id, {
		"capability_ids": Array(IdentityCatalog.capability_ids_for_selection(
			player_core.definition.occupation_id,
			player_core.definition.trait_ids,
			player_core.definition.flaw_ids
		)),
		"item_tags": item_tags,
		"known_knowledge_ids": known_ids,
	})
	if not bool(decode.get("decoded", false)):
		result["message"] = str(decode.get("reason", "The evidence cannot be decoded."))
		_last_macro_event = result["message"]
		return
	var entry: Dictionary = decode.get("entry", {})
	if _meta_progress != null and _meta_progress.has_method("record_codex_entry"):
		_meta_progress.record_codex_entry(entry_id)
	var applied: Dictionary = _world_state.get_run_flags_snapshot().get(
		"applied_knowledge_ids", {}
	).duplicate(true)
	var changed_nodes := PackedStringArray()
	if not bool(applied.get(entry_id, false)):
		for trigger_id in decode.get("trigger_ids", []):
			for node_id in apply_campaign_discovery_trigger(str(trigger_id)):
				if not changed_nodes.has(str(node_id)):
					changed_nodes.append(str(node_id))
		applied[entry_id] = true
		_world_state.patch_run_flags({"applied_knowledge_ids": applied})
	var title := str(entry.get("title", entry_id))
	var body := str(entry.get("body", entry.get("summary", "")))
	if not changed_nodes.is_empty():
		body += "\n\nNODE WEB UPDATED: " + ", ".join(changed_nodes)
	var deployed_actor := _deploy_eligible_plot_actor()
	if not deployed_actor.is_empty():
		body += "\n\nWORLD RESPONSE: %s entered the area." % deployed_actor
	result["knowledge_result"] = decode
	result["message"] = body
	_last_macro_event = "Decoded: %s" % title
	_show_interaction_result("KNOWLEDGE // " + title.to_upper(), body)


func _deploy_eligible_plot_actor() -> String:
	if campaign == null or campaign.active_node_id.is_empty():
		return ""
	var director: Variant = _PlotDirector.data()
	if director == null:
		return ""
	var known_ids: Array = []
	if _meta_progress != null and _meta_progress.has_method("get_codex_entry_ids"):
		known_ids = Array(_meta_progress.get_codex_entry_ids())
	var deployment: Variant = director.eligible_deployment(
		known_ids,
		campaign.active_node_id,
		_world_state.get_run_flags_snapshot()
	)
	if deployment == null:
		return ""
	var player_coords := player_token.current_hex_coords
	var candidates: Array[Vector2i] = []
	for coords in _NpcSimulator.coords_in_radius(
		player_coords,
		deployment.maximum_spawn_distance
	):
		var distance: int = _NpcSimulator.hex_distance(player_coords, coords)
		if distance < deployment.minimum_spawn_distance:
			continue
		var hex_data := world_generator.get_hex_at(coords)
		if (
			not hex_data.is_passable()
			or not hex_data.encounter_entity_id.is_empty()
			or not _npc_get_occupying_entity_id(coords).is_empty()
		):
			continue
		candidates.append(coords)
	if candidates.is_empty():
		return ""
	var seed_key: String = (
		_world_state.world_seed + ":plot_deployment:" + deployment.deployment_id
	)
	candidates.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return absi((seed_key + ":" + str(a)).hash()) < absi((seed_key + ":" + str(b)).hash())
	)
	var spawn_coords := candidates[0]
	var record := mob_spawner.generate_authored_actor_record(
		spawn_coords,
		deployment.deployment_id,
		deployment.actor_name,
		deployment.faction,
		deployment.world_status,
		deployment.role_id,
		deployment.dialogue_id,
		deployment.visual_mode,
		deployment.token_sprite_path,
		seed_key
	)
	_initialize_npc_runtime(record)
	var entity_id := _world_state.register_entity(record)
	var spawn_hex := world_generator.get_hex_at(spawn_coords)
	spawn_hex.encounter_entity_id = entity_id
	spawn_hex.encounter_evaluated = true
	world_generator.commit_hex_projection(spawn_coords, spawn_hex)
	_spawn_enemy_token_from_record(record)
	if not deployment.run_once_key.is_empty():
		var deployment_flag_patch: Dictionary = {}
		deployment_flag_patch[deployment.run_once_key] = true
		_world_state.patch_run_flags(deployment_flag_patch)
	return deployment.actor_name

func _refresh_exploration_ground() -> void:
	if exploration_window == null or not exploration_window.is_open():
		return
	var snapshot := _build_inventory_snapshot()
	var available := _PoiController.available_interaction_options(
		player_token.get_humanoid_core().inventory.get_all_items()
	)
	exploration_window.refresh_session_state(
		available,
		snapshot.get("ground", []),
		player_token.capture_runtime_record()
	)

func _build_inventory_snapshot() -> Dictionary:
	_configure_snapshot_facade()
	return _snapshot_facade.build_inventory_snapshot()

func _build_world_hud_snapshot() -> Dictionary:
	_configure_snapshot_facade()
	return _snapshot_facade.build_world_hud_snapshot()


func _build_minimap_snapshot() -> Dictionary:
	_configure_snapshot_facade()
	return _snapshot_facade.build_minimap_snapshot()


func _build_current_location_snapshot(inventory_snapshot: Dictionary) -> Dictionary:
	return _location_snapshot_service.build_current(inventory_snapshot)


func _build_target_location_snapshot(snapshot: Dictionary) -> Dictionary:
	return _location_snapshot_service.build_target(snapshot)


func _build_hex_descriptor(coords: Vector2i) -> Dictionary:
	_configure_snapshot_facade()
	return _snapshot_facade.build_hex_descriptor(coords)


func _build_macro_activity_snapshot() -> Dictionary:
	_configure_snapshot_facade()
	return _snapshot_facade.build_macro_activity_snapshot()


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
	snapshot["current_location"] = _build_current_location_snapshot(inventory_snapshot)
	snapshot["target_location"] = _build_target_location_snapshot(snapshot)
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

func _on_player_items_spilled(spilled_items: Array[ItemData]) -> void:
	if not is_visible_in_tree():
		return
	var item_states: Array = []
	for item in spilled_items:
		item_states.append(item.to_runtime_state())
	_world_state.add_ground_items(player_token.current_hex_coords, item_states)

func _resolve_core_activation(coords: Vector2i, hex_data: MacroHexData) -> void:
	_campaign_progression_service.resolve_central_core_activation(
		coords,
		hex_data,
		_meta_progress
	)


func _resolve_regional_core_restoration(coords: Vector2i, hex_data: MacroHexData) -> void:
	_campaign_progression_service.resolve_regional_core_restoration(
		coords,
		hex_data,
		_meta_progress
	)

func _resolve_search(
	coords: Vector2i,
	hex_data: MacroHexData,
	base_metrics: Dictionary,
	selected_item_ids: Array,
	selected_search_option_id: String = "",
	preferred_target_id: String = "",
	work_hit_success_window: bool = true
) -> void:
	_search_action_service.resolve(
		coords,
		hex_data,
		base_metrics,
		selected_item_ids,
		selected_search_option_id,
		preferred_target_id,
		work_hit_success_window
	)


func _commit_search_transaction(payload: Dictionary) -> bool:
	var coords: Vector2i = payload.get("coords", player_token.current_hex_coords)
	var target_state: Dictionary = payload.get("target_state", {})
	var request := WorldActionRequest.new()
	request.actor_id = "player"
	request.target_id = str(target_state.get("object_id", "search:%s" % str(coords)))
	request.target_coords = coords
	request.verb_id = WorldActionResolver.VERB_SEARCH
	request.expected_actor_revision = _world_state.player_revision
	request.expected_target_revision = int(target_state.get("revision", -1))
	request.payload["action_id"] = "search:%s:%d" % [
		str(coords),
		int(payload.get("attempt_index", 0)),
	]
	request.payload["world_time_minutes"] = _world_state.world_time_minutes
	var receipt := _world_action_coordinator.resolve_direct_action(
		request,
		int(payload.get("elapsed_minutes", 0)),
		float(payload.get("exertion", 1.0)),
		float(payload.get("noise_intensity", 0.75)),
		"Search outcome committed."
	)
	receipt.mutations.append({
		"type": WorldActionSearchTransactionService.MUTATION_TYPE,
		"expected_search_count": int(payload.get("expected_search_count", -1)),
		"searched_target_id": str(payload.get("searched_target_id", "")),
	})
	for item_state in payload.get("ground_items", []):
		if item_state is Dictionary:
			receipt.mutations.append({
				"type": "add_ground_item",
				"item_state": item_state.duplicate(true),
			})
	for key in payload.get("run_flags", {}).keys():
		receipt.mutations.append({
			"type": "set_run_flag",
			"key": str(key),
			"value": payload["run_flags"][key],
		})
	if float(payload.get("injury_damage", 0.0)) > 0.0:
		receipt.mutations.append({
			"type": "biological_hit",
			"limb_region": int(payload.get("injury_limb", GameEnums.LimbRegion.LEFT_ARM)),
			"damage": float(payload.get("injury_damage", 0.0)),
			"armor": 0.0,
		})
	var trace: Dictionary = payload.get("trace", {})
	if not trace.is_empty():
		receipt.mutations.append({"type": "append_trace", "trace": trace})
	var target := WorldObjectRecord.from_dict(target_state) if not target_state.is_empty() else null
	var application := _commit_world_action_receipt(receipt, coords, target)
	if application == null or not application.applied:
		_world_state.cancel_world_action(receipt.action_id)
		return false
	return true

func _resolve_camp(
	coords: Vector2i,
	hex_data: MacroHexData,
	base_metrics: Dictionary,
	_selected_item_ids: Array
) -> void:
	_camp_action_service.resolve(
		coords,
		hex_data,
		base_metrics,
		_selected_item_ids
	)

func _spawn_search_intruder(coords: Vector2i) -> void:
	# Search pressure comes from an inhabitant that can physically react to the
	# emitted signal. Do not conjure a disposable intruder at the work marker.
	var record: EntityRecord = null
	var closest_distance := 999
	for candidate_snapshot in _world_state.get_all_entity_snapshots():
		if not candidate_snapshot is Dictionary:
			continue
		var candidate := EntityRecord.from_dict(candidate_snapshot)
		if not _world_state.is_entity_alive(candidate.entity_id):
			continue
		if candidate.world_status != GameEnums.EntityWorldStatus.HOSTILE:
			continue
		var distance := _NpcSimulator.hex_distance(candidate.coords, coords)
		if distance <= 3 and distance < closest_distance:
			record = candidate
			closest_distance = distance
	if record == null or not _world_state.is_entity_alive(record.entity_id):
		_show_interaction_result(
			"INTERRUPTED",
			"The noise carried, but no hostile was close enough to reach you yet."
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
	# Freeze the player's current live projection before WorldCore assembles the
	# immutable encounter snapshot.
	if not _world_state.set_player_record(
		player_token.capture_runtime_record(),
		player_token.current_hex_coords
	):
		push_error("Combat request rejected: player runtime could not be committed.")
		return
	var combat_coords: Vector2i = request.get("coords", Vector2i.ZERO)
	var encounter := _build_combat_encounter_record(request)
	if encounter == null:
		push_error("Combat request rejected: source hex could not be resolved.")
		return
	if _world_state.begin_combat_handoff(encounter) == null:
		push_error("Combat request rejected: authoritative handoff could not be registered.")
		return
	request["encounter"] = encounter.to_dict()
	_pending_interaction.clear()
	if exploration_window and exploration_window.is_open():
		exploration_window.close_window(false)
	if macro_hud:
		# Hard-reset the complete exploration surface before the director adds
		# combat. A collision dimmer with MOUSE_FILTER_STOP must never survive
		# merely because its modal state changed during the same frame.
		macro_hud.clear_exploration_presentation(false)
	combat_requested.emit(request)


func _build_combat_encounter_record(request: Dictionary) -> CombatEncounterRecord:
	return _combat_encounter_service.build(request)

func _get_loot_profile(hex_data: MacroHexData) -> Dictionary:
	var profile_id := WorldRules.get_loot_profile_id(
		hex_data.biome,
		hex_data.poi_id,
		hex_data.region,
		hex_data.search_site_id,
		hex_data.loot_tier_id
	)
	return _loot_catalog.call("get_profile_descriptor", profile_id)


func _get_camp_access(
	coords: Vector2i,
	hex_data: MacroHexData
) -> Dictionary:
	var hostile_present := false
	var entity_snapshot := _world_state.get_entity_snapshot_at(coords)
	if not entity_snapshot.is_empty():
		var entity_id := str(entity_snapshot.get("entity_id", ""))
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
	if (
		macro_hud
		and macro_hud.is_location_open()
		and _pending_interaction.get("type") == GameEnums.MacroInteractionType.POI
	):
		_refresh_world_hud()
		macro_hud.show_location_outcome(title, message)
	elif exploration_window and exploration_window.is_open():
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
	selected_item_ids: Array,
	mode: String
) -> Dictionary:
	return _poi_selection_action_service.resolve(
		coords,
		selected_item_ids,
		mode
	)

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
	var record_snapshot := _world_state.get_entity_snapshot(entity_id) if _world_state else {}
	var record := (
		EntityRecord.from_dict(record_snapshot)
		if not record_snapshot.is_empty()
		else null
	)
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


func refresh_hex_runtime_projection(coords: Vector2i) -> void:
	## RuntimeStateStore is authoritative after cross-scene application. Refresh
	## the live MacroHexData projection so a later save synchronization cannot
	## overwrite combat-site mutations with a stale scene copy.
	if _world_state == null or world_generator == null:
		return
	var record := _world_state.get_hex_record(coords)
	var projection := world_generator.get_hex_at(coords)
	if record == null or projection == null:
		return
	projection.apply_state(record)
	_refresh_exploration_ground()

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
	if _is_player_movement_active():
		_last_macro_event = "Cannot retreat while another movement is still resolving."
		_refresh_world_hud()
		return false

	var occupying_id := _world_state.get_entity_id_at(retreat_coords)
	if not occupying_id.is_empty() and _world_state.is_entity_alive(occupying_id):
		_last_macro_event = "Escape route occupied at HEX %d,%d." % [
			retreat_coords.x,
			retreat_coords.y,
		]
		_refresh_world_hud()
		return false

	_select_hex_for_hud(retreat_coords)
	_begin_player_route([retreat_coords], "retreat", false)
	_movement_state["phase"] = "walking"
	_movement_state["can_cancel"] = false
	_movement_state["message"] = "TURN RESOLVE // RETREAT TO HEX %d,%d..." % [
		retreat_coords.x,
		retreat_coords.y,
	]
	var movement_id := player_token.walk_to_hex(
		retreat_coords,
		map_visualizer.map_to_local(retreat_coords)
	)
	_pending_player_step = {
		"kind": "retreat",
		"resolution_id": int(_movement_state.get("resolution_id", 0)),
		"movement_id": movement_id,
		"from": current_coords,
		"to": retreat_coords,
		"started_minute": _world_state.world_time_minutes,
	}
	_last_macro_event = _movement_state["message"]
	_refresh_world_hud()
	return true
func refresh_proximity(center_coords: Vector2i) -> void:
	if _is_player_movement_active():
		_movement_debug_mark("proximity/NPC update")
	_get_proximity_director().refresh_proximity(center_coords)

func _force_project_npc_token(record: EntityRecord) -> MacroEnemy:
	return _get_proximity_director().force_project_npc_token(record)

func _advance_npc_macro_turn(allow_during_interaction: bool = false) -> bool:
	if _pending_interaction.is_empty() == false and not allow_during_interaction:
		return false
	_macro_turn_index += 1
	var player_coords := player_token.current_hex_coords
	var turn_result := _npc_turn_service.advance_turn(
		player_coords,
		_world_state.world_seed,
		_macro_turn_index,
		npc_evaluation_radius,
		npc_wander_chance,
		npc_pursuit_radius,
		craven_pursuit_radius,
		{
			"get_hex_at": Callable(self, "_npc_get_hex_at"),
			"has_ground_items": Callable(self, "_npc_has_ground_items"),
			"get_occupying_entity_id": Callable(self, "_npc_get_occupying_entity_id"),
			"move_record": Callable(self, "_move_npc_record"),
			"collect_ground": Callable(self, "_npc_try_collect_ground"),
			"try_work": Callable(self, "_npc_try_work"),
			"refresh_proximity": Callable(self, "refresh_proximity"),
		}
	)
	_macro_log(
		"NPC macro turn %d begins (player @%s, %d total records)."
		% [
			_macro_turn_index,
			str(player_coords),
			int(turn_result.get("planning_record_count", 0)),
		]
	)
	var moved_count := int(turn_result.get("moved_count", 0))
	var collision: Dictionary = turn_result.get("collision", {})
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
	if record == null:
		return ""
	# This callback is consumed by HUD/snapshot builders. The simulator helper
	# normalizes missing fields by writing the supplied record, so keep even
	# direct callers from turning presentation into an authority mutation.
	var projection_record := EntityRecord.from_dict(record.to_dict())
	return _NpcSimulator.ensure_npc_purpose(projection_record)


func _notify_npcs_of_noise(coords: Vector2i, event_id: String) -> void:
	_npc_perception_service.emit_noise(
		_world_state,
		world_generator,
		coords,
		event_id,
		_macro_turn_index
	)


func _notify_npcs_of_signal(signal_record: WorldSignalRecord) -> void:
	_npc_perception_service.notify_signal(
		_world_state,
		world_generator,
		signal_record,
		_macro_turn_index
	)


func _npc_try_collect_ground(record: EntityRecord) -> void:
	_npc_runtime_service.collect_ground_items(
		_world_state,
		record,
		Callable(self, "_build_npc_pickup_receipt"),
		Callable(self, "_commit_world_action_receipt"),
	)


func _build_npc_pickup_receipt(
	record: EntityRecord,
	instance_id: String
) -> WorldActionReceipt:
	if record == null:
		return null
	var pickup_request := WorldActionRequest.new()
	pickup_request.actor_id = record.entity_id
	pickup_request.target_id = instance_id
	pickup_request.target_coords = record.coords
	pickup_request.verb_id = WorldActionResolver.VERB_PICK_UP
	pickup_request.expected_actor_revision = record.revision
	pickup_request.payload["world_time_minutes"] = _world_state.world_time_minutes
	pickup_request.payload["action_id"] = "npc-pickup:%s:%s:%d" % [
		record.entity_id,
		instance_id,
		record.revision,
	]
	var receipt := _world_action_coordinator.resolve_direct_action(
		pickup_request,
		_time_rules_service.action_minutes("action"),
		0.05,
		0.0,
		"%s picked up carried salvage." % record.entity_id
	)
	if receipt != null:
		receipt.mutations.append({
			"type": "transfer_ground_item",
			"instance_id": instance_id,
		})
	return receipt


func _initialize_npc_runtime(record: EntityRecord) -> void:
	_npc_runtime_service.initialize_runtime(
		_world_state,
		record,
		_macro_turn_index,
		player_token.current_hex_coords,
		Callable(self, "_materialize_npc_loadout"),
		Callable(self, "_npc_get_hex_at"),
		Callable(self, "_npc_has_ground_items")
	)

func _move_npc_record(
	record: EntityRecord,
	target_coords: Vector2i
) -> bool:
	var old_coords := record.coords
	# NPC travel is the same committed action as player travel. The token can
	# animate after this point, but the actor's location and elapsed time have a
	# single authoritative receipt boundary.
	var target_hex := world_generator.get_hex_at(target_coords)
	var move_request := WorldActionRequest.new()
	move_request.actor_id = record.entity_id
	move_request.target_id = "hex:%s" % str(target_coords)
	move_request.target_coords = target_coords
	move_request.verb_id = "travel"
	move_request.payload["world_time_minutes"] = _world_state.world_time_minutes
	move_request.payload["action_id"] = "travel:%s:%s:%s:%d" % [
		record.entity_id,
		str(old_coords),
		str(target_coords),
		record.revision,
	]
	var move_receipt := _world_action_coordinator.resolve_direct_action(
		move_request,
		_time_rules_service.move_minutes_for_hex(target_hex),
		_time_rules_service.exertion_for_hex(target_hex),
		0.0,
		"NPC arrived at HEX %d,%d." % [target_coords.x, target_coords.y]
	)
	move_receipt.mutations.append({
		"type": "move_actor",
		"from": old_coords,
		"to": target_coords,
	})
	_movement_service.append_trace_to_receipt(
		move_receipt,
		record.entity_id,
		old_coords,
		target_coords,
		str(campaign.active_node_id) if campaign != null else "",
		_world_state.world_time_minutes,
		target_hex
	)
	var application := _commit_world_action_receipt(
		move_receipt,
		target_coords,
		null,
		record.entity_id
	)
	if application == null or not application.applied:
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
	_npc_runtime_service.refresh_encounters(
		_world_state,
		world_generator,
		mob_spawner,
		center_coords,
		generation_radius,
		max_new_encounters_per_refresh,
		safe_start_radius,
		base_enemy_spawn_chance,
		fog_gated_spawning,
		Callable(self, "_is_hex_visible"),
		Callable(self, "_npc_get_hex_at"),
		Callable(self, "_initialize_npc_runtime"),
		Callable(self, "_log_seeded_encounter"),
	)


func _log_seeded_encounter(
	entity_id: String,
	faction: GameEnums.Faction,
	coords: Vector2i,
	spawn_chance: float
) -> void:
	_macro_log(
		"Seeded encounter %s (%s) @%s [chance %.3f, out-of-sight fog]."
		% [
			entity_id,
			GameEnums.Faction.keys()[faction],
			str(coords),
			spawn_chance,
		]
	)


func _coords_in_radius(center_coords: Vector2i, radius: int) -> Array[Vector2i]:
	return _NpcSimulator.coords_in_radius(center_coords, radius)


func _hex_distance(from_coords: Vector2i, to_coords: Vector2i) -> int:
	return _NpcSimulator.hex_distance(from_coords, to_coords)


func _encounter_key(coords: Vector2i) -> String:
	return _NpcSimulator.encounter_key(_world_state.world_seed, coords)

func _spawn_enemy_token_from_record(record: EntityRecord) -> MacroEnemy:
	return _get_proximity_director().spawn_from_record(record)
