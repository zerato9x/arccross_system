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
@export var inventory_panel: InventoryPanel

@export_group("Proximity Loading")
@export_range(1, 12) var active_radius: int = 4
@export_range(2, 16) var unload_radius: int = 6
@export_range(1, 12) var generation_radius: int = 5
@export_range(0, 4) var safe_start_radius: int = 1
@export_range(0.0, 1.0) var base_enemy_spawn_chance: float = 0.12

var active_enemies: Dictionary = {} # Stores Vector2i -> MacroEnemy projections
var _world_state: RuntimeStateStore
var _loot_catalog: Node
var _pending_interaction: Dictionary = {}
var _last_inventory_error: String = ""

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

	var player_inventory := player_token.get_humanoid_core().inventory
	player_inventory.inventory_error.connect(_on_player_inventory_error)
	player_inventory.items_spilled.connect(_on_player_items_spilled)
		
	if _world_state.consume_pending_loaded_world():
		_initialize_loaded_world()
	else:
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

func _initialize_loaded_world() -> void:
	if _world_state.world_seed.is_empty() or _world_state.player_record.is_empty():
		push_error("Loaded world state is incomplete. Starting a new demo world.")
		_initialize_demo()
		return

	world_generator.configure_seed(_world_state.world_seed)
	world_generator.inject_unique_poi(
		Vector2i(1, 0),
		"demo_relay_shelter",
		"Abandoned Relay Shelter",
		GameEnums.GridBiome.PLAINS
	)
	player_token.restore_runtime_record(_world_state.player_record)
	var loaded_coords := _world_state.player_coords
	player_token.snap_to_hex(
		loaded_coords,
		map_visualizer.map_to_local(loaded_coords)
	)
	map_visualizer.render_radius(loaded_coords, 3)
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
	if (
		event is InputEventKey
		and event.pressed
		and not event.echo
		and event.keycode == KEY_I
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
	_advance_survival_time(
		GameTimeRules.MOVE_MINUTES,
		_get_exertion_for_biome(hex_data.biome),
		target_coords
	)
	
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

func _get_exertion_for_biome(biome: GameEnums.GridBiome) -> float:
	if biome == GameEnums.GridBiome.SWAMP or biome == GameEnums.GridBiome.MUD:
		return 2.0
	return 1.0

func _begin_poi_interaction(
	coords: Vector2i,
	hex_data: MacroHexData
) -> void:
	_pending_interaction = {
		"type": GameEnums.MacroInteractionType.POI,
		"coords": coords,
	}
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
	interaction_panel.open_poi({
		"poi_name": hex_data.poi_name,
		"search_metric_keys": MacroInteractionResolver.SEARCH_KEYS,
		"camp_metric_keys": MacroInteractionResolver.CAMP_KEYS,
		"available_items": _available_interaction_options(),
		"camp_items": _camp_item_options(hex_data.camp_item_states),
		"camp_item_ids": camp_item_ids,
		"camp_allowed": camp_access.get("allowed", false),
		"camp_block_reason": camp_access.get("reason", ""),
		"world_time": _world_state.get_world_time_snapshot(),
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
	if not interaction_panel:
		push_error("Entity interaction opened without a presentation subscriber.")
		close_macro_interaction()
		return
	interaction_panel.open_entity_collision({
		"entity_name": definition.get("archetype_name", "Unknown"),
	})

func preview_poi_action(
	action: GameEnums.PoiAction,
	selected_item_ids: Array
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
		var loot_profile := _get_loot_profile(hex_data)
		var descriptors := _inventory_descriptors_for_ids(
			selected_item_ids,
			GameEnums.InteractionItemRole.SEARCH_TOOL
		)
		metrics = MacroInteractionResolver.calculate_search_metrics(
			profile["search"],
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

func open_inventory() -> void:
	if not inventory_panel:
		push_error("Inventory requested without a presentation subscriber.")
		return
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
		InventoryPanel.ACTION_TAKE:
			var item_state := _world_state.take_ground_item(
				coords,
				instance_id
			)
			if item_state.is_empty():
				message = "That ground item is no longer available."
			else:
				var ground_item := ItemData.from_runtime_state(item_state)
				if inventory.add_to_backpack(ground_item):
					message = "Took %s." % ground_item.display_name
				else:
					_world_state.add_ground_items(coords, [item_state])
					message = _inventory_error_or(
						"That item does not fit in the backpack."
					)
		InventoryPanel.ACTION_DROP:
			var dropped := inventory.remove_item_by_instance_id(instance_id)
			if dropped:
				_world_state.add_ground_items(
					coords,
					[dropped.to_runtime_state()]
				)
				message = "Dropped %s." % dropped.display_name
			else:
				message = "That carried item is no longer available."
		InventoryPanel.ACTION_EQUIP:
			var equippable := inventory.find_item_by_instance_id(instance_id)
			if equippable == null or not inventory.backpack_array.has(equippable):
				message = "Only backpack items can be equipped."
			elif (
				equipment_slot != equippable.target_slot
				or not _can_offer_equip(equippable)
			):
				message = "That item cannot be equipped in the requested slot."
			elif inventory.equip_item(equippable, equippable.target_slot):
				message = "Equipped %s." % equippable.display_name
			else:
				message = _inventory_error_or("The equipment change failed.")
		InventoryPanel.ACTION_UNEQUIP:
			if not inventory.paper_doll.has(equipment_slot):
				message = "That equipment slot does not exist."
			else:
				var equipped: ItemData = inventory.paper_doll[equipment_slot]
				if equipped == null or equipped.instance_id != instance_id:
					message = "That equipped item is no longer available."
				else:
					inventory.unequip_item(equipment_slot)
					message = "Unequipped %s." % equipped.display_name
		InventoryPanel.ACTION_CONSUME:
			var consumable := inventory.find_item_by_instance_id(instance_id)
			if consumable == null or not inventory.backpack_array.has(consumable):
				message = "Only backpack consumables can be used."
			elif player_core.use_consumable_item(consumable):
				message = "Used %s." % consumable.display_name
			else:
				message = _inventory_error_or("The item could not be used.")
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

func _on_inventory_closed() -> void:
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
	var inventory := player_token.get_humanoid_core().inventory
	var equipment: Array = []
	for slot in GameEnums.EquipmentSlot.values():
		if slot == GameEnums.EquipmentSlot.NONE:
			continue
		var equipped: ItemData = inventory.paper_doll.get(slot)
		if equipped:
			equipment.append(_item_inventory_descriptor(equipped, slot))

	var backpack: Array = []
	for item in inventory.backpack_array:
		backpack.append(_item_inventory_descriptor(item))

	var ground: Array = []
	for item_state in _world_state.get_ground_items(
		player_token.current_hex_coords
	):
		ground.append(_ground_inventory_descriptor(item_state))

	return {
		"coords": player_token.current_hex_coords,
		"world_time": _world_state.get_world_time_snapshot(),
		"current_capacity": inventory.current_size,
		"maximum_capacity": inventory.current_max_capacity,
		"equipment": equipment,
		"backpack": backpack,
		"ground": ground,
	}

func _item_inventory_descriptor(
	item: ItemData,
	equipment_slot: int = GameEnums.EquipmentSlot.NONE
) -> Dictionary:
	return {
		"instance_id": item.instance_id,
		"name": item.display_name,
		"description": item.lore_description,
		"item_type": item.item_type,
		"size_cost": item.size_cost,
		"target_slot": item.target_slot,
		"equipment_slot": equipment_slot,
		"can_equip": _can_offer_equip(item),
		"can_consume": item.item_type == GameEnums.ItemType.CONSUMABLE,
	}

func _ground_inventory_descriptor(item_state: Dictionary) -> Dictionary:
	var definition: Dictionary = item_state.get("definition", {})
	return {
		"instance_id": item_state.get("instance_id", ""),
		"name": definition.get("display_name", "Unknown Item"),
		"description": definition.get("lore_description", ""),
		"item_type": definition.get(
			"item_type",
			GameEnums.ItemType.JUNK
		),
		"size_cost": definition.get("size_cost", 0),
		"target_slot": definition.get(
			"target_slot",
			GameEnums.EquipmentSlot.NONE
		),
		"equipment_slot": GameEnums.EquipmentSlot.NONE,
		"can_equip": false,
		"can_consume": false,
	}

func _can_offer_equip(item: ItemData) -> bool:
	return (
		item.target_slot != GameEnums.EquipmentSlot.NONE
		and (
			item.item_type == GameEnums.ItemType.WEAPON
			or item.item_type == GameEnums.ItemType.ARMOR
		)
	)

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
	selected_item_ids: Array
) -> void:
	var descriptors := _inventory_descriptors_for_ids(
		selected_item_ids,
		GameEnums.InteractionItemRole.SEARCH_TOOL
	)
	var metrics := MacroInteractionResolver.calculate_search_metrics(
		base_metrics,
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
		loot_profile
	)
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

	var message := (
		"Found: " + ", ".join(found_names)
		if not found_names.is_empty()
		else "The search produced no usable supplies."
	)
	message += "\nTime: " + _format_world_time()
	if result.get("injured", false):
		message += "\nUnstable debris caused an injury."

	if result.get("attracted_enemy", false):
		message += "\nThe noise attracted a hostile."
		_spawn_search_intruder(coords)
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
	hex_data.camp_rest_count += 1

	var body := player_token.get_humanoid_core().body
	body.fatigue = maxf(
		0.0,
		body.fatigue - float(result.get("fatigue_recovery", 0.0))
	)
	_advance_survival_time(
		GameTimeRules.CAMP_MINUTES,
		0.25,
		coords,
		float(metrics.get("shelter", 0.0))
	)
	var healing_amount: float = result.get("healing_amount", 0.0)
	for limb in body.limb_hp.keys():
		if body.limb_hp[limb] > 0.0:
			body.limb_hp[limb] = minf(
				body.get_limb_max(limb),
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
	_show_interaction_result(
		"REST COMPLETE",
		(
			"Fatigue recovered by %.1f / 12. Camp healing restored %.1f limb health."
			+ "\nTime: %s"
		) % [
			float(result.get("fatigue_recovery", 0.0)),
			healing_amount,
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
	if record.is_empty():
		_show_interaction_result(
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

func _available_interaction_options() -> Array:
	var descriptors: Array = []
	for item in player_token.get_humanoid_core().inventory.get_all_items():
		if not item.interaction_roles.is_empty():
			descriptors.append({
				"instance_id": item.instance_id,
				"name": item.display_name,
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
		hex_data.poi_id
	)
	return _loot_catalog.call("get_profile_descriptor", profile_id)

func _get_camp_access(
	coords: Vector2i,
	hex_data: MacroHexData
) -> Dictionary:
	var hostile_present := false
	var entity_record := _world_state.get_entity_at(coords)
	if not entity_record.is_empty():
		var entity_id: String = entity_record.get("entity_id", "")
		hostile_present = (
			_world_state.is_entity_alive(entity_id)
			and _world_state.is_entity_hostile(entity_id)
		)
	return WorldRules.get_camp_access(
		hex_data.is_poi,
		hex_data.hazard_level,
		hostile_present
	)

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
