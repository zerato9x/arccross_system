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
@onready var mob_spawner: MobSpawner = get_node("/root/MobSpawner") as MobSpawner
@onready var debug_log: RichTextLabel = $DebugUI/DebugLog

var player_core: HumanoidCore
var enemy_core: HumanoidCore
var enemy_entity_id: String = ""

var dropped_combat_loot: Array[ItemData] = []

func _ready() -> void:
	# AUTO-TEST BOOTSTRAP: Only run if we are testing the scene directly!
	if get_parent() == get_tree().root:
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

	if not player_core.inventory.items_spilled.is_connected(_on_player_items_spilled):
		player_core.inventory.items_spilled.connect(_on_player_items_spilled)
	
	# 2. Wire up status alerts to update our visual console readouts
	turn_manager.turn_started.connect(_on_turn_cycled)
	turn_manager.ap_spent.connect(_on_action_logged)
	turn_manager.entity_escaped.connect(_on_entity_escaped)
	
	# 3. Wire up death listeners for duel resolution
	player_core.died.connect(_on_combatant_died.bind(player_core))
	enemy_core.died.connect(_on_combatant_died.bind(enemy_core))
	
	# 4. Drop them into the mud using our tactical layout matrix
	encounter_builder.build_encounter(
		player_core,
		enemy_core,
		encounter_setup
	)
	_refresh_debug_hud()

## Alternative entry: spawn a procedural enemy from the MobSpawner.
func setup_duel_procedural(existing_player_core: HumanoidCore, enemy_faction: GameEnums.Faction, difficulty: int = 0) -> void:
	var enemy_record := mob_spawner.generate_mob_record(
		Vector2i.ZERO,
		enemy_faction,
		difficulty
	)
	setup_duel(existing_player_core, enemy_record)

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
	if not runtime_state.is_empty():
		core.restore_runtime_state(runtime_state)
		print("[FABRICATE] ", unit_name, " restored from persistent runtime state.")
	elif definition.loadout:
		definition.loadout.apply_to(inv)
		print("[FABRICATE] ", unit_name, " spawned with loadout. Weight: ", inv.get_total_weight(), " | Threat: ", inv.get_total_threat())
	else:
		print("[FABRICATE] ", unit_name, " spawned naked. Giving them a random weapon for the test!")
		
		# Give them a backpack so they have pocket space
		var test_bag = load("res://ItemCore/Items/military_backpack.tres")
		if test_bag:
			inv.equip_item(test_bag, GameEnums.EquipmentSlot.BACKPACK)
			
		# Give them a weapon so they can actually fight
		var test_weapon = load("res://ItemCore/Items/rusty_pipe.tres")
		if unit_name == "Player_Unit":
			test_weapon = load("res://ItemCore/Items/makeshift_sidearm.tres")
		if test_weapon:
			inv.equip_item(test_weapon, GameEnums.EquipmentSlot.HANDS)
			
			if test_weapon.is_ranged():
				for i in range(18):
					var ammo = ItemData.new()
					ammo.id = "ammo_round"
					ammo.display_name = "Loose Ammo"
					ammo.item_type = GameEnums.ItemType.JUNK
					ammo.weight = 0.05
					inv.add_to_backpack(ammo)
				print("Supplied ", unit_name, " with 18 rounds of loose ammo.")
	
	return core

func _refresh_debug_hud() -> void:
	if not player_core or not enemy_core: return
	
	var txt = ""
	txt += "[color=green]=== ARCCROSS COMBAT LANE CONSOLE ===[/color]\n"
	txt += "ROUND: %d | ACTIVE TIMEPOOL POOL: %d AP\n" % [turn_manager.current_round, turn_manager.current_ap_pool]
	txt += "---------------------------------------------------------\n\n"
	
	txt += _build_entity_readout(player_core)
	txt += "\n"
	txt += _build_entity_readout(enemy_core)
	
	debug_log.text = txt

func _build_entity_readout(entity: HumanoidCore) -> String:
	var t = ""
	var weapon_name: String = "UNARMED"
	var held = entity.inventory.paper_doll.get(GameEnums.EquipmentSlot.HANDS)
	if held: weapon_name = held.display_name
	
	t += "[b]%s[/b] (%s) | Flee: %s\n" % [entity.name, entity.definition.archetype_name, str(entity.is_fleeing)]
	t += "Vitals -> AP: %d (Tier: %s | Burden: %d) | Blood: %.2f | Morale: %.1f\n" % [entity.current_max_ap, GameEnums.KineticTier.keys()[entity.kinetic_tier], entity.total_burden, entity.body.blood_level, entity.current_morale]
	t += "Stance -> %s (%d/12) | Weapon: %s\n" % [GameEnums.StanceState.keys()[entity.current_stance], entity.stance_points, weapon_name]
	t += "Gear -> THREAT: %.1f | WEIGHT: %.1f | BULK: %.1f | Inventory: %d/%d\n" % [entity.get_effective_threat(), entity.inventory.get_total_weight(), entity.get_bulk_modifier(), entity.inventory.current_size, entity.inventory.current_max_capacity]
	t += "Trauma -> U-Torso: %.1f | Head: %.1f | L-Arm: %.1f\n" % [entity.body.limb_hp[GameEnums.LimbRegion.UPPER_TORSO], entity.body.limb_hp[GameEnums.LimbRegion.HEAD], entity.body.limb_hp[GameEnums.LimbRegion.LEFT_ARM]]
	return t

func _on_turn_cycled(_active_entity: HumanoidCore) -> void:
	_refresh_debug_hud()

func _on_action_logged(_entity: HumanoidCore, _remaining_ap: int) -> void:
	_refresh_debug_hud()

func _on_items_spilled(spilled_items: Array[ItemData], entity: HumanoidCore) -> void:
	print("[COMBAT DROPS] ", entity.name, " spilled ", spilled_items.size(), " items into the dirt!")
	dropped_combat_loot.append_array(spilled_items)

func _on_player_items_spilled(spilled_items: Array[ItemData]) -> void:
	_on_items_spilled(spilled_items, player_core)

func _on_combatant_died(cause: String, dead_entity: HumanoidCore) -> void:
	turn_manager.halt_loop()
	var outcome := (
		GameEnums.CombatOutcome.PLAYER_DEFEAT
		if dead_entity == player_core
		else GameEnums.CombatOutcome.PLAYER_VICTORY
	)
	var winner := enemy_core if dead_entity == player_core else player_core

	print("\n[DUEL RESOLVED] ", winner.name, " stands victorious. Cause of death: ", cause)
	duel_finished.emit(
		outcome,
		enemy_entity_id,
		capture_enemy_runtime_state(),
		_capture_dropped_item_states()
	)
	
	if get_parent() == get_tree().root:
		if winner == player_core:
			print("\n[SYSTEM] Standalone Test: Player won! Spawning next mob in 2 seconds...")
			get_tree().create_timer(2.0).timeout.connect(_spawn_next_mob)
		else:
			print("\n[SYSTEM] Standalone Test: Player died! Reloading scene in 2 seconds...")
			get_tree().create_timer(2.0).timeout.connect(func(): get_tree().reload_current_scene())

func _on_entity_escaped(escaper: HumanoidCore) -> void:
	turn_manager.halt_loop()
	print("\n[DUEL ESCAPED] ", escaper.name, " has successfully fled the battlefield!")
	var outcome := (
		GameEnums.CombatOutcome.PLAYER_ESCAPED
		if escaper == player_core
		else GameEnums.CombatOutcome.ENEMY_ESCAPED
	)
	duel_finished.emit(
		outcome,
		enemy_entity_id,
		capture_enemy_runtime_state(),
		_capture_dropped_item_states()
	)
	
	if get_parent() == get_tree().root:
		print("\n[SYSTEM] Standalone Test: Entity escaped! Spawning next mob in 2 seconds...")
		get_tree().create_timer(2.0).timeout.connect(_spawn_next_mob)

func _spawn_next_mob() -> void:
	if is_instance_valid(enemy_core):
		turn_manager.combatants.erase(enemy_core)
		# Remove from lane
		for slot in lane_manager.lane_slots:
			if slot.occupants.has(enemy_core):
				slot.occupants.erase(enemy_core)
		enemy_core.queue_free()
		
	# Generate new enemy
	var factions = [GameEnums.Faction.CRAVEN_HIVE, GameEnums.Faction.SCAVENGER_CELL]
	var e_def = mob_spawner.generate_mob(factions.pick_random(), randi() % 3)
	enemy_core = _fabricate_humanoid("Endless_Mob", e_def, true)
	
	enemy_core.died.connect(_on_combatant_died.bind(enemy_core))
	lane_manager.force_spawn_entity(enemy_core, 9)
	
	turn_manager.combatants.append(enemy_core)
	turn_manager.reserved_ap[enemy_core] = 0
	_refresh_debug_hud()
	print("\n>>> NEW CHALLENGER APPROACHES <<<")
	turn_manager.resume_loop()

func capture_enemy_runtime_state() -> Dictionary:
	if not enemy_core:
		return {}
	return enemy_core.capture_runtime_state()

func _capture_dropped_item_states() -> Array:
	var states: Array = []
	for item in dropped_combat_loot:
		states.append(item.to_runtime_state())
	return states
