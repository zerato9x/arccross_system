extends Node2D
class_name MacroGameManager

# Cross-system handoff contains only IDs, primitives, and GameEnums values.
signal combat_requested(request: Dictionary)

@export_group("The Strings")
@export var world_generator: HexWorldGenerator
@export var map_visualizer: HexMapVisualizer
@export var player_token: MacroPlayer
@export var enemy_token_scene: PackedScene
@export var mob_spawner: MobSpawner
@export var interaction_panel: MacroInteractionPanel

@export_group("Proximity Loading")
@export_range(1, 12) var active_radius: int = 4
@export_range(2, 16) var unload_radius: int = 6
@export_range(1, 12) var generation_radius: int = 5
@export_range(0, 4) var safe_start_radius: int = 1
@export_range(0.0, 1.0) var base_enemy_spawn_chance: float = 0.12

var active_enemies: Dictionary = {} # Stores Vector2i -> MacroEnemy projections
var _world_state: RuntimeStateStore
var _pending_interaction: Dictionary = {}

const SEARCH_LOOT_PATHS := {
	"ration_bar": "res://ItemCore/Items/ration_bar.tres",
	"clean_water": "res://ItemCore/Items/clean_water.tres",
	"blood_bag": "res://ItemCore/Items/blood_bag.tres",
	"scrap_pipe": "res://ItemCore/Items/scrap_pipe.tres",
}

const HEX_NEIGHBORS = [
	Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1), 
	Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1)
]

func _ready() -> void:
	_world_state = get_node("/root/WorldState") as RuntimeStateStore
	if not mob_spawner:
		mob_spawner = get_node_or_null("/root/MobSpawner") as MobSpawner

	if not world_generator or not map_visualizer or not player_token or not mob_spawner:
		push_error("The Puppet Master is missing its strings. Check the inspector.")
		return

	if interaction_panel:
		interaction_panel.poi_action_submitted.connect(resolve_poi_action)
		interaction_panel.talk_action_submitted.connect(resolve_talk_action)
		interaction_panel.ambush_submitted.connect(resolve_entity_ambush)
		interaction_panel.interaction_closed.connect(close_macro_interaction)
		
	_initialize_demo()

func _initialize_demo() -> void:
	var seed := "DEMO_WASTELAND_01"
	_world_state.begin_new_world(seed)
	world_generator.configure_seed(seed)
	world_generator.inject_unique_poi(
		Vector2i(1, 0),
		"demo_relay_shelter",
		"Abandoned Relay Shelter",
		GameEnums.GridBiome.PLAINS
	)
	
	# Spawn Player
	var start_coords = Vector2i(0, 0)
	var start_pixel_pos = map_visualizer.map_to_local(start_coords)
	player_token.snap_to_hex(start_coords, start_pixel_pos)
	_world_state.set_player_record(player_token.capture_runtime_record(), start_coords)
	map_visualizer.render_radius(start_coords, 3)
	refresh_proximity(start_coords)

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
		if _world_state.is_entity_alive(existing.get("entity_id", "")):
			_spawn_enemy_token(existing)
		return

	var deterministic_key := _encounter_key(coords)
	var record := mob_spawner.generate_mob_record(
		coords,
		faction,
		difficulty,
		deterministic_key
	)
	_world_state.register_entity(record)
	_spawn_enemy_token(record)

## Legacy: spawn from a pre-built definition .tres (still works).
func spawn_macro_enemy(coords: Vector2i) -> void:
	push_warning("spawn_macro_enemy requires a persistent entity record and is deprecated.")

# ---------------------------------------------------------
# INPUT & MOVEMENT LOGIC
# ---------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not _pending_interaction.is_empty():
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_attempt_move_to_mouse()

func _attempt_move_to_mouse() -> void:
	var mouse_pos = map_visualizer.get_local_mouse_position()
	var clicked_hex_coords = map_visualizer.local_to_map(mouse_pos)
	
	var distance_vector = clicked_hex_coords - player_token.current_hex_coords
	if not HEX_NEIGHBORS.has(distance_vector):
		return # Ignored. Too far away.
		
	_execute_player_step(clicked_hex_coords)

func _execute_player_step(target_coords: Vector2i) -> void:
	var pixel_pos = map_visualizer.map_to_local(target_coords)
	player_token.walk_to_hex(target_coords, pixel_pos)
	_world_state.update_player_runtime(
		player_token.get_humanoid_core().capture_runtime_state(),
		target_coords
	)
	map_visualizer.render_radius(target_coords, 3)
	refresh_proximity(target_coords)

	var hex_data := world_generator.get_hex_at(target_coords)
	_apply_movement_survival_tick(hex_data, target_coords)
	
	if active_enemies.has(target_coords):
		var enemy: MacroEnemy = active_enemies[target_coords]
		if not _world_state.is_entity_alive(enemy.entity_id):
			unload_enemy_token(target_coords)
			return
		_begin_entity_collision(enemy.entity_id, target_coords)
		return
		
	if hex_data.is_poi:
		_begin_poi_interaction(target_coords, hex_data)
		return
		
	if _world_state.has_ground_items(target_coords):
		print(">>> You stumbled upon dropped items on this hex! <<<")

func _apply_movement_survival_tick(
	hex_data: MacroHexData,
	target_coords: Vector2i
) -> void:
	var exertion: float = 1.0
	if hex_data.biome == GameEnums.GridBiome.SWAMP or hex_data.biome == GameEnums.GridBiome.MUD:
		exertion = 2.0 
		
	var current_player_core := player_token.get_humanoid_core()
	if current_player_core:
		var insulation := current_player_core.get_insulation_rating()
		current_player_core.body.process_biological_tick(15.0, insulation, exertion)
		_world_state.update_player_runtime(
			current_player_core.capture_runtime_state(),
			target_coords
		)

func _begin_poi_interaction(
	coords: Vector2i,
	hex_data: MacroHexData
) -> void:
	var profile := MacroInteractionResolver.build_poi_profile(
		_world_state.world_seed,
		coords,
		hex_data.biome,
		hex_data.poi_id
	)
	var camp_items := _camp_item_descriptors(hex_data.camp_item_states)
	var camp_item_ids: Array = []
	for descriptor in camp_items:
		camp_item_ids.append(descriptor.get("instance_id", ""))
	_pending_interaction = {
		"type": GameEnums.MacroInteractionType.POI,
		"coords": coords,
	}
	set_process_unhandled_input(false)
	if interaction_panel:
		interaction_panel.open_poi({
			"poi_name": hex_data.poi_name,
			"search_base": profile["search"],
			"camp_base": profile["camp"],
			"search_count": hex_data.search_count,
			"available_items": _available_interaction_descriptors(),
			"camp_items": camp_items,
			"camp_item_ids": camp_item_ids,
		})

func _begin_entity_collision(enemy_id: String, coords: Vector2i) -> void:
	var enemy_record := _world_state.get_entity(enemy_id)
	if enemy_record.is_empty() or not _world_state.is_entity_hostile(enemy_id):
		return
	var definition: Dictionary = enemy_record.get("definition", {})
	_pending_interaction = {
		"type": GameEnums.MacroInteractionType.ENTITY_COLLISION,
		"coords": coords,
		"enemy_id": enemy_id,
	}
	set_process_unhandled_input(false)
	if interaction_panel:
		interaction_panel.open_entity_collision({
			"entity_name": definition.get("archetype_name", "Unknown"),
		})

func resolve_poi_action(
	action: GameEnums.PoiAction,
	selected_item_ids: Array
) -> void:
	if _pending_interaction.get("type") != GameEnums.MacroInteractionType.POI:
		return
	var coords: Vector2i = _pending_interaction.get("coords", Vector2i.ZERO)
	var hex_data := world_generator.get_hex_at(coords)
	var profile := MacroInteractionResolver.build_poi_profile(
		_world_state.world_seed,
		coords,
		hex_data.biome,
		hex_data.poi_id
	)
	if action == GameEnums.PoiAction.SEARCH:
		_resolve_search(coords, hex_data, profile["search"], selected_item_ids)
	else:
		_resolve_camp(coords, hex_data, profile["camp"], selected_item_ids)

func resolve_talk_action(action: GameEnums.TalkAction) -> void:
	if (
		_pending_interaction.get("type")
		!= GameEnums.MacroInteractionType.ENTITY_COLLISION
	):
		return
	var enemy_id: String = _pending_interaction.get("enemy_id", "")
	var enemy_record := _world_state.get_entity(enemy_id)
	var attempt: int = enemy_record.get("negotiation_attempts", 0)
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
		enemy_record.get("definition", {})
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
		interaction_panel.show_result("NEGOTIATION SUCCESS", message)

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

func _resolve_search(
	coords: Vector2i,
	hex_data: MacroHexData,
	base_metrics: Dictionary,
	selected_item_ids: Array
) -> void:
	var descriptors := _inventory_descriptors_for_ids(
		selected_item_ids,
		GameEnums.InteractionItemRole.SEARCH_TOOL
	)
	var metrics := MacroInteractionResolver.calculate_search_metrics(
		base_metrics,
		descriptors,
		hex_data.search_count
	)
	var loot_pool: Array[String] = []
	for loot_id in SEARCH_LOOT_PATHS.keys():
		loot_pool.append(str(loot_id))
	var result := MacroInteractionResolver.resolve_search(
		_world_state.world_seed,
		coords,
		hex_data.search_count,
		metrics,
		loot_pool
	)
	hex_data.search_count += 1

	var found_names: Array[String] = []
	for loot_id in result.get("loot_ids", []):
		var item_path: String = SEARCH_LOOT_PATHS.get(loot_id, "")
		var item := load(item_path) as ItemData
		if not item:
			continue
		var runtime_item := item.create_runtime_instance()
		if player_token.get_humanoid_core().inventory.add_to_backpack(runtime_item):
			found_names.append(runtime_item.display_name)
		else:
			_world_state.add_ground_items(coords, [runtime_item.to_runtime_state()])

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

	var message := (
		"Found: " + ", ".join(found_names)
		if not found_names.is_empty()
		else "The search produced no usable supplies."
	)
	if result.get("injured", false):
		message += "\nUnstable debris caused an injury."

	if result.get("attracted_enemy", false):
		message += "\nThe noise attracted a hostile."
		_spawn_search_intruder(coords)
		return
	if interaction_panel:
		interaction_panel.show_result("SEARCH COMPLETE", message)

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
	hex_data.camp_rest_count += 1

	var body := player_token.get_humanoid_core().body
	body.fatigue = maxf(
		0.0,
		body.fatigue - float(result.get("fatigue_recovery", 0.0))
	)
	var healing_amount: float = result.get("healing_amount", 0.0)
	for limb in body.limb_hp.keys():
		if body.limb_hp[limb] > 0.0:
			body.limb_hp[limb] = minf(
				body.BASE_LIMB_MAX[limb],
				body.limb_hp[limb] + healing_amount
			)

	_world_state.set_hex_record(coords, hex_data.to_state())
	_world_state.update_player_runtime(
		player_token.get_humanoid_core().capture_runtime_state(),
		coords
	)

	if result.get("interrupted", false):
		_spawn_search_intruder(coords)
		return
	if interaction_panel:
		interaction_panel.show_result(
			"REST COMPLETE",
			"Fatigue recovered by %.0f%%. Camp healing restored %.1f limb health."
			% [
				float(result.get("fatigue_recovery", 0.0)) * 100.0,
				healing_amount,
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
	if record.is_empty():
		if interaction_panel:
			interaction_panel.show_result(
				"INTERRUPTED",
				"A hostile was heard nearby, but no encounter could be projected."
			)
		return
	_pending_interaction = {
		"type": GameEnums.MacroInteractionType.ENTITY_COLLISION,
		"coords": coords,
		"enemy_id": record.get("entity_id", ""),
	}
	_request_pending_combat(
		GameEnums.EncounterContext.ENEMY_AMBUSH,
		GameEnums.AmbushPosition.STANDARD,
		record.get("entity_id", "")
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

func _available_interaction_descriptors() -> Array:
	var descriptors: Array = []
	for item in player_token.get_humanoid_core().inventory.get_all_items():
		if not item.interaction_roles.is_empty():
			descriptors.append(item.to_interaction_descriptor())
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

func _rob_enemy(enemy_record: Dictionary) -> String:
	var loadout: Dictionary = enemy_record.get("definition", {}).get("loadout", {})
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
	enemy.queue_free()

func load_enemy_token(entity_id: String) -> MacroEnemy:
	var record := _world_state.get_entity(entity_id)
	if (
		record.is_empty()
		or not _world_state.is_entity_alive(entity_id)
		or not _world_state.is_entity_hostile(entity_id)
	):
		return null
	return _spawn_enemy_token(record)

func add_ground_item_states(coords: Vector2i, item_states: Array) -> void:
	_world_state.add_ground_items(coords, item_states)

func refresh_proximity(center_coords: Vector2i) -> void:
	_ensure_encounter_records(center_coords)

	for record in _world_state.get_all_entity_records():
		var entity_id: String = record.get("entity_id", "")
		var coords: Vector2i = record.get("coords", Vector2i.ZERO)
		if _hex_distance(center_coords, coords) <= active_radius:
			if (
				_world_state.is_entity_alive(entity_id)
				and _world_state.is_entity_hostile(entity_id)
			):
				_spawn_enemy_token(record)

	for coords in active_enemies.keys().duplicate():
		var token: MacroEnemy = active_enemies[coords]
		if (
			_hex_distance(center_coords, coords) > unload_radius
			or not _world_state.is_entity_alive(token.entity_id)
			or not _world_state.is_entity_hostile(token.entity_id)
		):
			unload_enemy_token(coords)

func _ensure_encounter_records(center_coords: Vector2i) -> void:
	for coords in _coords_in_radius(center_coords, generation_radius):
		var hex_data := world_generator.get_hex_at(coords)
		if hex_data.encounter_evaluated:
			continue

		hex_data.encounter_evaluated = true
		if _hex_distance(Vector2i.ZERO, coords) <= safe_start_radius:
			_world_state.set_hex_record(coords, hex_data.to_state())
			continue

		var rng := RandomNumberGenerator.new()
		rng.seed = _encounter_key(coords).hash()
		var spawn_chance := _get_spawn_chance(hex_data.biome)
		if rng.randf() < spawn_chance:
			var faction := _roll_faction(rng, hex_data.biome)
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
			var entity_id := _world_state.register_entity(record)
			hex_data.encounter_entity_id = entity_id

		_world_state.set_hex_record(coords, hex_data.to_state())

func _get_spawn_chance(biome: GameEnums.GridBiome) -> float:
	match biome:
		GameEnums.GridBiome.SWAMP:
			return base_enemy_spawn_chance * 1.35
		GameEnums.GridBiome.MUD:
			return base_enemy_spawn_chance * 1.15
		GameEnums.GridBiome.FOREST:
			return base_enemy_spawn_chance * 1.1
		GameEnums.GridBiome.HILLS:
			return base_enemy_spawn_chance * 0.9
		_:
			return base_enemy_spawn_chance

func _roll_faction(
	rng: RandomNumberGenerator,
	biome: GameEnums.GridBiome
) -> GameEnums.Faction:
	var roll := rng.randf()
	if biome == GameEnums.GridBiome.SWAMP and roll < 0.45:
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

func _spawn_enemy_token(record: Dictionary) -> MacroEnemy:
	if not enemy_token_scene:
		push_error("Cannot spawn enemy. Assign the PackedScene in the Inspector.")
		return null

	var entity_id: String = record.get("entity_id", "")
	if not _world_state.is_entity_hostile(entity_id):
		return null

	var coords: Vector2i = record.get("coords", Vector2i.ZERO)
	if active_enemies.has(coords):
		return active_enemies[coords]

	var enemy := enemy_token_scene.instantiate() as MacroEnemy
	add_child(enemy)
	enemy.setup_from_record(record)
	enemy.snap_to_hex(coords, map_visualizer.map_to_local(coords))
	active_enemies[coords] = enemy

	var definition_state: Dictionary = record.get("definition", {})
	print(
		"[MACRO] Spawned ",
		definition_state.get("archetype_name", "Unknown"),
		" at hex ",
		coords
	)
	return enemy
