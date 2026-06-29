extends Node2D

signal duel_finished(
	outcome: GameEnums.CombatOutcome,
	enemy_id: String,
	enemy_runtime: Dictionary,
	dropped_items: Array
)

@onready var lane_manager: CombatLaneManager = $CombatLaneManager
@onready var turn_manager: CombatTurnManager = $CombatTurnManager
@onready var resolution_engine: CombatResolutionEngine = $CombatResolutionEngine
@onready var encounter_builder: EncounterBuilder = $EncounterBuilder
@onready var command_adapter: CombatCommandAdapter = $CombatCommandAdapter
@onready var mob_spawner: MobSpawner = get_node("/root/MobSpawner") as MobSpawner
@onready var lane_hud: CombatLaneHUD = $CombatLaneHUD

var player_core: HumanoidCore
var enemy_core: HumanoidCore
var enemy_entity_id: String = ""

var dropped_combat_loot: Array[ItemData] = []

func _ready() -> void:
	lane_hud.action_requested.connect(command_adapter.request_player_action)
	lane_hud.pass_requested.connect(command_adapter.pass_player_turn)
	lane_hud.reaction_selected.connect(
		command_adapter.resolve_player_reaction
	)
	command_adapter.snapshot_changed.connect(lane_hud.show_snapshot)
	command_adapter.presentation_event.connect(
		lane_hud.show_presentation_event
	)
	command_adapter.reaction_requested.connect(lane_hud.show_reaction)
	command_adapter.command_feedback.connect(lane_hud.show_feedback)
	lane_hud.open_hud()

	# AUTO-TEST BOOTSTRAP: Only run if we are testing the scene directly!
	if get_parent() == get_tree().root and get_tree().current_scene == self:
		print("\n>>> INITIALIZING ARCCROSS COMBAT SIMULATION (STANDALONE) <<<")
		var p_def = preload("res://BiologicalCore/player_def.tres")
		var e_def = preload("res://BiologicalCore/scavenger_def.tres")
		if p_def and e_def:
			var standalone_player := _fabricate_humanoid("Player_Unit", p_def, false)
			setup_duel(standalone_player, {
				"entity_id": "standalone_enemy",
				"definition": e_def.to_state(),
				"runtime": {},
			})
		else:
			print("Failed to load entity definitions for test.")

func setup_duel(
	existing_player_core: HumanoidCore,
	enemy_record: Dictionary,
	encounter_setup: Dictionary = {}
) -> void:
	if not existing_player_core:
		push_error("Cannot start duel without an authoritative player core.")
		return

	# Clean up any existing HumanoidCore children from previous setups or ready bootstrap
	for child in get_children():
		if child is HumanoidCore and child != existing_player_core:
			child.queue_free()

	# Clear the lane slots of any old occupants to prevent ghost locks
	if lane_manager:
		for slot in lane_manager.lane_slots:
			slot.occupants.clear()
			slot.is_melee_locked = false
			slot.grapple_stance_scale = 12

	# Reuse the persistent player and fabricate only the encounter enemy.
	player_core = existing_player_core
	enemy_entity_id = enemy_record.get("entity_id", "")
	var enemy_definition := EntityDefinition.from_state(
		enemy_record.get("definition", {})
	)
	enemy_core = _fabricate_humanoid(
		"Enemy_Scavenger",
		enemy_definition,
		true,
		enemy_record.get("runtime", {})
	)
	player_core.reset_combat_transients()
	enemy_core.reset_combat_transients()

	if not player_core.inventory.items_spilled.is_connected(_on_player_items_spilled):
		player_core.inventory.items_spilled.connect(_on_player_items_spilled)
	
	if not turn_manager.entity_escaped.is_connected(_on_entity_escaped):
		turn_manager.entity_escaped.connect(_on_entity_escaped)
	
	# 2. Wire up death listeners for duel resolution
	player_core.died.connect(_on_combatant_died.bind(player_core))
	enemy_core.died.connect(_on_combatant_died.bind(enemy_core))

	command_adapter.configure(
		player_core,
		enemy_core,
		lane_manager,
		turn_manager,
		resolution_engine
	)
	
	# 3. Wire player signals to AudioConductor (player-subjective audio only)
	var conductor = get_node_or_null("/root/AudioConductor")
	if conductor:
		if not player_core.kinetic_burden_calculated.is_connected(conductor.on_kinetic_tier_changed):
			player_core.kinetic_burden_calculated.connect(conductor.on_kinetic_tier_changed)
		if not player_core.stance_changed.is_connected(conductor.on_stance_changed):
			player_core.stance_changed.connect(conductor.on_stance_changed)
		if not player_core.morale_broken.is_connected(conductor.on_morale_broken):
			player_core.morale_broken.connect(conductor.on_morale_broken)
		if not player_core.died.is_connected(conductor.on_player_died):
			player_core.died.connect(conductor.on_player_died)
		if not resolution_engine.first_combat_action.is_connected(conductor.on_first_strike):
			resolution_engine.first_combat_action.connect(conductor.on_first_strike)
		resolution_engine.reset_first_strike()
	
	# 4. Drop them into the mud using our tactical layout matrix
	encounter_builder.build_encounter(
		player_core,
		enemy_core,
		encounter_setup
	)
	command_adapter.refresh_snapshot()

## Alternative entry: spawn a procedural enemy from the MobSpawner.
func setup_duel_procedural(existing_player_core: HumanoidCore, enemy_faction: GameEnums.Faction, difficulty: int = 0) -> void:
	var enemy_record := mob_spawner.generate_mob_record(
		Vector2i.ZERO,
		enemy_faction,
		difficulty
	)
	setup_duel(existing_player_core, enemy_record.to_dict())

func _fabricate_humanoid(
	unit_name: String,
	definition: EntityDefinition,
	attach_ai: bool,
	runtime_state: Dictionary = {}
) -> HumanoidCore:
	# Programmatic assembly since we are bypassing custom .tscn instantiation
	var core = HumanoidCore.new()
	core.name = unit_name
	core.definition = definition
	
	var body = HumanoidBody.new()
	body.name = "HumanoidBody"
	core.add_child(body)
	core.body = body
	
	var inv = InventorySystem.new()
	inv.name = "InventorySystem"
	core.add_child(inv)
	core.inventory = inv
	
	# Connect to the items spilled signal
	inv.items_spilled.connect(_on_items_spilled.bind(core))
	
	if attach_ai:
		var ai = CombatAIEvaluator.new()
		ai.name = "CombatAIEvaluator"
		ai.ai_core = core
		ai.lane_manager = lane_manager
		ai.turn_manager = turn_manager
		ai.resolution_engine = resolution_engine
		core.add_child(ai)
	
	add_child(core)
	
	# A persistent snapshot supersedes the initial loadout.
	var has_humanoid_runtime := _has_humanoid_runtime(runtime_state)
	var inventory_runtime = runtime_state.get("inventory", {})
	var has_inventory_runtime: bool = (
		has_humanoid_runtime
		and inventory_runtime is Dictionary
		and not inventory_runtime.is_empty()
	)
	if has_inventory_runtime:
		core.restore_runtime_state(runtime_state)
		print("[FABRICATE] ", unit_name, " restored from persistent runtime state.")
	elif definition.loadout:
		definition.loadout.apply_to(inv)
		if has_humanoid_runtime:
			core.restore_runtime_state(runtime_state)
			print("[FABRICATE] ", unit_name, " restored body state on generated loadout.")
		else:
			print("[FABRICATE] ", unit_name, " spawned with loadout. Weight: ", inv.get_total_weight(), " | Threat: ", inv.get_total_threat())
	else:
		print("[FABRICATE] ", unit_name, " spawned naked. Giving them a random weapon for the test!")
		
		# Give them a backpack so they have pocket space
		var test_bag = load("res://ItemCore/Items/backpack_service_big.tres")
		if test_bag:
			inv.equip_item(test_bag, GameEnums.EquipmentSlot.BACKPACK)
		var test_rig = load("res://ItemCore/Items/webbing.tres")
		if test_rig:
			inv.equip_item(test_rig, GameEnums.EquipmentSlot.VEST)
			
		# Give them a weapon so they can actually fight
		var test_weapon = load("res://ItemCore/Items/rebar.tres")
		if unit_name == "Player_Unit":
			test_weapon = load("res://ItemCore/Items/service_pistol.tres")
		if test_weapon:
			inv.equip_item(test_weapon, GameEnums.EquipmentSlot.HAND)
			
			if test_weapon.is_ranged():
				_supply_test_ammunition(inv, test_weapon, 18)
				print(
					"Supplied ",
					unit_name,
					" with 18 compatible rounds and feed equipment."
				)
		if has_humanoid_runtime:
			core.restore_runtime_state(runtime_state)
	
	return core

func _has_humanoid_runtime(runtime_state: Dictionary) -> bool:
	for key in [
		"body",
		"inventory",
		"base_ap",
		"current_max_ap",
		"is_dead",
		"stance_points",
		"current_morale",
	]:
		if runtime_state.has(key):
			return true
	return false

func _supply_test_ammunition(
	inventory: InventorySystem,
	weapon: ItemData,
	round_count: int
) -> void:
	if weapon.ammunition_id.is_empty():
		return
	var ammo_path := "res://ItemCore/Items/%s.tres" % weapon.ammunition_id
	var ammo_definition := load(ammo_path) as ItemData
	if ammo_definition:
		for _round_index in range(round_count):
			inventory.add_to_backpack(ammo_definition)

	for support_id in [weapon.magazine_id, weapon.reload_aid_id]:
		if support_id.is_empty():
			continue
		var support_definition := load(
			"res://ItemCore/Items/%s.tres" % support_id
		) as ItemData
		if support_definition:
			var runtime_support := support_definition.create_runtime_instance()
			if inventory.add_to_backpack(runtime_support):
				inventory.load_magazine(runtime_support)

func _on_items_spilled(spilled_items: Array[ItemData], entity: HumanoidCore) -> void:
	print("[COMBAT DROPS] ", entity.name, " spilled ", spilled_items.size(), " items into the dirt!")
	_append_dropped_items(spilled_items)

func _on_player_items_spilled(spilled_items: Array[ItemData]) -> void:
	_on_items_spilled(spilled_items, player_core)

func _on_combatant_died(cause: String, dead_entity: HumanoidCore) -> void:
	turn_manager.halt_loop()
	if dead_entity == enemy_core:
		_append_dropped_items(enemy_core.inventory.drain_all_items())
	var outcome := (
		GameEnums.CombatOutcome.PLAYER_DEFEAT
		if dead_entity == player_core
		else GameEnums.CombatOutcome.PLAYER_VICTORY
	)
	var winner := enemy_core if dead_entity == player_core else player_core

	print("\n[DUEL RESOLVED] ", winner.name, " stands victorious. Cause of death: ", cause)
	if lane_hud and dead_entity == enemy_core:
		await lane_hud.show_resolve_screen({
			"title": "Combat Resolved",
			"focus_side": "enemy",
			"dead_side": "enemy",
			"dead_name": dead_entity.name,
			"cause": cause,
			"loot_names": _dropped_item_names(),
		})
	lane_hud.close_hud()
	_clear_encounter_transients()
	duel_finished.emit(
		outcome,
		enemy_entity_id,
		capture_enemy_runtime_state(),
		_capture_dropped_item_states()
	)
	
	if get_parent() == get_tree().root and get_tree().current_scene == self:
		if winner == player_core:
			print("\n[SYSTEM] Standalone Test: Player won! Spawning next mob in 2 seconds...")
			get_tree().create_timer(2.0).timeout.connect(_spawn_next_mob)
		else:
			print("\n[SYSTEM] Standalone Test: Player died! Reloading scene in 2 seconds...")
			get_tree().create_timer(2.0).timeout.connect(func(): get_tree().reload_current_scene())

func _on_entity_escaped(escaper: HumanoidCore) -> void:
	turn_manager.halt_loop()
	lane_hud.close_hud()
	print("\n[DUEL ESCAPED] ", escaper.name, " has successfully fled the battlefield!")
	var outcome := (
		GameEnums.CombatOutcome.PLAYER_ESCAPED
		if escaper == player_core
		else GameEnums.CombatOutcome.ENEMY_ESCAPED
	)
	_clear_encounter_transients()
	duel_finished.emit(
		outcome,
		enemy_entity_id,
		capture_enemy_runtime_state(),
		_capture_dropped_item_states()
	)
	
	if get_parent() == get_tree().root and get_tree().current_scene == self:
		print("\n[SYSTEM] Standalone Test: Entity escaped! Spawning next mob in 2 seconds...")
		get_tree().create_timer(2.0).timeout.connect(_spawn_next_mob)

func _spawn_next_mob() -> void:
	if is_instance_valid(enemy_core):
		turn_manager.combatants.erase(enemy_core)
		lane_manager.remove_entity(enemy_core)
		enemy_core.queue_free()
		
	# Generate new enemy
	var factions = [GameEnums.Faction.CRAVEN_HIVE, GameEnums.Faction.SCAVENGER_CELL]
	var e_def = mob_spawner.generate_mob(factions.pick_random(), randi() % 3)
	enemy_core = _fabricate_humanoid("Endless_Mob", e_def, true)
	
	enemy_core.died.connect(_on_combatant_died.bind(enemy_core))
	lane_manager.force_spawn_entity(enemy_core, 9)
	
	turn_manager.combatants.append(enemy_core)
	turn_manager.reserved_ap[enemy_core] = 0
	command_adapter.configure(
		player_core,
		enemy_core,
		lane_manager,
		turn_manager,
		resolution_engine
	)
	lane_hud.open_hud()
	command_adapter.refresh_snapshot()
	print("\n>>> NEW CHALLENGER APPROACHES <<<")
	turn_manager.resume_loop()

func capture_enemy_runtime_state() -> Dictionary:
	if not enemy_core:
		return {}
	return enemy_core.capture_runtime_state().to_dict()

func _clear_encounter_transients() -> void:
	if player_core:
		player_core.reset_combat_transients()
	if enemy_core:
		enemy_core.reset_combat_transients()

func _capture_dropped_item_states() -> Array:
	var states: Array = []
	for item in dropped_combat_loot:
		states.append(item.to_runtime_state())
	return states

func _dropped_item_names() -> Array[String]:
	var names: Array[String] = []
	for item in dropped_combat_loot:
		if item == null:
			continue
		var label := item.display_name
		if label.is_empty():
			label = item.id
		if not label.is_empty():
			names.append(label)
	return names

func _append_dropped_items(items: Array[ItemData]) -> void:
	var known_ids: Dictionary = {}
	for existing in dropped_combat_loot:
		known_ids[existing.instance_id] = true

	for item in items:
		if item == null or known_ids.has(item.instance_id):
			continue
		dropped_combat_loot.append(item)
		known_ids[item.instance_id] = true
