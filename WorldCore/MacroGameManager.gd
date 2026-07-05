extends Node2D
class_name MacroGameManager

# Cross-system handoff contains only IDs, primitives, and GameEnums values.
signal combat_requested(request: Dictionary)
signal save_requested
signal load_requested
signal core_activated

@export_group("The Strings")
@export var world_generator: HexWorldGenerator
@export var map_visualizer: HexMapVisualizer
@export var player_token: MacroPlayer
@export var enemy_token_scene: PackedScene
@export var mob_spawner: MobSpawner
@export var interaction_panel: MacroInteractionPanel
@export var inventory_panel: InventoryUI
@export var macro_hud: MacroHudController
@export var exploration_window_scene: PackedScene

var exploration_window: MacroExplorationWindow

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

var active_enemies: Dictionary = {} # Stores Vector2i -> MacroEnemy projections
var _visible_hexes: Dictionary = {} # Vector2i -> true for the current line of sight
var _world_state: RuntimeStateStore
var _loot_catalog: Node
var _world_bootstrapped := false
var _pending_interaction: Dictionary = {}
var _last_inventory_error: String = ""
var _selected_hex_coords: Vector2i = Vector2i.ZERO
var _macro_turn_index := 0
var _last_macro_event := "Macro systems nominal."
var _mutation_store: Node

const HEX_NEIGHBORS = [
	Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1), 
	Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1)
]
const _SnapshotBuilder := preload("res://WorldCore/MacroSnapshotBuilder.gd")
const _PoiController := preload("res://WorldCore/MacroPoiController.gd")
const _NpcSimulator := preload("res://WorldCore/MacroNpcSimulator.gd")

func configure_services(
	world_state: RuntimeStateStore,
	loot_catalog: Node
) -> void:
	_world_state = world_state
	_loot_catalog = loot_catalog
	if world_generator:
		world_generator.configure_services(world_state)
	if is_node_ready() and not _world_bootstrapped:
		_bootstrap_world()


func get_runtime_state_store() -> RuntimeStateStore:
	return _world_state


func debug_step_player_to(target_coords: Vector2i) -> void:
	_execute_player_step(target_coords)


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
	if _loot_catalog == null:
		_loot_catalog = get_node("/root/LootCatalog")
	if not mob_spawner:
		mob_spawner = get_node_or_null("/root/MobSpawner") as MobSpawner
	if world_generator and _world_state:
		world_generator.configure_services(_world_state)

	if not world_generator or not map_visualizer or not player_token or not mob_spawner:
		push_error("The Puppet Master is missing its strings. Check the inspector.")
		return

	if interaction_panel:
		interaction_panel.poi_action_submitted.connect(resolve_poi_action)
		interaction_panel.poi_preview_requested.connect(preview_poi_action)
		interaction_panel.talk_action_submitted.connect(resolve_talk_action)
		interaction_panel.ambush_submitted.connect(resolve_entity_ambush)
		interaction_panel.inventory_requested.connect(open_inventory)
		interaction_panel.interaction_closed.connect(close_macro_interaction)

	if exploration_window_scene:
		exploration_window = (
			exploration_window_scene.instantiate() as MacroExplorationWindow
		)
		exploration_window.name = "MacroExplorationWindow"
		add_child(exploration_window)
		exploration_window.poi_action_submitted.connect(resolve_poi_action)
		exploration_window.poi_preview_requested.connect(preview_poi_action)
		exploration_window.inventory_action_requested.connect(resolve_inventory_action)
		exploration_window.interaction_closed.connect(close_macro_interaction)
	else:
		push_error("[MacroGameManager] Missing exploration_window_scene.")

	if inventory_panel:
		inventory_panel.inventory_action_requested.connect(resolve_inventory_action)
		inventory_panel.inventory_closed.connect(_on_inventory_closed)

	if macro_hud:
		macro_hud.hex_preview_expand_requested.connect(_expand_hex_at)
		macro_hud.hex_preview_travel_requested.connect(_on_hex_preview_travel)
		macro_hud.viewport_insets_changed.connect(_on_hud_viewport_insets_changed)
		macro_hud.medical_action_requested.connect(_on_medical_action_requested)
		if inventory_panel:
			macro_hud.get_inventory_corner_panel().inventory_ui = inventory_panel
		if exploration_window:
			macro_hud.get_hex_panel().exploration_window = exploration_window

	var player_inventory := player_token.get_humanoid_core().inventory
	player_inventory.inventory_error.connect(_on_player_inventory_error)
	player_inventory.items_spilled.connect(_on_player_items_spilled)
		
	if not _world_bootstrapped:
		_bootstrap_world()


func _bootstrap_world() -> void:
	if _world_bootstrapped or _world_state == null:
		return
	_world_bootstrapped = true
	if _world_state.consume_pending_loaded_world():
		_initialize_loaded_world()
	else:
		_initialize_demo()
	_refresh_world_hud()

func _initialize_demo() -> void:
	var seed := "DEMO_WASTELAND_01"
	_world_state.begin_new_world(seed)
	world_generator.configure_seed(seed)
	_bind_authored_map_profile()

	var start_coords := Vector2i(3, 0)
	if (
		world_generator.authored_map != null
		and world_generator.authored_map.get("start_coords") != null
	):
		start_coords = world_generator.authored_map.start_coords

	var start_pixel_pos = map_visualizer.map_to_local(start_coords)
	player_token.snap_to_hex(start_coords, start_pixel_pos)
	_world_state.set_player_record(player_token.capture_runtime_record(), start_coords)
	_mark_hex_explored(start_coords)
	_update_fog_of_war(start_coords)
	_select_hex_for_hud(start_coords)
	map_visualizer.render_radius(start_coords, 3)
	_macro_log("Demo world initialized at %s." % str(start_coords))
	refresh_proximity(start_coords)

func _initialize_loaded_world() -> void:
	if _world_state.world_seed.is_empty() or _world_state.player_record == null:
		push_error("Loaded world state is incomplete. Starting a new demo world.")
		_initialize_demo()
		return

	world_generator.configure_seed(_world_state.world_seed)
	_bind_authored_map_profile()
	player_token.restore_runtime_record(_world_state.player_record)
	var loaded_coords := _world_state.player_coords
	player_token.snap_to_hex(
		loaded_coords,
		map_visualizer.map_to_local(loaded_coords)
	)
	_mark_hex_explored(loaded_coords)
	_update_fog_of_war(loaded_coords)
	_select_hex_for_hud(loaded_coords)
	map_visualizer.render_radius(loaded_coords, 3)
	_macro_log("Loaded world initialized at %s." % str(loaded_coords))
	refresh_proximity(loaded_coords)

func synchronize_runtime_state() -> void:
	_world_state.set_player_record(
		player_token.capture_runtime_record(),
		player_token.current_hex_coords
	)
	for coords in world_generator.world_hex_cache.keys():
		var hex_data: MacroHexData = world_generator.world_hex_cache[coords]
		_world_state.set_hex_record(coords, hex_data.to_state())
	flush_world_mutations()


func flush_world_mutations() -> void:
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
	if not enemy_token_scene:
		push_error("Cannot spawn enemy. Assign the PackedScene in the Inspector.")
		return
	
	if not mob_spawner:
		push_error("Cannot spawn enemy. MobSpawner is not assigned.")
		return
	
	if _world_state.has_entity_at(coords):
		var existing := _world_state.get_entity_at(coords)
		if existing != null and _world_state.is_entity_alive(existing.entity_id):
			_spawn_enemy_token_from_record(existing)
		return

	var deterministic_key := _encounter_key(coords)
	var record := mob_spawner.generate_mob_record(
		coords,
		faction,
		difficulty,
		deterministic_key
	)
	_initialize_npc_runtime(record)
	_world_state.register_entity(record)
	_macro_log(
		"Procedural enemy %s (%s) requested @%s."
		% [record.entity_id, GameEnums.Faction.keys()[faction], str(coords)]
	)
	_spawn_enemy_token_from_record(record)

# ---------------------------------------------------------
# INPUT & MOVEMENT LOGIC
# ---------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
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
	_select_hex_for_hud(clicked_hex_coords)
	
	var distance_vector = clicked_hex_coords - player_token.current_hex_coords
	if not HEX_NEIGHBORS.has(distance_vector):
		return false # Ignored. Too far away.
		
	var target_hex := world_generator.get_hex_at(clicked_hex_coords)
	if not target_hex.is_passable():
		return false # Ignored. Rock fields are unpassable.

	_execute_player_step(clicked_hex_coords)
	return true

func _execute_player_step(target_coords: Vector2i) -> void:
	if not _pending_interaction.is_empty():
		return
	var origin_coords := player_token.current_hex_coords
	var pixel_pos = map_visualizer.map_to_local(target_coords)
	player_token.walk_to_hex(target_coords, pixel_pos)
	_select_hex_for_hud(target_coords)
	_world_state.update_player_runtime(
		player_token.get_humanoid_core().capture_runtime_state().to_dict(),
		target_coords
	)
	map_visualizer.render_radius(target_coords, 3)
	_macro_log("Player stepped to %s." % str(target_coords))
	_update_fog_of_war(target_coords)
	refresh_proximity(target_coords)

	var hex_data := world_generator.get_hex_at(target_coords)
	_mark_hex_explored(target_coords, hex_data)
	_advance_survival_time(
		GameTimeRules.MOVE_MINUTES,
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
		
	if _world_state.has_ground_items(target_coords):
		_last_macro_event = "Ground items detected at HEX %d,%d." % [
			target_coords.x,
			target_coords.y,
		]

	advance_macro_world(1)
	_refresh_world_hud()

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
func _update_fog_of_war(center_coords: Vector2i) -> void:
	_visible_hexes.clear()
	var newly_revealed := 0
	for coords in _coords_in_radius(center_coords, vision_radius):
		_visible_hexes[coords] = true
		var hex_data := world_generator.get_hex_at(coords)
		if not hex_data.is_explored:
			hex_data.is_explored = true
			_world_state.set_hex_record(coords, hex_data.to_state())
			newly_revealed += 1
	_macro_log(
		"Fog update @%s: %d visible hex(es), %d newly explored."
		% [str(center_coords), _visible_hexes.size(), newly_revealed]
	)

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
		return 2.5
	if biome == GameEnums.GridBiome.SWAMP or biome == GameEnums.GridBiome.MUD:
		return 2.0
	return 1.0

func _get_exertion_for_hex(hex_data: MacroHexData) -> float:
	return hex_data.travel_exertion()

func begin_poi_interaction(
	coords: Vector2i,
	hex_data: MacroHexData
) -> void:
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
		macro_hud.dock_hex_session(session)
	else:
		exploration_window.open_landmark(session, inventory_snapshot)

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
	if not interaction_panel:
		push_error("Entity interaction opened without a presentation subscriber.")
		return
	interaction_panel.open_entity_collision({
		"entity_name": _world_state.get_entity(enemy_id).definition.get(
			"archetype_name",
			"Unknown"
		),
	})

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
		if selected_search_option_id == "activate_core":
			_resolve_core_activation(coords, hex_data)
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

	var message: String
	if outcome == GameEnums.NegotiationOutcome.ROB_SUCCESS:
		_world_state.set_entity_world_status(
			enemy_id,
			GameEnums.EntityWorldStatus.WITHDRAWN
		)
		var rob_result: Dictionary = MacroInteractionResolver.resolve_rob_transfer(
			enemy_record.definition,
			_loot_catalog,
			player_core,
			player_token.current_hex_coords
		)
		message = str(rob_result.get("message", ""))
		if not rob_result.get("player_runtime", {}).is_empty():
			_world_state.update_player_runtime(
				rob_result.get("player_runtime", {}),
				player_token.current_hex_coords
			)
		if not rob_result.get("ground_items", []).is_empty():
			_world_state.add_ground_items(
				player_token.current_hex_coords,
				rob_result.get("ground_items", [])
			)
	elif outcome == GameEnums.NegotiationOutcome.INTIMIDATED:
		_world_state.set_entity_world_status(
			enemy_id,
			GameEnums.EntityWorldStatus.WITHDRAWN
		)
		message = "The target backs away and leaves the area."
	else:
		_world_state.set_entity_world_status(
			enemy_id,
			GameEnums.EntityWorldStatus.CEASEFIRE
		)
		message = "Both sides lower their weapons and separate."

	unload_enemy_token(_pending_interaction.get("coords", Vector2i.ZERO))
	if interaction_panel:
		_show_interaction_result("NEGOTIATION SUCCESS", message)

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
	if interaction_panel and interaction_panel.is_open():
		interaction_panel.close_panel(false)
	if exploration_window and exploration_window.is_open():
		exploration_window.close_window(false)
	if macro_hud:
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
	if macro_hud:
		macro_hud.toggle_inventory_panel()


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
	pass

func resolve_inventory_action(
	action_id: String,
	instance_id: String,
	equipment_slot: int
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
		_inventory_error_or
	)

	for item_state in result.get("ground_restore", []):
		_world_state.add_ground_items(coords, [item_state])
	if not result.get("ground_mutations", []).is_empty():
		_world_state.add_ground_items(
			coords,
			result.get("ground_mutations", [])
		)

	_world_state.update_player_runtime(
		result.get("player_runtime", {}),
		coords
	)
	_emit_inventory_item_used(result)
	var snapshot := _build_inventory_snapshot()
	if inventory_panel and inventory_panel.is_open():
		inventory_panel.open_loadout_panel(snapshot, "")
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
	return _SnapshotBuilder.build_world_hud_snapshot(
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
	snapshot["backpack"] = inventory_snapshot.get("backpack", [])
	snapshot["current_capacity"] = inventory_snapshot.get("current_capacity", 0)
	snapshot["maximum_capacity"] = inventory_snapshot.get("maximum_capacity", 0)
	var hex_data := world_generator.get_hex_at(_selected_hex_coords)
	snapshot["selected_scene_descriptor"] = EventBgCatalog.build_scene_descriptor(
		hex_data,
		_world_state.world_seed,
		_selected_hex_coords
	)
	macro_hud.refresh(snapshot)

func _can_offer_equip(item: ItemData) -> bool:
	return (
		not _allowed_equipment_slots(item).is_empty()
		and (
			item.item_type == GameEnums.ItemType.WEAPON
			or item.item_type == GameEnums.ItemType.ARMOR
		)
	)

func _allowed_equipment_slots(item: ItemData) -> Array[int]:
	if item.item_type == GameEnums.ItemType.WEAPON:
		if item.requires_two_hands:
			return [GameEnums.EquipmentSlot.HAND]
		return [
			GameEnums.EquipmentSlot.HAND,
			GameEnums.EquipmentSlot.OFFHAND,
		]
	if (
		item.item_type == GameEnums.ItemType.ARMOR
		and item.target_slot == GameEnums.EquipmentSlot.HAND
	):
		return [GameEnums.EquipmentSlot.OFFHAND]
	if item.target_slot != GameEnums.EquipmentSlot.NONE:
		return [item.target_slot]
	return []

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
	if hex_data.poi_id != "alpha_central_hub":
		_show_interaction_result(
			"ACTIVATION BLOCKED",
			"This location cannot bring the Alpha Core online."
		)
		return
	if _mutation_store != null and bool(_mutation_store.core_activated):
		_show_interaction_result(
			"CORE ONLINE",
			"The Alpha Core is already active. The wasteland remembers."
		)
		return

	_advance_survival_time(GameTimeRules.SEARCH_MINUTES, 1.5, coords)
	if _mutation_store != null and _mutation_store.has_method("mark_core_activated"):
		_mutation_store.mark_core_activated(true)
	flush_world_mutations()
	close_macro_interaction()
	_last_macro_event = "Alpha Core activated at %s." % str(coords)
	_refresh_world_hud()
	core_activated.emit()

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
	if interaction_panel:
		interaction_panel.close_panel(false)
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
	return player_token.get_humanoid_core().inventory.find_item_by_instance_id(
		instance_id
	)


func _inventory_has_any_item_id(item_ids: Array) -> bool:
	for item in player_token.get_humanoid_core().inventory.get_all_items():
		if item_ids.has(item.id):
			return true
	return false

func _inventory_has_any_tag(tags: Array) -> bool:
	for item in player_token.get_humanoid_core().inventory.get_all_items():
		for tag in tags:
			if item.tags.has(str(tag)):
				return true
	return false

func _inventory_has_any_role(roles: Array) -> bool:
	for item in player_token.get_humanoid_core().inventory.get_all_items():
		for role in roles:
			if item.has_interaction_role(int(role)):
				return true
	return false


func _hex_label(coords: Vector2i, hex_data: MacroHexData) -> String:
	var region := _SnapshotBuilder.enum_key(
		GameEnums.MacroRegion.keys(),
		int(hex_data.region)
	)
	return "HEX %d,%d // %s" % [coords.x, coords.y, region]

func _show_interaction_result(title: String, message: String) -> void:
	if exploration_window and exploration_window.is_open():
		exploration_window.show_result(title, message)
	elif interaction_panel and interaction_panel.is_open():
		interaction_panel.show_result(title, message)
	else:
		close_macro_interaction()

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
	if not active_enemies.has(coords):
		return
	var enemy: MacroEnemy = active_enemies[coords]
	active_enemies.erase(coords)
	_macro_log("Despawned token %s @%s." % [enemy.entity_id, str(coords)])
	enemy.queue_free()

func load_enemy_token(entity_id: String) -> MacroEnemy:
	var record := _world_state.get_entity(entity_id)
	if (
		record == null
		or not _world_state.is_entity_alive(entity_id)
	):
		return null
	return _spawn_enemy_token_from_record(record)

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
	map_visualizer.render_radius(retreat_coords, 3)
	_update_fog_of_war(retreat_coords)
	_mark_hex_explored(retreat_coords, retreat_hex)
	refresh_proximity(retreat_coords)
	_last_macro_event = "Escaped combat; fell back to HEX %d,%d." % [
		retreat_coords.x,
		retreat_coords.y,
	]
	_refresh_world_hud()
	return true

func refresh_proximity(center_coords: Vector2i) -> void:
	var tokens_before := active_enemies.size()
	_ensure_encounter_records(center_coords)

	# Hysteresis: tokens are projected within active_radius but only torn down
	# once they drift past the larger unload_radius. Using a single radius for
	# both made tokens thrash (despawn/respawn) whenever the player stepped back
	# and forth across the boundary.
	for coords in active_enemies.keys().duplicate():
		var token: MacroEnemy = active_enemies[coords]
		var distance := _hex_distance(center_coords, coords)
		var alive := _world_state.is_entity_alive(token.entity_id)
		if distance > unload_radius or not alive:
			_macro_log(
				"Unload token %s @%s (dist %d, alive %s)."
				% [token.entity_id, str(coords), distance, str(alive)]
			)
			unload_enemy_token(coords)

	_trim_visible_npc_tokens(center_coords)

	for record in _projection_candidates(center_coords):
		if active_enemies.size() >= max_visible_npc_tokens:
			break
		_spawn_enemy_token_from_record(record)

	_trim_visible_npc_tokens(center_coords)
	if active_enemies.size() != tokens_before:
		_macro_log(
			"Proximity @%s: tokens %d -> %d (cap %d)."
			% [
				str(center_coords),
				tokens_before,
				active_enemies.size(),
				max_visible_npc_tokens,
			]
		)

func _projection_candidates(center_coords: Vector2i) -> Array:
	return _NpcSimulator.projection_candidates(
		_world_state.get_all_entity_records(),
		center_coords,
		active_radius,
		Callable(_world_state, "is_entity_alive"),
	)


func _projection_score(record: EntityRecord, center_coords: Vector2i) -> float:
	return _NpcSimulator.projection_score(record, center_coords)

func _trim_visible_npc_tokens(center_coords: Vector2i) -> void:
	var visible_coords := active_enemies.keys()
	visible_coords.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var a_record := _world_state.get_entity(
			(active_enemies[a] as MacroEnemy).entity_id
		)
		var b_record := _world_state.get_entity(
			(active_enemies[b] as MacroEnemy).entity_id
		)
		if a_record == null or b_record == null:
			return a_record != null
		return _projection_score(a_record, center_coords) > _projection_score(b_record, center_coords)
	)
	while visible_coords.size() > max_visible_npc_tokens:
		var coords_to_unload: Vector2i = visible_coords.pop_back()
		unload_enemy_token(coords_to_unload)

func _force_project_npc_token(record: EntityRecord) -> MacroEnemy:
	if record == null:
		return null
	if active_enemies.has(record.coords):
		return active_enemies[record.coords]
	if active_enemies.size() >= max_visible_npc_tokens:
		_trim_visible_npc_tokens(player_token.current_hex_coords)
	if active_enemies.size() >= max_visible_npc_tokens:
		var farthest_coords := _farthest_visible_token_coords(player_token.current_hex_coords)
		if active_enemies.has(farthest_coords):
			unload_enemy_token(farthest_coords)
	return _spawn_enemy_token_from_record(record)

func _farthest_visible_token_coords(center_coords: Vector2i) -> Vector2i:
	return _NpcSimulator.farthest_token_coords(
		active_enemies.keys(),
		center_coords
	)

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
		_apply_fog_tint(token, target_coords)
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
	if not enemy_token_scene:
		push_error("Cannot spawn enemy. Assign the PackedScene in the Inspector.")
		return null

	var entity_id: String = record.entity_id
	if not _world_state.is_entity_alive(entity_id):
		return null

	var coords: Vector2i = record.coords
	if active_enemies.has(coords):
		var existing := active_enemies[coords] as MacroEnemy
		# Same entity already projected here: reuse it. A DIFFERENT entity sharing
		# the coord means the index desynced (e.g. a record relocated without its
		# token); tear the stale token down so we never render the wrong identity.
		if existing != null and existing.entity_id == entity_id:
			_apply_fog_tint(existing, coords)
			return existing
		_macro_log(
			"Replacing stale token at %s (%s -> %s)."
			% [
				str(coords),
				str(existing.entity_id) if existing != null else "<null>",
				entity_id,
			]
		)
		unload_enemy_token(coords)

	var enemy := enemy_token_scene.instantiate() as MacroEnemy
	add_child(enemy)
	enemy.setup_from_record(record.to_dict())
	enemy.snap_to_hex(coords, map_visualizer.map_to_local(coords))
	active_enemies[coords] = enemy
	_apply_fog_tint(enemy, coords)

	var definition_state: Dictionary = record.definition
	_macro_log(
		"Spawned token %s (%s) at hex %s."
		% [
			entity_id,
			str(definition_state.get("archetype_name", "Unknown")),
			str(coords),
		]
	)
	return enemy

## Dim tokens that sit in explored-but-currently-unseen hexes so the fog-of-war
## state reads visually: enemies inside the player's sight are fully lit, those
## lurking just out of view are shadowed.
func _apply_fog_tint(enemy: MacroEnemy, coords: Vector2i) -> void:
	if enemy == null:
		return
	enemy.modulate.a = 1.0 if _is_hex_visible(coords) else 0.45
