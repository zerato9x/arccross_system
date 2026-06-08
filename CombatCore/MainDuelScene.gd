extends Node2D

signal duel_resolved(winner: HumanoidCore, loser: HumanoidCore, dropped_loot: Array[ItemData])
signal duel_escaped(escaper: HumanoidCore)

@onready var lane_manager: CombatLaneManager = $CombatLaneManager
@onready var turn_manager: CombatTurnManager = $CombatTurnManager
@onready var resolution_engine: CombatResolutionEngine = $CombatResolutionEngine
@onready var encounter_builder: EncounterBuilder = $EncounterBuilder
@onready var mob_spawner: MobSpawner = $MobSpawner
@onready var debug_log: RichTextLabel = $DebugUI/DebugLog

var player_core: HumanoidCore
var enemy_core: HumanoidCore

var dropped_combat_loot: Array[ItemData] = []

func _ready() -> void:
	# AUTO-TEST BOOTSTRAP: Only run if we are testing the scene directly!
	if get_parent() == get_tree().root:
		print("\n>>> INITIALIZING ARCCROSS COMBAT SIMULATION (STANDALONE) <<<")
		var p_def = preload("res://BiologicalCore/player_def.tres")
		var e_def = preload("res://BiologicalCore/scavenger_def.tres")
		if p_def and e_def:
			setup_duel(p_def, e_def)
		else:
			print("Failed to load entity definitions for test.")

func setup_duel(p_def: EntityDefinition, e_def: EntityDefinition) -> void:
	# 1. Programmatically assemble the complex entity structures from scratch
	player_core = _fabricate_humanoid("Player_Unit", p_def)
	enemy_core = _fabricate_humanoid("Enemy_Scavenger", e_def)
	
	# 2. Wire up status alerts to update our visual console readouts
	turn_manager.turn_started.connect(_on_turn_cycled)
	turn_manager.ap_spent.connect(_on_action_logged)
	turn_manager.entity_escaped.connect(_on_entity_escaped)
	
	# 3. Wire up death listeners for duel resolution
	player_core.died.connect(_on_combatant_died.bind(player_core))
	enemy_core.died.connect(_on_combatant_died.bind(enemy_core))
	
	# 4. Drop them into the mud using our tactical layout matrix
	encounter_builder.build_encounter(player_core, enemy_core, GameEnums.EncounterContext.NEUTRAL_MEET)
	_refresh_debug_hud()

## Alternative entry: spawn a procedural enemy from the MobSpawner.
func setup_duel_procedural(p_def: EntityDefinition, enemy_faction: GameEnums.Faction, difficulty: int = 0) -> void:
	var e_def: EntityDefinition = mob_spawner.generate_mob(enemy_faction, difficulty)
	setup_duel(p_def, e_def)

func _fabricate_humanoid(unit_name: String, definition: EntityDefinition) -> HumanoidCore:
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
	
	# AUTO-TEST FIX: Attach an AI to both units so they fight each other automatically!
	var ai = CombatAIEvaluator.new()
	ai.name = "CombatAIEvaluator"
	ai.ai_core = core
	ai.lane_manager = lane_manager
	ai.turn_manager = turn_manager
	ai.resolution_engine = resolution_engine
	core.add_child(ai)
	
	add_child(core)
	
	# After _ready() fires and the inventory paper_doll is built, apply the loadout
	if definition.loadout:
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

func _on_combatant_died(cause: String, dead_entity: HumanoidCore) -> void:
	var winner: HumanoidCore
	var loser: HumanoidCore = dead_entity
	
	if dead_entity == player_core:
		winner = enemy_core
	else:
		winner = player_core
	
	print("\n[DUEL RESOLVED] ", winner.name, " stands victorious. Cause of death: ", cause)
	duel_resolved.emit(winner, loser, dropped_combat_loot)
	
	if get_parent() == get_tree().root:
		turn_manager.halt_loop()
		if winner == player_core:
			print("\n[SYSTEM] Standalone Test: Player won! Spawning next mob in 2 seconds...")
			get_tree().create_timer(2.0).timeout.connect(_spawn_next_mob)
		else:
			print("\n[SYSTEM] Standalone Test: Player died! Reloading scene in 2 seconds...")
			get_tree().create_timer(2.0).timeout.connect(func(): get_tree().reload_current_scene())

func _on_entity_escaped(escaper: HumanoidCore) -> void:
	print("\n[DUEL ESCAPED] ", escaper.name, " has successfully fled the battlefield!")
	duel_escaped.emit(escaper)
	
	if get_parent() == get_tree().root:
		turn_manager.halt_loop()
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
	enemy_core = _fabricate_humanoid("Endless_Mob", e_def)
	
	enemy_core.died.connect(_on_combatant_died.bind(enemy_core))
	lane_manager.force_spawn_entity(enemy_core, 9)
	
	turn_manager.combatants.append(enemy_core)
	turn_manager.reserved_ap[enemy_core] = 0
	_refresh_debug_hud()
	print("\n>>> NEW CHALLENGER APPROACHES <<<")
	turn_manager.resume_loop()
