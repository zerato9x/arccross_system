extends Node2D
class_name MacroGameManager

# Cross-system handoff contains only IDs, primitives, and GameEnums values.
signal combat_requested(request: Dictionary)
signal save_requested
signal load_requested

@export_group("The Strings")
@export var world_generator: HexWorldGenerator
@export var map_visualizer: HexMapVisualizer
@export var player_token: MacroPlayer
@export var enemy_token_scene: PackedScene
@export var mob_spawner: MobSpawner
@export var interaction_panel: MacroInteractionPanel
@export var inventory_panel: InventoryUI
@export var world_hud: WorldHUD

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

const NPC_PURPOSE_SCAVENGE := "scavenge"
const NPC_PURPOSE_PATROL := "patrol"
const NPC_PURPOSE_HUNT := "hunt"
const NPC_PURPOSE_ROAM := "roam"

var active_enemies: Dictionary = {} # Stores Vector2i -> MacroEnemy projections
var _visible_hexes: Dictionary = {} # Vector2i -> true for the current line of sight
var _world_state: RuntimeStateStore
var _loot_catalog: Node
var _pending_interaction: Dictionary = {}
var _last_inventory_error: String = ""
var _selected_hex_coords: Vector2i = Vector2i.ZERO
var _macro_turn_index := 0
var _last_macro_event := "Macro systems nominal."

const HEX_NEIGHBORS = [
	Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1), 
	Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1)
]

func _ready() -> void:
	_world_state = get_node("/root/WorldState") as RuntimeStateStore
	_loot_catalog = get_node("/root/LootCatalog")
	if not mob_spawner:
		mob_spawner = get_node_or_null("/root/MobSpawner") as MobSpawner

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

	if inventory_panel:
		inventory_panel.inventory_action_requested.connect(
			resolve_inventory_action
		)
		inventory_panel.inventory_closed.connect(_on_inventory_closed)

	if world_hud:
		world_hud.inventory_requested.connect(open_inventory)
		world_hud.save_requested.connect(save_requested.emit)
		world_hud.load_requested.connect(load_requested.emit)
		world_hud.hex_action_requested.connect(_resolve_hex_hud_action)

	var player_inventory := player_token.get_humanoid_core().inventory
	player_inventory.inventory_error.connect(_on_player_inventory_error)
	player_inventory.items_spilled.connect(_on_player_items_spilled)
		
	if _world_state.consume_pending_loaded_world():
		_initialize_loaded_world()
	else:
		_initialize_demo()
	_refresh_world_hud()

func _initialize_demo() -> void:
	var seed := "DEMO_WASTELAND_01"
	_world_state.begin_new_world(seed)
	world_generator.configure_seed(seed)
	
	# Alpha starts in the safe city. Random starts can replace this later
	# without changing the hub's region or POI contract.
	var start_coords = Vector2i(0, 0)
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

## Legacy: spawn from a pre-built definition .tres (still works).
func spawn_macro_enemy(coords: Vector2i) -> void:
	push_warning("spawn_macro_enemy requires a persistent entity record and is deprecated.")

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
		if inventory_panel:
			if inventory_panel.is_open():
				inventory_panel.close_panel()
			elif _pending_interaction.is_empty():
				open_inventory()
		get_viewport().set_input_as_handled()
		return
	if inventory_panel and inventory_panel.is_open():
		return
	if not _pending_interaction.is_empty():
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
	var pixel_pos = map_visualizer.map_to_local(target_coords)
	player_token.walk_to_hex(target_coords, pixel_pos)
	_select_hex_for_hud(target_coords)
	_world_state.update_player_runtime(
		player_token.get_humanoid_core().capture_runtime_state(),
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
			_begin_entity_collision(target_entity.entity_id, target_coords)
			return
		
	if hex_data.is_poi:
		advance_macro_world(1)
		_begin_poi_interaction(target_coords, hex_data)
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
		"scan":
			_select_hex_for_hud(_selected_hex_coords)
		"travel":
			_try_travel_to_selected_hex()
		"act":
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
	var coords := player_token.current_hex_coords
	var hex_data := world_generator.get_hex_at(coords)
	if active_enemies.has(coords):
		var enemy: MacroEnemy = active_enemies[coords]
		_begin_entity_collision(enemy.entity_id, coords)
		return
	if hex_data.is_poi:
		_begin_poi_interaction(coords, hex_data)
		return
	if _world_state.has_ground_items(coords):
		open_inventory()
		return
	_last_macro_event = "No immediate interaction at HEX %d,%d." % [
		coords.x,
		coords.y,
	]
	_refresh_world_hud()

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
			current_player_core.capture_runtime_state(),
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

func _begin_poi_interaction(
	coords: Vector2i,
	hex_data: MacroHexData
) -> void:
	_pending_interaction = {
		"type": GameEnums.MacroInteractionType.POI,
		"coords": coords,
	}
	player_token.play_interaction()
	set_process_unhandled_input(false)
	if not interaction_panel:
		push_error("POI interaction opened without a presentation subscriber.")
		close_macro_interaction()
		return
	_present_poi_session(coords, hex_data)

func _present_poi_session(
	coords: Vector2i,
	hex_data: MacroHexData
) -> void:
	var camp_items := _camp_item_descriptors(hex_data.camp_item_states)
	var camp_item_ids: Array = []
	for descriptor in camp_items:
		camp_item_ids.append(descriptor.get("instance_id", ""))
	var camp_access := _get_camp_access(coords, hex_data)
	var search_options := _evaluated_search_options(coords, hex_data)
	var camp_interactions := _evaluated_camp_interactions(
		MacroInteractionResolver.build_camp_interactions(
			hex_data,
			camp_access
		)
	)
	interaction_panel.open_poi({
		"poi_name": hex_data.poi_name,
		"hex_label": _hex_label(coords, hex_data),
		"search_metric_keys": MacroInteractionResolver.SEARCH_KEYS,
		"camp_metric_keys": MacroInteractionResolver.CAMP_KEYS,
		"search_options": search_options,
		"camp_interactions": camp_interactions,
		"available_items": _available_interaction_options(),
		"camp_items": _camp_item_options(hex_data.camp_item_states),
		"camp_item_ids": camp_item_ids,
		"camp_allowed": camp_access.get("allowed", false),
		"camp_block_reason": camp_access.get("reason", ""),
		"world_time": _world_state.get_world_time_snapshot(),
	})

func _begin_entity_collision(enemy_id: String, coords: Vector2i) -> void:
	if not _pending_interaction.is_empty():
		return
	var enemy_record := _world_state.get_entity(enemy_id)
	if enemy_record == null or not _world_state.is_entity_hostile(enemy_id):
		return
	var definition: Dictionary = enemy_record.definition
	_pending_interaction = {
		"type": GameEnums.MacroInteractionType.ENTITY_COLLISION,
		"coords": coords,
		"enemy_id": enemy_id,
	}
	player_token.play_interaction()
	if active_enemies.has(coords):
		var enemy: MacroEnemy = active_enemies[coords]
		enemy.play_interaction()
	set_process_unhandled_input(false)
	if not interaction_panel:
		push_error("Entity interaction opened without a presentation subscriber.")
		close_macro_interaction()
		return
	interaction_panel.open_entity_collision({
		"entity_name": definition.get("archetype_name", "Unknown"),
	})

func preview_poi_action(
	action: GameEnums.PoiAction,
	selected_item_ids: Array,
	selected_search_option_id: String = ""
) -> void:
	if (
		_pending_interaction.get("type")
		!= GameEnums.MacroInteractionType.POI
		or not interaction_panel
	):
		return
	var coords: Vector2i = _pending_interaction.get("coords", Vector2i.ZERO)
	var hex_data := world_generator.get_hex_at(coords)
	var profile := MacroInteractionResolver.build_poi_profile(
		_world_state.world_seed,
		coords,
		hex_data.biome,
		hex_data.poi_id
	)
	var metrics: Dictionary
	if action == GameEnums.PoiAction.SEARCH:
		var search_option := _available_search_option(
			_evaluated_search_options(coords, hex_data),
			selected_search_option_id
		)
		var base_metrics: Dictionary = profile["search"]
		if not selected_search_option_id.is_empty():
			base_metrics = MacroInteractionResolver.apply_search_option_metrics(
				profile["search"],
				search_option
			)
		var loot_profile := _get_loot_profile(hex_data)
		var descriptors := _inventory_descriptors_for_ids(
			selected_item_ids,
			GameEnums.InteractionItemRole.SEARCH_TOOL
		)
		metrics = MacroInteractionResolver.calculate_search_metrics(
			base_metrics,
			descriptors,
			hex_data.search_count,
			loot_profile.get("max_searches", 4)
		)
	else:
		var selected_states := _camp_states_for_preview(
			hex_data.camp_item_states,
			selected_item_ids
		)
		metrics = MacroInteractionResolver.calculate_camp_metrics(
			profile["camp"],
			_camp_item_descriptors(selected_states)
		)
	interaction_panel.show_poi_preview(action, metrics)

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
		_resolve_search(
			coords,
			hex_data,
			profile["search"],
			selected_item_ids,
			selected_search_option_id
		)
	else:
		var camp_access := _get_camp_access(coords, hex_data)
		if not camp_access.get("allowed", false):
			_show_interaction_result(
				"CAMP UNAVAILABLE",
				camp_access.get("reason", "This location is unsafe.")
			)
			return
		_resolve_camp(coords, hex_data, profile["camp"], selected_item_ids)

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
		message = _rob_enemy(enemy_record)
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
	_refresh_world_hud()

func open_inventory() -> void:
	if not inventory_panel:
		push_error("Inventory requested without a presentation subscriber.")
		return
	if world_hud:
		world_hud.set_inventory_open(true)
	inventory_panel.open_inventory(_build_inventory_snapshot())

func resolve_inventory_action(
	action_id: String,
	instance_id: String,
	equipment_slot: int
) -> void:
	if not inventory_panel or not inventory_panel.is_open():
		return

	_last_inventory_error = ""
	var player_core := player_token.get_humanoid_core()
	var inventory := player_core.inventory
	var coords := player_token.current_hex_coords
	var message := ""

	match action_id:
		InventoryUI.ACTION_TAKE:
			var item_state := _world_state.take_ground_item(
				coords,
				instance_id
			)
			if item_state.is_empty():
				message = "That ground item is no longer available."
			else:
				var ground_item := ItemData.from_runtime_state(item_state)
				if inventory.add_to_backpack(
					ground_item,
					equipment_slot as GameEnums.EquipmentSlot
				):
					message = "Took %s." % ground_item.display_name
				else:
					_world_state.add_ground_items(coords, [item_state])
					message = _inventory_error_or(
						"That item does not fit in the backpack."
					)
		InventoryUI.ACTION_DROP:
			var dropped := inventory.remove_item_by_instance_id(instance_id)
			if dropped:
				_world_state.add_ground_items(
					coords,
					[dropped.to_runtime_state()]
				)
				message = "Dropped %s." % dropped.display_name
			else:
				message = "That carried item is no longer available."
		InventoryUI.ACTION_EQUIP:
			var equippable := inventory.find_item_by_instance_id(instance_id)
			if equippable == null or not inventory.backpack_array.has(equippable):
				message = "Only stowed items can be equipped."
			elif (
				not inventory.can_equip_in_slot(
					equippable,
					equipment_slot as GameEnums.EquipmentSlot
				)
				or not _can_offer_equip(equippable)
			):
				message = "That item cannot be equipped in the requested slot."
			elif inventory.equip_item(
				equippable,
				equipment_slot as GameEnums.EquipmentSlot
			):
				message = "Equipped %s." % equippable.display_name
			else:
				message = _inventory_error_or("The equipment change failed.")
		InventoryUI.ACTION_UNEQUIP:
			if not inventory.paper_doll.has(equipment_slot):
				message = "That equipment slot does not exist."
			else:
				var equipped: ItemData = inventory.paper_doll[equipment_slot]
				if equipped == null or equipped.instance_id != instance_id:
					message = "That equipped item is no longer available."
				else:
					inventory.unequip_item(equipment_slot)
					message = "Unequipped %s." % equipped.display_name
		InventoryUI.ACTION_CONSUME:
			var consumable := inventory.find_item_by_instance_id(instance_id)
			if consumable == null or not inventory.backpack_array.has(consumable):
				message = "Only backpack consumables can be used."
			elif player_core.use_consumable_item(consumable):
				message = "Used %s." % consumable.display_name
			else:
				message = _inventory_error_or("The item could not be used.")
		InventoryUI.ACTION_MOVE:
			var movable := inventory.find_item_by_instance_id(instance_id)
			if movable == null or not inventory.backpack_array.has(movable):
				message = "That stowed item is no longer available."
			elif inventory.move_to_container(
				movable,
				equipment_slot as GameEnums.EquipmentSlot
			):
				message = "Moved %s." % movable.display_name
			else:
				message = _inventory_error_or("That item does not fit there.")
		InventoryUI.ACTION_LOAD_MAGAZINE:
			var magazine := inventory.find_item_by_instance_id(instance_id)
			var loaded_rounds := inventory.load_magazine(magazine)
			if loaded_rounds > 0:
				message = "Fitted %d rounds into %s." % [
					loaded_rounds,
					magazine.display_name,
				]
			else:
				message = _inventory_error_or("The magazine could not be loaded.")
		InventoryUI.ACTION_INTERACT:
			message = "That object is too large to carry. It remains on the ground."
		_:
			message = "Unknown inventory command."

	_world_state.update_player_runtime(
		player_core.capture_runtime_state(),
		coords
	)
	inventory_panel.open_inventory(
		_build_inventory_snapshot(),
		message
	)
	_refresh_world_hud()

func _on_inventory_closed() -> void:
	if world_hud:
		world_hud.set_inventory_open(false)
	_refresh_world_hud()
	if (
		_pending_interaction.get("type")
		!= GameEnums.MacroInteractionType.POI
		or not interaction_panel
	):
		return
	var coords: Vector2i = _pending_interaction.get(
		"coords",
		player_token.current_hex_coords
	)
	var hex_data := world_generator.get_hex_at(coords)
	_present_poi_session(coords, hex_data)

func _build_inventory_snapshot() -> Dictionary:
	var player_core := player_token.get_humanoid_core()
	var inventory := player_core.inventory
	var equipment: Array = []
	var seen_slots: Dictionary = {}
	for slot in GameEnums.EquipmentSlot.values():
		if slot == GameEnums.EquipmentSlot.NONE:
			continue
		if seen_slots.has(slot):
			continue
		seen_slots[slot] = true
		var equipped: ItemData = inventory.paper_doll.get(slot)
		if equipped:
			equipment.append(_item_inventory_descriptor(equipped, slot))

	var backpack: Array = []
	for item in inventory.backpack_array:
		backpack.append(_item_inventory_descriptor(
			item,
			GameEnums.EquipmentSlot.NONE,
			inventory.get_item_container_slot(item)
		))

	var ground: Array = []
	for item_state in _world_state.get_ground_items(
		player_token.current_hex_coords
	):
		ground.append(_ground_inventory_descriptor(item_state))

	var capacity_breakdown: Array = []
	var containers: Array = []
	for slot in inventory.get_storage_slots():
		var equipped: ItemData = inventory.paper_doll.get(slot)
		var container_items: Array = []
		for item in inventory.get_container_items(slot):
			container_items.append(_item_inventory_descriptor(
				item,
				GameEnums.EquipmentSlot.NONE,
				slot
			))
		capacity_breakdown.append({
			"name": equipped.display_name,
			"capacity": equipped.capacity_bonus,
		})
		containers.append({
			"slot": slot,
			"name": equipped.display_name,
			"capacity": inventory.get_container_capacity(slot),
			"used": inventory.get_container_used_capacity(slot),
			"combat_accessible": slot == GameEnums.EquipmentSlot.VEST,
			"items": container_items,
		})

	return {
		"coords": player_token.current_hex_coords,
		"world_time": _world_state.get_world_time_snapshot(),
		"current_capacity": inventory.current_size,
		"maximum_capacity": inventory.current_max_capacity,
		"capacity_breakdown": capacity_breakdown,
		"containers": containers,
		"equipment": equipment,
		"limbs": _build_limb_snapshot(player_core.body),
		"backpack": backpack,
		"ground": ground,
	}

func _build_world_hud_snapshot() -> Dictionary:
	if not player_token:
		return {}
	var player_core := player_token.get_humanoid_core()
	if not player_core or not player_core.body or not player_core.inventory:
		return {}
	var body := player_core.body
	var inventory := player_core.inventory
	return {
		"coords": player_token.current_hex_coords,
		"current_hex": _build_hex_descriptor(player_token.current_hex_coords),
		"selected_hex": _build_hex_descriptor(_selected_hex_coords),
		"macro_activity": _build_macro_activity_snapshot(),
		"last_macro_event": _last_macro_event,
		"world_time": _world_state.get_world_time_snapshot(),
		"blood": body.blood_level,
		"hunger": body.hunger,
		"thirst": body.thirst,
		"fatigue": body.fatigue,
		"core_temperature": body.core_temperature,
		"stance": player_core.stance_points,
		"stance_state": GameEnums.StanceState.keys()[player_core.current_stance],
		"morale": player_core.current_morale,
		"arc_energy": player_core.current_arc_energy,
		"red_mist": player_core.red_mist_corruption,
		"current_capacity": inventory.current_size,
		"maximum_capacity": inventory.current_max_capacity,
		"limbs": _build_limb_snapshot(body),
	}

func _build_limb_snapshot(body: HumanoidBody) -> Array:
	var limbs: Array = []
	if body == null:
		return limbs
	for region in [
		GameEnums.LimbRegion.HEAD,
		GameEnums.LimbRegion.UPPER_TORSO,
		GameEnums.LimbRegion.LOWER_TORSO,
		GameEnums.LimbRegion.LEFT_ARM,
		GameEnums.LimbRegion.RIGHT_ARM,
		GameEnums.LimbRegion.LEFT_LEG,
		GameEnums.LimbRegion.RIGHT_LEG,
	]:
		var trauma_index := int(
			body.limb_trauma.get(region, GameEnums.TraumaType.NONE)
		)
		limbs.append({
			"region": GameEnums.LimbRegion.keys()[region],
			"current": float(body.limb_hp.get(region, 0.0)),
			"maximum": body.get_limb_max(region),
			"trauma": GameEnums.TraumaType.keys()[trauma_index],
		})
	return limbs

func _refresh_world_hud() -> void:
	if world_hud:
		world_hud.show_snapshot(_build_world_hud_snapshot())

func _build_hex_descriptor(coords: Vector2i) -> Dictionary:
	var hex_data := world_generator.get_hex_at(coords)
	var player_coords := player_token.current_hex_coords
	var entity_record := _world_state.get_entity_at(coords)
	var entity_name := ""
	var entity_status := ""
	var entity_purpose := ""
	var hostile := false
	if entity_record != null and _world_state.is_entity_alive(entity_record.entity_id):
		entity_name = str(entity_record.definition.get("archetype_name", "Unknown"))
		entity_status = _enum_key(
			GameEnums.EntityWorldStatus.keys(),
			int(entity_record.world_status)
		)
		entity_purpose = _ensure_npc_purpose(entity_record).capitalize()
		hostile = _world_state.is_entity_hostile(entity_record.entity_id)

	var ground_items := _world_state.get_ground_items(coords)
	var distance := _hex_distance(player_coords, coords)
	return {
		"coords": coords,
		"label": _hex_label(coords, hex_data),
		"region": _enum_key(GameEnums.MacroRegion.keys(), int(hex_data.region)),
		"arm_direction": _enum_key(
			GameEnums.MacroArmDirection.keys(),
			int(hex_data.arm_direction)
		),
		"terrain": _enum_key(
			GameEnums.MacroTerrainTile.keys(),
			int(hex_data.terrain_tile)
		),
		"flora": _enum_key(
			GameEnums.MacroFloraLayer.keys(),
			int(hex_data.flora_layer)
		),
		"rock": _enum_key(GameEnums.MacroRockLayer.keys(), int(hex_data.rock_layer)),
		"structure": _enum_key(
			GameEnums.MacroStructureLayer.keys(),
			int(hex_data.structure_layer)
		),
		"passable": hex_data.is_passable(),
		"explored": hex_data.is_explored,
		"hazard": hex_data.hazard_level,
		"distance": distance,
		"is_current": coords == player_coords,
		"can_travel": distance == 1 and hex_data.is_passable(),
		"can_interact": (
			coords == player_coords
			and (
				hex_data.is_poi
				or not ground_items.is_empty()
				or hostile
			)
		),
		"is_poi": hex_data.is_poi,
		"poi_name": hex_data.poi_name,
		"search_count": hex_data.search_count,
		"camp_rest_count": hex_data.camp_rest_count,
		"ground_item_count": ground_items.size(),
		"entity_name": entity_name,
		"entity_status": entity_status,
		"entity_purpose": entity_purpose,
		"hostile": hostile,
	}

func _build_macro_activity_snapshot() -> Dictionary:
	var hostile_count := 0
	var passive_count := 0
	var purpose_counts: Dictionary = {}
	var nearest_hostile_distance := 999999
	var nearest_hostile_coords := Vector2i.ZERO
	var nearest_hostile_name := ""
	var player_coords := player_token.current_hex_coords
	for record in _world_state.get_all_entity_records():
		if (
			record.kind != GameEnums.RuntimeEntityKind.NPC
			or record.life_state != GameEnums.EntityLifeState.ALIVE
			or record.world_status == GameEnums.EntityWorldStatus.WITHDRAWN
		):
			continue
		if record.world_status == GameEnums.EntityWorldStatus.HOSTILE:
			hostile_count += 1
			var purpose := _ensure_npc_purpose(record)
			purpose_counts[purpose] = int(purpose_counts.get(purpose, 0)) + 1
			var distance := _hex_distance(player_coords, record.coords)
			if distance < nearest_hostile_distance:
				nearest_hostile_distance = distance
				nearest_hostile_coords = record.coords
				nearest_hostile_name = str(
					record.definition.get("archetype_name", "Unknown")
				)
		else:
			passive_count += 1
	return {
		"turn": _macro_turn_index,
		"active_tokens": active_enemies.size(),
		"hostile_count": hostile_count,
		"passive_count": passive_count,
		"purpose_counts": purpose_counts,
		"nearest_hostile_distance": nearest_hostile_distance,
		"nearest_hostile_coords": nearest_hostile_coords,
		"nearest_hostile_name": nearest_hostile_name,
	}

func _enum_key(keys: Array, value: int) -> String:
	if value >= 0 and value < keys.size():
		return str(keys[value])
	return str(value)

func _item_inventory_descriptor(
	item: ItemData,
	equipment_slot: int = GameEnums.EquipmentSlot.NONE,
	container_slot: int = GameEnums.EquipmentSlot.NONE
) -> Dictionary:
	var allowed_slots := _allowed_equipment_slots(item)
	return {
		"instance_id": item.instance_id,
		"item_id": item.id,
		"name": item.display_name,
		"description": item.lore_description,
		"item_type": item.item_type,
		"catalog_category": item.catalog_category,
		"tags": item.tags.duplicate(),
		"size_cost": item.get_inventory_cost(),
		"item_size": item.get_effective_item_size(),
		"stack_count": item.stack_count,
		"stack_limit": item.get_stack_limit(),
		"capacity_bonus": item.capacity_bonus,
		"target_slot": item.target_slot,
		"preferred_equipment_slot": (
			player_token.get_humanoid_core().inventory
				.get_preferred_equipment_slot(item)
		),
		"allowed_equipment_slots": allowed_slots,
		"equipment_slot": equipment_slot,
		"container_slot": container_slot,
		"can_equip": _can_offer_equip(item),
		"can_consume": item.item_type == GameEnums.ItemType.CONSUMABLE,
		"can_load_magazine": (
			item.is_magazine()
			and item.loaded_rounds < item.magazine_capacity
		),
		"can_pick_up": item.get_effective_item_size() != GameEnums.ItemSize.BIG,
		"sprite_path": item.get_inventory_sprite_path(),
		"equipped_sprite_paths": item.get_equipped_sprite_paths(),
		"requires_two_hands": item.requires_two_hands,
		"weapon_type": item.weapon_type,
		"damage_type": item.damage_type,
		"flesh_damage": item.flesh_damage,
		"stance_damage": item.stance_damage,
		"armor_penetration": item.armor_penetration,
		"accuracy_rating": item.accuracy_rating,
		"effective_range": item.effective_range,
		"optimal_range": item.optimal_range,
		"protection_blunt": item.protection_blunt,
		"protection_sharp": item.protection_sharp,
		"protection_ballistic": item.protection_ballistic,
		"bulk": item.bulk,
		"weight": item.weight,
		"threat": item.threat,
		"insulation": item.insulation,
		"consumable_effect": item.consumable_effect,
		"consumable_potency": item.consumable_potency,
		"current_magazine": item.current_magazine,
		"max_magazine": item.max_magazine,
		"needs_cycling": item.needs_cycling,
		"accepted_ammunition_id": item.accepted_ammunition_id,
		"magazine_capacity": item.magazine_capacity,
		"loaded_rounds": item.loaded_rounds,
		"search_loot_bonus": item.search_loot_bonus,
		"search_safety_bonus": item.search_safety_bonus,
		"search_sneak_bonus": item.search_sneak_bonus,
		"camp_sleep_bonus": item.camp_sleep_bonus,
		"camp_shelter_bonus": item.camp_shelter_bonus,
		"camp_healing_bonus": item.camp_healing_bonus,
		"camp_concealment_bonus": item.camp_concealment_bonus,
		"camp_alertness_bonus": item.camp_alertness_bonus,
	}

func _ground_inventory_descriptor(item_state: Dictionary) -> Dictionary:
	var item := ItemData.from_runtime_state(item_state)
	var descriptor := _item_inventory_descriptor(item)
	descriptor["can_equip"] = false
	descriptor["can_consume"] = false
	descriptor["can_load_magazine"] = false
	return descriptor

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

func _resolve_search(
	coords: Vector2i,
	hex_data: MacroHexData,
	base_metrics: Dictionary,
	selected_item_ids: Array,
	selected_search_option_id: String = ""
) -> void:
	var search_options := _evaluated_search_options(coords, hex_data)
	var search_option := _available_search_option(
		search_options,
		selected_search_option_id
	)
	if search_option.is_empty():
		_show_interaction_result(
			"SEARCH BLOCKED",
			"No unlocked search target is available at this hex."
		)
		return
	if bool(search_option.get("locked", false)):
		_show_interaction_result(
			"SEARCH LOCKED",
			str(search_option.get("lock_reason", "That target is locked."))
		)
		return

	var option_metrics: Dictionary = base_metrics
	if not selected_search_option_id.is_empty():
		option_metrics = MacroInteractionResolver.apply_search_option_metrics(
			base_metrics,
			search_option
		)
	var descriptors := _inventory_descriptors_for_ids(
		selected_item_ids,
		GameEnums.InteractionItemRole.SEARCH_TOOL
	)
	var metrics := MacroInteractionResolver.calculate_search_metrics(
		option_metrics,
		descriptors,
		hex_data.search_count,
		_get_loot_profile(hex_data).get("max_searches", 4)
	)
	var loot_profile := _get_loot_profile(hex_data)
	_advance_survival_time(
		GameTimeRules.SEARCH_MINUTES,
		1.0,
		coords
	)
	var result := MacroInteractionResolver.resolve_search(
		_world_state.world_seed,
		coords,
		hex_data.search_count,
		metrics,
		loot_profile,
		selected_search_option_id
	)
	if hex_data.region == GameEnums.MacroRegion.CENTRAL_HUB:
		result["injured"] = false
		result["attracted_enemy"] = false
	hex_data.search_count += 1

	var found_names: Array[String] = []
	for loot_id in result.get("loot_ids", []):
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

	if result.get("injured", false):
		player_token.get_humanoid_core().body.apply_targeted_hit(
			result.get("injury_limb", GameEnums.LimbRegion.LEFT_ARM),
			result.get("injury_damage", 0.0),
			0.0
		)

	_world_state.set_hex_record(coords, hex_data.to_state())
	_world_state.update_player_runtime(
		player_token.get_humanoid_core().capture_runtime_state(),
		coords
	)
	_refresh_world_hud()

	var message := "Target: %s\n" % str(search_option.get("label", "Search"))
	message += (
		"Found: " + ", ".join(found_names)
		if not found_names.is_empty()
		else "The search produced no usable supplies."
	)
	message += "\nTime: " + _format_world_time()
	if result.get("injured", false):
		message += "\nUnstable debris caused an injury."

	if result.get("attracted_enemy", false):
		message += "\nThe noise attracted a hostile."
		advance_macro_world(1, true)
		_spawn_search_intruder(coords)
		return
	_last_macro_event = "Searched %s at HEX %d,%d." % [
		str(search_option.get("label", "target")),
		coords.x,
		coords.y,
	]
	
	advance_macro_world(1, true)
	if not _pending_interaction.is_empty() and _pending_interaction.get("type") == GameEnums.MacroInteractionType.ENTITY_COLLISION:
		return
		
	_show_interaction_result("SEARCH COMPLETE", message)

func _resolve_camp(
	coords: Vector2i,
	hex_data: MacroHexData,
	base_metrics: Dictionary,
	selected_item_ids: Array
) -> void:
	var selected: Array[String] = []
	for instance_id in selected_item_ids:
		if not selected.has(instance_id) and selected.size() < 3:
			selected.append(instance_id)

	var existing_states: Dictionary = {}
	for item_state in hex_data.camp_item_states:
		existing_states[item_state.get("instance_id", "")] = item_state

	var new_states: Array = []
	for instance_id in selected:
		if existing_states.has(instance_id):
			new_states.append(existing_states[instance_id])
			continue
		var item := player_token.get_humanoid_core().inventory.find_item_by_instance_id(
			instance_id
		)
		if (
			item == null
			or not item.has_interaction_role(
				GameEnums.InteractionItemRole.CAMP_GEAR
			)
		):
			continue
		var removed := player_token.get_humanoid_core().inventory.remove_item_by_instance_id(
			instance_id
		)
		if removed:
			new_states.append(removed.to_runtime_state())

	for instance_id in existing_states.keys():
		if selected.has(instance_id):
			continue
		var returned_item := ItemData.from_runtime_state(existing_states[instance_id])
		if not player_token.get_humanoid_core().inventory.add_to_backpack(returned_item):
			_world_state.add_ground_items(coords, [returned_item.to_runtime_state()])

	hex_data.camp_item_states = new_states
	var descriptors := _camp_item_descriptors(new_states)
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
	if hex_data.region == GameEnums.MacroRegion.CENTRAL_HUB:
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
			if hex_data.region == GameEnums.MacroRegion.CENTRAL_HUB:
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
				player_token.get_humanoid_core().capture_runtime_state(),
				coords
			)
			_refresh_world_hud()
			_spawn_search_intruder(coords)
			return
			
		if not _pending_interaction.is_empty() and _pending_interaction.get("type") == GameEnums.MacroInteractionType.ENTITY_COLLISION:
			_world_state.set_hex_record(coords, hex_data.to_state())
			_world_state.update_player_runtime(
				player_token.get_humanoid_core().capture_runtime_state(),
				coords
			)
			_refresh_world_hud()
			return

	_world_state.set_hex_record(coords, hex_data.to_state())
	_world_state.update_player_runtime(
		player_token.get_humanoid_core().capture_runtime_state(),
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
		"context": context,
		"initiator_id": initiator_id,
		"ambush_position": ambush_position,
	}
	_pending_interaction.clear()
	if interaction_panel:
		interaction_panel.close_panel(false)
	combat_requested.emit(request)

func _available_interaction_options() -> Array:
	var descriptors: Array = []
	for item in player_token.get_humanoid_core().inventory.get_all_items():
		if not item.interaction_roles.is_empty():
			descriptors.append({
				"instance_id": item.instance_id,
				"item_id": item.id,
				"name": item.display_name,
				"tags": item.tags.duplicate(),
				"roles": item.interaction_roles.duplicate(),
			})
	return descriptors

func _inventory_descriptors_for_ids(
	instance_ids: Array,
	role: GameEnums.InteractionItemRole
) -> Array:
	var descriptors: Array = []
	for instance_id in instance_ids:
		var item := player_token.get_humanoid_core().inventory.find_item_by_instance_id(
			instance_id
		)
		if item != null and item.has_interaction_role(role):
			descriptors.append(item.to_interaction_descriptor())
	return descriptors

func _camp_item_descriptors(item_states: Array) -> Array:
	var descriptors: Array = []
	for item_state in item_states:
		var item := ItemData.from_runtime_state(item_state)
		var descriptor := item.to_interaction_descriptor()
		descriptor["installed"] = true
		descriptors.append(descriptor)
	return descriptors

func _camp_item_options(item_states: Array) -> Array:
	var options: Array = []
	for item_state in item_states:
		var definition: Dictionary = item_state.get("definition", {})
		options.append({
			"instance_id": item_state.get("instance_id", ""),
			"name": definition.get("display_name", "Unknown Camp Gear"),
			"roles": definition.get("interaction_roles", []).duplicate(),
			"installed": true,
		})
	return options

func _camp_states_for_preview(
	existing_states: Array,
	selected_item_ids: Array
) -> Array:
	var states_by_id: Dictionary = {}
	for item_state in existing_states:
		states_by_id[item_state.get("instance_id", "")] = item_state
	for instance_id in selected_item_ids:
		if states_by_id.has(instance_id):
			continue
		var item := player_token.get_humanoid_core().inventory.find_item_by_instance_id(
			instance_id
		)
		if item and item.has_interaction_role(
			GameEnums.InteractionItemRole.CAMP_GEAR
		):
			states_by_id[instance_id] = item.to_runtime_state()
	var selected_states: Array = []
	for instance_id in selected_item_ids:
		if states_by_id.has(instance_id):
			selected_states.append(states_by_id[instance_id])
	return selected_states

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
	return WorldRules.get_camp_access(
		hex_data.is_poi,
		hex_data.hazard_level,
		hostile_present
	)

func _evaluated_search_options(
	coords: Vector2i,
	hex_data: MacroHexData
) -> Array:
	var evaluated_options: Array = []
	for option in MacroInteractionResolver.build_search_options(
		_world_state.world_seed,
		coords,
		hex_data
	):
		var evaluated: Dictionary = option.duplicate(true)
		var requirements: Dictionary = evaluated.get("requirements", {})
		var unlocked := _requirements_met(requirements)
		evaluated["locked"] = not unlocked
		evaluated["lock_reason"] = "" if unlocked else _requirement_text(requirements)
		evaluated_options.append(evaluated)
	return evaluated_options

func _evaluated_camp_interactions(interactions: Array) -> Array:
	var evaluated_interactions: Array = []
	for interaction in interactions:
		var evaluated: Dictionary = interaction.duplicate(true)
		if bool(evaluated.get("available", false)):
			evaluated["lock_reason"] = ""
		else:
			var requirements: Dictionary = evaluated.get("requirements", {})
			evaluated["lock_reason"] = str(
				requirements.get("reason", "This camp interaction is unavailable.")
			)
		evaluated_interactions.append(evaluated)
	return evaluated_interactions

func _available_search_option(
	options: Array,
	selected_search_option_id: String
) -> Dictionary:
	var selected := MacroInteractionResolver.find_option(
		options,
		selected_search_option_id
	)
	if not selected.is_empty():
		return selected
	for option in options:
		if not bool(option.get("locked", false)):
			return option
	return {}

func _requirements_met(requirements: Dictionary) -> bool:
	if requirements.is_empty():
		return true

	var has_requirement := false
	var satisfied := false
	var item_ids: Array = requirements.get("any_item_ids", [])
	if not item_ids.is_empty():
		has_requirement = true
		satisfied = satisfied or _inventory_has_any_item_id(item_ids)

	var tags: Array = requirements.get("any_tags", [])
	if not tags.is_empty():
		has_requirement = true
		satisfied = satisfied or _inventory_has_any_tag(tags)

	var roles: Array = requirements.get("any_roles", [])
	if not roles.is_empty():
		has_requirement = true
		satisfied = satisfied or _inventory_has_any_role(roles)

	var traits: Array = requirements.get("any_traits", [])
	if not traits.is_empty():
		has_requirement = true

	return not has_requirement or satisfied

func _requirement_text(requirements: Dictionary) -> String:
	var parts: Array[String] = []
	var item_ids: Array = requirements.get("any_item_ids", [])
	if not item_ids.is_empty():
		parts.append("item: " + "/".join(PackedStringArray(item_ids)))
	var tags: Array = requirements.get("any_tags", [])
	if not tags.is_empty():
		parts.append("tag: " + "/".join(PackedStringArray(tags)))
	var roles: Array = requirements.get("any_roles", [])
	if not roles.is_empty():
		var role_names := PackedStringArray()
		for role in roles:
			role_names.append(_interaction_role_name(int(role)))
		parts.append("role: " + "/".join(role_names))
	var traits: Array = requirements.get("any_traits", [])
	if not traits.is_empty():
		parts.append("trait: " + "/".join(PackedStringArray(traits)))
	if parts.is_empty():
		return str(requirements.get("reason", "Requirement not met."))
	return "Requires " + " or ".join(parts) + "."

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

func _interaction_role_name(role: int) -> String:
	if role >= 0 and role < GameEnums.InteractionItemRole.keys().size():
		return GameEnums.InteractionItemRole.keys()[role]
	return str(role)

func _hex_label(coords: Vector2i, hex_data: MacroHexData) -> String:
	var region := _enum_key(GameEnums.MacroRegion.keys(), int(hex_data.region))
	return "HEX %d,%d // %s" % [coords.x, coords.y, region]

func _show_interaction_result(title: String, message: String) -> void:
	if interaction_panel:
		interaction_panel.show_result(title, message)
	else:
		close_macro_interaction()

func _format_world_time() -> String:
	var snapshot := _world_state.get_world_time_snapshot()
	return "Day %d, %02d:%02d" % [
		snapshot.get("day", 1),
		snapshot.get("hour", 0),
		snapshot.get("minute", 0),
	]

func _rob_enemy(enemy_record: EntityRecord) -> String:
	var loadout: Dictionary = enemy_record.definition.get("loadout", {})
	var candidate_paths: Array = loadout.get("starting_items", []).duplicate()
	var weapon_path: String = loadout.get("weapon", "")
	if not weapon_path.is_empty():
		candidate_paths.append(weapon_path)
	if candidate_paths.is_empty():
		return "The target withdraws, but carries nothing worth taking."

	var item := load(candidate_paths[0]) as ItemData
	if not item:
		return "The target withdraws before any usable property changes hands."
	var runtime_item := item.create_runtime_instance()
	if player_token.get_humanoid_core().inventory.add_to_backpack(runtime_item):
		_world_state.update_player_runtime(
			player_token.get_humanoid_core().capture_runtime_state(),
			player_token.current_hex_coords
		)
		return "The target surrenders %s and withdraws." % runtime_item.display_name
	_world_state.add_ground_items(
		player_token.current_hex_coords,
		[runtime_item.to_runtime_state()]
	)
	return "%s was surrendered and left on the ground." % runtime_item.display_name

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
	var candidates: Array = []
	for record in _world_state.get_all_entity_records():
		if not _can_project_npc_record(record, center_coords):
			continue
		candidates.append(record)
	candidates.sort_custom(func(a: EntityRecord, b: EntityRecord) -> bool:
		return _projection_score(a, center_coords) > _projection_score(b, center_coords)
	)
	return candidates

func _can_project_npc_record(record: EntityRecord, center_coords: Vector2i) -> bool:
	if (
		record == null
		or record.kind != GameEnums.RuntimeEntityKind.NPC
		or record.world_status == GameEnums.EntityWorldStatus.WITHDRAWN
		or not _world_state.is_entity_alive(record.entity_id)
		or _hex_distance(center_coords, record.coords) > active_radius
	):
		return false
	return true

func _projection_score(record: EntityRecord, center_coords: Vector2i) -> float:
	var distance := float(_hex_distance(center_coords, record.coords))
	var score := 100.0 - (distance * 12.0)
	if record.world_status == GameEnums.EntityWorldStatus.HOSTILE:
		score += 20.0
	var purpose := _ensure_npc_purpose(record)
	match purpose:
		NPC_PURPOSE_HUNT:
			score += 12.0
		NPC_PURPOSE_SCAVENGE:
			score += 6.0
		NPC_PURPOSE_PATROL:
			score += 4.0
	return score

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
	var farthest := Vector2i.ZERO
	var farthest_distance := -1
	for coords in active_enemies.keys():
		var distance := _hex_distance(center_coords, coords)
		if distance > farthest_distance:
			farthest = coords
			farthest_distance = distance
	return farthest

func _advance_npc_macro_turn(allow_during_interaction: bool = false) -> bool:
	if _pending_interaction.is_empty() == false and not allow_during_interaction:
		return false
	_macro_turn_index += 1
	var player_coords := player_token.current_hex_coords
	var moved_count := 0
	var collision_enemy_id := ""
	_macro_log(
		"NPC macro turn %d begins (player @%s, %d total records)."
		% [
			_macro_turn_index,
			str(player_coords),
			_world_state.get_all_entity_records().size(),
		]
	)
	var records := _world_state.get_all_entity_records()
	records.sort_custom(func(a: EntityRecord, b: EntityRecord) -> bool:
		return _hex_distance(player_coords, a.coords) < _hex_distance(player_coords, b.coords)
	)

	for record_entry in records:
		var record := record_entry as EntityRecord
		if record == null:
			continue
		if (
			record.kind != GameEnums.RuntimeEntityKind.NPC
			or record.life_state != GameEnums.EntityLifeState.ALIVE
			or record.world_status == GameEnums.EntityWorldStatus.WITHDRAWN
			or _hex_distance(player_coords, record.coords) > npc_evaluation_radius
		):
			continue
		var old_coords: Vector2i = record.coords
		var target_coords: Vector2i = _evaluate_npc_step(record, player_coords)
		if target_coords == old_coords:
			continue
		if not _move_npc_record(record, target_coords):
			continue
		moved_count += 1
		if (
			target_coords == player_coords
			and record.world_status == GameEnums.EntityWorldStatus.HOSTILE
		):
			collision_enemy_id = record.entity_id
			break

	refresh_proximity(player_coords)
	if not collision_enemy_id.is_empty():
		_last_macro_event = "A hostile closes on your hex."
		_macro_log("NPC macro turn %d ended in a collision." % _macro_turn_index)
		_begin_entity_collision(collision_enemy_id, player_coords)
		return true
	elif moved_count > 0:
		_last_macro_event = "NPC turn %d: %d token(s) repositioned." % [
			_macro_turn_index,
			moved_count,
		]
	else:
		_last_macro_event = "NPC turn %d: no nearby token committed." % _macro_turn_index
	_macro_log(
		"NPC macro turn %d ended: %d moved." % [_macro_turn_index, moved_count]
	)
	# Keep the macro-activity HUD in sync with the post-turn world so observers
	# (and the exploration smoke test) always see current hostile counts even
	# when the turn is advanced outside the normal player-step wrapper.
	_refresh_world_hud()
	return false

func _evaluate_npc_step(
	record: EntityRecord,
	player_coords: Vector2i
) -> Vector2i:
	var current_coords := record.coords
	var distance_to_player := _hex_distance(current_coords, player_coords)
	if distance_to_player <= 0:
		return current_coords

	var purpose := _ensure_npc_purpose(record)
	var rng := RandomNumberGenerator.new()
	rng.seed = (
		_world_state.world_seed
		+ ":npc_eval:"
		+ record.entity_id
		+ ":"
		+ str(_macro_turn_index)
	).hash()

	if record.world_status != GameEnums.EntityWorldStatus.HOSTILE:
		if distance_to_player <= 2:
			return _best_npc_neighbor(record, player_coords, false)
		if rng.randf() <= npc_wander_chance * 0.5:
			return _wander_npc_neighbor(record, rng)
		return current_coords

	match purpose:
		NPC_PURPOSE_HUNT:
			return _evaluate_hunt_step(record, player_coords, distance_to_player, rng)
		NPC_PURPOSE_SCAVENGE:
			return _evaluate_targeted_purpose_step(
				record,
				player_coords,
				_purpose_target_for(record, purpose),
				rng,
				true
			)
		NPC_PURPOSE_PATROL:
			return _evaluate_targeted_purpose_step(
				record,
				player_coords,
				_purpose_target_for(record, purpose),
				rng,
				false
			)
		_:
			if rng.randf() <= npc_wander_chance:
				return _wander_npc_neighbor(record, rng)
			return current_coords

func _evaluate_hunt_step(
	record: EntityRecord,
	player_coords: Vector2i,
	distance_to_player: int,
	rng: RandomNumberGenerator
) -> Vector2i:
	if record.world_status == GameEnums.EntityWorldStatus.HOSTILE:
		var pursuit_radius := _pursuit_radius_for(record)
		var label := _record_aggro_label(record)
		if distance_to_player == 1:
			print("[Aggro] ", label, " lunges at adjacent prey.")
			if _npc_can_enter(record, player_coords, player_coords):
				return player_coords
			return record.coords
		if distance_to_player <= pursuit_radius:
			print(
				"[Aggro] ", label, " pursues (dist ", distance_to_player,
				" <= leash ", pursuit_radius, ")."
			)
			return _best_npc_neighbor(record, player_coords, true)
		# Outside the aggro leash: relentless hunters loiter, but cowards lose
		# their nerve entirely and drift away from the player.
		print(
			"[Aggro] ", label, " breaks off (dist ", distance_to_player,
			" > leash ", pursuit_radius, ")."
		)
		if rng.randf() <= npc_wander_chance:
			return _wander_npc_neighbor(record, rng)
		return record.coords
	return record.coords

## Aggro leash (pursuit radius) for this record. Craven Hive thralls use a much
## shorter, cowardly leash; everyone else uses the relentless default.
func _pursuit_radius_for(record: EntityRecord) -> int:
	var faction: GameEnums.Faction = record.definition.get(
		"faction",
		GameEnums.Faction.UNALIGNED
	)
	if faction == GameEnums.Faction.CRAVEN_HIVE:
		return clampi(craven_pursuit_radius, 1, npc_pursuit_radius)
	return npc_pursuit_radius

func _record_aggro_label(record: EntityRecord) -> String:
	return str(record.definition.get("archetype_name", "NPC")) + " " + str(record.entity_id)

func _evaluate_targeted_purpose_step(
	record: EntityRecord,
	player_coords: Vector2i,
	target_coords: Vector2i,
	rng: RandomNumberGenerator,
	avoid_player: bool
) -> Vector2i:
	var distance_to_player := _hex_distance(record.coords, player_coords)
	if avoid_player and distance_to_player <= 1:
		return _best_npc_neighbor(record, player_coords, false)
	if target_coords == record.coords:
		record.runtime.erase("macro_target_coords")
		if rng.randf() <= npc_wander_chance:
			return _wander_npc_neighbor(record, rng)
		return record.coords
	var next_step := _best_step_toward(record, target_coords)
	if next_step != record.coords:
		return next_step
	if rng.randf() <= npc_wander_chance:
		return _wander_npc_neighbor(record, rng)
	return record.coords

func _ensure_npc_purpose(record: EntityRecord) -> String:
	var purpose := str(record.runtime.get("macro_purpose", ""))
	if not purpose.is_empty():
		return purpose
	var faction: GameEnums.Faction = record.definition.get(
		"faction",
		GameEnums.Faction.UNALIGNED
	)
	match faction:
		GameEnums.Faction.CRAVEN_HIVE:
			purpose = NPC_PURPOSE_HUNT
		GameEnums.Faction.ARCBORN_RESISTANCE:
			purpose = NPC_PURPOSE_PATROL
		GameEnums.Faction.SCAVENGER_CELL:
			purpose = NPC_PURPOSE_SCAVENGE
		_:
			purpose = NPC_PURPOSE_ROAM
	record.runtime["macro_purpose"] = purpose
	record.runtime["macro_purpose_label"] = purpose.capitalize()
	return purpose

func _initialize_npc_runtime(record: EntityRecord) -> void:
	if record == null:
		return
	if not record.runtime.has("macro_origin_coords"):
		record.runtime["macro_origin_coords"] = record.coords
	var purpose := _ensure_npc_purpose(record)
	if not record.runtime.has("macro_target_coords"):
		record.runtime["macro_target_coords"] = _purpose_target_for(record, purpose)

func _purpose_target_for(record: EntityRecord, purpose: String) -> Vector2i:
	var existing = record.runtime.get("macro_target_coords", null)
	if existing is Vector2i:
		return existing
	var target := record.coords
	match purpose:
		NPC_PURPOSE_SCAVENGE:
			target = _find_scavenge_target(record.coords)
		NPC_PURPOSE_PATROL:
			target = _patrol_target(record)
		NPC_PURPOSE_HUNT:
			target = player_token.current_hex_coords
		_:
			target = _roam_target(record)
	record.runtime["macro_target_coords"] = target
	return target

func _find_scavenge_target(origin: Vector2i) -> Vector2i:
	var best := origin
	var best_score := -999999.0
	for coords in _coords_in_radius(origin, 5):
		var hex_data := world_generator.get_hex_at(coords)
		if not hex_data.is_passable():
			continue
		var score := -float(_hex_distance(origin, coords))
		if hex_data.is_poi:
			score += 12.0
		if hex_data.structure_layer != GameEnums.MacroStructureLayer.NONE:
			score += 8.0
		if _world_state.has_ground_items(coords):
			score += 6.0
		if hex_data.region == GameEnums.MacroRegion.CENTRAL_HUB:
			score -= 20.0
		if score > best_score:
			best = coords
			best_score = score
	return best

func _patrol_target(record: EntityRecord) -> Vector2i:
	var patrol_points := [
		Vector2i(3, 0),
		Vector2i(3, -2),
		Vector2i(1, -3),
		Vector2i(-2, -1),
		Vector2i(-1, 3),
		Vector2i(2, 2),
	]
	var index := absi((record.entity_id + ":patrol").hash()) % patrol_points.size()
	return patrol_points[index]

func _roam_target(record: EntityRecord) -> Vector2i:
	var rng := RandomNumberGenerator.new()
	rng.seed = (
		_world_state.world_seed
		+ ":npc_roam:"
		+ record.entity_id
		+ ":"
		+ str(_macro_turn_index / 4)
	).hash()
	var choices := _coords_in_radius(record.coords, 3)
	if choices.is_empty():
		return record.coords
	return choices[rng.randi_range(0, choices.size() - 1)]

func _best_npc_neighbor(
	record: EntityRecord,
	player_coords: Vector2i,
	pursue: bool
) -> Vector2i:
	var best_coords := record.coords
	var best_distance := _hex_distance(record.coords, player_coords)
	for direction in HEX_NEIGHBORS:
		var candidate: Vector2i = record.coords + direction
		if not _npc_can_enter(record, candidate, player_coords):
			continue
		var candidate_distance := _hex_distance(candidate, player_coords)
		if (
			(pursue and candidate_distance < best_distance)
			or (not pursue and candidate_distance > best_distance)
		):
			best_coords = candidate
			best_distance = candidate_distance
	return best_coords

func _best_step_toward(record: EntityRecord, target_coords: Vector2i) -> Vector2i:
	var best_coords := record.coords
	var best_distance := _hex_distance(record.coords, target_coords)
	for direction in HEX_NEIGHBORS:
		var candidate: Vector2i = record.coords + direction
		if not _npc_can_enter(record, candidate, player_token.current_hex_coords):
			continue
		var candidate_distance := _hex_distance(candidate, target_coords)
		if candidate_distance < best_distance:
			best_coords = candidate
			best_distance = candidate_distance
	return best_coords

func _wander_npc_neighbor(
	record: EntityRecord,
	rng: RandomNumberGenerator
) -> Vector2i:
	var candidates: Array[Vector2i] = []
	for direction in HEX_NEIGHBORS:
		var candidate: Vector2i = record.coords + direction
		if _npc_can_enter(record, candidate, player_token.current_hex_coords):
			candidates.append(candidate)
	if candidates.is_empty():
		return record.coords
	return candidates[rng.randi_range(0, candidates.size() - 1)]

func _npc_can_enter(
	record: EntityRecord,
	target_coords: Vector2i,
	player_coords: Vector2i
) -> bool:
	var target_hex := world_generator.get_hex_at(target_coords)
	if not target_hex.is_passable():
		return false
	if (
		record.world_status == GameEnums.EntityWorldStatus.HOSTILE
		and target_hex.region == GameEnums.MacroRegion.CENTRAL_HUB
	):
		return false
	if target_coords == player_coords:
		return record.world_status == GameEnums.EntityWorldStatus.HOSTILE
	var occupying_id: String = _world_state.entity_ids_by_coords.get(
		target_coords,
		""
	)
	return occupying_id.is_empty() or occupying_id == record.entity_id

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
	var new_encounter_count := 0
	for coords in _coords_in_radius(center_coords, generation_radius):
		if (
			max_new_encounters_per_refresh > 0
			and new_encounter_count >= max_new_encounters_per_refresh
		):
			return
		var hex_data := world_generator.get_hex_at(coords)
		if hex_data.encounter_evaluated:
			continue

		# Fog-of-war gate: encounters are never rolled inside the player's current
		# line of sight, so a hostile can never pop into existence on-screen or on
		# top of the player. They still seed deterministically in the surrounding
		# fog (the ring between vision_radius and generation_radius) and walk into
		# view. Visible hexes are intentionally left UN-evaluated so they get a
		# fair roll later, once the player has moved on and they fall out of sight.
		if fog_gated_spawning and _is_hex_visible(coords):
			continue

		hex_data.encounter_evaluated = true
		if (
			hex_data.region == GameEnums.MacroRegion.CENTRAL_HUB
			or _hex_distance(Vector2i.ZERO, coords) <= safe_start_radius
		):
			_world_state.set_hex_record(coords, hex_data.to_state())
			continue

		var rng := RandomNumberGenerator.new()
		rng.seed = _encounter_key(coords).hash()
		var spawn_chance := _get_spawn_chance(hex_data)
		if rng.randf() < spawn_chance:
			var faction := _roll_faction(rng, hex_data)
			var difficulty := mini(
				3,
				floori(float(_hex_distance(Vector2i.ZERO, coords)) / 8.0)
			)
			var record := mob_spawner.generate_mob_record(
				coords,
				faction,
				difficulty,
				_encounter_key(coords)
			)
			_initialize_npc_runtime(record)
			var entity_id := _world_state.register_entity(record)
			hex_data.encounter_entity_id = entity_id
			new_encounter_count += 1
			_macro_log(
				"Seeded encounter %s (%s) @%s [chance %.3f, out-of-sight fog]."
				% [
					entity_id,
					GameEnums.Faction.keys()[faction],
					str(coords),
					spawn_chance,
				]
			)

		_world_state.set_hex_record(coords, hex_data.to_state())

func _get_spawn_chance(hex_data: MacroHexData) -> float:
	if not hex_data.is_passable():
		return 0.0
	var chance := base_enemy_spawn_chance
	if hex_data.terrain_tile == GameEnums.MacroTerrainTile.MUD_YELLOW:
		chance *= 1.15
	elif hex_data.terrain_tile == GameEnums.MacroTerrainTile.FOREST_SPARSE:
		chance *= 1.1
	elif hex_data.terrain_tile == GameEnums.MacroTerrainTile.SNOW_TRANSITION:
		chance *= 0.9
	if hex_data.rock_layer == GameEnums.MacroRockLayer.HILLS:
		chance *= 0.9
	if hex_data.structure_layer != GameEnums.MacroStructureLayer.NONE:
		chance *= 1.2
	return chance

func _roll_faction(
	rng: RandomNumberGenerator,
	hex_data: MacroHexData
) -> GameEnums.Faction:
	var roll := rng.randf()
	if (
		hex_data.terrain_tile == GameEnums.MacroTerrainTile.MUD_YELLOW
		and roll < 0.35
	):
		return GameEnums.Faction.CRAVEN_HIVE
	if roll < 0.72:
		return GameEnums.Faction.SCAVENGER_CELL
	if roll < 0.92:
		return GameEnums.Faction.CRAVEN_HIVE
	return GameEnums.Faction.ARCBORN_RESISTANCE

func _coords_in_radius(center_coords: Vector2i, radius: int) -> Array[Vector2i]:
	var coords_list: Array[Vector2i] = []
	for q in range(-radius, radius + 1):
		for r in range(
			max(-radius, -q - radius),
			min(radius, -q + radius) + 1
		):
			coords_list.append(center_coords + Vector2i(q, r))
	return coords_list

func _hex_distance(from_coords: Vector2i, to_coords: Vector2i) -> int:
	var delta := to_coords - from_coords
	return maxi(abs(delta.x), maxi(abs(delta.y), abs(delta.x + delta.y)))

func _encounter_key(coords: Vector2i) -> String:
	return (
		_world_state.world_seed
		+ ":encounter:"
		+ str(coords.x)
		+ ":"
		+ str(coords.y)
	)

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
